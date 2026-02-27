# Dual Release Guide (Claude + Codex)

This repository now supports two release artifacts from one source tree:

- Claude plugin releases (marketplace/plugin manifests)
- Codex skill releases (`codex/skills/...` folders)

## Directory Contract

- Claude release sources:
  - `.claude-plugin/marketplace.json`
  - `plugins/solidity-function-audit/`
  - `plugins/solidity-function-audit-team/`
- Codex release sources:
  - `codex/skills/solidity-function-audit/SKILL.md`
  - `codex/skills/solidity-function-audit/agents/openai.yaml`
  - `codex/skills/solidity-function-audit/resources/*`
- Shared resource source-of-truth:
  - `shared/solidity-function-audit/resources/common/`
  - `shared/solidity-function-audit/resources/solo/STAGE_PROMPTS.md`
  - `shared/solidity-function-audit/resources/team/STAGE_PROMPTS.md`

## Single Source of Truth

Canonical resource files live only under `shared/`. Release folders contain synchronized copies for packaging/runtime compatibility.

Sync copies into all release folders:

```bash
scripts/sync_shared_resources.sh
```

Verify nothing drifted:

```bash
scripts/sync_shared_resources.sh --check
```

## Versioning

Keep independent release tags even if content versions happen to match.

- Claude tags: `claude-vX.Y.Z`
- Codex tags: `codex-vX.Y.Z`

You may publish one platform without publishing the other.

## Release Checklist

### Claude release

1. Update plugin versions in:
- `.claude-plugin/marketplace.json`
- `plugins/solidity-function-audit/.claude-plugin/plugin.json`
- `plugins/solidity-function-audit-team/.claude-plugin/plugin.json`
2. Sync shared resources:
```bash
scripts/sync_shared_resources.sh
scripts/sync_shared_resources.sh --check
```
3. Validate plugin structure:
```bash
claude plugin validate .
```
4. Commit and tag:
```bash
git tag claude-vX.Y.Z
git push origin claude-vX.Y.Z
```

### Codex release

1. Update Codex skill metadata if needed:
- `codex/skills/solidity-function-audit/SKILL.md`
- `codex/skills/solidity-function-audit/agents/openai.yaml`
2. Sync shared resources:
```bash
scripts/sync_shared_resources.sh
scripts/sync_shared_resources.sh --check
```
3. Commit and tag:
```bash
git tag codex-vX.Y.Z
git push origin codex-vX.Y.Z
```

## Maintenance Rule

When updating audit logic:

- Update shared resources in `shared/solidity-function-audit/resources/` if the change is resource-level
- Run `scripts/sync_shared_resources.sh`
- Update platform entrypoints as needed:
  - Claude orchestration in `plugins/.../SKILL.md`
  - Codex orchestration in `codex/skills/solidity-function-audit/SKILL.md`

If a change is only runtime-specific (e.g., Claude teams API behavior), update only the affected platform.
