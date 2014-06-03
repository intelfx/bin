#!/bin/bash
#
# The script to sync a local mirror of the Arch Linux repositories and ISOs
#
# Copyright (C) 2007 Woody Gilk <woody@archlinux.org>
# Modifications by Dale Blount <dale@archlinux.org>
# and Roman Kyrylych <roman@archlinux.org>
# and Vadim Gamov <nickleiten@gmail.com>
# Licensed under the GNU GPL (version 2)

# Filesystem locations for the sync operations
SYNC_HOME="/mnt/data1/__userfiles/dist/linux/arch"
SYNC_LOGS="$SYNC_HOME/logs"
SYNC_FILES="$SYNC_HOME/files"
SYNC_LOCK="$SYNC_HOME/mirrorsync.lck"

# Select which repositories to sync
# Valid options are: core, extra, testing, community, iso
# Leave empty to sync a complete mirror
# SYNC_REPO=(core extra testing community iso)
SYNC_REPO=(iso/archboot/latest:archboot iso/latest:archiso)

# Set the rsync server to use
# Only official public mirrors are allowed to use rsync.archlinux.org
# SYNC_SERVER=rsync.archlinux.org::ftp
#SYNC_SERVER=distro.ibiblio.org::archlinux
SYNC_SERVER=mirror.yandex.ru::archlinux
#SYNC_SERVER=ftp://mirror.yandex.ru/archlinux

# Set the format of the log file name
# This example will output something like this: sync_20070201-8.log
LOG_FILE="pkgsync_$(date +%Y%m%d-%H).log"

#Watchdog part (time in seconds of uninterruptable work of script)
#        Needed for low-speed and/or unstable links to prevent
#       rsync hunging up.
#        New instance of script checks for timeout, if it occurs
#       it'll kill previous instance, in elsecase it'll exit without
#       any work.
WD_TIMEOUT=10800 

# Do not edit the following lines, they protect the sync from running more than
# one instance at a time
if [ ! -d $SYNC_HOME ]; then
  echo "$SYNC_HOME does not exist, please create it, then run this script again."
  exit 1
fi

mkdir -p "$SYNC_LOGS" "$SYNC_FILES"

if [ -f $SYNC_LOCK ];then
    OPID=`head -n1 $SYNC_LOCK`;
    TIMEOUT=`head -n2 $SYNC_LOCK|tail -n1`;
    NOW=`date +%s`;
    if [ "$NOW" -ge "$TIMEOUT" ];then
       kill -9 $OPID;
    fi
    MYNAME=`basename $0`;
    TESTPID=`ps -p $OPID|grep $OPID|grep $MYNAME`;
    if [ "$TESTPID" != "" ];then
        echo "exit";
        exit 1;
    else
        rm $SYNC_LOCK;
    fi
fi
echo $$ > "$SYNC_LOCK"
echo `expr \`date +%s\` + $WD_TIMEOUT` >> "$SYNC_LOCK"
# End of non-editable lines

# Create the log file and insert a timestamp
touch "$SYNC_LOGS/$LOG_FILE"
echo "=============================================" | tee -a "$SYNC_LOGS/$LOG_FILE"
echo ">> Starting sync on $( date --rfc-3339=seconds )" | tee -a "$SYNC_LOGS/$LOG_FILE"
echo ">> ---" | tee -a "$SYNC_LOGS/$LOG_FILE"

if [ -z $SYNC_REPO ]; then
  # Sync a complete mirror
  rsync -rtlvhHSP --delete-after --safe-links --max-delete=1000 --log-file "$SYNC_LOGS/$LOG_FILE"  $SYNC_SERVER "$SYNC_FILES"
  # Create $repo.lastsync file with timestamp like "2007-05-02 03:41:08+03:00"
  # which may be useful for users to know when the mirror was last updated
  date --rfc-3339=seconds > "$SYNC_FILES/repo.lastsync"
else
  # Sync each of the repositories set in $SYNC_REPO
  for repo in ${SYNC_REPO[@]}; do

	IFS=':' read repo_name repo_dest < <(tr [:upper:] [:lower:] <<< "$repo")
	: ${repo_dest:=$repo_name}

    # If you only want to mirror i686 packages, you can add
    # " --exclude=os/x86_64" after "--delete-after"
    # 
    # If you only want to mirror x86_64 packages, use "--exclude=os/i686"
    # If you want both i686 and x86_64, leave the following line as it is
    #
	RES=1
	TRIES=0
	while (($RES)); do
		TRIES=$(($TRIES+1))
    	echo ">> RETRY $TRIES: Syncing $repo_name to $SYNC_FILES/$repo_dest" | tee -a "$SYNC_LOGS/$LOG_FILE"
		mkdir -p "$SYNC_FILES/$repo_dest"
    	rsync -rtlvhHSP --delete-after --max-delete=1000 --log-file "$SYNC_LOGS/$LOG_FILE" "$SYNC_SERVER/$repo_name/" "$SYNC_FILES/$repo_dest"
		RES=$?
	done

	echo ">> Succeeded after $TRIES tries" | tee -a "$SYNC_LOGS/$LOG_FILE"

    # Create $repo.lastsync file with timestamp like "2007-05-02 03:41:08+03:00"
    # which may be useful for users to know when the repository was last updated
    date --rfc-3339=seconds > "$SYNC_FILES/$repo_dest.lastsync"

    # Sleep 5 seconds after each repository to avoid too many concurrent connections
    # to rsync server if the TCP connection does not close in a timely manner
    sleep 5 
  done
fi

# Insert another timestamp and close the log file
echo ">> ---" | tee -a "$SYNC_LOGS/$LOG_FILE"
echo ">> Finished sync on $( date --rfc-3339=seconds )" | tee -a "$SYNC_LOGS/$LOG_FILE"
echo "=============================================" | tee -a "$SYNC_LOGS/$LOG_FILE"
echo "" | tee -a "$SYNC_LOGS/$LOG_FILE"

# Remove the lock file and exit
rm -f "$SYNC_LOCK"
exit 0
