---
name: solidity-function-audit-team
description: Agent team variant of solidity-function-audit with human-in-the-loop review. Uses agent teams for inter-agent messaging, shared task list with dependencies, plus interactive design decision capture (Stage 0), findings review (Stage 4), and dispute re-evaluation (Stage 5). Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1.
disable-model-invocation: true
---

# Function Audit (Agent Team)

## Purpose

Perform a comprehensive per-function audit using an agent team with human-in-the-loop review. Stage 0 captures design decisions interactively. Stages 1-3 use agent teams with inter-agent messaging and shared task list. Stage 4 presents findings for developer classification. Stage 5 re-evaluates disputed findings. The lead handles pre-flight, Stage 0, synthesis, Stage 4, and Stage 5 directly — only Stages 1-3 are delegated to teammates.

## Prerequisites

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` must be set in `.claude/settings.json` env or shell environment

---

## Pre-Flight Discovery (Lead Only)

### 0. Check for Previous Run
Check if `docs/audit/function-audit/` exists. If it does, ask the user:
- **Archive**: Rename to `docs/audit/function-audit-{YYYY-MM-DD-HHMMSS}/` (using current timestamp) and proceed fresh
- **Overwrite**: Delete contents and proceed
- **Cancel**: Stop execution

If the directory does not exist, proceed normally.

### 1. Identify Project Path
- Use `$ARGUMENTS` as the project path if provided, otherwise use the current working directory.
- Store as `PROJECT_PATH` for all subsequent steps.

### 2. Discover Contracts (lean — Grep only)
Use Glob for `src/**/*.sol` (excluding `src/artifacts/`) to find all source files. Then use Grep for `contract \w+` and `library \w+` to identify contract and library declarations. Do NOT Read entire source files — only Read a specific file when domain grouping is ambiguous (e.g., a function straddles two contracts). The goal is to know file paths + contract names, not to understand the code.

### 3. Discover Functions (lean — Grep only)
Use Grep for `function \w+\(` in each discovered .sol file to find all function declarations. Use Grep context flags (`-A 1` or `-B 1`) to determine visibility from the surrounding lines — do NOT Read full files:
- Collect all `external` and `public` functions
- Also collect `internal` functions (they are often where the real logic lives)
- Skip auto-generated getters and pure view helpers that just return a constant

### 4. Group Into Domains
Group functions into logical domains using these heuristics (in priority order):
1. **Shared modifiers**: Functions sharing the same access control modifier belong together
2. **Shared state writes**: Functions that write to the same state variables belong together
3. **Lifecycle stages**: Functions that form a sequence (request -> process -> claim) belong together
4. **Name prefixes**: Functions with common prefixes (deposit/withdraw, add/remove, register/deregister)

Target 4-10 domains of 3-15 functions each. If the contract has fewer than 15 functions total, use a single domain. If natural grouping exceeds 10 domains, merge the smallest related domains.

### 5. Create Output Directory
```
mkdir -p docs/audit/function-audit/{stage0,stage1,stage2,stage3,review}
```

### 6. Preview Domains
Display to the user:
- Number of contracts found
- Number of functions found
- Domain groupings with function lists
- Proceed to Stage 0 for design decision capture before confirming

### 7. Collect Source File Paths
Build the list of all .sol source file paths (absolute paths) that teammates will need to read. Format as one absolute path per line when substituting into `{source_file_list}` placeholders in teammate prompts.

### 8. Detect Project Characteristics
Scan source files for DeFi-relevant patterns to condition Stage 2/3 prompts:
- **Token interfaces**: Grep for `ERC20`, `ERC721`, `ERC1155`, `ERC4626`, `IERC20`, `SafeERC20` → set `{has_tokens}` true/false
- **Proxy/upgrade patterns**: Grep for `UUPSUpgradeable`, `TransparentProxy`, `Initializable` → set `{has_proxies}` true/false
- **Oracle imports**: Grep for `AggregatorV3Interface`, `IOracle`, `TWAP` → set `{has_oracles}` true/false

---

## Context Compaction Guidance

If auto-compaction occurs during this session, preserve these critical values:
- `PROJECT_PATH` and all source file paths
- Domain groupings with function lists
- All output file absolute paths (stage0/, stage1/, stage2/, stage3/, review/)
- All placeholder values: `{design_decisions_file}`, `{slither_file}`, `{template_file}`, `{example_file}`
- Finding tallies per stage (CRITICAL/HIGH/MEDIUM/LOW/INFO counts)
- Current stage number and completion status of each stage
- Team name (`function-audit`) and all task IDs with their statuses

---

## Stage 0: Design Decisions (Lead Only — interactive)

Capture developer intent before the automated audit. Read `resources/REVIEW_PROMPTS.md` (Stage 0 section) for extraction patterns, confirmation script, and output format. Execute the three phases:

1. **Automated extraction**: Grep source files for NatSpec `@dev` comments, static analysis annotations, intent keywords, and code-level patterns (rounding, access control, upgrades, reentrancy, pausability)
2. **Interactive confirmation**: Present detections grouped by category, ask user to confirm/correct/add context per category
3. **Write output**: Write `docs/audit/function-audit/stage0/design-decisions.md`. Store path as `{design_decisions_file}` for Stage 2 and Stage 3 agent prompts.

### 8. Confirm with User

Display to the user:
- Number of contracts found, functions found, domain groupings
- Design decisions summary (categories and counts)
- Ask for confirmation before proceeding to Stage 1

---

## Slither Integration (Lead Only — between Stage 0 and Stage 1)

Run Slither static analysis if available. This is NOT a teammate — the lead does this directly.

1. Run `which slither` via Bash
2. If not found → display "Slither not detected. Install with `pip install slither-analyzer` for automated static analysis. Continuing without it." → set `{slither_file}` to empty → proceed
3. If found → run `slither . --json /tmp/slither-output.json --exclude-informational --filter-paths "test|script|lib|node_modules" 2>&1 || true`
4. Check if `/tmp/slither-output.json` exists and is non-empty (use Bash: `test -s /tmp/slither-output.json`)
5. If the file doesn't exist or is empty → display "Slither failed to analyze the project (likely a compilation or solc version issue). Continuing without it." → set `{slither_file}` to empty → proceed to Stage 1
6. If the file exists → Read it, map findings (High→HIGH, Medium→MEDIUM, Low→LOW, Informational→INFO), write to `docs/audit/function-audit/stage0/slither-findings.md`
7. Display summary: "Slither found N findings (H high, M medium, L low, I info)"
8. Store path as `{slither_file}` for teammate prompts

---

### 9. Plan Task IDs and Dependency Graph
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
TeamCreate(team_name: "function-audit", description: "Function audit for {PROJECT_PATH}")
```

This creates the shared task list and team config at `~/.claude/teams/function-audit/`.

### Step 2: Create ALL tasks using TaskCreate tool

Create every task upfront BEFORE spawning any teammates. Read the prompt templates from `resources/STAGE_PROMPTS.md` and fill in all placeholders. For Stage 2 and Stage 3 tasks, fill in `{design_decisions_file}` (absolute path to `stage0/design-decisions.md`) and `{slither_file}` (absolute path to `stage0/slither-findings.md`, or empty string if Slither was not run). Stage 1 prompts do not use these placeholders. Each task's `description` field must contain the FULL analysis prompt (the filled-in template from STAGE_PROMPTS.md), not a summary. Build task descriptions mechanically from templates — substitute placeholders without analyzing the code content. The task description is for the teammate, not the lead.

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

For `{source_file_list}` in Stage 2 prompts, scope to domain-relevant files only: include files containing the domain's functions, files containing contracts called by those functions (from Stage 1c external call map), and files containing inherited contracts or imported libraries. Do NOT include all project source files.

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

Each teammate's `prompt` parameter includes a **role-specific opening** followed by shared operational instructions. The role opening gives the agent identity and specialty context.

**Shared operational block** (appended to every role opening):
```
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

## Important Rules
- Write ALL analysis to the output file specified in the task using the Write tool. Do NOT return analysis in messages.
- Always use absolute paths when reading files.
- Mark tasks completed only after writing the output file.
```

**Stage 1 teammates** (3) — each with a specialized role opening:
```
Task(subagent_type: "general-purpose", name: "state-vars", team_name: "function-audit", prompt: "You are **state-vars**, a Solidity security auditor specializing in **state variable analysis** — mapping storage variables, readers/writers, invariants, and duplication risks.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 15)
Task(subagent_type: "general-purpose", name: "access-ctrl", team_name: "function-audit", prompt: "You are **access-ctrl**, a Solidity security auditor specializing in **access control analysis** — mapping roles, modifiers, privilege levels, and authorization gaps.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 15)
Task(subagent_type: "general-purpose", name: "ext-calls", team_name: "function-audit", prompt: "You are **ext-calls**, a Solidity security auditor specializing in **external call analysis** — mapping cross-contract calls, reentrancy vectors, and trust boundaries.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 15)
```

**Stage 2 teammates** (one per domain):
```
Task(subagent_type: "general-purpose", name: "domain-{slug}", team_name: "function-audit", prompt: "You are **domain-{slug}**, a Solidity security auditor specializing in the **{domain_name}** domain — per-function audit of {N} functions covering {brief description}.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 25)
```
Note: Stage 2 teammates send their analysis plan as a message to the lead before executing (see STAGE_PROMPTS.md). This is informational — teammates proceed without waiting for approval.

**Stage 3 teammates** (3):
```
Task(subagent_type: "general-purpose", name: "state-consistency", team_name: "function-audit", prompt: "You are **state-consistency**, a Solidity security auditor specializing in **cross-domain state consistency** — accounting invariants, divergent tracking, stale state, transition completeness.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 25)
Task(subagent_type: "general-purpose", name: "math-rounding", team_name: "function-audit", prompt: "You are **math-rounding**, a Solidity security auditor specializing in **mathematical analysis** — overflow, rounding, precision loss, exchange rate manipulation, fee arithmetic.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 25)
Task(subagent_type: "general-purpose", name: "reentrancy-trust", team_name: "function-audit", prompt: "You are **reentrancy-trust**, a Solidity security auditor specializing in **reentrancy and trust boundary analysis** — CEI compliance, delegatecall safety, trust boundaries, callback vectors.\n\n<shared operational block>", mode: "bypassPermissions", max_turns: 25)
```

Spawn ALL teammates at once (all stages). Teammates blocked by dependencies will wait automatically — the task list handles stage ordering.

---

## Delegation (Lead Only)

After spawning all teammates:

1. The lead MUST NOT do any analysis work itself — only coordinate
2. Teammates self-claim tasks from the shared list as they become unblocked
3. Monitor progress via `TaskList` tool
4. **Stage 2 plan messages**: Stage 2 teammates send their analysis plan as a message before executing. Review these for awareness — if a plan has obvious gaps (missing functions, wrong focus areas), message the teammate with corrections. Teammates do not wait for approval, so respond promptly if you see issues.
5. When ALL tasks show status "completed" in TaskList, quick-validate all output files before proceeding:
   - Use Glob to verify files exist in `stage1/*.md`, `stage2/*.md`, and `stage3/*.md`
   - Read the first 5 and last 5 lines of each file. Verify each is non-empty and contains `## ` headings
   - For Stage 2 files: verify they contain `## Summary of Findings` or `## Cross-Cutting Analysis` and at least one severity tag (`**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, or `**INFO -- `)
   - For Stage 3 files: verify they contain at least one severity tag
   - If validation fails for any file, note it as INCOMPLETE in synthesis
6. Proceed to Synthesis
7. Send shutdown requests to all teammates: `SendMessage(type: "shutdown_request", recipient: "<name>", content: "All tasks complete")`
7. After all teammates shut down, call `TeamDelete` to clean up

### Concurrency
- Stage 1: 3 teammates active simultaneously (tasks have no blockedBy)
- Stage 2: All N domain teammates active simultaneously (tasks unblock together when Stage 1 completes)
- Stage 3: 3 teammates active simultaneously (tasks unblock together when Stage 2 completes)

---

## Synthesis (Lead Only)

After all tasks are completed, the lead performs synthesis directly (not as a teammate task — the lead's context is clean from delegate mode).

### 1. Gather Findings via Grep (do NOT read full files)
Use **Grep** to extract all findings and verdicts in one pass — do NOT read each output file in full:
- `Grep(pattern: "\\*\\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ", path: "docs/audit/function-audit/", output_mode: "content")` — returns all findings with file paths and line numbers
- `Grep(pattern: "\\*\\*Verdict\\*\\*: \\*\\*", path: "docs/audit/function-audit/", output_mode: "content")` — returns all verdicts

### 2. Tally Findings from Grep Results
From the Grep output, count findings per severity per file:
- Count `**CRITICAL --`, `**HIGH --`, `**MEDIUM --`, `**LOW --`, `**INFO --` matches per file

Count per-function verdicts:
- Count `**Verdict**: **SOUND**`, `**Verdict**: **NEEDS_REVIEW**`, `**Verdict**: **ISSUE_FOUND**` matches

Do NOT count domain-level overall verdicts in the per-function tally — track those separately.

### 3. Extract Finding Details for Master Table
From the Grep results, extract each finding's severity, title, source file path, and location. Only Read individual files briefly (first/last 10 lines) for executive summary context. Build task descriptions mechanically from templates — substitute placeholders without analyzing the code content.

### 4. Write INDEX.md
Write `docs/audit/function-audit/INDEX.md` with sections for Stage 0, Stage 1, Stage 2 (per-domain with verdicts), Stage 3, an "All Findings" master table (sorted by severity: CRITICAL first), and Totals. Include `**Method**: Agent Team (inter-agent communication enabled)` in the header. Link every output file with finding counts using 5-level format (`{C}C / {H}H / {M}M / {L}L / {I}I`).

The "All Findings" table format:
```markdown
## All Findings

| # | Severity | Finding | Location | Source File |
|---|----------|---------|----------|-------------|
| 1 | CRITICAL | {title} | `Contract.function()` L{line} | [domain-{slug}.md](stage2/domain-{slug}.md) |
| ... | ... | ... | ... | ... |
```

### 5. Write SUMMARY.md
Write `docs/audit/function-audit/SUMMARY.md` containing:
- Executive summary (2-3 paragraphs)
- Top CRITICAL and HIGH findings (if any) with file links
- Notable MEDIUM findings with file links
- Cross-cutting themes observed
- Inter-agent findings (findings that emerged from teammate communication)
- Recommended action items (prioritized)

### 6. Report to User
Display finding stats and ask if the user wants to proceed to human review:
- Total files generated
- Finding breakdown by severity (5 levels)
- Verdict breakdown
- Any CRITICAL or HIGH findings highlighted
- "Proceed to findings review? [yes/no]"

If the user declines, output links to INDEX.md and SUMMARY.md and stop.

---

## Stage 4: Human Review (Lead Only — interactive)

Read the review flow from `resources/REVIEW_PROMPTS.md` (Stage 4 section). Execute interactively:

1. **Extract findings**: Parse all stage2/ and stage3/ files for `**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, `**INFO -- ` patterns. Note `DESIGN_DECISION -- ` tagged findings separately.
2. **Present CRITICALs** (if any): Numbered list, ask user to classify each: `BUG`, `DESIGN`, `DISPUTED`, or `DISCUSS`.
3. **Present HIGHs** (if any): Same format.
4. **Present MEDIUMs** (if any): Same format.
5. **Present LOWs and INFOs**: Summary count, opt-in to review.
6. **Follow-up on DISPUTED/DISCUSS**: Show full finding + source code, record developer reasoning.
6. **Write output**: `docs/audit/function-audit/review/review-responses.md`

---

## Stage 5: Re-Evaluation (Lead Only — conditional, 1 agent)

**Skip this stage** if no DISPUTED or DISCUSS items exist from Stage 4.

If items exist: read the Stage 5 agent prompt from `resources/REVIEW_PROMPTS.md`, fill in placeholders (`{output_file}`, `{design_decisions_file}`, `{review_responses_file}`, `{source_file_list}`, `{disputed_findings}`), and launch ONE Task agent with `run_in_background: true`, `subagent_type: "general-purpose"`, `mode: "bypassPermissions"`, `max_turns: 15`. Wait with `TaskOutput(block: true, timeout: 600000)`. Quick-validate the re-evaluation output: verify `review/re-evaluation.md` is non-empty and contains at least one `## ` heading. If validation fails, report the issue to the user.

### Final Synthesis Update

Update `SUMMARY.md` with a "Human Review" section (classification table + before/after status). Update `INDEX.md` with review file links. Display final summary to the user.

---

## Guardrails

- **All teammates write to files** — never return analysis in responses. Returns fill the main context window and cause overflow in later stages.
- **Use blockedBy dependencies** — Stage 2 needs Stage 1 output, Stage 3 needs Stage 2 output. Only teammates *within* each stage run in parallel.
- **Always complete Stage 3** — cross-cutting issues emerge from combining individually-sound functions, even when no CRITICALs are found in Stage 2.
- **Include communication guidelines** — Stage 2 agents miss cross-domain issues that only emerge when domains communicate in real-time. Every task must have communication guidelines.
- **Lead runs synthesis directly** — lead's context is lean from delegate mode; synthesis benefits from this clean context.
- **Stage 0 is best-effort** — if no design signals are detected, write an empty design-decisions.md and proceed. Agents evaluate independently.
- **Stage 4 requires patience** — present findings in severity batches. Let the user classify at their own pace. Never auto-classify.
- **Stage 5 is conditional** — only runs if DISPUTED or DISCUSS items exist. Do not spawn the agent otherwise.

---

## Notes

- **Agent teams**: Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in environment.
- **Teammate count**: Spawn at least N teammates where N = max(3, number of domains). Stage 1 uses 3, Stage 2 uses N, Stage 3 uses 3. Teammates self-schedule via the task list.
- **Stage 2 planning**: Stage 2 teammates design and share their analysis plan via messaging before executing. This is prompt-enforced (not permission-enforced) to avoid deadlocks with the plan approval protocol.
- **File paths**: Always use absolute paths in task descriptions so teammates can Read files without ambiguity.
- **Error handling**: If a teammate fails or a task gets stuck, the lead should investigate via TaskList and reassign if needed. In synthesis, note missing files in INDEX.md with status `INCOMPLETE — agent failed` and proceed using available outputs.
- **Previous runs**: Step 0 of Pre-Flight checks for existing output and offers archive, overwrite, or cancel options.
