#!/usr/bin/env bash
# Reconciles stage-checkpoint.md STAGE_STATUS with file-system evidence
# before compaction. Called by PreCompact hook. Reads JSON from stdin.
# Exit 0 always — this hook must never block compaction.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

AUDIT_DIR="${CWD}/docs/audit/function-audit"
CHECKPOINT="${AUDIT_DIR}/stage-checkpoint.md"

# Guard: no checkpoint means no audit session or pre-first-write
if [ ! -f "$CHECKPOINT" ]; then
  exit 0
fi

# Guard: checkpoint must have a STAGE_STATUS line to update
if ! grep -q '^STAGE_STATUS:' "$CHECKPOINT" 2>/dev/null; then
  exit 0
fi

# --- Scan audit directory for stage output files ---

STATUS_PARTS=""

# Stage 0: design-decisions.md
if [ -f "${AUDIT_DIR}/stage0/design-decisions.md" ]; then
  STATUS_PARTS="${STATUS_PARTS} stage0=complete"
fi

# Stage 1: expect 3 .md files
if [ -d "${AUDIT_DIR}/stage1" ]; then
  STAGE1_COUNT=$(find "${AUDIT_DIR}/stage1" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
  if [ "$STAGE1_COUNT" -ge 3 ]; then
    STATUS_PARTS="${STATUS_PARTS} stage1=complete"
  elif [ "$STAGE1_COUNT" -gt 0 ]; then
    STATUS_PARTS="${STATUS_PARTS} stage1=partial:${STAGE1_COUNT}"
  fi
fi

# Stage 2: domain-*.md files
if [ -d "${AUDIT_DIR}/stage2" ]; then
  STAGE2_COUNT=$(find "${AUDIT_DIR}/stage2" -maxdepth 1 -name "domain-*.md" 2>/dev/null | wc -l)
  if [ "$STAGE2_COUNT" -gt 0 ]; then
    STATUS_PARTS="${STATUS_PARTS} stage2=complete:${STAGE2_COUNT}"
  fi
fi

# Stage 3: expect 4 .md files
if [ -d "${AUDIT_DIR}/stage3" ]; then
  STAGE3_COUNT=$(find "${AUDIT_DIR}/stage3" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
  if [ "$STAGE3_COUNT" -ge 4 ]; then
    STATUS_PARTS="${STATUS_PARTS} stage3=complete"
  elif [ "$STAGE3_COUNT" -gt 0 ]; then
    STATUS_PARTS="${STATUS_PARTS} stage3=partial:${STAGE3_COUNT}"
  fi
fi

# Synthesis: INDEX.md + SUMMARY.md both exist
if [ -f "${AUDIT_DIR}/INDEX.md" ] && [ -f "${AUDIT_DIR}/SUMMARY.md" ]; then
  STATUS_PARTS="${STATUS_PARTS} synthesis=complete"
fi

# Stage 4: review-responses.md
if [ -f "${AUDIT_DIR}/review/review-responses.md" ]; then
  STATUS_PARTS="${STATUS_PARTS} stage4=complete"
fi

# Stage 5: re-evaluation.md
if [ -f "${AUDIT_DIR}/review/re-evaluation.md" ]; then
  STATUS_PARTS="${STATUS_PARTS} stage5=complete"
fi

# If no stages detected, nothing to reconcile
if [ -z "$STATUS_PARTS" ]; then
  exit 0
fi

# --- Update checkpoint file ---

# Preserve preflight status from existing checkpoint
EXISTING_PREFLIGHT=""
if grep -q 'preflight=complete' "$CHECKPOINT" 2>/dev/null; then
  EXISTING_PREFLIGHT="preflight=complete"
fi

NEW_STATUS="STAGE_STATUS: ${EXISTING_PREFLIGHT}${STATUS_PARTS}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TMP="${CHECKPOINT}.precompact.tmp"

# Replace STAGE_STATUS line and update/append LAST_COMPACTION
sed "s|^STAGE_STATUS:.*|${NEW_STATUS}|" "$CHECKPOINT" > "$TMP"

if grep -q '^LAST_COMPACTION:' "$TMP" 2>/dev/null; then
  sed -i "s|^LAST_COMPACTION:.*|LAST_COMPACTION: ${TIMESTAMP}|" "$TMP"
else
  echo "LAST_COMPACTION: ${TIMESTAMP}" >> "$TMP"
fi

mv "$TMP" "$CHECKPOINT"

exit 0
