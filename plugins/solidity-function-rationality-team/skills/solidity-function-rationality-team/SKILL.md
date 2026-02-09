---
name: solidity-function-rationality-team
description: Agent team variant of solidity-function-rationality. Uses Claude Code agent teams for inter-agent messaging, plan mode for Stage 2, and shared task list with dependencies. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1.
disable-model-invocation: true
---

# Function Rationality Analysis (Agent Team)

## Purpose

Perform a comprehensive per-function rationality analysis using an agent team. Teammates communicate findings to each other in real-time, use plan mode for complex domain analysis, and coordinate via a shared task list with dependencies. The lead stays lean by delegating all analysis work and only performing pre-flight discovery and synthesis.

## Prerequisites

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set in `.claude/settings.json` env or shell environment

---

## Pre-Flight Discovery (Lead Only)

### 1. Identify Project Path
- Use `$ARGUMENTS` as the project path if provided, otherwise use the current working directory.
- Store as `PROJECT_PATH` for all subsequent steps.

### 2. Discover Contracts
Use Glob for `src/**/*.sol` (excluding `src/artifacts/`) to find all source files. Then use Grep for `contract \w+` and `library \w+` to identify contract and library declarations. Read each file to confirm.

### 3. Discover Functions
Use Grep for `function \w+\(` in each discovered .sol file to find all function declarations. Read the surrounding lines to determine visibility:
- Collect all `external` and `public` functions
- Also collect `internal` functions (they are often where the real logic lives)
- Skip auto-generated getters and pure view helpers that just return a constant

### 4. Group Into Domains
Group functions into logical domains using these heuristics (in priority order):
1. **Shared modifiers**: Functions sharing the same access control modifier belong together
2. **Shared state writes**: Functions that write to the same state variables belong together
3. **Lifecycle stages**: Functions that form a sequence (request -> process -> claim) belong together
4. **Name prefixes**: Functions with common prefixes (deposit/withdraw, add/remove, register/deregister)

Aim for 4-10 domains. Each domain should have 3-15 functions. Merge tiny domains, split huge ones.

### 5. Create Output Directory
```
mkdir -p docs/audit/function-rationality/{stage1,stage2,stage3}
```

### 6. Confirm with User
Display to the user:
- Number of contracts found
- Number of functions found
- Domain groupings with function lists
- Ask for confirmation before proceeding

### 7. Collect Source File Paths
Build the list of all .sol source file paths (absolute paths) that teammates will need to read. Format as one absolute path per line when substituting into `{source_file_list}` placeholders in teammate prompts.

### 8. Plan Task IDs and Dependency Graph
Before creating tasks, plan out all task IDs and their dependencies:

```
Stage 1 (no deps — start immediately):
  T1: State Variable Map
  T2: Access Control Map
  T3: External Call Map

Stage 2 (blocked by all Stage 1 tasks):
  T4: Domain "{domain_1_name}"      | blockedBy: [T1, T2, T3]
  T5: Domain "{domain_2_name}"      | blockedBy: [T1, T2, T3]
  ...
  T(3+N): Domain "{domain_N_name}"  | blockedBy: [T1, T2, T3]

Stage 3 (blocked by all Stage 2 tasks):
  T(4+N): State Consistency         | blockedBy: [T4 .. T(3+N)]
  T(5+N): Math & Rounding           | blockedBy: [T4 .. T(3+N)]
  T(6+N): Reentrancy & Trust        | blockedBy: [T4 .. T(3+N)]
```

---

## Team Creation (Lead Only — use exact tools specified)

### Step 1: Create the team using TeamCreate tool

Call the `TeamCreate` tool:
```
TeamCreate(team_name: "function-rationality", description: "Function rationality analysis for {PROJECT_PATH}")
```

This creates the shared task list and team config at `~/.claude/teams/function-rationality/`.

### Step 2: Create ALL tasks using TaskCreate tool

Create every task upfront BEFORE spawning any teammates. Read the prompt templates from `resources/STAGE_PROMPTS.md` and fill in all placeholders. Each task's `description` field must contain the FULL analysis prompt (the filled-in template from STAGE_PROMPTS.md), not a summary.

**Stage 1 tasks** (no dependencies — created first):

