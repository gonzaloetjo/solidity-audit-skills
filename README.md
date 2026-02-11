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

Add the marketplace and install the plugin you want:

```bash
claude plugin marketplace add gonzaloetjo/solidity-audit-skills
```

**Team variant** (recommended) — agents communicate cross-domain findings, shared task list with dependency tracking:

```bash
claude plugin install solidity-function-audit-team@solidity-audit-skills
```

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your environment or `.claude/settings.json`.

**Solo variant** — lighter-weight, agents run independently in the background:

```bash
claude plugin install solidity-function-audit@solidity-audit-skills
```

Both require a Foundry project layout (`src/**/*.sol`).

## Usage

Start Claude Code in your Foundry project directory:

```bash
cd your-project
claude
```

Then run the skill:

```
/solidity-function-audit
# or
/solidity-function-audit-team
```

You can also pass a path to a specific project:

```
/solidity-function-audit /path/to/your/foundry/project
```

The skill will:

1. **Discover contracts** — scans `src/**/*.sol` for contracts, libraries, and functions
2. **Group into domains** — presents domain groupings for your confirmation
3. **Capture design decisions** — asks about intentional trade-offs (Stage 0)
4. **Run Slither** — if installed, runs static analysis automatically
5. **Launch parallel agents** — Stages 1-3 run concurrently, writing to `docs/audit/function-audit/`
6. **Present findings** — shows severity breakdown and asks to proceed to review
7. **Interactive review** — you classify each finding as BUG, DESIGN, DISPUTED, or DISCUSS (Stage 4)
8. **Re-evaluate disputes** — if any DISPUTED/DISCUSS items, an agent re-analyzes with your reasoning (Stage 5)

Output lands in `docs/audit/function-audit/`:

```
docs/audit/function-audit/
├── INDEX.md                    # Links to all files with finding counts
├── SUMMARY.md                  # Executive summary + action items
├── stage0/
│   ├── design-decisions.md     # Confirmed design intent
│   └── slither-findings.md     # Slither output (if available)
├── stage1/
│   ├── state-variables.md      # Storage variable map
│   ├── access-control.md       # Access control surface
│   └── external-calls.md       # External call map
├── stage2/
│   ├── domain-staking.md       # Per-function analysis (one file per domain)
│   ├── domain-rewards.md
│   └── ...
├── stage3/
│   ├── state-consistency.md    # Cross-domain state audit
│   ├── math-rounding.md        # Arithmetic + precision audit
│   └── reentrancy-trust.md     # Reentrancy + trust boundaries
└── review/
    ├── review-responses.md     # Your classifications
    └── re-evaluation.md        # Dispute re-analysis (if needed)
```

## Monitoring a Team Audit

The team variant runs multiple agents from a shared task list at `~/.claude/tasks/`. You can watch progress in real time with [claude-code-kanban](https://github.com/L1AD/claude-task-viewer) — a zero-config Kanban board that shows pending/in-progress/completed tasks, agent assignments, and dependency chains.

**Terminal 1 — Kanban board:**

```bash
npx claude-code-kanban
# Opens http://localhost:3456 in your browser
```

**Terminal 2 — Run the audit:**

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
cd your-project
claude
```

Then inside Claude: `/solidity-function-audit-team`

The env var is only needed in the terminal running Claude. To make it permanent:

```bash
echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' >> ~/.bashrc
source ~/.bashrc
```

The Kanban board will show Stage 1 tasks completing, Stage 2 domain audits unblocking and getting picked up by teammates, and Stage 3 cross-cutting tasks waiting on Stage 2. No configuration needed — it watches the filesystem directly.

**Keyboard shortcuts** in the Claude terminal for live teammate control:

| Key | Action |
|-----|--------|
| `Shift+Up/Down` | Select teammate |
| `Enter` | View teammate session |
| `Escape` | Interrupt teammate |
| `Ctrl+T` | Toggle task list overlay |

### Deep observability with hooks

For full visibility into what agents are actually doing — every tool call, file write, and message between teammates — see [claude-code-hooks-multi-agent-observability](https://github.com/disler/claude-code-hooks-multi-agent-observability). It captures 12 hook events and renders them as a real-time Vue dashboard with agent swim lanes and event timeline.

> **Security notice**: We audited this tool ([audit notes](https://github.com/disler/claude-code-hooks-multi-agent-observability)). There is no malware or data exfiltration in the default config, and its hooks won't conflict with this plugin's validation hooks (they run in parallel at different levels). However, **the server binds to `0.0.0.0` with wildcard CORS and no auth** — meaning anyone on your LAN can read all captured events, including source code. The `--summarize` flag also sends truncated event payloads to Anthropic's API for one-line summaries. Apply the fixes below before using it with proprietary code.

<details>
<summary>Setup and required security fixes</summary>

**Install** (clone it anywhere, it lives outside your project):

```bash
git clone https://github.com/disler/claude-code-hooks-multi-agent-observability
cd claude-code-hooks-multi-agent-observability
bun install        # needs Bun and uv (astral.sh) installed
```

**Required fixes before first use:**

1. Bind server to localhost only — edit `apps/server/src/index.ts`:

```typescript
// find Bun.serve({ ... }) and add hostname:
const server = Bun.serve({
  hostname: 'localhost',   // ADD THIS — default is 0.0.0.0
  port: parseInt(process.env.SERVER_PORT || '4000'),
  // ...
});
```

2. Restrict CORS — in the same file, replace `'*'` with the client origin:

```typescript
'Access-Control-Allow-Origin': 'http://localhost:5173',  // was '*'
```

3. Disable API summarization — in the `.claude/settings.json` you'll copy to your project, remove `--summarize` from all `send_event.py` commands to prevent truncated payloads being sent to Anthropic's API:

```bash
sed -i 's/ --summarize//g' .claude/settings.json
```

**Copy hooks into your Foundry project:**

```bash
cp -R .claude /path/to/your-foundry-project/
```

Edit the `source-app` value in the copied `settings.json`:

```bash
cd /path/to/your-foundry-project
sed -i 's/cc-hook-multi-agent-obvs/my-vault-audit/g' .claude/settings.json
```

**Run it** (three terminals):

```bash
# Terminal 1 — observability server + dashboard
cd claude-code-hooks-multi-agent-observability
./scripts/start-system.sh
# Server on :4000, dashboard on http://localhost:5173

# Terminal 2 — (optional) Kanban board for task state
npx claude-code-kanban

# Terminal 3 — run the audit
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
cd your-foundry-project
claude
# then: /solidity-function-audit-team
```

</details>

## License

MIT
