#!/bin/bash

pushd $BASEDIR

BASEDIR="$(pwd)"
COUNT="$1"
BASEBRANCH="${2:-master}"
OUTDIR="$HOME/devel/patches/export/$(basename $BASEDIR)"
TAGPREFIX="${3:-r}"
SEQ="$(seq 1 ${COUNT})"

echo "-- Verifying markup tags presence for prefix=\"${TAGPREFIX}\" and count=${COUNT}"

if ! git tag | grep -q ${TAGPREFIX}_0; then
	echo "-- Zero tag (${TAGPREFIX}_0 does not exist; creating at $BASEBRANCH"
	git tag "${TAGPREFIX}_0" "$BASEBRANCH"
fi

TAGS=( $(git tag | grep ${TAGPREFIX}) )
for point in $SEQ; do
	tag="${TAGS[$point]}"
	if ! [ "$tag" = "${TAGPREFIX}_${point}" ]; then
		echo " * tag \"${TAGPREFIX}_${point}\" not found; offending tag: \"$tag\""
		exit 1
	fi
done

mkdir -p "$OUTDIR/__tmp"

PATCHES=( $(git format-patch ${TAGPREFIX}_0..${TAGPREFIX}_$COUNT -o "$OUTDIR/__tmp") )
INDEX=0

echo "-- Exporting ${#PATCHES[@]} patches in $COUNT review-requests"

for point in $SEQ; do
	LABEL_T="${TAGPREFIX}_${point}"
	LABEL_P="${TAGPREFIX}_$(( ${point} - 1 ))"
	mkdir -p "${OUTDIR}/${LABEL_T}"

	COMMIT_COUNT=$(git rev-list ${LABEL_P}..${LABEL_T} | wc -l)
	echo " * writing ${COMMIT_COUNT} patches for review-request ${point}"

	DEST_INDEX=$(( ${INDEX} + ${COMMIT_COUNT} ))
	for (( ; ${INDEX} != ${DEST_INDEX} ; INDEX = ${INDEX} + 1 )); do
		mv "${PATCHES[$INDEX]}" "${OUTDIR}/${LABEL_T}"
	done
	if (( ${COMMIT_COUNT} > 1 )); then
		(
		pushd "${OUTDIR}/${LABEL_T}"
		tar -czf "patchset_${point}.tgz" *.patch
		rm -f *.patch
		popd
		) >/dev/null
	fi

	git diff ${BASEBRANCH}..$LABEL_P > $OUTDIR/$LABEL_T/abs.patch
	git diff      $LABEL_P..$LABEL_T > $OUTDIR/$LABEL_T/rel.patch
done

echo "-- Removing tags and temporary directory"
for point in 0 $SEQ; do
	git tag -d "${TAGPREFIX}_${point}"
done

rm -rf $OUTDIR/__tmp
popd

# vim: set ts=4 sw=4 tw=0 ft=sh :
