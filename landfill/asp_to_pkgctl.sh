#!/bin/bash

. lib.sh || exit

ASP_URL="/srv/build/asp"
GITLAB_URL="https://gitlab.archlinux.org/archlinux/packaging/"
PKGBUILD_ROOT="$HOME/pkgbuild"
PKGBUILD_NEW_ROOT="$HOME/pkgbuild.new"
PKGBUILD_OLD_ROOT="$HOME/pkgbuild.old"

declare -A CONVERT_FAIL
fail() {
	CONVERT_FAIL[$dir]="$*"
}

#git() {
#	/usr/bin/git -C "$dir" "$@"
#}

map_commit() {
	local old_dir="$1" old_tip="$2" old_subdir="$3"
	local new_dir="$4" new_tip="$5"

	{ git -C "$old_dir" log --format='%h %at %s' "$old_tip" -- "$old_subdir" ||:; } | while read old_sha old_time old_subject; do
		found_sha=
		found_time=
		found_subject=
		{ git -C "$new_dir" log --format='%h %at %s' "$new_tip" ||:; } | while read new_sha new_time new_subject; do
			if [[ $old_time != $new_time ]]; then
				continue
			fi

			if [[ $found_sha ]]; then
				fail "ref $ref: old tip $old_tip as $old_sha @ $old_time '$old_subject' matches more than one commit at new tip $new_tip ($found_sha @ $found_time '$found_subject' and $new_sha @ $new_time '$new_subject'"
				return 1
			fi

			found_sha="$new_sha"
			found_time="$new_time"
			found_subject="$new_subject"
		done

		if [[ $found_sha ]]; then
			break
		fi
	done

	if [[ $found_sha ]]; then
		log "$dirname: ref $ref: tip $old_tip as $old_sha '$old_subject' matched $found_sha '$found_subject'"
		echo "$found_sha"
		return 0
	fi
	fail "ref $ref: tip $old_tip did not match anything"
	return 1
}

rollback_files() (
	eval "$(ltraps)"

	local pkgbuild_dir="$1"

	# rollback pkgver=, pkgrel= updates
	local pkgbuild="$pkgbuild_dir/PKGBUILD"
	if ! git diff --quiet HEAD -- "$pkgbuild"; then
		local pkgbuild_diff="$(mktemp)"
		local pkgbuild_bak="$(mktemp -p "$pkgbuild_dir")"
		ltrap "rm -f '$pkgbuild_diff' '$pkgbuild_bak'"
		cp -a "$pkgbuild" "$pkgbuild_bak"
		(
		set -eo pipefail
		git diff "$pkgbuild" \
			| sed -r \
				-e ' /^\+(pkgver|pkgrel)=/d' \
				-e 's/^\-(pkgver|pkgrel)=/ \1=/' \
			>"$pkgbuild_diff"
		git checkout -f "$pkgbuild"
		git apply --recount --allow-empty "$pkgbuild_diff"
		) || { mv "$pkgbuild_bak" "$pkgbuild"; return 1; }
		lruntrap
	fi
	# rollback local modifications to .SRCINFO
	local srcinfo="$pkgbuild_dir/.SRCINFO"
	if git ls-files --error-unmatch "$srcinfo" &>/dev/null && \
	 ! git diff --quiet HEAD -- "$srcinfo"; then
		git reset "$srcinfo"
		git checkout -f "$srcinfo"
	elif ! git ls-files --error-unmatch "$srcinfo" &>/dev/null; then
		rm -f "$srcinfo"
	fi
)

eval "$(globaltraps)"

mkdir -p "$PKGBUILD_NEW_ROOT" "$PKGBUILD_OLD_ROOT"
ltrap "rm -df '$PKGBUILD_NEW_ROOT.tmp'"

# pre: clone repos
find "$PKGBUILD_ROOT" -type d -name .git -printf '%h\n' | while read dir; do
	[[ $dir != *.old ]] || { fail "skipping *.old"; continue; }

	dirname="${dir##*/}"
	cd "$dir"

	# find suitable remote and check if this is a candidate repo
	remote=
	{ git config --get-regexp '^remote\..*\.url$' || :; } | while read key value; do
		if [[ $value == $ASP_URL ]]; then
			key="${key#remote.}"
			key="${key%.url}"
			remote="$key"
		fi
	done
	[[ $remote ]] || continue

	# XXX: assume PKGBUILD directory
	pkgbuild_dir="trunk"
	pkgbuild="$pkgbuild_dir/PKGBUILD"
	# check that we guessed $pkgbuild_dir correctly
	git ls-files --error-unmatch "$pkgbuild" &>/dev/null || { fail "could not find $pkgbuild"; continue; }

	# load remote_branches
	remote_branches=()
	{
		git for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/$remote/**"
	} | sort -u | readarray -t remote_branches
	(( ${#remote_branches[@]} == 1 )) || { fail "${#remote_branches[@]} != 1 remote branches"; continue; }

	# derive "main" branch and pkgbase
	main_remote="${remote_branches[0]}"
	main_local="${remote_branches[0]#$remote/}"
	pkgbase="${main_remote##*/}"

	# clone replacement repo
	echo "$PKGBUILD_NEW_ROOT"
	echo "$pkgbase"
	echo "$dirname"
