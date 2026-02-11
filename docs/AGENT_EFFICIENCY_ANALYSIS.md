# Agent Efficiency Analysis

**Date**: 2026-02-10
**Scope**: solidity-function-audit (solo) and solidity-function-audit-team (team) plugins
**Purpose**: Map our agent architecture against Claude Code best practices, quantify token costs, and identify improvement levers.

---

## Part 1: Claude Code Agent Best Practices (Reference Baseline)

Synthesized from official Claude Code documentation and Anthropic engineering blog posts.

### 1.1 Context Window Management

The core constraint: **"Most best practices are based on one constraint: Claude's context window fills up fast, and performance degrades as it fills."** ([best-practices](https://code.claude.com/docs/en/best-practices))

- 200K token context window; auto-compaction triggers at ~95% capacity (configurable via `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`). ([sub-agents](https://code.claude.com/docs/en/sub-agents))
- Subagents run in their own context window with a custom system prompt — they do NOT inherit the parent's conversation history. ([sub-agents](https://code.claude.com/docs/en/sub-agents))
- **Delegate verbose operations to subagents** — running tests, fetching docs, or processing log files consumes significant context. ([sub-agents](https://code.claude.com/docs/en/sub-agents))
- Use `/clear` between unrelated tasks; `/compact` with custom instructions to preserve critical details. ([best-practices](https://code.claude.com/docs/en/best-practices))
- Keep CLAUDE.md under ~500 lines. Skills use ~100 tokens for metadata scanning and <5K tokens when activated. ([costs](https://code.claude.com/docs/en/costs), [skills blog](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills))

### 1.2 Subagent Cost Profile

- Each subagent receives only its system prompt plus basic environment details — **not** the full Claude Code system prompt. ([sub-agents](https://code.claude.com/docs/en/sub-agents))
- Initialization overhead: ~5K-15K tokens depending on the system prompt injected by the tool call, environment details, and the prompt content itself (estimated from documented system prompt structure + CLAUDE.md inclusion).
- Model selection is critical for cost control:

| Agent Type | Default Model | Purpose |
|------------|--------------|---------|
| Explore | Haiku | File discovery, code search (read-only) |
| Plan | Inherits parent | Codebase research for planning (read-only) |
| general-purpose | Inherits parent | Complex research, multi-step operations, code modifications |
| claude-code-guide | Haiku | Answering questions about Claude Code features |

**Key guidance**: "Control costs by routing tasks to faster, cheaper models like Haiku." ([sub-agents](https://code.claude.com/docs/en/sub-agents))

### 1.3 Agent Team Coordination Patterns

- **7x token multiplier**: "Agent teams use approximately 7x more tokens than standard sessions when teammates run in plan mode." ([costs](https://code.claude.com/docs/en/costs))
- **5-6 tasks per teammate**: "Having 5-6 tasks per teammate keeps everyone productive and lets the lead reassign work if someone gets stuck." ([agent-teams](https://code.claude.com/docs/en/agent-teams))
- **Delegate mode** prevents the lead from implementing tasks itself — restricts to coordination-only tools. ([agent-teams](https://code.claude.com/docs/en/agent-teams))
- Task claiming uses file locking to prevent race conditions. Tasks support `blockedBy` dependencies for staged execution. ([agent-teams](https://code.claude.com/docs/en/agent-teams))
- "Agent teams add coordination overhead and use significantly more tokens than a single session." ([agent-teams](https://code.claude.com/docs/en/agent-teams))

### 1.4 Permission Modes

| Mode | Behavior | When to Use |
|------|----------|-------------|
| `default` | Standard permission checking with prompts | Interactive workflows |
| `acceptEdits` | Auto-accept file edits | Trusted file modification |
| `dontAsk` | Auto-deny permission prompts | Read-only agents |
| `delegate` | Coordination-only tools | Agent team leads |
| `bypassPermissions` | Skip all permission checks | Trusted structured analysis |
| `plan` | Read-only exploration until approval | Domain analysis requiring review |

([sub-agents](https://code.claude.com/docs/en/sub-agents))

### 1.5 Prompt Engineering for Agents

- Four-phase workflow: **Explore -> Plan -> Implement -> Commit** ([best-practices](https://code.claude.com/docs/en/best-practices))
- "The more precise your instructions, the fewer corrections you'll need." ([best-practices](https://code.claude.com/docs/en/best-practices))
- Reference specific files, mention constraints, point to example patterns. ([best-practices](https://code.claude.com/docs/en/best-practices))
- Common failure: "Infinite exploration — unscoped investigation fills context. Fix: Scope narrowly or use subagents." ([best-practices](https://code.claude.com/docs/en/best-practices))

### 1.6 Hooks as Quality Gates

Three hooks enable automated quality gates on agent completion:

| Hook Event | Fires When | Can Block? | Quality Gate Use |
|------------|-----------|------------|-----------------|
| `TeammateIdle` | Teammate about to go idle | Yes (code 2 → keep working) | Validate output completeness before idling |
| `TaskCompleted` | Task marked completed | Yes (code 2 → prevent completion) | Validate output file structure/content |
| `Stop` | Main agent finishes responding | Yes (code 2 → continue) | Ensure all stages completed |
| `SubagentStop` | Subagent finishes | Yes | Validate subagent output before returning |

Hook handler types: command (600s timeout), prompt (30s LLM evaluation), agent (60s subagent with Read/Grep/Glob). ([hooks](https://code.claude.com/docs/en/hooks))

### 1.7 Eval Methodology

From [Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents):

- **pass@k**: Probability of at least one correct solution in k attempts. Rises with k.
- **pass^k**: Probability that all k trials succeed. Falls with k. Example: 75% per-trial across 3 trials ≈ 42% pass^3.
- **Grader types**: Code-based (fast, cheap, brittle), LLM-as-judge (flexible, expensive), Human (gold standard, slow).
- **Minimum task count**: Start with **20-50 simple tasks drawn from real failures**; early evals benefit from large effect sizes.
- **Capability evals** target low pass rates; **regression evals** maintain ~100% pass rate.
- **Isolated environments**: Each trial needs clean state; shared state causes unreliable correlation.

### 1.8 Reference: C Compiler Case Study

From [Building a C Compiler with Parallel Claudes](https://www.anthropic.com/engineering/building-c-compiler):

- 16 agents in parallel, ~2,000 sessions over 2 weeks
- 100,000 lines of code, $20,000 total API cost
- 2 billion input tokens, 140 million output tokens
- 99% pass rate on most compiler test suites
- Git-based synchronization with task locks

This establishes the scale at which agent teams become viable: sustained multi-day workloads with clear test suites.

---

## Part 2: Our Architecture — Quantified

### 2.1 Agent Count Formula

**Solo variant** (background agents via `Task` + `run_in_background`):

```
Total agents = 3 (Stage 1) + N (Stage 2, one per domain) + 3 (Stage 3) + 0|1 (Stage 5 conditional)
             = 6 + N + (0|1)
```

**Team variant** (agent teams via `TeamCreate` + `SendMessage`):

```
Total teammates = 3 (Stage 1) + N (Stage 2) + 3 (Stage 3) = 6 + N
All spawned upfront. Stage 5 uses a solo background agent (+1 if needed).
Total agents = 6 + N + (0|1) teammates + 1 lead = 7 + N + (0|1)
```

For a typical 6-domain project: **Solo = 12-13 agents**, **Team = 13-14 agents**.

### 2.2 Timeout Budget

| Stage | Timeout per Agent | Max Wall Time | Rationale |
|-------|------------------|---------------|-----------|
| Stage 1 | 300,000ms (5 min) | 5 min (parallel) | Structural mapping only, no deep analysis |
| Stage 2 | 600,000ms (10 min) | 10 min (parallel) | Heaviest stage: per-function template + cross-cutting |
| Stage 3 | 600,000ms (10 min) | 10 min (parallel) | Reads all prior outputs + source files |
| Stage 5 | 600,000ms (10 min) | 10 min (single) | Re-evaluation of disputed findings |

**Max wall time for automated stages**: 5 + 10 + 10 = **25 minutes** (plus Stage 0 interactive + Slither).

Note: `600,000ms` is the maximum allowed by the `TaskOutput` tool. No higher timeout is possible.

### 2.3 Read Fan-In Analysis

How many times each file is read across all agents (6-domain project):

| File | Readers | Total Reads |
|------|---------|-------------|
| Source .sol files | Stage 1 (×3), Stage 2 (×6), Stage 3 (×3) | 12 reads per file |
| `design-decisions.md` | Stage 2 (×6), Stage 3 (×3) | 9 reads |
| `state-variable-map.md` | Stage 2 (×6), Stage 3 (×3) | 9 reads |
| `access-control-map.md` | Stage 2 (×6), Stage 3 (×3) | 9 reads |
| `external-call-map.md` | Stage 2 (×6), Stage 3 (×3) | 9 reads |
| `slither-findings.md` | Stage 2 (×6), Stage 3 (×3) | 9 reads (if Slither ran) |
| `FUNCTION_TEMPLATE.md` | Stage 2 (×6) | 6 reads |
| `EXAMPLE_OUTPUT.md` | Stage 2 (×6) | 6 reads |
| Stage 2 domain files | Stage 3 (×3 each) | 3 reads per domain file |

**Key insight**: Stage 1 outputs are read **9 times each** (by 6 domain agents + 3 cross-cutting agents). Each read consumes context in a separate agent window. There is no shared cache — each agent independently reads the same files.

### 2.4 Prompt Injection Sizes

Token estimates (1 token ≈ 3.5-4 chars for code-mixed markdown):

| Component | Bytes | ~Tokens | Injected Into |
|-----------|-------|---------|---------------|
| SKILL.md (solo) | 18,069 | ~4,700 | Orchestrator only (once) |
| SKILL.md (team) | 20,186 | ~5,200 | Orchestrator/lead only (once) |
| STAGE_PROMPTS.md (solo) | 14,546 | ~3,800 | Orchestrator reads, extracts per-agent |
| STAGE_PROMPTS.md (team) | 20,677 | ~5,400 | Orchestrator reads, extracts per-agent |
| FUNCTION_TEMPLATE.md | 2,046 | ~530 | Stage 2 agents (×N) at runtime |
| EXAMPLE_OUTPUT.md | 4,489 | ~1,200 | Stage 2 agents (×N) at runtime |
| REVIEW_PROMPTS.md | 8,064 | ~2,100 | Orchestrator only (Stage 0/4/5) |

**Per-agent prompt sizes** (filled template, approximate):

| Agent Type | Prompt Template | + Placeholder Data | Total ~Tokens |
|------------|----------------|-------------------|---------------|
| Stage 1 (any) | ~400 | ~200 (source file list) | ~600 |
| Stage 2 (domain) | ~900 | ~800 (file list + function list + paths) | ~1,700 |
| Stage 3 (any) | ~500 | ~400 (file lists + paths) | ~900 |
| Stage 5 (re-eval) | ~500 | ~500 (disputed findings) | ~1,000 |

Team variant adds ~250 tokens per agent (Communication Guidelines block + teammate_roles substitution).

### 2.5 Estimated Token Budget Per Run (6-Domain Project)

**Solo variant — per agent breakdown:**

| Stage | Agents | Prompt | File Reads | Analysis+Write | Subtotal per Agent | Stage Total |
|-------|--------|--------|------------|----------------|-------------------|-------------|
| Orchestrator | 1 | 4,700 (SKILL) + 3,800 (STAGE_PROMPTS read) | ~5,000 (source discovery) | ~3,000 (synthesis reads) | ~16,500 | 16,500 |
| Stage 1 | 3 | ~600 | ~8,000 (source files) | ~4,000 | ~12,600 | 37,800 |
| Stage 2 | 6 | ~1,700 | ~12,000 (source + Stage 1 + template + example + design + slither) | ~6,000 | ~19,700 | 118,200 |
| Stage 3 | 3 | ~900 | ~15,000 (source + Stage 1 + Stage 2 + design + slither) | ~5,000 | ~20,900 | 62,700 |
| Stage 5 | 0-1 | ~1,000 | ~3,000 | ~2,000 | ~6,000 | 0-6,000 |
| **Total** | | | | | | **~235,200 - 241,200** |

Note: These are input token estimates. Output tokens (analysis written to files) add ~20-30% on top, but cost significantly less per token. Extended thinking (31,999 token budget default) can add substantial output token cost per agent.

**Team variant — additional overhead per run:**

| Component | Token Cost | Source |
|-----------|-----------|--------|
| Team creation/teardown | ~200 | TaskCreate × (6+N), TeamCreate, TeamDelete |
| Task descriptions (full prompts embedded) | ~8,000 | Each task description = filled prompt template |
| Plan mode (Stage 2) | ~12,000 | Plan generation + approval round-trip × N domains |
| Inter-agent messaging | ~8,000 | SendMessage overhead, ~2-4 messages per Stage 1/3 agent, ~3-5 per Stage 2 |
| TaskList/TaskUpdate polling | ~3,000 | ~50 tokens per call × ~60 calls across all agents |
| Shared teammate prompt | ~1,500 | 200 tokens × (6+N) agents |
| Communication Guidelines | ~1,500 | ~250 extra tokens × (6+N) agent prompts |
| **Team overhead total** | **~34,200** | |

**Estimated totals:**

| Variant | Base | Overhead | Total Input Tokens | ~USD (Opus @ $15/MTok in, $75/MTok out) |
|---------|------|----------|--------------------|-----|
| Solo (6 domains) | ~235K | — | ~235K | ~$6-10 |
| Team (6 domains) | ~235K | ~34K | ~269K | ~$8-14 |

These exclude extended thinking tokens. With default 32K thinking budget per agent turn, multiply by average turns per agent (3-5) for thinking cost.

### 2.6 Team Variant Overhead Breakdown

| Category | Tokens | % of Team Overhead |
|----------|--------|--------------------|
| Plan mode round-trips | ~12,000 | 35% |
| Task descriptions (duplicated prompts) | ~8,000 | 23% |
| Inter-agent messaging | ~8,000 | 23% |
| TaskList/TaskUpdate polling | ~3,000 | 9% |
| Communication Guidelines in prompts | ~1,500 | 4% |
| Shared teammate prompt overhead | ~1,500 | 4% |
| Team creation/teardown | ~200 | 1% |

The biggest team-specific costs are **plan mode** (read-plan-approve cycle) and **prompt duplication** (full prompts embedded in task descriptions).

---

## Part 3: Efficiency Audit

### 3.1 What We Do Well

| Practice | Our Implementation | Best Practice Alignment |
|----------|-------------------|------------------------|
| **File-based output** | All agents write to markdown files; return only one-line confirmation | Matches "delegate verbose operations to subagents" — zero analysis content returns to orchestrator context |
| **Sequential file reading in synthesis** | "Read one, count findings, move to next" instruction in both SKILL.md variants | Prevents context overflow during synthesis phase |
| **Stage-gated parallelism** | `blockedBy` dependencies (team) / sequential `TaskOutput` waits (solo) | Prevents premature reads of unwritten files |
| **`disable-model-invocation: true`** | Both skills set this in frontmatter | Zero context cost until user explicitly invokes; ~100 tokens for metadata scan |
| **Prompt templates in resources/** | SKILL.md: 356/357 lines; detailed templates in 4 resource files | SKILL.md stays under 400-line guideline; orchestrator reads templates at runtime |
| **Permission modes matched to risk** | `bypassPermissions` for Stage 1/3 (structured output), `plan` for Stage 2 (requires review) | Stage 2 is the only stage where agents make judgment calls about severity — plan mode adds a review checkpoint |
| **Domain grouping heuristic** | 4-10 domains, 3-15 functions each, confirmed with user | Prevents both too-small agents (coordination overhead) and too-large agents (context overflow) |
| **Design decisions pre-capture** | Stage 0 extracts developer intent before automated audit | Reduces false positives; findings classified against documented decisions |
| **Template-driven output** | FUNCTION_TEMPLATE.md enforces consistent per-function format | Enables reliable automated parsing (exact severity patterns) |
| **Example-driven quality** | EXAMPLE_OUTPUT.md provides calibration reference | Agents anchor on demonstrated depth and tone |

### 3.2 What Could Improve

#### 3.2.1 No Model Differentiation (High Impact, Trivial Effort)

**Current**: All agents use `subagent_type: "general-purpose"` which inherits the parent model (Opus). Every Stage 1 structural mapping agent runs on the same expensive model as Stage 2 domain analysis agents.

**Best practice**: "Control costs by routing tasks to faster, cheaper models like Haiku." Stage 1 agents do structural mapping (list variables, list access controls, list external calls) — well-suited for Haiku.

**Impact**: Stage 1 accounts for ~37,800 input tokens across 3 agents. Haiku is ~60x cheaper than Opus per input token ($0.25 vs $15/MTok). Switching Stage 1 to Haiku would save ~$0.50-0.55 per run on Stage 1 input alone, and significantly more on thinking/output tokens.

**Limitation**: The `Task` tool's `model` parameter accepts `"sonnet"`, `"opus"`, `"haiku"` — but only the `general-purpose` subagent type supports file writes. Explore (which defaults to Haiku) cannot edit/write files. We would need to use `Task(subagent_type: "general-purpose", model: "haiku")`.

#### 3.2.2 No `max_turns` Caps (High Impact, Trivial Effort)

**Current**: No `max_turns` parameter on any agent spawn. Agents can loop indefinitely if they encounter issues (e.g., file not found, permission denied).

**Best practice**: The `max_turns` field sets maximum agentic turns before stopping. Without it, a stuck agent burns tokens until the timeout expires.

**Recommended caps**: Stage 1 agents: `max_turns: 15` (read files + write output). Stage 2 agents: `max_turns: 25` (more files to read, longer analysis). Stage 3 agents: `max_turns: 25`. Stage 5 agent: `max_turns: 15`.

#### 3.2.3 No Hooks for Quality Gates (Medium Impact, Medium Effort)

**Current**: No hooks configured. Agent output quality is verified only during synthesis (orchestrator reads files and counts findings).

**Best practice**: `TaskCompleted` hooks can validate output before marking a task done. `SubagentStop` hooks can validate subagent output before it returns.

**Opportunity**: A `TaskCompleted` or `SubagentStop` hook could:
1. Check that the output file exists and is non-empty
2. Verify the file contains expected section headers (e.g., `## Per-Function Analysis`, `## Summary of Findings`)
3. Verify severity format compliance (`**CRITICAL -- `, `**WARNING -- `, `**INFO -- `)
4. Reject and provide feedback if validation fails (exit code 2)

This would catch malformed output before synthesis, preventing cascading errors.

#### 3.2.4 Duplicate File Reads Across Agents (Low-Medium Impact, Hard to Mitigate)

**Current**: Each agent independently reads the same source files and Stage 1 outputs. A 6-domain project has source files read 12 times total (§2.3).

**Structural constraint**: Subagents have independent context windows. There is no shared file cache across agents. This is by design — agents are isolated for safety and correctness.

**Partial mitigation available**: For Stage 2 agents, the `{source_file_list}` could be scoped to only the files relevant to that domain (currently all source files are listed). This reduces per-agent reads at the cost of missing cross-contract interactions outside the domain.

**Not mitigable**: Stage 3 agents legitimately need all prior outputs + all source files.

#### 3.2.5 No Eval Harness (High Impact, High Effort)

**Current**: No automated testing of audit quality. No ground truth contracts, no regression tests, no cost tracking across runs.

**Gap**: Without evals, we cannot measure whether changes (model selection, prompt modifications, hook additions) actually improve output quality. We also cannot detect regressions.

**What's available**: See Part 5 for detailed assessment.

#### 3.2.6 Stage 1 Agents Read Design Decisions Unnecessarily (Low Impact, Trivial Effort)

**Current**: The `{design_decisions_file}` placeholder is listed in the SKILL.md Stage 1 section (SKILL.md:118 solo, SKILL.md:134 team for task description templates), but Stage 1 prompt templates in STAGE_PROMPTS.md do NOT include a Design Decisions section. The SKILL.md orchestration instruction fills this placeholder, but the template doesn't use it.

**Observation**: Stage 1 agents do structural mapping — they list variables, access controls, and external calls. They don't classify findings by severity, so design decisions are irrelevant to their work.

**Action**: Confirm that Stage 1 prompt templates don't reference `{design_decisions_file}` (verified: they don't in STAGE_PROMPTS.md). Remove the mention from SKILL.md's Stage 1 placeholder list to avoid confusion. No token savings — it's already not injected.

#### 3.2.7 No Compaction Guidance (Low Impact, Trivial Effort)

**Current**: SKILL.md doesn't instruct the orchestrator on when or how to compact. Long sessions (especially with interactive Stage 0 and Stage 4) can fill the orchestrator's context.

**Best practice**: "Customize in CLAUDE.md: 'When compacting, always preserve the full list of modified files and any test commands.'" The orchestrator should preserve: domain groupings, file paths, finding counts, and stage completion status.

**Action**: Add a note to SKILL.md's orchestrator instructions: "If context compaction occurs, preserve: PROJECT_PATH, domain list, all output file paths, finding tallies, and current stage number."

#### 3.2.8 Team Variant Spawns All Teammates Upfront (Medium Impact, High Effort)

**Current**: All 6+N teammates are spawned simultaneously at team creation. Stage 2 teammates sit blocked (waiting on Stage 1 `blockedBy` dependencies) and Stage 3 teammates sit blocked even longer.

**Cost**: Each blocked teammate still holds its system prompt in context (~1,500 tokens for the shared teammate prompt + environment overhead). For a 6-domain project, 6 Stage 2 + 3 Stage 3 = 9 teammates waiting. At ~5K tokens idle overhead each (system prompt + initial TaskList call), that's ~45K tokens spent before these agents can work.

**Best practice**: "Having 5-6 tasks per teammate keeps everyone productive." Our Stage 1 teammates have exactly 1 task each (below the 5-6 recommendation). Stage 3 teammates also have 1 task each.

**Alternative**: Lazy spawning — spawn Stage 2 teammates only after Stage 1 completes, Stage 3 only after Stage 2 completes. This would save ~45K tokens of idle overhead but adds ~30-60 seconds of spawn latency per wave.

**Constraint**: The `blockedBy` mechanism was designed for exactly this use case, and the docs don't flag idle teammates as a significant cost concern. The 7x multiplier already accounts for this overhead.

#### 3.2.9 Extended Thinking Budget Not Tuned (Medium Impact, Trivial Effort)

**Current**: Default extended thinking budget of 31,999 tokens applies to every agent turn. Stage 1 structural mapping doesn't benefit from deep reasoning — it's essentially a structured extraction task.

**Opportunity**: `MAX_THINKING_TOKENS=8000` for Stage 1 agents would reduce output token cost significantly. Stage 2 and Stage 3 agents likely benefit from the full thinking budget.

**Limitation**: `MAX_THINKING_TOKENS` is an environment variable, not a per-agent parameter. It would need to be set differently per stage, which isn't straightforward without hooks or wrapper scripts.

---

## Part 4: Cost Model

### 4.1 Per-Agent Token Estimates (6-Domain Project)

All estimates assume a medium-complexity Solidity project (~2,000 LoC across 4-6 contracts, 40-60 functions).

| Agent | Prompt Tokens | File Read Tokens | Thinking Tokens | Analysis Output | Total |
|-------|--------------|-----------------|-----------------|-----------------|-------|
| Stage 1a (State Vars) | 600 | 8,000 | 16,000 (×3 turns) | 3,000 | ~59,600 |
| Stage 1b (Access Ctrl) | 600 | 8,000 | 16,000 (×3 turns) | 3,000 | ~59,600 |
| Stage 1c (External Calls) | 600 | 8,000 | 16,000 (×3 turns) | 2,500 | ~59,100 |
| Stage 2 (per domain, ×6) | 1,700 | 12,000 | 16,000 (×4 turns) | 5,000 | ~82,700 |
| Stage 3a (State Consistency) | 900 | 15,000 | 16,000 (×4 turns) | 4,000 | ~83,900 |
| Stage 3b (Math & Rounding) | 900 | 15,000 | 16,000 (×4 turns) | 4,000 | ~83,900 |
| Stage 3c (Reentrancy) | 900 | 15,000 | 16,000 (×4 turns) | 4,000 | ~83,900 |
| Stage 5 (Re-eval) | 1,000 | 3,000 | 16,000 (×2 turns) | 2,000 | ~38,000 |

Note: Thinking tokens are output tokens billed at output rate. "×N turns" = estimated agentic turns per agent.

### 4.2 Aggregate Per-Stage and Per-Run

**Solo variant (6 domains, with Stage 5):**

| Stage | Input Tokens | Output Tokens (incl. thinking) | Input Cost | Output Cost | Total |
|-------|-------------|-------------------------------|------------|-------------|-------|
| Orchestrator | ~25,000 | ~8,000 | $0.38 | $0.60 | $0.98 |
| Stage 1 (×3) | ~26,400 | ~152,400 | $0.40 | $11.43 | $11.83 |
| Stage 2 (×6) | ~82,200 | ~414,000 | $1.23 | $31.05 | $32.28 |
| Stage 3 (×3) | ~47,700 | ~207,600 | $0.72 | $15.57 | $16.29 |
| Stage 5 (×1) | ~4,000 | ~34,000 | $0.06 | $2.55 | $2.61 |
| **Total** | **~185,300** | **~816,000** | **$2.78** | **$61.20** | **$63.98** |

**Team variant (6 domains, same workload + coordination overhead):**

| Category | Additional Input | Additional Output | Additional Cost |
|----------|-----------------|-------------------|----------------|
| Task descriptions | ~8,000 | — | $0.12 |
| Plan mode cycles | ~12,000 | ~18,000 | $1.53 |
| Messaging | ~8,000 | ~4,000 | $0.42 |
| Task list polling | ~3,000 | ~1,500 | $0.16 |
| Prompts/guidelines | ~3,000 | — | $0.05 |
| **Team overhead** | **~34,000** | **~23,500** | **~$2.28** |
| **Team total** | **~219,300** | **~839,500** | **~$66.26** |

Pricing: Opus 4.6 at $15/MTok input, $75/MTok output. Extended thinking tokens billed as output.

### 4.3 Solo vs Team Comparison

| Metric | Solo | Team | Difference |
|--------|------|------|------------|
| Total agents | 13 | 14 | +1 (lead) |
| Input tokens | ~185K | ~219K | +18% |
| Output tokens (incl. thinking) | ~816K | ~840K | +3% |
| Estimated cost | ~$64 | ~$66 | +3% |
| Wall time (automated stages) | ~25 min | ~28 min (plan approval latency) | +12% |
| Inter-agent findings | None | Possible (messaging) | Qualitative |

**Key finding**: The team variant adds only ~3% cost overhead (not 7x) because:
1. The 7x multiplier cited in docs is for a full session comparison, not marginal coordination cost
2. Our team tasks are large enough that coordination overhead is amortized
3. Most tokens go to file reads and thinking, which are identical across variants

The 7x multiplier applies when comparing "one agent doing everything" vs "a team doing the same work." Our solo variant already uses multiple agents — it's a multi-agent system either way.

### 4.4 Sensitivity Analysis: Cost vs Domain Count (N)

| Domains (N) | Solo Input | Solo Output | Solo Cost | Team Cost | Delta |
|-------------|-----------|-------------|-----------|-----------|-------|
| 2 | ~115K | ~472K | ~$37 | ~$39 | +$2 |
| 4 | ~150K | ~644K | ~$50 | ~$53 | +$3 |
| 6 | ~185K | ~816K | ~$64 | ~$66 | +$2 |
| 8 | ~220K | ~988K | ~$77 | ~$80 | +$3 |
| 10 | ~255K | ~1.16M | ~$90 | ~$93 | +$3 |

**Scaling characteristics**:
- Cost grows linearly with N (each domain adds ~$6.50 in Stage 2)
- Stage 3 cost is constant regardless of N (always 3 agents), but Stage 3 agents read more files as N grows
- At N=10, Stage 3 agents read 10 domain files + 3 Stage 1 files + source files — this may approach context limits for large projects

### 4.5 Dominant Cost Driver: Extended Thinking

The single largest cost component is **extended thinking tokens**. At $75/MTok output and an estimated 48K-64K thinking tokens per agent (32K budget × 1.5-2 turns average), thinking alone accounts for **~$3.60-4.80 per agent**.

For a 6-domain project with 13 agents: **~$47-62 in thinking tokens alone** — roughly 75% of total cost.

This makes thinking budget tuning the highest-leverage cost optimization available.

---

## Part 5: Eval Readiness Assessment

### 5.1 Available CLI Primitives

The skill can be invoked headlessly for automated evaluation:

```bash
claude -p "/solidity-function-audit /path/to/test-contract" \
  --output-format json \
  --plugin-dir ./plugins/solidity-function-audit \
  --allowedTools "Read,Write,Glob,Grep,Bash,Task,TaskOutput"
```

The `--output-format json` flag includes usage fields for token tracking. `--output-format stream-json` provides streaming output for real-time monitoring.

### 5.2 Ground Truth Sources

| Source | Contracts | Labeled Bugs | Suitable For |
|--------|-----------|-------------|--------------|
| [SmartBugs Curated](https://github.com/smartbugs/smartbugs-curated) | ~143 | ~208 labeled vulnerabilities | Single-function finding accuracy (pass@k) |
| [SCONE-bench](https://github.com/AuditWen/SCONE-bench) | ~1,200 | Multi-category labels | Large-scale capability eval |
| [Code4rena reports](https://code4rena.com/reports) | Production audits | Severity-labeled findings | Domain analysis quality (LLM-as-judge) |
| Custom hand-labeled | 5-10 contracts | Hand-labeled findings + design decisions | End-to-end pipeline eval (regression) |

### 5.3 Grading Approach

**Code-based graders** (fast, cheap, reproducible):
- Output file existence and structure (section headers, severity format compliance)
- Finding count within expected range (zero findings on a buggy contract = fail)
- Severity format: regex match `\*\*CRITICAL -- `, `\*\*WARNING -- `, `\*\*INFO -- `
- Verdict format: regex match `\*\*Verdict\*\*: \*\*(SOUND|NEEDS_REVIEW|ISSUE_FOUND)\*\*`

**LLM-as-judge graders** (flexible, expensive):
- Finding quality: "Does this finding identify a real vulnerability? Rate 1-5."
- False positive rate: "Is this finding a false positive? Yes/No with reasoning."
- Coverage: "Given this known vulnerability list, which vulnerabilities did the audit find?"

**Human graders** (gold standard, for calibration):
- Review 10-20 outputs manually to calibrate LLM-as-judge grader
- Establish ground truth for regression eval set

### 5.4 Metrics to Track

| Metric | Definition | Target |
|--------|-----------|--------|
| pass@1 (finding) | % of known bugs found on first run | >60% |
| pass@3 (finding) | % of known bugs found in at least 1 of 3 runs | >80% |
| False positive rate | % of CRITICALs/WARNINGs that are false positives | <30% |
| Cost per finding | Total run cost / number of valid findings | Track trend |
| Coverage | % of known vulnerabilities mentioned anywhere in output | >70% |
| Format compliance | % of output files passing code-based structural validation | >95% |
| Wall time | Total elapsed time for automated stages | Track trend |

### 5.5 Cost Tracking

- **ccusage**: Community tool that reads `~/.claude/projects/*/sessions/` to extract token usage per session. ([github.com/ryoppippi/ccusage](https://github.com/ryoppippi/ccusage))
- **`--output-format json`**: Built-in token usage in CLI output. Parse `usage.input_tokens`, `usage.output_tokens` fields.
- **Custom tracking**: Wrap `claude -p` invocation with timing + cost calculation based on model pricing.

### 5.6 Minimum Viable Eval Harness

To start evaluating with minimal effort:

1. **5 SmartBugs contracts** with known reentrancy, integer overflow, and access control bugs
2. **5 custom contracts** with known design decisions (to test Stage 0 + false positive rate)
3. **Code-based grader** checking: file existence, section structure, severity format, finding count range
4. **One LLM-as-judge prompt** checking: "Given these known vulnerabilities, which did the audit find?"
5. **Cost tracker**: Parse `--output-format json` output for token usage
6. **Run script**: Loop over contracts, invoke skill, grade, report

Estimated effort: 2-3 days to build, ~$50-100 per full eval run (10 contracts × $5-10 each).

---

## Part 6: Recommendations (Prioritized)

Ranked by impact-to-effort ratio. Impact estimates assume a 6-domain project.

### Priority 1: Tune Extended Thinking Budget per Stage (High Impact, Trivial Effort)

**What**: Set `MAX_THINKING_TOKENS=10000` for Stage 1 agents. Keep default (31,999) for Stage 2/3.

**Why**: Thinking tokens are ~75% of total cost. Stage 1 is structured extraction, not deep reasoning. Reducing from 32K to 10K saves ~$1.50 per Stage 1 agent, ~$4.50 per run.

**How**: Add to SKILL.md Stage 1 instructions: "When spawning Stage 1 agents, include in the prompt: 'Keep your reasoning concise — this is structural mapping, not security analysis.'" Alternatively, investigate if a wrapper hook can set `MAX_THINKING_TOKENS` per subagent.

**Effort**: Prompt modification only. No code changes.

### Priority 2: Add Haiku Model for Stage 1 Agents (High Impact, Trivial Effort)

**What**: Change Stage 1 agent spawns from `Task(subagent_type: "general-purpose")` to `Task(subagent_type: "general-purpose", model: "haiku")`.

**Why**: Stage 1 does structural mapping (list variables, list access controls, list external calls). This is well within Haiku's capabilities and ~60x cheaper per input token.

**Savings**: ~$10-11 per run on Stage 1 alone (input + output + thinking).

**Risk**: Haiku may produce less detailed structural maps. Mitigate by running one eval comparison (Opus vs Haiku Stage 1 output) before committing.

**Effort**: One line change per agent spawn in SKILL.md (×3 agents, ×2 variants = 6 edits).

### Priority 3: Add `max_turns` Caps to Agent Spawns (High Impact, Trivial Effort)

**What**: Add `max_turns` to every `Task` call. Recommended: Stage 1 = 15, Stage 2 = 25, Stage 3 = 25, Stage 5 = 15.

**Why**: Without caps, a stuck agent burns tokens until the 5-10 minute timeout expires. With `max_turns: 25` and ~30s per turn, the effective cap is ~12.5 minutes — but it limits token spend to ~25 turns × ~5K tokens = ~125K tokens max per agent.

**Effort**: Add one parameter per agent spawn (12-13 edits across 2 variants).

### Priority 4: Add Output Validation Hooks (Medium Impact, Medium Effort)

**What**: Add a `SubagentStop` (solo) or `TaskCompleted` (team) hook that validates output files.

**Validation script** (command hook):
```bash
#!/bin/bash
# Validate audit output file structure
FILE=$(echo "$CLAUDE_HOOK_INPUT" | jq -r '.output_file // empty')
[ -z "$FILE" ] && exit 0
[ ! -s "$FILE" ] && echo "Output file is empty: $FILE" >&2 && exit 2
grep -q "## Summary" "$FILE" || (echo "Missing ## Summary section in $FILE" >&2 && exit 2)
```

**Why**: Catches empty files, malformed output, and missing sections before synthesis. Currently these failures silently produce incomplete INDEX.md/SUMMARY.md.

**Effort**: Write validation script + configure in plugin hooks.json. Medium because hook testing requires running the full pipeline.

### Priority 5: Build Minimal Eval Harness (High Impact, High Effort)

**What**: Create `eval/` directory with 10 test contracts (5 SmartBugs + 5 custom), a grading script, and a run script per §5.6.

**Why**: Every other recommendation in this list is speculative without measurement. Evals convert opinions into data.

**Effort**: 2-3 days initial build, ~$50-100 per eval run. Ongoing maintenance as prompts change.

### Priority 6: Add Compaction Guidance to SKILL.md (Low Impact, Trivial Effort)

**What**: Add to both SKILL.md variants: "If context compaction occurs during this session, preserve: PROJECT_PATH, domain groupings with function lists, all output file absolute paths, finding tallies per stage, current stage number, and all placeholder values ({design_decisions_file}, {slither_file}, etc.)."

**Why**: Long interactive sessions (Stage 0 + Stage 4 can take 30+ minutes) may trigger compaction. Without guidance, the compactor may drop domain groupings or file paths.

**Effort**: Add ~3 lines to each SKILL.md.

### Priority 7: Scope Stage 2 Source File Lists to Domain-Relevant Files (Low Impact, Low Effort)

**What**: Instead of passing all source files to every Stage 2 agent, pass only the files containing functions in that domain.

**Why**: A Stage 2 agent analyzing the "Deposit" domain doesn't need to read the "Governance" contract. Reduces per-agent file read tokens by ~30-50% for projects with many contracts.

**Risk**: May miss cross-contract interactions where a domain function calls into a contract not in its domain. Mitigate by also including files containing contracts referenced in the domain's external calls (detectable from Stage 1c output).

**Effort**: Modify orchestrator instructions to filter source file list per domain.

### Priority 8: Investigate Lazy Teammate Spawning (Medium Impact, High Effort)

**What**: In team variant, spawn Stage 2 teammates only after Stage 1 completes, and Stage 3 only after Stage 2 completes.

**Why**: Saves ~45K tokens of idle overhead from blocked teammates.

**Trade-off**: Adds 30-60 seconds of spawn latency per wave. The `blockedBy` mechanism already handles sequencing efficiently — lazy spawning is an optimization, not a correctness fix.

**Effort**: Significant restructuring of team creation section in SKILL.md. Must handle edge case of teammate names being referenced in task descriptions before teammates exist.

---

## Appendix A: Source References

| Claim | Source |
|-------|--------|
| Auto-compaction at ~95% capacity | [sub-agents docs](https://code.claude.com/docs/en/sub-agents) |
| 7x token multiplier for teams | [costs docs](https://code.claude.com/docs/en/costs) |
| 5-6 tasks per teammate | [agent-teams docs](https://code.claude.com/docs/en/agent-teams) |
| Skills use ~100 tokens for metadata | [skills blog post](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) |
| CLAUDE.md under ~500 lines | [costs docs](https://code.claude.com/docs/en/costs) |
| 31,999 default thinking budget | [costs docs](https://code.claude.com/docs/en/costs) |
| pass@k/pass^k definitions | [evals blog post](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) |
| 20-50 task minimum for evals | [evals blog post](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) |
| C compiler: $20K, 2B input tokens | [C compiler blog post](https://www.anthropic.com/engineering/building-c-compiler) |
| Hook events and handler types | [hooks docs](https://code.claude.com/docs/en/hooks) |
| Permission mode descriptions | [sub-agents docs](https://code.claude.com/docs/en/sub-agents) |
| Delegate mode prevents lead from implementing | [agent-teams docs](https://code.claude.com/docs/en/agent-teams) |
| File read counts (§2.3) | Calculated from SKILL.md pipeline structure |
| Prompt sizes (§2.4) | Measured from file byte counts (÷3.75 for token estimate) |
| Cost estimates (§4.2) | Calculated from per-agent estimates × Opus pricing |

## Appendix B: File Sizes (Measured)

| File | Lines | Bytes | ~Tokens |
|------|-------|-------|---------|
| SKILL.md (solo) | 356 | 18,069 | ~4,700 |
| SKILL.md (team) | 357 | 20,186 | ~5,200 |
| STAGE_PROMPTS.md (solo) | 325 | 14,546 | ~3,800 |
| STAGE_PROMPTS.md (team) | 409 | 20,677 | ~5,400 |
| FUNCTION_TEMPLATE.md | 44 | 2,046 | ~530 |
| EXAMPLE_OUTPUT.md | 101 | 4,489 | ~1,200 |
| REVIEW_PROMPTS.md | 218 | 8,064 | ~2,100 |
| **Team overhead (STAGE_PROMPTS diff)** | **84** | **6,131** | **~1,600** |
