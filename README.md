# solidity-audit-skills

Claude Code plugin marketplace for Solidity smart contract auditing.

## Installation

```bash
# Add the marketplace
/plugin marketplace add gonzaloetjo/solidity-audit-skills

# Install individual plugins
/plugin install solidity-function-rationality@solidity-audit-skills
/plugin install solidity-function-rationality-team@solidity-audit-skills
```

## Skills

| Skill | Trigger | Description |
|-------|---------|-------------|
| **solidity-function-rationality** | `/solidity-function-rationality` | 3-stage parallelized per-function rationality analysis. Spawns background agents for foundation context, per-domain analysis, and cross-cutting audits. |
| **solidity-function-rationality-team** | `/solidity-function-rationality-team` | Agent team variant with inter-agent messaging, plan mode for Stage 2, and shared task list. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. |

## Choosing a Skill

- **Quick per-function audit** — use `solidity-function-rationality`
- **Deep audit with agent collaboration** — use `solidity-function-rationality-team`

## License

MIT
