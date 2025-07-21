#!/hint/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh

ZPOOL_CREATE_OPTS=(
    -o cachefile=/etc/zfs/zpool.cache

    -o ashift=12
    -o autotrim=on
    -o feature@fast_dedup=enabled
    -o feature@block_cloning=enabled
    -o feature@empty_bpobj=enabled
    -O dnodesize=auto -O xattr=sa -O acltype=posixacl
    # -O compression=zstd-1  # 5231 MiB/s (5143 MiB/s)
    # -O compression=zstd-2  # 3790 MiB/s (4004 MiB/s)
    # -O compression=zstd-3  # 2550 MiB/s (2505 MiB/s)
    # -O compression=zstd-4  # 1538 MiB/s (1963 MiB/s)
    # -O compression=zstd-5  # 1300 MiB/s (1288 MiB/s)
    # -O compression=zstd-6  # 1158 MiB/s (1007 MiB/s)
    # -O compression=zstd-7  # 814 MiB/s (862 MiB/s)
    # -O compression=zstd-8  # 735 MiB/s (745 MiB/S)
    # -O compression=zstd-9  # 480 MiB/s (508 MiB/s)
    # -O compression=zstd-10  # 288 MiB/s (296 MiB/s)
    -O compression=zstd-11  # 207 MiB/s (220 MiB/s)
    -O checksum=sha256
    # -O dedup=sha256

    # -O recordsize=1M
    # -O special_small_blocks=256K

    -O atime=off
    -O relatime=off
    # -O overlay=on
    # -O readonly=off
    # -O sync=standard
    # -O redundant_metadata=all
    # -O volmode=full
    # -O primarycache=all
    # -O secondarycache=all
    # -O defcontext=none
    # -O rootcontext=none
)

BPOOL_CREATE_OPTS=(
    -o compatibility=grub2
    -o cachefile=/etc/zfs/zpool.cache

    -o ashift=12
    -o autotrim=on
    -o cachefile=/etc/zfs/zpool.cache
    -O dnodesize=legacy -O xattr=sa -O acltype=posixacl
    -O compression=lz4
    -O checksum=sha256

    -O atime=off
    -O relatime=off
)

zfs_allow_create() {
    local pool="$1"
    shift

    zfs allow -s @allops \
        allow,bookmark,change-key,clone,create,destroy,diff,hold,load-key,mount,promote,receive,release,rename,rollback,send,share,snapshot \
        "$pool"

    zfs allow -s @allprops \
        aclinherit,aclmode,acltype,atime,canmount,casesensitivity,checksum,compression,context,copies,dedup,defcontext,devices,dnodesize,encryption,exec,filesystem_limit,fscontext,keyformat,keylocation,logbias,mountpoint,nbmand,normalization,overlay,pbkdf2iters,primarycache,quota,readonly,recordsize,redundant_metadata,refquota,refreservation,relatime,reservation,rootcontext,secondarycache,setuid,sharenfs,sharesmb,snapdev,snapdir,snapshot_limit,special_small_blocks,sync,utf8only,version,volblocksize,volmode,volsize,vscan,xattr,zoned \
        "$pool"

    zfs allow -s @allquota \
        groupobjquota,groupobjused,groupquota,groupused,projectobjquota,projectobjused,projectquota,projectused,userobjquota,userobjused,userprop,userquota,userused \
        "$pool"

    if (( $# )); then
        zfs_allow_to "$pool" "$@"
    fi
}

zfs_allow_to() {
    local pool="$1"
    shift

    zfs allow "$@" \
        @allops,@allprops,@allquota \
        "$pool"
}

par1() {
    { local -; set +x; } &>/dev/null
    local -a cmd

    while (( $# )); do
        if [[ $1 == ::: ]]; then
            break
        fi
        cmd+=("$1")
        shift
    done

    parallel -j1 --tty "set -x; ${cmd[@]@Q}" "$@"
}
