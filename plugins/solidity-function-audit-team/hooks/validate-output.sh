#!/usr/bin/env bash
# Validates teammate output files when a task is marked completed.
# Called by TaskCompleted hook. Reads JSON from stdin.
# Exit 2 = blocking error (task stays incomplete, stderr fed to teammate).
# Exit 0 = validation passed.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
AUDIT_DIR="${CWD}/docs/audit/function-audit"

# Only validate if this is an audit session (audit directory exists)
if [ ! -d "$AUDIT_DIR" ]; then
  exit 0
fi

# Extract the output file path from the task description
# Task descriptions contain: "Write your COMPLETE analysis to the file: {path}"
TASK_DESC=$(echo "$INPUT" | jq -r '.task_description // empty')
if [ -z "$TASK_DESC" ]; then
  exit 0
fi

# Look for the output file path in the task description
OUTPUT_FILE=$(echo "$TASK_DESC" | grep -oP 'Write your COMPLETE analysis to the file: \K\S+' | head -1 || true)

if [ -z "$OUTPUT_FILE" ]; then
  # Not an analysis task, skip
  exit 0
fi

# Only validate files in the audit directory
case "$OUTPUT_FILE" in
  */docs/audit/function-audit/*) ;;
  *) exit 0 ;;
esac

# Validation 1: File exists and is non-empty
if [ ! -s "$OUTPUT_FILE" ]; then
  echo "Output validation failed: ${OUTPUT_FILE} is empty or does not exist. Write your analysis before marking the task complete." >&2
  exit 2
fi

# Validation 2: Contains at least one markdown section header
if ! grep -q '^## ' "$OUTPUT_FILE" 2>/dev/null; then
  echo "Output validation failed: ${OUTPUT_FILE} has no section headers (## ). Ensure output follows the markdown format." >&2
  exit 2
fi

# Determine which stage this file belongs to
case "$OUTPUT_FILE" in
  */stage2/*)
    # Validation 3: Stage 2 must have per-function or summary section
    if ! grep -qE '## (Per-Function Analysis|Summary of Findings|Summary|Cross-Cutting)' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 2 file ${OUTPUT_FILE} missing required sections (Per-Function Analysis, Summary of Findings, or Cross-Cutting)." >&2
      exit 2
    fi
    # Validation 4: Stage 2 must have at least one severity tag
    if ! grep -qE '\*\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 2 file ${OUTPUT_FILE} has no severity tags (**CRITICAL -- , **HIGH -- , **MEDIUM -- , **LOW -- , or **INFO -- )." >&2
      exit 2
    fi
    ;;
  */stage3/*)
    # Validation 4: Stage 3 must have at least one severity tag
    if ! grep -qE '\*\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 3 file ${OUTPUT_FILE} has no severity tags (**CRITICAL -- , **HIGH -- , **MEDIUM -- , **LOW -- , or **INFO -- )." >&2
      exit 2
    fi
    ;;
esac

exit 0