done | parallel -N3 --bar 'root={1}; pkgbase={2}; dirname={3}; if ! [[ -d "$root/$dirname" ]]; then mkdir -p "$root.tmp"; cd "$root.tmp"; pkgctl repo clone "$pkgbase"; mv "$pkgbase" "$root/$dirname"; fi'

find "$PKGBUILD_ROOT" -type d -name .git -printf '%h\n' | while read dir; do
	[[ $dir != *.old ]] || { fail "skipping *.old"; continue; }

	dirname="${dir##*/}"
	cd "$dir"

	# find suitable remote and check if this is a candidate repo
	remote=
	{ git config --get-regexp '^remote\..*\.url$' || :; } | while read key value; do
		if [[ $value == $ASP_URL ]]; then
			key="${key#remote.}"
			key="${key%.url}"
			remote="$key"
		fi
	done
	[[ $remote ]] || continue

	# XXX: assume PKGBUILD directory
	pkgbuild_dir="trunk"
	pkgbuild="$pkgbuild_dir/PKGBUILD"
	# check that we guessed $pkgbuild_dir correctly
	git ls-files --error-unmatch "$pkgbuild" &>/dev/null || { fail "could not find $pkgbuild"; continue; }

	# load remote branches
	remote_branches=()
	{
		git for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/$remote/**"
	} | sort -u | readarray -t remote_branches
	(( ${#remote_branches[@]} == 1 )) || { fail "${#remote_branches[@]} != 1 remote branches"; continue; }

	# derive package name and "main" branch
	main_remote="${remote_branches[0]}"
	main_local="${remote_branches[0]#$remote/}"
	pkgbase="${main_remote##*/}"

	# if HEAD is detached, turn it into a branch
	if ! git symbolic-ref -q HEAD &>/dev/null; then
		#branches[HEAD]="$(git rev-parse --verify --quiet HEAD)"
		git checkout -b _head_
	fi
	# get active branch (always exists)
	HEAD="$(git symbolic-ref -q --short HEAD)"
	# load all branches
	declare -A branches
	branches=()
	git for-each-ref --format '%(objectname) %(refname:lstrip=2)' 'refs/heads/**' | while read sha ref; do
		branches[$ref]="$sha"
	done

	# verify whether we know how to process this repo
	for ref in "${!branches[@]}"; do
		git log --format='%P' "$main_remote..$ref" | while read parents; do
			echo "$parents" | wc -w | read parents_nr
			if (( $parents_nr != 1 )); then
				fail "unimplemented - branch $ref has merge commits ($parents_nr != 1 parents)"
				continue 3
			fi
		done
	done 

	# verify that there are no changes outside guessed prefix
	for ref in "${!branches[@]}"; do
		git log --format='' --name-only "$main_remote..$ref" | sort -u | { grep -vE "^$pkgbuild_dir/" ||:; } | readarray -t changed_files
		if (( ${#changed_files[@]} )); then
			fail "unimplemented - branch $ref has changes outside of $pkgbuild_dir ($(join ',' "${changed_files[@]}"))"
			continue 2
		fi
	done

	# rollback .SRCINFO and pkgver=/pkgrel= changes to PKGBUILD
	rollback_files "$pkgbuild_dir"

	# commit all changes
	if ! git diff --quiet --cached HEAD; then
		log "$dir: committing index"
		git commit -m 'asp_to_pkgctl: WIP: index'
	fi
	if ! git diff --quiet HEAD; then
		log "$dir: committing worktree"
		git commit -a -m 'asp_to_pkgctl: WIP: unstaged'
	fi
	if git ls-files --others --exclude-standard | grep -q .; then
		log "$dir: committing untracked files"
		git add -A .
		git commit -m 'asp_to_pkgctl: WIP: untracked'
	fi

	git diff --quiet --cached HEAD || { fail "changes left in index"; continue; }
	git diff --quiet HEAD || { fail "changes left in worktree"; continue; }
	! git ls-files --others --exclude-standard | grep -q . || { fail "untracked files left in worktree"; continue; }

	# clone replacement repo
	new_dir="$PKGBUILD_NEW_ROOT/$dirname"
	if ! [[ -d "$new_dir" ]]; then (
		mkdir -p "$PKGBUILD_NEW_ROOT.tmp"
		cd "$PKGBUILD_NEW_ROOT.tmp"
		pkgctl repo clone "$pkgbase"
		mv "$pkgbase" "$new_dir"
	) fi

	# in the replacement repo, find suitable remote
	new_remote=
	{ git -C "$new_dir" config --get-regexp '^remote\..*\.url$' || :; } | while read key value; do
		if [[ $value == $GITLAB_URL* ]]; then
			key="${key#remote.}"
			key="${key%.url}"
			new_remote="$key"
		fi
	done
	[[ $new_remote ]] || { fail "new: could not find remote"; continue; }

	# in the replacement repo, load remote branches
	new_remote_branches=()
	{
		git -C "$new_dir" for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/$remote/**"
	} | grep -v '/HEAD$' | sort -u | readarray -t new_remote_branches
	(( ${#new_remote_branches[@]} == 1 )) || { fail "new: ${#new_remote_branches[@]} != 1 remote branches"; continue; }

	# derive "main" branch
	new_main_remote="${new_remote_branches[0]}"
	new_main_local="${new_remote_branches[0]#$new_remote/}"

	# now the hard part -- map old->new commits
	for ref in "${!branches[@]}"; do
		sha="$(git rev-parse --verify --quiet "$ref")"
		base="$(git merge-base "$sha" "$main_remote")"
		new_base="$(map_commit "$dir" "$(git rev-parse --short "$base")" "$pkgbuild_dir" "$new_dir" main)" || continue 2

		new_ref=$ref
		if [[ $ref == $main_local ]]; then
			new_ref=$new_main_local
		fi
		if [[ $ref == $HEAD ]]; then
			new_HEAD="$new_ref"
		fi

		if [[ $base != $sha ]]; then
			log "$dirname: copying branch $ref ($base..$sha) -> $new_ref (onto $new_base)"
			git -C "$new_dir" fetch "$dir" "$ref"
			git -C "$new_dir" rebase -Xsubtree="$pkgbuild_dir" --onto "$new_base" "$base" "$sha" || { fail "failed to rebase $ref"; continue 2; }
			#|| { log "Failed to rebase, running shell, finish rebase and exit with 0 if OK or 1 to abort"; $SHELL; } 
			git -C "$new_dir" checkout -B "$new_ref"
		else
			git -C "$new_dir" checkout -B "$new_ref" "$new_base"
		fi
	done

	log "$dirname: new: checking out head branch $new_HEAD"
	git -C "$new_dir" checkout "$new_HEAD"
	if [[ "$new_HEAD" == _head_ ]]; then
		log "$dirname: new: head branch is fake, detaching"
		git -C "$new_dir" checkout --detach
		git -C "$new_dir" branch -D _head_
	fi
	if [[ "$(git -C "$new_dir" log -1 --format='%s')" == "asp_to_pkgctl: WIP: untracked" ]]; then
		log "$dirname: new: undoing fake commit with untracked files"
		git -C "$new_dir" reset --mixed HEAD~
	fi
	if [[ "$(git -C "$new_dir" log -1 --format='%s')" == "asp_to_pkgctl: WIP: unstaged" ]]; then
		log "$dirname: new: undoing fake commit with unstaged files"
		git -C "$new_dir" reset --mixed HEAD~
	fi
	if [[ "$(git -C "$new_dir" log -1 --format='%s')" == "asp_to_pkgctl: WIP: index" ]]; then
		log "$dirname: new: undoing fake commit with staged files"
		git -C "$new_dir" reset --soft HEAD~
	fi
	git -C "$new_dir" update-ref -d FETCH_HEAD ||:
	git -C "$new_dir" gc-now

	log "$dirname: moving old repo: $dir -> $PKGBUILD_OLD_ROOT/$dirname"
	mv "$dir" -T "$PKGBUILD_OLD_ROOT/$dirname"
	log "$dirname: moving new repo: $new_dir -> $dir"
	mv "$new_dir" -T "$dir"
done

log "fails:"
for arg in "${!CONVERT_FAIL[@]}"; do
	say " * $arg: ${CONVERT_FAIL[$arg]}"
done