Call `TaskCreate` 3 times:
- T1: `TaskCreate(subject: "State Variable Map", description: "<filled Stage 1a prompt>", activeForm: "Mapping state variables")`
- T2: `TaskCreate(subject: "Access Control Map", description: "<filled Stage 1b prompt>", activeForm: "Mapping access control")`
- T3: `TaskCreate(subject: "External Call Map", description: "<filled Stage 1c prompt>", activeForm: "Mapping external calls")`

For `{teammate_roles}` in Stage 1 prompts, substitute:
```
- state-vars: State Variable Map — analyzing all storage variables, their readers/writers, and invariants
- access-ctrl: Access Control Map — analyzing all access control modifiers, roles, and gaps
- ext-calls: External Call Map — analyzing all external calls, reentrancy risks, and trust levels
```

**Stage 2 tasks** (one per domain, blocked by Stage 1):

For each domain, call `TaskCreate`:
- `TaskCreate(subject: "Domain: {domain_name}", description: "<filled Stage 2 prompt>", activeForm: "Analyzing {domain_name} domain")`

Then call `TaskUpdate` to set dependencies:
- `TaskUpdate(taskId: "{stage2_task_id}", addBlockedBy: ["{T1_id}", "{T2_id}", "{T3_id}"])`

For `{teammate_roles}` in Stage 2 prompts, list ALL teammates across all stages so domain analysts can message anyone:
```
Stage 1 (completed by now — reference their output files):
- state-vars: State Variable Map → {stage1_state_var_file}
- access-ctrl: Access Control Map → {stage1_access_control_file}
- ext-calls: External Call Map → {stage1_external_call_file}

Stage 2 (your peers — message them about cross-domain findings):
- domain-{slug1}: {domain_1_name} — functions: {function_list_summary_1}
- domain-{slug2}: {domain_2_name} — functions: {function_list_summary_2}
- ... (all domains)

Stage 3 (not started yet):
- state-consistency: State Consistency Audit
- math-rounding: Math & Rounding Audit
- reentrancy-trust: Reentrancy & Trust Boundaries Audit
```

**Stage 3 tasks** (blocked by ALL Stage 2 tasks):

Call `TaskCreate` 3 times:
- `TaskCreate(subject: "State Consistency Audit", description: "<filled Stage 3a prompt>", activeForm: "Auditing state consistency")`
- `TaskCreate(subject: "Math & Rounding Audit", description: "<filled Stage 3b prompt>", activeForm: "Auditing math and rounding")`
- `TaskCreate(subject: "Reentrancy & Trust Audit", description: "<filled Stage 3c prompt>", activeForm: "Auditing reentrancy and trust")`

Then call `TaskUpdate` to set dependencies on ALL Stage 2 task IDs:
- `TaskUpdate(taskId: "{stage3_task_id}", addBlockedBy: ["{T4_id}", "{T5_id}", ..., "{T3+N_id}"])`

For `{teammate_roles}` in Stage 3 prompts:
```
- state-consistency: State Consistency — analyzing accounting invariants, divergent tracking, stale state, transition completeness
- math-rounding: Math & Rounding — analyzing overflow, rounding direction, precision loss, exchange rate manipulation, fee arithmetic
- reentrancy-trust: Reentrancy & Trust — analyzing CEI compliance, delegatecall safety, trust boundaries, external dependencies, callback vectors
```

### Step 3: Spawn teammates using Task tool with team_name

After ALL tasks are created, spawn teammates using the `Task` tool with `team_name` and `name` parameters. Each teammate is a separate Claude Code session.

