# Claude Code Agent Teams — Reference Guide

## 1. Team Visualization

### claude-code-kanban (Recommended)

Zero-config Kanban board watching `~/.claude/tasks/`. Real-time task cards with agent assignment, dependencies, progress bars.

```bash
npx claude-code-kanban  # launches on port 3456
```

- Three-column board: Pending → In Progress → Completed
- Color-coded agent assignment, dependency info
- Clicking a task opens detail panel with note field Claude can read
- Observation-only — Claude Code owns the task state

Source: [NikiforovAll/claude-task-viewer](https://github.com/L1AD/claude-task-viewer)

### claude-code-hooks-multi-agent-observability

Full observability capturing every tool call, session event, and subagent interaction. Vue dashboard with event timeline and activity pulse chart.

Architecture: `Claude Agents → Hook Scripts (Python/uv) → HTTP POST → Bun Server → SQLite → WebSocket → Vue 3 Client`

12 event types captured: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `Notification`, `SessionStart`, `SessionEnd`, `Stop`, `SubagentStart`, `SubagentStop`, `PermissionRequest`, `PreCompact`.

Source: [disler/claude-code-hooks-multi-agent-observability](https://github.com/disler/claude-code-hooks-multi-agent-observability)

### Claude Squad

TUI replacing raw tmux management. Session list with status indicators, diff tabs, auto-accept mode. 6k+ GitHub stars.

```bash
curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash
```

- Automatic git worktree isolation per task
- Background task execution
- Integrated commit and push workflows

Source: [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad)

### Official Built-in Modes

**In-process mode (default):** All teammates in your main terminal. `Shift+Up/Down` to select teammate, `Enter` to view session, `Escape` to interrupt, `Ctrl+T` to toggle task list.

**Split-pane mode:** Each teammate gets its own pane (requires tmux or iTerm2).

```json
{ "teammateMode": "tmux" }
```

Or force in-process: `claude --teammate-mode in-process`

### Other Tools

| Tool | Description | Source |
|------|-------------|--------|
| Vibe Kanban | Agent-agnostic Kanban with parallel worktree execution, PR creation | [BloopAI/vibe-kanban](https://github.com/BloopAI/vibe-kanban) |
| Claude Code Board | Web-based multi-instance management with WebSocket chat | [cablate/Claude-Code-Board](https://github.com/cablate/Claude-Code-Board) |
| Claude Code Agentrooms | Desktop app for multi-agent orchestration via @mentions | [claudecode.run](https://claudecode.run/) |
| Dev-Agent-Lens | OpenTelemetry proxy for raw prompt/tool/cost tracing | [Teraflop-Inc/dev-agent-lens](https://github.com/Teraflop-Inc/dev-agent-lens) |

### Recommended Setup

tmux split panes (live terminal output) + `claude-code-kanban` in browser (task overview) + `claude-code-hooks-multi-agent-observability` (deep debugging when needed).

---

## 2. Efficient Team Usage

### When to Use Teams

| Approach | Best For | Cost | Coordination |
|----------|----------|------|--------------|
| Subagents | Focused tasks, result-only reporting | Lower | Report to caller only |
| Agent Teams | Complex work needing discussion/collaboration | Higher | Shared task list, peer messaging |
| Git Worktrees | Fully independent parallel work | Lowest | Manual merge at end |

**Good team use cases:** Research/review with competing perspectives, new modules with file-level isolation, debugging with competing hypotheses, cross-layer changes (frontend/backend/tests).

**Avoid teams for:** Sequential tasks with many dependencies, same-file edits, simple/routine tasks, small changes.

### Cost Management

| Configuration | Approximate Token Cost |
|---------------|----------------------|
| Solo session | ~200k tokens |
| 3 subagents | ~440k tokens |
| 3-person agent team | ~800k tokens |
| Agent teams with plan mode | ~7x standard session cost |

**Model selection:**
- **Opus for lead** — complex reasoning, coordination decisions
- **Sonnet for teammates** — balances capability and cost for implementation
- **Haiku for exploration subagents** — fast, cheap codebase searches

This reduces cost 60-80% vs Opus for everything.

### Key Recommendations

1. **2-4 teammates max** — coordination overhead scales poorly beyond this
2. **Plan first, team second** — ~10k tokens planning vs 500k+ for a misdirected team
3. **File/directory ownership** — the #1 rule to prevent conflicts
4. **5-6 tasks per teammate** — keeps everyone productive without excessive coordination
5. **Use delegate mode** (`Shift+Tab`) — keeps the lead coordinating, not implementing
6. **Use `TaskCompleted` hooks** — quality gates that run tests before allowing task completion
7. **Direct messages, not broadcasts** — broadcasts cost scales linearly with team size
8. **Clean up teams when done** — active teammates continue consuming tokens

### Quality Gate Hooks

```json
{
  "hooks": {
    "TaskCompleted": [{
      "hooks": [{
        "type": "command",
        "command": "./scripts/verify-task-complete.sh"
      }]
    }]
  }
}
```

Exit with code 2 from the hook to prevent completion and send feedback.

`TeammateIdle` hook runs when a teammate is about to go idle — exit with code 2 to send feedback and keep them working.

### Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `mode: "plan"` deadlocks | Use `mode: "bypassPermissions"` + prompt-based planning |
| Lead implements instead of delegating | Use delegate mode (`Shift+Tab`) |
| Context compaction destroys team state | Keep sessions shorter, or use [Cozempic](https://github.com/junaidtitan/cozempic). See [#23620](https://github.com/anthropics/claude-code/issues/23620) |
| File conflicts from concurrent edits | Structure work so each teammate owns distinct files |
| Teammates forget to mark tasks complete | Monitor output files, manually mark done if needed |
| Vague spawn prompts | Include file paths, constraints, expected output, done criteria |
| Teammates in delegate mode lose tools | Known bug [#24073](https://github.com/anthropics/claude-code/issues/24073), [#24307](https://github.com/anthropics/claude-code/issues/24307) |
| `replace_all` collapsing lines | Always check results after bulk replacements |

### Anthropic's C Compiler Lessons (16 parallel agents, 100k lines of Rust)

- Testing is the primary communication mechanism between agents
- Design for agent cognition — grep-friendly error formats, pre-computed statistics
- Use oracles (reference implementations) for parallel decomposition
- Include `--fast` flags that run 1-10% random samples to prevent agents wasting hours on full suites
- File locking via task creation prevents race conditions
- Specialized cleanup agents are valuable (dedup, optimize, improve idioms)

Source: [Building a C compiler with parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler)

---

## 3. Plan Mode in Teams

### How It Works

1. Teammate spawned with `plan_mode_required` operates read-only (Read, Grep, Glob, Bash)
2. Teammate calls `ExitPlanMode` → sends `plan_approval_request` to lead
3. Lead receives JSON: `{"type": "plan_approval_request", "from": "architect", "requestId": "abc-123", "content": "<plan>"}`
4. Lead responds via `SendMessage` with `type: "plan_approval_response"`:
   - Approve: `{"type": "plan_approval_response", "request_id": "abc-123", "recipient": "architect", "approve": true}`
   - Reject: `{"type": "plan_approval_response", "request_id": "abc-123", "recipient": "architect", "approve": false, "content": "Add error handling"}`
5. Approved → teammate exits plan mode. Rejected → teammate revises and resubmits.

**Who approves:** The team lead agent decides autonomously. Influence via prompt criteria ("only approve plans that include test coverage").

### The Deadlock Problem

Messages queue when the lead is mid-turn. `plan_approval_request` sits in queue → teammate blocks indefinitely → deadlock.

Contributing factors:
- Mailbox polling only activates between conversation turns ([#24108](https://github.com/anthropics/claude-code/issues/24108))
- Messages can queue even when agent is not busy ([#11106](https://github.com/anthropics/claude-code/issues/11106))

### Ways to Set Plan Mode

| Method | Works For | Status |
|--------|-----------|--------|
| Natural language instruction to lead | Teams | Works but prone to deadlock |
| `plan_mode_required` parameter at spawn | Teams | Works but prone to deadlock |
| `permissionMode: plan` in `.claude/agents/` | Subagents only | NOT available for team teammates ([#24316](https://github.com/anthropics/claude-code/issues/24316)) |

### `mode` Parameter Values

| Mode | Behavior |
|------|----------|
| `default` | Standard permission checking with prompts |
| `acceptEdits` | Auto-accept file edits |
| `dontAsk` | Auto-deny permission prompts |
| `delegate` | Coordination-only (team management tools only) |
| `bypassPermissions` | Skip all permission checks |
| `plan` | Read-only exploration until plan approved |

### Practical Workarounds

**Best approach — prompt-based planning (no deadlock risk):**
```
Spawn teammate with prompt: "First explore the codebase and send me a detailed plan
as a regular message. DO NOT make any file edits until I send you a message approving
your plan."
```

Uses standard messaging instead of the plan approval protocol. Not enforced at permission level but reliable.

**Two-phase approach:** Spawn read-only agent (`mode: "dontAsk"`, tools: Read/Grep/Glob/Bash) for planning, then spawn full agent for implementation.

### Known ExitPlanMode Issues

| Issue | Problem |
|-------|---------|
| [#23754](https://github.com/anthropics/claude-code/issues/23754) | Rejection/interruption causes session restart, losing all context |
| [#15755](https://github.com/anthropics/claude-code/issues/15755) | Allow does not exit plan mode |
| [#12288](https://github.com/anthropics/claude-code/issues/12288) | Doesn't return the plan as a tool result |
| [#9701](https://github.com/anthropics/claude-code/issues/9701) | Bypasses restrictions and auto-approves without consent |

---

## 4. Parallel Git Workflows

### Git Worktrees — The Dominant Pattern

Every major guide converges on git worktrees for parallel agent isolation.

```bash
# Create isolated worktrees
git worktree add ../project-feature-a -b feature-a
git worktree add ../project-feature-b -b feature-b

# Run Claude in each
cd ../project-feature-a && claude
cd ../project-feature-b && claude

# Clean up
git worktree remove ../project-feature-a
git worktree prune
```

Each worktree has independent file state while sharing Git history and remote connections.

Source: [Official Claude Code docs](https://code.claude.com/docs/en/common-workflows)

### Tools

#### Worktrunk
Ergonomic worktree management. Three core commands, branch-name addressing, `wt merge` from feature worktree.

```bash
brew install worktrunk
```

Source: [worktrunk.dev](https://worktrunk.dev/) | [GitHub](https://github.com/max-sixty/worktrunk)

#### ccswarm
Rust-based multi-agent orchestration with per-agent worktrees, specialized agent pool (Frontend/Backend/DevOps/QA), TUI dashboard, 93% token savings via conversation compression.

Source: [nwiizo/ccswarm](https://github.com/nwiizo/ccswarm)

#### CCPM (Claude Code Project Manager)
Bridges GitHub Issues + worktrees. Slash commands: `/pm:prd-new`, `/pm:epic-decompose`, `/pm:issue-start`, `/pm:epic-merge`. Tasks marked `parallel: true` target non-overlapping code regions.

Source: [automazeio/ccpm](https://github.com/automazeio/ccpm)

#### CCManager
CLI for managing multiple AI coding sessions across worktrees. Supports Claude Code, Gemini CLI, Codex CLI, Cursor Agent, and more. No tmux dependency.

Source: [kbwo/ccmanager](https://github.com/kbwo/ccmanager)

### Custom Slash Commands

**Parallel Init/Execute pattern:**
```
.claude/commands/init-parallel.md  — Creates N worktrees for a feature
.claude/commands/exe-parallel.md   — Spawns parallel subagents, each in a separate worktree
```

Usage: `/project:init-parallel interview-dashboard 3` then `/project:exe-parallel specs/interview-dashboard.md 3`

Source: [agentinterviews.com](https://docs.agentinterviews.com/blog/parallel-ai-coding-with-gitworktrees/)

**Worktree Flow skill** (`~/.claude/skills/worktree-flow/`):

| Command | Function |
|---------|----------|
| `/worktree-flow` | Coordinator analyzes requirements, decomposes tasks, assesses file overlap |
| `/wt-commit` | Stages work with structured messages |
| `/wt-done` | Atomic lock, rebase, fast-forward merge, release lock |
| `/wt-status` | Current and overall progress |
| `/wt-cleanup` | Removes completed worktrees |

Key feature: atomic locking via `.worktree-flow/<session-id>/lock.d/` + file overlap risk matrix (HIGH/MEDIUM/LOW) before task distribution.

Source: [xugj520.cn](https://www.xugj520.cn/en/archives/claude-code-git-worktree-parallel-development.html)

### Merge Conflict Strategies

1. **Prevention through spatial isolation** — assign non-overlapping files/directories (most effective)
2. **Agent-based resolution** — the agent that built the feature resolves its own conflicts (best context)
3. **Sequential merge with locking** — atomic locks, one agent merges at a time, `--ff-only` for linear history
4. **Let Claude figure it out** — Anthropic's C compiler project noted agents handle conflicts well

### Production Example: incident.io

4-5 Claude agents running parallel features via worktrees. Custom bash function `w`:

```bash
w myproject new-feature          # Create and enter worktree
w myproject new-feature claude   # Launch Claude in that worktree
```

Source: [incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees)

### Foundry-Specific Notes

- Each worktree needs its own `forge build` (compiled artifacts are local)
- `FOUNDRY_PROFILE=dev` optimization applies per-worktree
- Solidity contracts map well to directory-level isolation (one agent per contract file)
- Agent Teams are better for audit/review tasks; worktrees are better for parallel feature implementation

---

## Key Links

### Official
- [Agent Teams](https://code.claude.com/docs/en/agent-teams)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [Cost Management](https://code.claude.com/docs/en/costs)
- [Hooks](https://code.claude.com/docs/en/hooks)
- [Model Configuration](https://code.claude.com/docs/en/model-config)

### Anthropic Engineering
- [Building a C Compiler with Parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler)

### Community
- [Addy Osmani — Claude Code Swarms](https://addyosmani.com/blog/claude-code-agent-teams/)
- [Alex Op — From Tasks to Swarms](https://alexop.dev/posts/from-tasks-to-swarms-agent-teams-in-claude-code/)
- [OpenClaw Complete Guide](https://jangwook.net/en/blog/en/claude-agent-teams-guide/)
- [Swarm Orchestration Skill Gist](https://gist.github.com/kieranklaassen/4f2aba89594a4aea4ad64d753984b2ea)

### Known Issues
- [#23620](https://github.com/anthropics/claude-code/issues/23620) — Context compaction destroys team state
- [#24073](https://github.com/anthropics/claude-code/issues/24073) — Delegate mode tool loss
- [#24316](https://github.com/anthropics/claude-code/issues/24316) — Custom agents as team teammates
- [#24108](https://github.com/anthropics/claude-code/issues/24108) — Mailbox polling only between turns
