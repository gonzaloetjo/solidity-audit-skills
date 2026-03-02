#!/usr/bin/env bash
set -euo pipefail

# match-finding.sh <title1> <title2>
# Computes Jaccard similarity between two finding titles.
# Exit 0 if Jaccard >= 0.4, exit 1 otherwise. Prints score to stdout.

if [[ $# -ne 2 ]]; then
  echo "Usage: match-finding.sh <title1> <title2>" >&2
  exit 2
fi

title1="$1"
title2="$2"

awk -v t1="$title1" -v t2="$title2" '
BEGIN {
  # Lowercase
  t1 = tolower(t1)
  t2 = tolower(t2)

  # Tokenize t1 — split on non-alphanumeric
  n1 = split(t1, a1, /[^a-z0-9]+/)
  n2 = split(t2, a2, /[^a-z0-9]+/)

  # Build sets (use associative arrays)
  for (i = 1; i <= n1; i++) {
    if (a1[i] != "") set1[a1[i]] = 1
  }
  for (i = 1; i <= n2; i++) {
    if (a2[i] != "") set2[a2[i]] = 1
  }

  # Intersection
  inter = 0
  for (tok in set1) {
    if (tok in set2) inter++
  }

  # Union = |set1| + |set2| - |intersection|
  s1_size = 0
  for (tok in set1) s1_size++
  s2_size = 0
  for (tok in set2) s2_size++

  union = s1_size + s2_size - inter

  if (union == 0) {
    jaccard = 0.0
  } else {
    jaccard = inter / union
  }

  printf "%.2f\n", jaccard

  if (jaccard >= 0.4) exit 0
  else exit 1
}
'
