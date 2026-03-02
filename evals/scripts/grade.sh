#!/usr/bin/env bash
set -euo pipefail

# grade.sh <output_dir> <fixture_dir>
# Reads: <output_dir>/INDEX.md, <output_dir>/verification/*.md, <fixture_dir>/GROUND_TRUTH.md
# Emits: grade.json to stdout

if [[ $# -ne 2 ]]; then
  echo "Usage: grade.sh <output_dir> <fixture_dir>" >&2
  exit 2
fi

OUTPUT_DIR="$1"
FIXTURE_DIR="$2"
SCRIPT_DIR="$(dirname "$0")"

INDEX_MD="${OUTPUT_DIR}/INDEX.md"
GROUND_TRUTH="${FIXTURE_DIR}/GROUND_TRUTH.md"

if [[ ! -f "$GROUND_TRUTH" ]]; then
  echo "Error: GROUND_TRUTH.md not found at ${GROUND_TRUTH}" >&2
  exit 1
fi

FIXTURE_NAME="$(basename "$FIXTURE_DIR")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# Parse GROUND_TRUTH.md YAML frontmatter
# Extract known_vulnerabilities and known_safe arrays using awk
# ---------------------------------------------------------------------------

# We'll parse the YAML frontmatter (between first --- markers) into shell arrays.
# YAML structure expected:
#   known_vulnerabilities:
#     - id: V001
#       severity: HIGH
#       title: "Some title"
#       contract: ContractName
#       function: functionName
#       location: "ContractName.sol:42"
#       verification_expected: CONFIRMED
#   known_safe:
#     - contract: ContractName
#       function: functionName

eval "$(awk '
BEGIN {
  in_front = 0
  after_front = 0
  vuln_idx = 0
  safe_idx = 0
  in_vuln = 0
  in_safe = 0
  in_vulns_block = 0
  in_safe_block = 0
}
/^---$/ {
  if (in_front == 0) { in_front = 1; next }
  else { in_front = 0; after_front = 1; next }
}
!in_front { next }
/^known_vulnerabilities:/ { in_vulns_block = 1; in_safe_block = 0; next }
/^known_safe:/ { in_safe_block = 1; in_vulns_block = 0; next }
/^[a-z]/ { in_vulns_block = 0; in_safe_block = 0 }
in_vulns_block && /^  - id:/ {
  vuln_idx++
  val = $0; sub(/.*id: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "GT_ID[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    severity:/ {
  val = $0; sub(/.*severity: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "GT_SEV[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    title:/ {
  val = $0; sub(/.*title: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val); gsub(/"/, "\\\\\"", val)
  print "GT_TITLE[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    contract:/ {
  val = $0; sub(/.*contract: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "GT_CONTRACT[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    function:/ {
  val = $0; sub(/.*function: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "GT_FUNCTION[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    location:/ {
  val = $0; sub(/.*location: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val); gsub(/"/, "\\\\\"", val)
  print "GT_LOCATION[" vuln_idx "]=\"" val "\""
}
in_vulns_block && /^    verification_expected:/ {
  val = $0; sub(/.*verification_expected: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "GT_VEXP[" vuln_idx "]=\"" val "\""
}
in_safe_block && /^  - contract:/ {
  safe_idx++
  val = $0; sub(/.*contract: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "SAFE_CONTRACT[" safe_idx "]=\"" val "\""
}
in_safe_block && /^    function:/ {
  val = $0; sub(/.*function: */, "", val); gsub(/^[ \t"]+|[ \t"]+$/, "", val)
  print "SAFE_FUNCTION[" safe_idx "]=\"" val "\""
}
END {
  print "GT_COUNT=" vuln_idx
  print "SAFE_COUNT=" safe_idx
}
' "$GROUND_TRUTH")"

# ---------------------------------------------------------------------------
# Parse INDEX.md "All Findings" table
# Format: | N | SEVERITY | Title | Location | ... |
# ---------------------------------------------------------------------------

declare -a IDX_SEV IDX_TITLE IDX_LOC
IDX_COUNT=0

if [[ -f "$INDEX_MD" ]]; then
  while IFS= read -r line; do
    # Parse table rows: | num | severity | title | location | ... |
    # Strip leading/trailing pipes and split on |
    row="${line#|}"
    row="${row%|}"
    IFS='|' read -r col1 col2 col3 col4 rest <<< "$row"
    # Trim whitespace
    col2="${col2#"${col2%%[![:space:]]*}"}"; col2="${col2%"${col2##*[![:space:]]}"}"
    col3="${col3#"${col3%%[![:space:]]*}"}"; col3="${col3%"${col3##*[![:space:]]}"}"
    col4="${col4#"${col4%%[![:space:]]*}"}"; col4="${col4%"${col4##*[![:space:]]}"}"
    IDX_COUNT=$((IDX_COUNT + 1))
    IDX_SEV[$IDX_COUNT]="$col2"
    IDX_TITLE[$IDX_COUNT]="$col3"
    IDX_LOC[$IDX_COUNT]="$col4"
  done < <(grep -E '^\| [0-9]+ \|' "$INDEX_MD" 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# Severity adjacency helper
# Returns 0 if within ±1 level, 1 otherwise
# Levels: CRITICAL=5, HIGH=4, MEDIUM=3, LOW=2, INFO=1
# ---------------------------------------------------------------------------
sev_level() {
  case "$1" in
    CRITICAL) echo 5 ;;
    HIGH)     echo 4 ;;
    MEDIUM)   echo 3 ;;
    LOW)      echo 2 ;;
    INFO)     echo 1 ;;
    *)        echo 0 ;;
  esac
}

sev_adjacent() {
  local a b
  a=$(sev_level "$1")
  b=$(sev_level "$2")
  local diff=$(( a - b ))
  [[ ${diff#-} -le 1 ]] && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Match each ground truth vulnerability against INDEX.md findings
# ---------------------------------------------------------------------------

declare -a MATCHED_IDX   # which IDX index matched each GT vuln (0=unmatched)
declare -a MATCHED_TITLE
declare -a MATCHED_JACCARD
declare -a MATCHED_SEV_MATCH
declare -a FINDING_USED   # track which IDX findings are "used"

for i in $(seq 1 $IDX_COUNT); do
  FINDING_USED[$i]=0
done

for g in $(seq 1 $GT_COUNT); do
  MATCHED_IDX[$g]=0
  MATCHED_TITLE[$g]=""
  MATCHED_JACCARD[$g]="null"
  MATCHED_SEV_MATCH[$g]="false"

  gt_contract="${GT_CONTRACT[$g]:-}"
  gt_function="${GT_FUNCTION[$g]:-}"
  gt_title="${GT_TITLE[$g]:-}"
  gt_sev="${GT_SEV[$g]:-}"

  best_i=0
  best_j=-1

  for i in $(seq 1 $IDX_COUNT); do
    [[ ${FINDING_USED[$i]} -eq 1 ]] && continue

    loc="${IDX_LOC[$i]:-}"
    # Step 1: Exact location match (location contains both contract and function)
    if [[ -n "$gt_contract" && -n "$gt_function" ]]; then
      if [[ "$loc" == *"$gt_contract"* && "$loc" == *"$gt_function"* ]]; then
        # Check severity adjacency
        if sev_adjacent "$gt_sev" "${IDX_SEV[$i]:-}"; then
          best_i=$i
          best_j=2.0  # sentinel for exact match
          break
        fi
      fi
    fi

    # Step 2: Fuzzy title match
    if [[ -n "$gt_title" ]]; then
      score=$("${SCRIPT_DIR}/match-finding.sh" "$gt_title" "${IDX_TITLE[$i]:-}" 2>/dev/null || true)
      if [[ -n "$score" ]]; then
        # Use awk for float comparison
        is_better=$(awk -v s="$score" -v b="$best_j" 'BEGIN { print (s > b) ? "1" : "0" }')
        if [[ "$is_better" == "1" ]]; then
          # Check severity adjacency gate
          if sev_adjacent "$gt_sev" "${IDX_SEV[$i]:-}"; then
            best_i=$i
            best_j="$score"
          fi
        fi
      fi
    fi
  done

  if [[ $best_i -gt 0 ]]; then
    MATCHED_IDX[$g]=$best_i
    MATCHED_TITLE[$g]="${IDX_TITLE[$best_i]:-}"
    if [[ "$best_j" == "2.0" ]]; then
      MATCHED_JACCARD[$g]="1.0"
    else
      MATCHED_JACCARD[$g]="$best_j"
    fi
    [[ "${IDX_SEV[$best_i]:-}" == "${gt_sev}" ]] && MATCHED_SEV_MATCH[$g]="true" || MATCHED_SEV_MATCH[$g]="false"
    FINDING_USED[$best_i]=1
  fi
done

# ---------------------------------------------------------------------------
# Compute TP, FN, FP
# ---------------------------------------------------------------------------
TP=0; FN=0; SEV_MATCH=0

for g in $(seq 1 $GT_COUNT); do
  if [[ ${MATCHED_IDX[$g]} -gt 0 ]]; then
    TP=$((TP + 1))
    [[ "${MATCHED_SEV_MATCH[$g]}" == "true" ]] && SEV_MATCH=$((SEV_MATCH + 1))
  else
    FN=$((FN + 1))
  fi
done

# FP: unmatched INDEX.md findings where location mentions a known_safe function
FP=0
for i in $(seq 1 $IDX_COUNT); do
  [[ ${FINDING_USED[$i]} -eq 1 ]] && continue
  loc="${IDX_LOC[$i]:-}"
  for s in $(seq 1 $SAFE_COUNT); do
    sc="${SAFE_CONTRACT[$s]:-}"
    sf="${SAFE_FUNCTION[$s]:-}"
    if [[ -n "$sf" && "$loc" == *"$sf"* ]]; then
      FP=$((FP + 1))
      break
    fi
  done
done

# ---------------------------------------------------------------------------
# Extract verification verdicts from verification/*.md files
# ---------------------------------------------------------------------------
declare -a V_IDS V_VERDICTS
V_COUNT=0

if [[ -d "${OUTPUT_DIR}/verification" ]]; then
  while IFS= read -r vfile; do
    verdict=$(grep -oE '\[(CONFIRMED|REFUTED|LIKELY-FP|INCONCLUSIVE)\]' "$vfile" 2>/dev/null | head -1 | tr -d '[]' || true)
    if [[ -n "$verdict" ]]; then
      V_COUNT=$((V_COUNT + 1))
      vbase="$(basename "$vfile" .md)"
      V_IDS[$V_COUNT]="$vbase"
      V_VERDICTS[$V_COUNT]="$verdict"
    fi
  done < <(find "${OUTPUT_DIR}/verification" -name "finding-*.md" 2>/dev/null | sort || true)
fi

# Compare verdicts against ground truth verification_expected
V_CORRECT=0
V_TOTAL=$V_COUNT
for v in $(seq 1 $V_COUNT); do
  vid="${V_IDS[$v]}"
  # Extract NNN from finding-NNN
  vnum="${vid#finding-}"
  # Find matching GT entry by index (finding-001 → V001, finding-002 → V002, etc.)
  for g in $(seq 1 $GT_COUNT); do
    gid="${GT_ID[$g]:-}"
    # Map V001 → 001
    gnum="${gid#V}"
    if [[ "$vnum" == "$gnum" ]]; then
      expected="${GT_VEXP[$g]:-}"
      [[ "${V_VERDICTS[$v]}" == "$expected" ]] && V_CORRECT=$((V_CORRECT + 1))
      break
    fi
  done
done

# ---------------------------------------------------------------------------
# Compute metrics (awk for float division)
# ---------------------------------------------------------------------------
compute_metric() {
  local num="$1" denom="$2"
  awk -v n="$num" -v d="$denom" 'BEGIN { if (d == 0) print "0.0"; else printf "%.4f", n/d }'
}

TOTAL_FOUND=$((TP + FN))
DR=$(compute_metric $TP $TOTAL_FOUND)
FPR=$(compute_metric $FP $((FP + TP)))
SA=$(compute_metric $SEV_MATCH $TP)
VA=$(compute_metric $V_CORRECT $V_TOTAL)
AYI=$(awk -v dr="$DR" -v fpr="$FPR" 'BEGIN { printf "%.4f", dr - fpr }')

# ---------------------------------------------------------------------------
# Emit grade.json
# ---------------------------------------------------------------------------

# Build details array
details_json=""
for g in $(seq 1 $GT_COUNT); do
  gid="${GT_ID[$g]:-}"
  matched="false"
  title_json="null"
  jaccard_json="null"
  sev_match_json="false"

  if [[ ${MATCHED_IDX[$g]} -gt 0 ]]; then
    matched="true"
    # Escape title for JSON
    t="${MATCHED_TITLE[$g]}"
    t="${t//\\/\\\\}"
    t="${t//\"/\\\"}"
    title_json="\"${t}\""
    jaccard_json="${MATCHED_JACCARD[$g]}"
    sev_match_json="${MATCHED_SEV_MATCH[$g]}"
  fi

  entry="    { \"ground_truth_id\": \"${gid}\", \"matched\": ${matched}, \"finding_title\": ${title_json}, \"jaccard\": ${jaccard_json}, \"severity_match\": ${sev_match_json} }"
  if [[ -z "$details_json" ]]; then
    details_json="$entry"
  else
    details_json="${details_json},
${entry}"
  fi
done

printf '{
  "fixture": "%s",
  "timestamp": "%s",
  "counts": { "tp": %d, "fn": %d, "fp": %d },
  "severity_matches": %d,
  "verification": { "correct": %d, "total": %d },
  "metrics": { "dr": %s, "fpr": %s, "sa": %s, "va": %s, "ayi": %s },
  "details": [
%s
  ]
}
' \
  "$FIXTURE_NAME" \
  "$TIMESTAMP" \
  "$TP" "$FN" "$FP" \
  "$SEV_MATCH" \
  "$V_CORRECT" "$V_TOTAL" \
  "$DR" "$FPR" "$SA" "$VA" "$AYI" \
  "$details_json"
