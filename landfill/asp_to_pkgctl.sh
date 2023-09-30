#!/bin/bash

. lib.sh || exit

ASP_URL="/srv/build/asp"
GITLAB_URL="https://gitlab.archlinux.org/archlinux/packaging/"
PKGBUILD_ROOT="$HOME/pkgbuild"
PKGBUILD_NEW_ROOT="$HOME/pkgbuild.new"
PKGBUILD_OLD_ROOT="$HOME/pkgbuild.old"

eval "$(globaltraps)"

declare -A CONVERT_FAIL
fail() {
	CONVERT_FAIL[$dir]="$*"
}

report() {
	if (( ${#CONVERT_FAIL[@]} )); then
		err "Failed to process ${#CONVERT_FAIL[@]} repositories:"
		for arg in "${!CONVERT_FAIL[@]}"; do
			say " * $arg: ${CONVERT_FAIL[$arg]}"
		done
		exit 1
	else
		log "All repositories processed"
	fi
}
ltrap report

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

function parse_remote() {
	local dir="$1" predicate="$2"
	declare -n n_remote="$3" 

	# find suitable remote or skip repo
	n_remote=
	git -C "$dir" config --get-regexp '^remote\..*\.url$' | while read key value; do
		if eval "$predicate"; then
			key="${key#remote.}"
			key="${key%.url}"
			n_remote="$key"
		fi
	done
	[[ $n_remote ]] || return 1
	return 0
}

function parse_remote_branches() {
	local dir="$1" remote="$2"
	declare -n n_remote_branches="$3" n_main_remote="$4" n_main_local="$5"

	# load remote branches
	n_remote_branches=()
	git -C "$dir" for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/$remote/**" \
		| grep -vE '/HEAD$' \
		| sort -u \
		| readarray -t n_remote_branches
	(( ${#n_remote_branches[@]} == 1 )) || return 1

	# derive "main" branch and pkgbase
	n_main_remote="${n_remote_branches[0]}"
	n_main_local="${n_remote_branches[0]#$remote/}"
	return 0
}

function pkgctl_clone_into() {
	local pkgbase="$1" destdir="$2"

	local basedir="$(dirname "$destdir")"
	local tmpdir="$basedir/.tmp.$$"

	if ! [[ -d "$destdir" ]]; then
		mkdir -p "$tmpdir"
		cd "$tmpdir"
		pkgctl repo clone "$pkgbase"
		mv "$pkgbase" -T "$destdir"
		rm -d "$tmpdir"
	fi
}
export -f pkgctl_clone_into

mkdir -p "$PKGBUILD_NEW_ROOT" "$PKGBUILD_OLD_ROOT"
ltrap "rm -rf '$PKGBUILD_NEW_ROOT'/.tmp.*"

# pre: clone repos
find "$PKGBUILD_ROOT" -type d -name .git -printf '%h\n' | while read dir; do
	[[ $dir != *.old ]] || { fail "skipping *.old"; continue; }

	dirname="${dir##*/}"
	cd "$dir"

	# find suitable remote or skip repo
	parse_remote "$dir" '[[ $value == $ASP_URL ]]' remote \
		|| continue
	# load remote branches and find "main" branch
	parse_remote_branches "$dir" "$remote" remote_branches main_remote main_local \
		|| { fail "${#remote_branches[@]} != 1 remote branches"; continue; }

	# derive pkgbase
	pkgbase="${main_remote##*/}"

	# clone replacement repo
	echo "$pkgbase"
	echo "$PKGBUILD_NEW_ROOT/$dirname"
done | parallel -N2 --bar pkgctl_clone_into

find "$PKGBUILD_ROOT" -type d -name .git -printf '%h\n' | while read dir; do
	[[ $dir != *.old ]] || { fail "skipping *.old"; continue; }

	dirname="${dir##*/}"
	cd "$dir"

	# find suitable remote or skip repo
	parse_remote "$dir" '[[ $value == $ASP_URL ]]' remote \
		|| continue
	# load remote branches and find "main" branch
	parse_remote_branches "$dir" "$remote" remote_branches main_remote main_local \
		|| { fail "${#remote_branches[@]} != 1 remote branches"; continue; }

	# derive pkgbase
	pkgbase="${main_remote##*/}"

	# XXX: assume PKGBUILD directory
	pkgbuild_dir="trunk"
	pkgbuild="$pkgbuild_dir/PKGBUILD"
	# check that we guessed $pkgbuild_dir correctly
	git ls-files --error-unmatch "$pkgbuild" &>/dev/null || { fail "could not find $pkgbuild"; continue; }

	# if HEAD is detached, turn it into a branch
	if ! git symbolic-ref -q HEAD &>/dev/null; then
		git checkout -b _head_
	fi
	# load all branches
	declare -a branches=()
	git for-each-ref --format '%(objectname) %(refname:lstrip=2)' 'refs/heads/**' | while read sha ref; do
		branches+=( "$ref" )
	done
	# load HEAD (always exists)
	HEAD="$(git symbolic-ref -q --short HEAD)"

	# verify whether we know how to process this repo
	for ref in "${branches[@]}"; do
		git log --format='%P' "$main_remote..$ref" | while read parents; do
			echo "$parents" | wc -w | read parents_nr
			if (( $parents_nr != 1 )); then
				fail "unimplemented - branch $ref has merge commits ($parents_nr != 1 parents)"
				continue 3
			fi
		done
	done 

	# verify that there are no changes outside guessed prefix
	for ref in "${branches[@]}"; do
		git log --format='' --name-only "$main_remote..$ref" \
			| { grep -vE "^$pkgbuild_dir/" ||:; } \
			| sort -u \
			| readarray -t changed_files
		if (( ${#changed_files[@]} )); then
			fail "unimplemented - branch $ref has changes outside of $pkgbuild_dir ($(join ', ' "${changed_files[@]}"))"
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
	( pkgctl_clone_into "$pkgbase" "$PKGBUILD_NEW_ROOT/$dirname" )
	new_dir="$PKGBUILD_NEW_ROOT/$dirname"

	# in the replacement repo, find suitable remote
	parse_remote "$new_dir" '[[ $value == $GITLAB_URL* ]]' new_remote \
		|| { fail "new: could not find remote"; continue; }
	# in the replacement repo, load remote branches and find "main" branch
	parse_remote_branches "$new_dir" "$new_remote" new_remote_branches new_main_remote new_main_local \
		|| { fail "new: ${#new_remote_branches[@]} != 1 remote branches"; continue; }

	# now the hard part -- map old->new commits
	for ref in "${branches[@]}"; do
		sha="$(git rev-parse --short --quiet "$ref")"
		base="$(git rev-parse --short --quiet "$(git merge-base "$sha" "$main_remote")")"
		new_base="$(map_commit "$dir" "$base" "$pkgbuild_dir" "$new_dir" "$new_main_remote")" || continue 2

		# map old->new ref
		case "$ref" in
		"$main_local") new_ref="$new_main_local" ;;
		*)             new_ref="$ref" ;;
		esac
		# map old->new HEAD
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

	log "$dirname: moving new/old repo: $new_dir -> $dir -> $PKGBUILD_OLD_ROOT/$dirname"
	mv "$dir" -T "$PKGBUILD_OLD_ROOT/$dirname"
	mv "$new_dir" -T "$dir"
done
