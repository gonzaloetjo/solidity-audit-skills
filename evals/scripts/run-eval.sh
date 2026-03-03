#!/usr/bin/env bash
set -euo pipefail

# run-eval.sh — Automated eval harness for solidity-function-audit-eval
# Usage:
#   run-eval.sh --fixture <name> [--trials N] [--model MODEL] [--max-budget-usd N.N]
#   run-eval.sh --all [--trials N] [--model MODEL] [--max-budget-usd N.N]
#   run-eval.sh --all --naive [--model MODEL]   # Raw model baseline (no pipeline)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$ROOT_DIR/evals/fixtures"
RESULTS_DIR="$ROOT_DIR/evals/results"
PLUGIN_DIR="$ROOT_DIR/plugins/solidity-function-audit-eval"

FIXTURE=""
ALL=false
TRIALS=1
MAX_BUDGET="12.0"
MAX_TURNS=200
MODEL=""
NAIVE=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture)
      shift; FIXTURE="${1:-}"
      ;;
    --all)
      ALL=true
      ;;
    --trials)
      shift; TRIALS="${1:-1}"
      ;;
    --model)
      shift; MODEL="${1:-}"
      ;;
    --naive)
      NAIVE=true
      ;;
    --max-budget-usd)
      shift; MAX_BUDGET="${1:-12.0}"
      ;;
    --max-turns)
      shift; MAX_TURNS="${1:-200}"
      ;;
    -h|--help)
      echo "Usage: run-eval.sh --fixture <name> [--trials N] [--model MODEL] [--max-budget-usd N.N]"
      echo "       run-eval.sh --all [--trials N] [--model MODEL] [--max-budget-usd N.N]"
      echo "       run-eval.sh --all --naive [--model MODEL]   # Raw model, no pipeline"
      echo ""
      echo "Options:"
      echo "  --fixture NAME       Run against a single fixture"
      echo "  --all                Run against all fixtures"
      echo "  --trials N           Number of trials per fixture (default: 1)"
      echo "  --model MODEL        Claude model to use (e.g. sonnet, opus, haiku,"
      echo "                       claude-sonnet-4-20250514, etc.) (default: CLI default)"
      echo "  --naive              Run raw model without audit pipeline (baseline comparison)"
      echo "  --max-budget-usd N   Budget cap per trial in USD (default: 12.0)"
      echo "  --max-turns N        Max agent turns per trial (default: 200)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

# Validate
if [[ "$ALL" == false && -z "$FIXTURE" ]]; then
  echo "Error: specify --fixture <name> or --all" >&2
  exit 2
fi

# Check claude CLI exists
if ! command -v claude &>/dev/null; then
  echo "Error: 'claude' CLI not found in PATH" >&2
  exit 1
fi

# Check plugin exists
if [[ ! -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]]; then
  echo "Error: eval plugin not found at $PLUGIN_DIR" >&2
  exit 1
fi