The shared prompt for ALL teammates (passed as `prompt` to each `Task` call):
```
You are a Solidity security auditor on an agent team performing function rationality analysis.

## How You Work
1. Check the task list (TaskList) for available tasks (status: pending, no owner, no unresolved blockedBy)
2. Claim a task by calling TaskUpdate(taskId: "...", owner: "<your name>", status: "in_progress")
3. Read the task description (TaskGet) for your full analysis prompt
4. Execute the analysis: read source files, write findings to the output file
5. Mark the task as completed: TaskUpdate(taskId: "...", status: "completed")
6. Call TaskList again to check for more available tasks — claim the next one if available

## Communication
- Use SendMessage(type: "message", recipient: "<teammate-name>", content: "...", summary: "...") to message other teammates
- Follow the Communication Guidelines in each task description
- When you receive a message, incorporate the finding into your analysis if relevant

## Plan Mode (Stage 2 Only)
- Stage 2 domain analysis tasks require plan mode
- Call EnterPlanMode, design your analysis approach, then call ExitPlanMode to send for approval
- Only proceed after the lead approves your plan
- Stages 1 and 3 execute directly without plan approval

## Important Rules
- Write ALL analysis to the output file specified in the task using the Write tool. Do NOT return analysis in messages.
- Always use absolute paths when reading files.
- Mark tasks completed only after writing the output file.
```

Spawn teammates with these exact `Task` tool calls:

**Stage 1 teammates** (3):
```
Task(subagent_type: "general-purpose", name: "state-vars", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
Task(subagent_type: "general-purpose", name: "access-ctrl", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
Task(subagent_type: "general-purpose", name: "ext-calls", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
```

**Stage 2 teammates** (one per domain):
```
Task(subagent_type: "general-purpose", name: "domain-{slug}", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "plan")
```
Note: `mode: "plan"` requires plan approval from the lead before they can implement.

**Stage 3 teammates** (3):
```
Task(subagent_type: "general-purpose", name: "state-consistency", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
Task(subagent_type: "general-purpose", name: "math-rounding", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
Task(subagent_type: "general-purpose", name: "reentrancy-trust", team_name: "function-rationality", prompt: "<shared prompt above>", mode: "bypassPermissions")
```

Spawn ALL teammates at once (all stages). Teammates blocked by dependencies will wait automatically — the task list handles stage ordering.

---

## Delegation (Lead Only)

After spawning all teammates:

1. The lead MUST NOT do any analysis work itself — only coordinate
2. Teammates self-claim tasks from the shared list as they become unblocked
3. Monitor progress via `TaskList` tool
4. **Stage 2 plan approval**: When Stage 2 teammates call ExitPlanMode, you receive a plan approval request. Use `SendMessage(type: "plan_approval_response", ...)` to approve or reject. Only approve plans that:
   - Cover ALL listed functions (no omissions)
   - Identify cross-domain state dependencies
   - Have reasonable focus areas
5. When ALL tasks show status "completed" in TaskList, proceed to Synthesis
6. Send shutdown requests to all teammates: `SendMessage(type: "shutdown_request", recipient: "<name>", content: "All tasks complete")`
7. After all teammates shut down, call `TeamDelete` to clean up

### Concurrency
- Stage 1: 3 teammates active simultaneously (tasks have no blockedBy)
- Stage 2: All N domain teammates active simultaneously (tasks unblock together when Stage 1 completes)
- Stage 3: 3 teammates active simultaneously (tasks unblock together when Stage 2 completes)

---

## Synthesis (Lead Only)

