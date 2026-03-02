#!/usr/bin/env bash
set -euo pipefail

MODE="sync"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMMON_SRC="$ROOT_DIR/shared/solidity-function-audit/resources/common"
SOLO_STAGE_SRC="$ROOT_DIR/shared/solidity-function-audit/resources/solo/STAGE_PROMPTS.md"
TEAM_STAGE_SRC="$ROOT_DIR/shared/solidity-function-audit/resources/team/STAGE_PROMPTS.md"

SOLO_DST="$ROOT_DIR/plugins/solidity-function-audit/skills/solidity-function-audit/resources"
TEAM_DST="$ROOT_DIR/plugins/solidity-function-audit-team/skills/solidity-function-audit-team/resources"
CODEX_DST="$ROOT_DIR/codex/skills/solidity-function-audit/resources"

COMMON_FILES=(
  "FUNCTION_TEMPLATE.md"
  "EXAMPLE_OUTPUT.md"
  "REVIEW_PROMPTS.md"
  "VERIFICATION_PROMPTS.md"
)

copy_or_check() {
  local src="$1"
  local dst="$2"

  if [[ "$MODE" == "sync" ]]; then
    cp "$src" "$dst"
    return 0
  fi

  if ! cmp -s "$src" "$dst"; then
    echo "Out of sync: ${dst#$ROOT_DIR/}" >&2
    return 1
  fi
}

ensure_exists() {
  local p="$1"
  if [[ ! -f "$p" ]]; then
    echo "Missing required file: ${p#$ROOT_DIR/}" >&2
    exit 1
  fi
}

for file in "${COMMON_FILES[@]}"; do
  ensure_exists "$COMMON_SRC/$file"
  if [[ "$MODE" == "check" ]]; then
    ensure_exists "$SOLO_DST/$file"
    ensure_exists "$TEAM_DST/$file"
    ensure_exists "$CODEX_DST/$file"
  fi

  copy_or_check "$COMMON_SRC/$file" "$SOLO_DST/$file"
  copy_or_check "$COMMON_SRC/$file" "$TEAM_DST/$file"
  copy_or_check "$COMMON_SRC/$file" "$CODEX_DST/$file"
done

ensure_exists "$SOLO_STAGE_SRC"
ensure_exists "$TEAM_STAGE_SRC"
ensure_exists "$SOLO_DST/STAGE_PROMPTS.md"
ensure_exists "$TEAM_DST/STAGE_PROMPTS.md"
ensure_exists "$CODEX_DST/STAGE_PROMPTS.md"

copy_or_check "$SOLO_STAGE_SRC" "$SOLO_DST/STAGE_PROMPTS.md"
copy_or_check "$TEAM_STAGE_SRC" "$TEAM_DST/STAGE_PROMPTS.md"
copy_or_check "$SOLO_STAGE_SRC" "$CODEX_DST/STAGE_PROMPTS.md"

if [[ "$MODE" == "sync" ]]; then
  echo "Synced shared resources into Claude + Codex release folders."
else
  echo "Shared resources are in sync."
fi