# Build fixture list
declare -a FIXTURE_LIST
if [[ "$ALL" == true ]]; then
  while IFS= read -r d; do
    name="$(basename "$d")"
    [[ -f "$d/GROUND_TRUTH.md" ]] && FIXTURE_LIST+=("$name")
  done < <(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
else
  if [[ ! -d "$FIXTURES_DIR/$FIXTURE" ]]; then
    echo "Error: fixture '$FIXTURE' not found at $FIXTURES_DIR/$FIXTURE" >&2
    exit 1
  fi
  FIXTURE_LIST=("$FIXTURE")
fi

# Build model args for claude CLI
MODEL_LABEL="default"
CLAUDE_MODEL_ARGS=""
if [[ -n "$MODEL" ]]; then
  CLAUDE_MODEL_ARGS="--model $MODEL"
  MODEL_LABEL="$MODEL"
fi

# Naive mode uses a different results subdirectory to keep runs separate
if [[ "$NAIVE" == true ]]; then
  RESULTS_DIR="$RESULTS_DIR/naive-${MODEL_LABEL}"
fi

echo "=== Eval Harness ==="
echo "Mode: $([ "$NAIVE" == true ] && echo "naive (raw model)" || echo "skill (full pipeline)")"
echo "Model: $MODEL_LABEL"
echo "Fixtures: ${FIXTURE_LIST[*]}"
echo "Trials: $TRIALS"
echo "Budget cap: \$${MAX_BUDGET}/trial"
echo ""

# Run function for one trial
run_trial() {
  local fixture_name="$1"
  local trial_num="$2"
  local fixture_dir="$FIXTURES_DIR/$fixture_name"
  local result_dir="$RESULTS_DIR/$fixture_name/trial-${trial_num}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  echo "--- ${fixture_name} trial ${trial_num} ---"
  echo "  Temp dir: $tmp_dir"

  # Copy fixture to temp dir
  cp -r "$fixture_dir"/* "$tmp_dir/"
  rm -rf "$tmp_dir/out" "$tmp_dir/cache" "$tmp_dir/lib"

  # Install forge-std
  echo "  Installing forge-std..."
  (cd "$tmp_dir" && git init -q && forge install foundry-rs/forge-std --no-git 2>/dev/null) || {
    echo "  Warning: forge install failed, continuing anyway" >&2
  }

  # Verify compilation
  if ! (cd "$tmp_dir" && forge build --force 2>/dev/null); then
    echo "  Error: fixture does not compile" >&2
    echo "  Temp dir preserved at: $tmp_dir"
    return 1
  fi

  # Invoke Claude
  local start_time
  start_time=$(date +%s)

  local stream_file="$tmp_dir/stream-output.jsonl"

  if [[ "$NAIVE" == true ]]; then
    # Naive mode: raw model prompt, no pipeline — asks Claude to audit and write findings
    # in the same directory structure so grade.sh can score it
    echo "  Running naive audit (raw model, no pipeline)..."
    local naive_prompt
    naive_prompt="$(cat <<'NAIVE_EOF'
You are a Solidity security auditor. Analyze all .sol files in the src/ directory of the project at $PROJECT_PATH for security vulnerabilities.

For each vulnerability you find, write a detailed finding. Then create an INDEX.md file at $OUTPUT_DIR/INDEX.md with this exact format:

# Audit Index

## All Findings

| # | Title | Severity | File | Function | Verdict |
|---|-------|----------|------|----------|---------|
| 1 | [Title] | [CRITICAL/HIGH/MEDIUM/LOW/INFO] | [contract.sol] | [functionName] | [ISSUE_FOUND/NEEDS_REVIEW/SOUND] |

Also create a SUMMARY.md at $OUTPUT_DIR/SUMMARY.md with a brief audit summary.

Rules:
- Only report real vulnerabilities with clear exploit paths
- Use severity levels: CRITICAL, HIGH, MEDIUM, LOW, INFO
- Verdict: ISSUE_FOUND for CRITICAL/HIGH, NEEDS_REVIEW for MEDIUM/LOW, SOUND for INFO
- Be precise about which contract and function each finding affects
- Write findings as markdown files in $OUTPUT_DIR/

Create the output directory first: mkdir -p $OUTPUT_DIR
NAIVE_EOF
)"
    # Substitute paths
    naive_prompt="${naive_prompt//\$PROJECT_PATH/$tmp_dir}"
    naive_prompt="${naive_prompt//\$OUTPUT_DIR/$tmp_dir/docs/audit/function-audit}"

    # shellcheck disable=SC2086
    env -u CLAUDECODE claude -p "$naive_prompt" \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      --max-turns "$MAX_TURNS" \
      --max-budget-usd "$MAX_BUDGET" \
      $CLAUDE_MODEL_ARGS \
      > "$stream_file" 2>"$tmp_dir/claude-stderr.log" || true
  else
    # Skill mode: full audit pipeline via eval plugin
    echo "  Running eval skill..."
    # shellcheck disable=SC2086
    env -u CLAUDECODE claude -p "/solidity-function-audit-eval $tmp_dir" \
      --plugin-dir "$PLUGIN_DIR" \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      --max-turns "$MAX_TURNS" \
      --max-budget-usd "$MAX_BUDGET" \
      $CLAUDE_MODEL_ARGS \
      > "$stream_file" 2>"$tmp_dir/claude-stderr.log" || true
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$(( end_time - start_time ))

  echo "  Duration: ${duration}s"

  # Check for output
  local output_dir="$tmp_dir/docs/audit/function-audit"
  if [[ ! -d "$output_dir" ]]; then
    echo "  Error: no audit output produced" >&2
    # Dump stderr for debugging
    if [[ -f "$tmp_dir/claude-stderr.log" ]]; then
      echo "  --- claude stderr ---"
      head -20 "$tmp_dir/claude-stderr.log" | sed 's/^/  /'
      echo "  ---"
    fi
    # Dump last few lines of stream output for clues
    if [[ -f "$stream_file" && -s "$stream_file" ]]; then
      echo "  --- stream tail ---"
      tail -5 "$stream_file" | sed 's/^/  /'
      echo "  ---"
    fi
    echo "  Temp dir preserved at: $tmp_dir"
    return 1
  fi

  # Copy output to results
  mkdir -p "$result_dir"
  cp -r "$output_dir"/* "$result_dir/" 2>/dev/null || true

  # Grade
  echo "  Grading..."
  "$SCRIPT_DIR/grade.sh" "$result_dir" "$fixture_dir" --duration-seconds "$duration" \
    > "$result_dir/grade.json" 2>/dev/null || {
    echo "  Warning: grading failed" >&2
  }

  # Extract cost from stream-json (look for cost/usage info in the last result message)
  local total_cost=""
  if [[ -f "$stream_file" ]]; then
    # stream-json has {"type":"result",...} at the end with cost info
    total_cost=$(grep -o '"total_cost_usd":[0-9.]*' "$stream_file" 2>/dev/null | tail -1 | awk -F: '{print $2}' || true)
  fi

  # Write cost.json
  printf '{\n  "duration_seconds": %d,\n  "cost_usd": %s,\n  "max_budget_usd": %s,\n  "max_turns": %d,\n  "model": "%s",\n  "mode": "%s"\n}\n' \
    "$duration" "${total_cost:-null}" "$MAX_BUDGET" "$MAX_TURNS" \
    "$MODEL_LABEL" "$([ "$NAIVE" == true ] && echo "naive" || echo "skill")" \
    > "$result_dir/cost.json"

  echo "  Results: $result_dir"

  # Cleanup
  rm -rf "$tmp_dir"
  echo "  Done."
}

# Main loop
TOTAL_PASS=0
TOTAL_FAIL=0

for fixture_name in "${FIXTURE_LIST[@]}"; do
  for trial in $(seq 1 "$TRIALS"); do
    if run_trial "$fixture_name" "$trial"; then
      TOTAL_PASS=$((TOTAL_PASS + 1))
    else
      TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    echo ""
  done
done

# Aggregate with score.sh
echo "=== Scoring ==="
"$SCRIPT_DIR/score.sh" "$RESULTS_DIR" --trials "$TRIALS"

echo ""
echo "=== Summary ==="
echo "Trials completed: $((TOTAL_PASS + TOTAL_FAIL)) ($TOTAL_PASS passed, $TOTAL_FAIL failed)"
echo "Results: $RESULTS_DIR"
