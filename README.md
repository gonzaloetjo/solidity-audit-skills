# solidity-audit-skills

Function-by-function security audit of your Solidity contracts, powered by Claude Code agents.

- Captures design decisions before the audit — trade-offs don't get flagged as bugs
- Parallel agents grouped by domain — one agent per domain, all domains run concurrently
- Interactive post-audit review — classify findings, dispute false positives, get re-evaluation
- Structured markdown output with per-domain files, an index, and a summary

## What It Catches

| Severity | Function | Finding |
|----------|----------|---------|
| CRITICAL | `withdraw()` | Missing reentrancy guard allows drain via callback before balance update |
| CRITICAL | `setOracle()` | No access control — any caller can replace the price oracle |
| WARNING | `deposit()` | Underflow revert produces generic `Panic(0x11)` instead of custom error |
| INFO | `_stakeToShares()` | Rounding direction correctly protocol-favorable (DOWN on deposit) |

<details>
<summary>Full per-function analysis format</summary>

Each function gets a standalone analysis block. Here's a trimmed example from a staking vault audit:

### deposit(uint256 minShares)

- **Rationale**: Entry point for users to deposit native token and receive LST shares. Must correctly convert deposited stake to shares at the current exchange rate, protect against sandwich/frontrunning via slippage, and maintain share supply/pool accounting invariants.

- **State mutations**:
  - `_mint(msg.sender, shares)` -- increases `totalSupply()` and `balanceOf(msg.sender)` by `shares`
  - `address(this).balance` is implicitly increased by `msg.value` at the start of the call

- **Dependencies**:
  - Reads: `getTotalPooledStake()`, `totalSupply()`, `INITIAL_SHARES_OFFSET`
  - Calls: `_stakeToShares(msg.value, preDepositStake)`, `_mint(msg.sender, shares)`
  - Modifiers: `nonReentrant`, `whenNotPaused`

- **Findings**:

  1. **WARNING -- Underflow revert acts as implicit insolvency guard**. The subtraction `getTotalPooledStake() - msg.value` will revert with arithmetic underflow if `getTotalPooledStake() < msg.value`. The revert reason will be a generic `Panic(0x11)` rather than a descriptive custom error.

  2. **INFO -- Zero-share deposit protection**. `if (shares == 0) revert StakingVault__InvalidAmount()` prevents dust deposits that produce zero shares.

  3. **INFO -- Slippage protection**. `minShares > 0 && shares < minShares` check allows callers to skip by passing 0.

- **Verdict**: **SOUND**

</details>

## How It Works

| Stage | What happens | Mode | Output |
|-------|-------------|------|--------|
| 0. Design decisions | Extract + confirm developer intent | Interactive | `stage0/` |
| 0.5 Slither | Static analysis (if installed) | Orchestrator | `stage0/slither-findings.md` |
| 1. Foundation | Map state variables, access control, external calls | Agents (parallel) | `stage1/` |
| 2. Domain audit | Per-function analysis grouped by domain | Agents (parallel) | `stage2/domain-*.md` |
| 3. Cross-cutting | Reentrancy paths, state consistency, math/rounding | Agents (parallel) | `stage3/` |
| 4. Human review | Classify findings: BUG, DESIGN, DISPUTED, DISCUSS | Interactive | `review/` |
| 5. Re-evaluation | Re-analyze disputed findings with developer context | Agent (conditional) | `review/` |

```
  Stage 0          ┌──────────────────┐
  interactive      │  Design Decisions │
                   └────────┬─────────┘
                            │
  Slither          ┌────────┴─────────┐
  if installed     │  Static Analysis  │
                   └────────┬─────────┘
                            │
                ┌───────────┼───────────┐
                ▼           ▼           ▼
  Stage 1    ┌──────┐  ┌──────┐  ┌──────────┐
  3 agents   │State │  │Access│  │ External │
             │ Vars │  │ Ctrl │  │  Calls   │
             └──┬───┘  └──┬───┘  └────┬─────┘
                └──────────┼──────────┘
                           │
               ┌───────────┼───────────┐
               ▼           ▼           ▼
  Stage 2   ┌──────┐  ┌──────┐  ┌──────────┐
  N agents  │Dom A │  │Dom B │  │ Dom ...  │
            └──┬───┘  └──┬───┘  └────┬─────┘
               └──────────┼──────────┘
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
  Stage 3  ┌───────┐ ┌────────┐ ┌──────────┐
  3 agents │ State │ │ Math & │ │Reentrancy│
           │Consist│ │Rounding│ │ & Trust  │
           └──┬────┘ └───┬────┘ └────┬─────┘
              └───────────┼──────────┘
                          │
  Synthesis    ┌──────────┴──────────┐
               │ INDEX.md + SUMMARY  │
               └──────────┬──────────┘
                          │
  Stage 4      ┌──────────┴──────────┐
  interactive  │    Human Review     │
               │ BUG/DESIGN/DISPUTED │
               └──────────┬──────────┘
                          │
  Stage 5      ┌──────────┴──────────┐
  conditional  │   Re-Evaluation     │
               └──────────┬──────────┘
                          ▼
               Final SUMMARY.md
```

All output goes to `docs/audit/function-audit/`.

## Slither Integration

If [Slither](https://github.com/crytic/slither) is installed (`pip install slither-analyzer`), it runs automatically before agents start. Agents cross-reference their manual analysis with Slither's automated detections — confirming findings, identifying false positives, and noting what Slither missed.

## Solo vs Team

Both variants run the same 6-stage pipeline (Stage 0 → 1 → 2 → 3 → 4 → 5). Stages 0, 4, and 5 are interactive and identical in both. The difference is how Stages 1-3 run:

The **team variant** (`/solidity-function-audit-team`) gives you control over the analysis pipeline:
- Agents self-schedule from a shared task list with dependency tracking
- Stage 2 agents share their analysis plan with the lead before executing
- Agents message each other about cross-domain findings (CRITICAL only)
- Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

The **solo variant** (`/solidity-function-audit`) is lighter-weight:
- Agents run in the background and write results directly
- No inter-agent messaging

## Installation

From your terminal:

```bash
# Add the marketplace
claude plugin marketplace add gonzaloetjo/solidity-audit-skills

# Install a plugin
claude plugin install solidity-function-audit@solidity-audit-skills
# or
claude plugin install solidity-function-audit-team@solidity-audit-skills
```

Or from inside a Claude Code session:

```
/plugin marketplace add gonzaloetjo/solidity-audit-skills
/plugin install solidity-function-audit-team@solidity-audit-skills
```

Then start a session in your Foundry project and run `/solidity-function-audit` or `/solidity-function-audit-team`.

Requires a Foundry project layout (`src/**/*.sol`). The team variant requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## License

MIT
