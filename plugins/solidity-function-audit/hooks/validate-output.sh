#!/usr/bin/env bash
# Validates agent output files after subagent completion.
# Called by SubagentStop hook. Reads JSON from stdin.
# Exit 2 = blocking error (agent should retry).
# Exit 0 = validation passed.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
AUDIT_DIR="${CWD}/docs/audit/function-audit"

# Only validate if this is an audit session (audit directory exists)
if [ ! -d "$AUDIT_DIR" ]; then
  exit 0
fi

# Extract the agent transcript path to find what file was written
TRANSCRIPT=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Find the output file from the agent's Write tool calls in the transcript
# The transcript is JSONL — look for Write tool uses targeting the audit directory
OUTPUT_FILE=$(grep -o "\"file_path\":\"${AUDIT_DIR}[^\"]*\"" "$TRANSCRIPT" 2>/dev/null | tail -1 | sed 's/"file_path":"//;s/"//' || true)

if [ -z "$OUTPUT_FILE" ]; then
  # No Write to audit directory found — may be a non-audit agent, skip
  exit 0
fi

# Validation 1: File exists and is non-empty
if [ ! -s "$OUTPUT_FILE" ]; then
  echo "Output validation failed: ${OUTPUT_FILE} is empty or does not exist." >&2
  exit 2
fi

# Validation 2: Contains at least one markdown section header
if ! grep -q '^## ' "$OUTPUT_FILE" 2>/dev/null; then
  echo "Output validation failed: ${OUTPUT_FILE} has no section headers (## )." >&2
  exit 2
fi

# Determine which stage this file belongs to
case "$OUTPUT_FILE" in
  */stage2/*)
    # Validation 3: Stage 2 must have per-function or summary section
    if ! grep -qE '## (Per-Function Analysis|Summary of Findings|Summary|Cross-Cutting)' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 2 file ${OUTPUT_FILE} missing required sections." >&2
      exit 2
    fi
    # Validation 4: Stage 2 must have at least one severity tag
    if ! grep -qE '\*\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 2 file ${OUTPUT_FILE} has no severity tags." >&2
      exit 2
    fi
    ;;
  */stage3/*)
    # Validation 4: Stage 3 must have at least one severity tag
    if ! grep -qE '\*\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ' "$OUTPUT_FILE" 2>/dev/null; then
      echo "Output validation failed: Stage 3 file ${OUTPUT_FILE} has no severity tags." >&2
      exit 2
    fi
    ;;
esac

exit 0
