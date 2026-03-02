#!/usr/bin/env bash
set -euo pipefail

# score.sh <results_dir> [--trials N] [--baseline FILE]
# Reads: <results_dir>/*/grade.json or <results_dir>/*/trial-N/grade.json
# Prints: markdown evaluation report to stdout

if [[ $# -lt 1 ]]; then
  echo "Usage: score.sh <results_dir> [--trials N] [--baseline FILE]" >&2
  exit 2
fi

RESULTS_DIR="$1"
TRIALS=0
BASELINE_FILE=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials)
      shift
      TRIALS="${1:-0}"
      ;;
    --baseline)
      shift
      BASELINE_FILE="${1:-}"
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Parse baseline.json if provided
# ---------------------------------------------------------------------------
declare -A BASELINE_AYI
HAS_BASELINE=false
if [[ -n "$BASELINE_FILE" && -f "$BASELINE_FILE" ]]; then
  HAS_BASELINE=true
  current_fixture=""
  while IFS= read -r line; do
    # Match fixture name line: "fixture-name": {
    if [[ "$line" =~ \"([a-z0-9-]+)\":\ *\{ ]]; then
      current_fixture="${BASH_REMATCH[1]}"
    fi
    # Match ayi value line: "ayi": 0.XX or "ayi": null
    if [[ -n "$current_fixture" && "$line" =~ \"ayi\":\ *([0-9.-]+) ]]; then
      BASELINE_AYI["$current_fixture"]="${BASH_REMATCH[1]}"
      current_fixture=""
    elif [[ -n "$current_fixture" && "$line" =~ \"ayi\":\ *null ]]; then
      BASELINE_AYI["$current_fixture"]="null"
      current_fixture=""
    fi
  done < "$BASELINE_FILE"
fi

# ---------------------------------------------------------------------------
# Helper: extract a numeric value from grade.json by key path
# ---------------------------------------------------------------------------
json_val() {
  local file="$1" key="$2"
  grep -o "\"${key}\": *[0-9.e+-]*" "$file" 2>/dev/null | head -1 | awk -F': *' '{print $2}'
}

json_str() {
  local file="$1" key="$2"
  grep -o "\"${key}\": *\"[^\"]*\"" "$file" 2>/dev/null | head -1 | awk -F'"' '{print $4}'
}

# ---------------------------------------------------------------------------
# Collect grade.json files
# ---------------------------------------------------------------------------

GRADE_FILES=()
declare -a FIXTURE_NAMES
declare -A FIX_SEEN

if [[ $TRIALS -gt 0 ]]; then
  # Multi-trial: <results_dir>/<fixture>/trial-N/grade.json
  while IFS= read -r f; do
    GRADE_FILES+=("$f")
  done < <(find "$RESULTS_DIR" -maxdepth 3 -path "*/trial-*/grade.json" | sort 2>/dev/null || true)
else
  # Single: <results_dir>/<fixture>/grade.json
  while IFS= read -r f; do
    GRADE_FILES+=("$f")
  done < <(find "$RESULTS_DIR" -maxdepth 2 -name "grade.json" | sort 2>/dev/null || true)
fi

if [[ ${#GRADE_FILES[@]} -eq 0 ]]; then
  echo "Error: no grade.json files found under ${RESULTS_DIR}" >&2
  exit 1
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------------------------------------------------------------------------
# Build per-fixture data
# ---------------------------------------------------------------------------

declare -A FIX_DR FIX_FPR FIX_SA FIX_VA FIX_AYI
declare -a FIXTURES_ORDER

if [[ $TRIALS -le 0 ]]; then
  # Single-trial mode
  for f in "${GRADE_FILES[@]}"; do
    fixture="$(json_str "$f" "fixture")"
    [[ -z "$fixture" ]] && fixture="$(basename "$(dirname "$f")")"

    dr="$(json_val "$f" "dr")"
    fpr="$(json_val "$f" "fpr")"
    sa="$(json_val "$f" "sa")"
    va="$(json_val "$f" "va")"
    ayi="$(json_val "$f" "ayi")"

    # Default to 0 if empty
    dr="${dr:-0}"; fpr="${fpr:-0}"; sa="${sa:-0}"; va="${va:-0}"; ayi="${ayi:-0}"

    FIX_DR["$fixture"]="$dr"
    FIX_FPR["$fixture"]="$fpr"
    FIX_SA["$fixture"]="$sa"
    FIX_VA["$fixture"]="$va"
    FIX_AYI["$fixture"]="$ayi"

    # Track unique fixture names in order
    if [[ -z "${FIX_SEEN[$fixture]+x}" ]]; then
      FIXTURES_ORDER+=("$fixture")
      FIX_SEEN["$fixture"]=1
    fi
  done
else
  # Multi-trial mode: group by fixture, compute best@k, median@k, pass^k
  declare -A TRIAL_AYIS TRIAL_DRS TRIAL_FPRS TRIAL_SAS TRIAL_VAS TRIAL_COUNTS
  declare -A FIX_SEEN_MULTI

  for f in "${GRADE_FILES[@]}"; do
    fixture="$(basename "$(dirname "$(dirname "$f")")")"
    [[ -z "$fixture" ]] && continue

    ayi="$(json_val "$f" "ayi")"
    dr="$(json_val "$f" "dr")"
    fpr="$(json_val "$f" "fpr")"
    sa="$(json_val "$f" "sa")"
    va="$(json_val "$f" "va")"

    ayi="${ayi:-0}"; dr="${dr:-0}"; fpr="${fpr:-0}"; sa="${sa:-0}"; va="${va:-0}"

    if [[ -z "${FIX_SEEN_MULTI[$fixture]+x}" ]]; then
      FIXTURES_ORDER+=("$fixture")
      FIX_SEEN_MULTI["$fixture"]=1
      TRIAL_AYIS["$fixture"]=""
      TRIAL_DRS["$fixture"]=""
      TRIAL_COUNTS["$fixture"]=0
    fi

    TRIAL_AYIS["$fixture"]+=" $ayi"
    TRIAL_DRS["$fixture"]+=" $dr"
    TRIAL_COUNTS["$fixture"]=$(( ${TRIAL_COUNTS[$fixture]} + 1 ))
  done
fi

# ---------------------------------------------------------------------------
# Aggregate stats with awk
# ---------------------------------------------------------------------------
awk_mean() {
  # args: space-separated floats, returns mean
  awk '{s=0; for(i=1;i<=NF;i++) s+=$i; if(NF>0) printf "%.4f", s/NF; else print "0.0000"}' <<< "$*"
}

awk_median() {
  # args: space-separated floats
  awk '{
    n=split($0,a," ")
    # simple sort
    for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(a[i]>a[j]){t=a[i];a[i]=a[j];a[j]=t}
    if(n%2==1) printf "%.4f", a[(n+1)/2]
    else printf "%.4f", (a[n/2]+a[n/2+1])/2
  }' <<< "$*"
}

awk_max() {
  awk '{m=$1; for(i=2;i<=NF;i++) if($i>m) m=$i; printf "%.4f", m}' <<< "$*"
}

# ---------------------------------------------------------------------------
# Print report
# ---------------------------------------------------------------------------

printf "# Evaluation Report\n\n"
printf "Generated: %s\n\n" "$TIMESTAMP"
printf "## Per-Fixture Results\n\n"

if [[ $TRIALS -le 0 ]]; then
  if [[ "$HAS_BASELINE" == true ]]; then
    printf "| Fixture | DR | FPR | SA | VA | AYI | Δ AYI | Verdict |\n"
    printf "|---------|------|------|------|------|------|-------|--------|\n"
  else
    printf "| Fixture | DR | FPR | SA | VA | AYI |\n"
    printf "|---------|------|------|------|------|------|\n"
  fi

  all_dr="" ; all_fpr="" ; all_sa="" ; all_va="" ; all_ayi=""
  baseline_pass=0 ; baseline_regress=0 ; baseline_total=0

  for fix in "${FIXTURES_ORDER[@]}"; do
    dr="${FIX_DR[$fix]:-0}"
    fpr="${FIX_FPR[$fix]:-0}"
    sa="${FIX_SA[$fix]:-0}"
    va="${FIX_VA[$fix]:-0}"
    ayi="${FIX_AYI[$fix]:-0}"

    if [[ "$HAS_BASELINE" == true ]]; then
      base_ayi="${BASELINE_AYI[$fix]:-}"
      if [[ -z "$base_ayi" || "$base_ayi" == "null" ]]; then
        delta_str="—"
        verdict_str="—"
      else
        delta=$(awk -v a="$ayi" -v b="$base_ayi" 'BEGIN { printf "%.4f", a - b }')
        delta_str=$(printf "%.2f" "$delta")
        verdict=$(awk -v d="$delta" 'BEGIN { print (d >= -0.1) ? "PASS" : "REGRESS" }')
        verdict_str="$verdict"
        baseline_total=$((baseline_total + 1))
        if [[ "$verdict" == "PASS" ]]; then
          baseline_pass=$((baseline_pass + 1))
        else
          baseline_regress=$((baseline_regress + 1))
        fi
      fi
      printf "| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %s | %s |\n" \
        "$fix" "$dr" "$fpr" "$sa" "$va" "$ayi" "$delta_str" "$verdict_str"
    else
      printf "| %s | %.2f | %.2f | %.2f | %.2f | %.2f |\n" \
        "$fix" "$dr" "$fpr" "$sa" "$va" "$ayi"
    fi

    all_dr="$all_dr $dr"
    all_fpr="$all_fpr $fpr"
    all_sa="$all_sa $sa"
    all_va="$all_va $va"
    all_ayi="$all_ayi $ayi"
  done

  if [[ "$HAS_BASELINE" == true && $baseline_total -gt 0 ]]; then
    printf "\nBaseline comparison: %d/%d fixtures PASS, %d REGRESS\n" \
      "$baseline_pass" "$baseline_total" "$baseline_regress"
  fi

  printf "\n## Aggregate\n\n"
  printf "| Metric | Value |\n"
  printf "|--------|-------|\n"

  mean_ayi=$(awk_mean $all_ayi)
  mean_dr=$(awk_mean $all_dr)
  mean_fpr=$(awk_mean $all_fpr)
  mean_sa=$(awk_mean $all_sa)
  mean_va=$(awk_mean $all_va)

  printf "| Mean AYI | %s |\n" "$mean_ayi"
  printf "| Mean DR  | %s |\n" "$mean_dr"
  printf "| Mean FPR | %s |\n" "$mean_fpr"
  printf "| Mean SA  | %s |\n" "$mean_sa"
  printf "| Mean VA  | %s |\n" "$mean_va"

else
  # Multi-trial output
  if [[ "$HAS_BASELINE" == true ]]; then
    printf "| Fixture | Trials | Best@%d | Median@%d | DR (mean) | Δ AYI | Verdict |\n" "$TRIALS" "$TRIALS"
    printf "|---------|--------|--------|----------|----------|-------|--------|\n"
  else
    printf "| Fixture | Trials | Best@%d | Median@%d | DR (mean) |\n" "$TRIALS" "$TRIALS"
    printf "|---------|--------|--------|----------|----------|\n"
  fi

  all_best="" ; all_median="" ; all_mean_dr=""
  baseline_pass=0 ; baseline_regress=0 ; baseline_total=0

  for fix in "${FIXTURES_ORDER[@]}"; do
    ayis="${TRIAL_AYIS[$fix]:-0}"
    drs="${TRIAL_DRS[$fix]:-0}"
    count="${TRIAL_COUNTS[$fix]:-0}"

    best=$(awk_max $ayis)
    median=$(awk_median $ayis)
    mean_dr=$(awk_mean $drs)

    if [[ "$HAS_BASELINE" == true ]]; then
      base_ayi="${BASELINE_AYI[$fix]:-}"
      if [[ -z "$base_ayi" || "$base_ayi" == "null" ]]; then
        delta_str="—"
        verdict_str="—"
      else
        delta=$(awk -v a="$median" -v b="$base_ayi" 'BEGIN { printf "%.4f", a - b }')
        delta_str=$(printf "%.2f" "$delta")
        verdict=$(awk -v d="$delta" 'BEGIN { print (d >= -0.1) ? "PASS" : "REGRESS" }')
        verdict_str="$verdict"
        baseline_total=$((baseline_total + 1))
        if [[ "$verdict" == "PASS" ]]; then
          baseline_pass=$((baseline_pass + 1))
        else
          baseline_regress=$((baseline_regress + 1))
        fi
      fi
      printf "| %s | %d | %s | %s | %s | %s | %s |\n" \
        "$fix" "$count" "$best" "$median" "$mean_dr" "$delta_str" "$verdict_str"
    else
      printf "| %s | %d | %s | %s | %s |\n" "$fix" "$count" "$best" "$median" "$mean_dr"
    fi

    all_best="$all_best $best"
    all_median="$all_median $median"
    all_mean_dr="$all_mean_dr $mean_dr"
  done

  if [[ "$HAS_BASELINE" == true && $baseline_total -gt 0 ]]; then
    printf "\nBaseline comparison: %d/%d fixtures PASS, %d REGRESS\n" \
      "$baseline_pass" "$baseline_total" "$baseline_regress"
  fi

  printf "\n## Multi-Trial Aggregate (k=%d)\n\n" "$TRIALS"
  printf "| Metric | Value |\n"
  printf "|--------|-------|\n"
  printf "| Mean Best@%d AYI  | %s |\n" "$TRIALS" "$(awk_mean $all_best)"
  printf "| Mean Median@%d AYI | %s |\n" "$TRIALS" "$(awk_mean $all_median)"
  printf "| Mean DR (mean)   | %s |\n" "$(awk_mean $all_mean_dr)"
fi