After all tasks are completed, the lead performs synthesis directly (not as a teammate task — the lead's context is clean from delegate mode).

### 1. Read All Output Files
Read each file in `docs/audit/function-rationality/` (stage1, stage2, stage3) **one at a time**, tallying findings as you go. Do NOT try to hold all files in context simultaneously — read one, count its findings, then move to the next.

### 2. Count Findings
Parse each file for findings by severity. Use these exact patterns to avoid over-counting:
- Count lines matching `**CRITICAL --` (finding-level severity)
- Count lines matching `**WARNING --` (finding-level severity)
- Count lines matching `**INFO --` (finding-level severity)

Count per-function verdicts using these exact patterns:
- Count lines matching `**Verdict**: **SOUND**`
- Count lines matching `**Verdict**: **NEEDS_REVIEW**`
- Count lines matching `**Verdict**: **ISSUE_FOUND**`

Do NOT count domain-level overall verdicts (e.g., "Overall Domain Verdict: **SOUND**") in the per-function tally — track those separately.

### 3. Write INDEX.md
Write `docs/audit/function-rationality/INDEX.md` containing:
- Table of contents linking to every output file
- Per-file finding counts (Critical / Warning / Info)
- Per-file verdict

Format:
```markdown
# Function Rationality Analysis -- Index

**Generated**: {date}
**Project**: {project_path}
**Method**: Agent Team (inter-agent communication enabled)

## Stage 1: Foundation Context
| File | Description | Findings |
|------|-------------|----------|
| [state-variable-map.md](stage1/state-variable-map.md) | State variable analysis | {C} critical, {W} warnings, {I} info |
| ... | ... | ... |

## Stage 2: Per-Domain Analysis
| File | Domain | Functions | Verdict | Findings |
|------|--------|-----------|---------|----------|
| [domain-{slug}.md](stage2/domain-{slug}.md) | {name} | {N} | {verdict} | {C}C / {W}W / {I}I |
| ... | ... | ... | ... | ... |

## Stage 3: Cross-Cutting Audit
| File | Focus | Findings |
|------|-------|----------|
| [state-consistency.md](stage3/state-consistency.md) | Accounting invariants, divergent tracking | {C}C / {W}W / {I}I |
| ... | ... | ... |

## Totals
- **CRITICAL**: {total}
- **WARNING**: {total}
- **INFO**: {total}
- Functions: **SOUND** {N} | **NEEDS_REVIEW** {N} | **ISSUE_FOUND** {N}
```

### 4. Write SUMMARY.md
Write `docs/audit/function-rationality/SUMMARY.md` containing:
- Executive summary (2-3 paragraphs)
- Top CRITICAL findings (if any) with file links
- Top WARNING findings with file links
- Cross-cutting themes observed
- Inter-agent findings (findings that emerged from teammate communication)
- Recommended action items (prioritized)

### 5. Report to User
Display final stats:
- Total files generated
- Finding breakdown by severity
- Verdict breakdown
- Any CRITICAL findings highlighted
- Links to INDEX.md and SUMMARY.md

---

## Rationalizations (Do Not Skip)

| Rationalization | Why It's Wrong | Required Action |
|-----------------|----------------|-----------------|
| "Return analysis in agent response for efficiency" | Returns fill main context window, causing overflow and losing later stages | ALL teammates must write to files and return only confirmations |
| "Pre-load source files in main context for agents" | Source files consume thousands of lines of context | Teammates read source files themselves via Read tool |
| "Skip Stage 1, agents can figure out context" | Without foundation maps, Stage 2 agents miss cross-function dependencies | Complete all 3 stages sequentially via task dependencies |
| "Run all stages in parallel" | Stage 2 needs Stage 1 output, Stage 3 needs Stage 2 output | Use blockedBy dependencies to enforce stage ordering |
| "Merge small domains to reduce agent count" | Fewer, larger agents hit context limits and produce shallower analysis | Keep domains focused (3-15 functions each) |
| "Skip cross-cutting analysis if no CRITICALs found" | Cross-cutting issues emerge from combining individually-sound functions | Always complete Stage 3 |
| "Summarize from task confirmations instead of reading files" | Confirmations contain no analysis data | Read actual output files for synthesis |
| "Skip user confirmation of domains" | Incorrect domain grouping wastes all subsequent analysis | Confirm domains before launching agents |
| "Skip inter-agent messaging, Stage 3 catches everything" | Stage 2 agents miss cross-domain issues that only emerge when domains communicate in real-time | Include communication guidelines in every task |
| "Spawn only 3 teammates for all stages" | Stage 2 parallelism is bottlenecked; domains wait in queue | Spawn enough teammates for all concurrent tasks |
| "Let lead do synthesis as a task" | Lead context is lean from delegate mode — synthesis benefits from this clean context | Lead runs synthesis directly, not as a teammate task |

---

## Notes

- **Agent teams**: Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in environment.
- **Teammate count**: Spawn at least N teammates where N = max(3, number of domains). Stage 1 uses 3, Stage 2 uses N, Stage 3 uses 3. Teammates self-schedule via the task list.
- **Plan mode**: Only Stage 2 tasks require plan approval. Stage 1 and 3 tasks are structured enough to execute directly.
- **File paths**: Always use absolute paths in task descriptions so teammates can Read files without ambiguity.
- **Error handling**: If a teammate fails or a task gets stuck, the lead should investigate via TaskList and reassign if needed.
- **Idempotency**: Running again overwrites previous output files. Consider renaming the old directory first if you want to preserve it.
