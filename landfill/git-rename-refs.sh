#!/bin/bash

SCOPE="$1"
REGEX="$2"
REPLACEMENT="$3"

set -x
git for-each-ref --format='%(objectname) %(refname)' "$SCOPE" | \
perl -ne '
  ($sha, $ref) = split;
  ($new = $ref) =~ s#'"$REGEX"'#'"$REPLACEMENT"'#;
  next if $new eq $ref;
  print "delete $ref\n";
  print "create $new $sha\n";
' | git update-ref --no-deref --stdin
