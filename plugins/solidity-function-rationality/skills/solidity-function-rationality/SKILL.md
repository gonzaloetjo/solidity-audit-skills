---
name: solidity-function-rationality
description: Multi-stage parallelized per-function rationality analysis for Solidity contracts. Discovers functions, groups by domain, runs 3 analysis stages (foundation context, per-domain analysis, cross-cutting audit) with all output written to markdown files.
disable-model-invocation: true
---

# Function Rationality Analysis

## Purpose

Perform a comprehensive per-function rationality analysis of all Solidity contracts in a project using a 3-stage parallelized approach. Each stage spawns background agents that write complete analysis to markdown files, keeping the main context window minimal. Stage 1 builds foundation context (state variables, access control, external calls). Stage 2 runs per-domain function analysis using Stage 1 as input. Stage 3 performs cross-cutting audits (state consistency, math/rounding, reentrancy/trust) using all prior output.

---

## Pre-Flight Discovery

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
Build the list of all .sol source file paths (absolute paths) that agents will need to read. Format as one absolute path per line when substituting into `{source_file_list}` placeholders in agent prompts.

---

## Stage 1: Foundation Context (3 background agents)

Launch 3 Task agents, ALL with `run_in_background: true` and `subagent_type: "general-purpose"`.

Read the prompt templates from `resources/STAGE_PROMPTS.md` and fill in the placeholders:
- `{output_file}` — the absolute path to the output markdown file
- `{source_file_list}` — the collected source file paths

| Agent | Output File | Prompt Template |
|-------|------------|-----------------|
| 1a: State Variable Map | `docs/audit/function-rationality/stage1/state-variable-map.md` | Stage 1a from STAGE_PROMPTS.md |
| 1b: Access Control Map | `docs/audit/function-rationality/stage1/access-control-map.md` | Stage 1b from STAGE_PROMPTS.md |
| 1c: External Call Map | `docs/audit/function-rationality/stage1/external-call-map.md` | Stage 1c from STAGE_PROMPTS.md |

### Completion Check
After launching all 3:
1. Use `TaskOutput(block: true, timeout: 300000)` on each agent to wait for completion (up to 5 minutes each)
2. Each agent should return ONLY a short confirmation like "Written to {file} -- {N} items analyzed."
3. Use Glob to verify all 3 files exist: `docs/audit/function-rationality/stage1/*.md`
4. Report Stage 1 completion to user before proceeding

---

## Stage 2: Per-Domain Analysis (N background agents)

Launch ONE Task agent per domain, ALL with `run_in_background: true` and `subagent_type: "general-purpose"`.

Read the Stage 2 prompt template from `resources/STAGE_PROMPTS.md` and fill in:
- `{domain_name}` — the domain name
- `{output_file}` — `docs/audit/function-rationality/stage2/domain-{slug}.md`
- `{stage1_state_var_file}` — absolute path to stage1/state-variable-map.md
- `{stage1_access_control_file}` — absolute path to stage1/access-control-map.md
- `{stage1_external_call_file}` — absolute path to stage1/external-call-map.md
- `{source_file_list}` — source files relevant to this domain
- `{function_list}` — the functions in this domain with their contract and line numbers
- `{template_file}` — absolute path to `resources/FUNCTION_TEMPLATE.md`
- `{example_file}` — absolute path to `resources/EXAMPLE_OUTPUT.md`

### Completion Check
After launching all domain agents:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes each — Stage 2 is the heaviest)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all domain files exist: `docs/audit/function-rationality/stage2/*.md`
4. Report Stage 2 completion to user with domain names and finding counts

---

## Stage 3: Cross-Cutting Analysis (3 background agents)

Launch 3 Task agents, ALL with `run_in_background: true` and `subagent_type: "general-purpose"`.

Read the Stage 3 prompt templates from `resources/STAGE_PROMPTS.md` and fill in:
- `{output_file}` — the absolute path to the output markdown file
- `{stage1_file_list}` — all 3 stage 1 file paths
- `{stage2_file_list}` — all stage 2 domain file paths
- `{source_file_list}` — all source file paths

| Agent | Output File | Prompt Template |
|-------|------------|-----------------|
| 3a: State Consistency | `docs/audit/function-rationality/stage3/state-consistency.md` | Stage 3a from STAGE_PROMPTS.md |
| 3b: Math & Rounding | `docs/audit/function-rationality/stage3/math-rounding.md` | Stage 3b from STAGE_PROMPTS.md |
| 3c: Reentrancy & Trust | `docs/audit/function-rationality/stage3/reentrancy-trust.md` | Stage 3c from STAGE_PROMPTS.md |

### Completion Check
After launching all 3:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes each — Stage 3 reads the most material)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all 3 files exist: `docs/audit/function-rationality/stage3/*.md`
4. Report Stage 3 completion to user

---

## Synthesis

After all 3 stages are complete, the orchestrator (you, in the main context) performs synthesis:

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
| "Return analysis in agent response for efficiency" | Returns fill main context window, causing overflow and losing later stages | ALL agents must write to files and return only confirmations |
| "Pre-load source files in main context for agents" | Source files consume thousands of lines of context | Agents read source files themselves via Read tool |
| "Skip Stage 1, agents can figure out context" | Without foundation maps, Stage 2 agents miss cross-function dependencies | Complete all 3 stages sequentially |
| "Run all stages in parallel" | Stage 2 needs Stage 1 output, Stage 3 needs Stage 2 output | Stages are sequential; agents within each stage are parallel |
| "Merge small domains to reduce agent count" | Fewer, larger agents hit context limits and produce shallower analysis | Keep domains focused (3-15 functions each) |
| "Skip cross-cutting analysis if no CRITICALs found" | Cross-cutting issues emerge from combining individually-sound functions | Always complete Stage 3 |
| "Summarize from agent confirmations instead of reading files" | Confirmations contain no analysis data | Read actual output files for synthesis |
| "Use TaskOutput without block:true" | Agents may not be finished, producing incomplete analysis | Always block and wait for completion |
| "Skip user confirmation of domains" | Incorrect domain grouping wastes all subsequent analysis | Confirm domains before launching agents |

---

## Notes

- **Agent type**: All agents use `subagent_type: "general-purpose"` — no special agents needed.
- **Timeouts**: Stage 1 agents get 5 minutes. Stage 2 and 3 agents get 10 minutes (Stage 2 analyzes many functions, Stage 3 reads the most material).
- **File paths**: Always use absolute paths in agent prompts so agents can Read files without ambiguity.
- **Error handling**: If an agent fails or times out, report the failure and continue with remaining agents. The synthesis step should note which files are missing.
- **Idempotency**: Running again overwrites previous output files. Consider renaming the old directory first if you want to preserve it.
