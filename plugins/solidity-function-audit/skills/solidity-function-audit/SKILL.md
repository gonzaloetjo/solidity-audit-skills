---
name: solidity-function-audit
description: Multi-stage parallelized per-function audit for Solidity contracts with human-in-the-loop review. Discovers functions, captures design decisions, runs 3 analysis stages, then presents findings for developer classification and re-evaluation of disputed items.
disable-model-invocation: true
---

# Function Audit

## Purpose

Perform a comprehensive per-function audit of all Solidity contracts in a project using a 6-stage approach. Stage 0 captures design decisions interactively. Stages 1-3 spawn background agents for parallelized analysis. Stage 4 presents findings for developer classification. Stage 5 re-evaluates disputed findings. Stages 0, 4, and 5 are orchestrator-interactive (no agents spawned). Stages 1-3 write to markdown files, keeping the main context window minimal.

---

## Pre-Flight Discovery

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
Build the list of all .sol source file paths (absolute paths) that agents will need to read. Format as one absolute path per line when substituting into `{source_file_list}` placeholders in agent prompts.

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

---

## Stage 0: Design Decisions (orchestrator-interactive)

Capture developer intent before the automated audit. This prevents design trade-offs from being flagged as bugs.

### Phase A — Automated Extraction

Read the extraction patterns from `resources/REVIEW_PROMPTS.md` (Stage 0 section). Using the source files already discovered in pre-flight:

1. Use Grep to scan for NatSpec `@dev` comments, static analysis annotations (`slither-disable`, `solhint-disable`, `@audit`), and intent keywords (`intentional`, `by design`, `trade-off`, `known`, `accepted`, `deliberate`)
2. Detect code-level patterns: rounding direction helpers, access control model (`Ownable`/`AccessControl`/custom), upgrade strategy, `nonReentrant` coverage gaps, `whenNotPaused` coverage gaps
3. Group all detections by category (Rounding Policy, Access Control Model, Upgrade Strategy, Reentrancy Approach, Pausability, Known Trade-offs)

### Phase B — Interactive Confirmation

Present each category to the user following the confirmation script in REVIEW_PROMPTS.md:
- Show detected items as a numbered table per category
- Ask the user to confirm, correct, or add context per category
- After all categories: "Any additional design decisions or context the auditors should know?"

### Phase C — Write Output

Write `docs/audit/function-audit/stage0/design-decisions.md` using the output format from REVIEW_PROMPTS.md. Store the absolute path as `{design_decisions_file}` for substitution into agent prompts in Stages 2-3.

### 8. Confirm with User

Display to the user:
- Number of contracts found
- Number of functions found
- Domain groupings with function lists
- Design decisions summary (categories and counts)
- Ask for confirmation before proceeding to Stage 1

---

## Slither Integration (orchestrator — between Stage 0 and Stage 1)

Run Slither static analysis if available. This is NOT an agent — the orchestrator does this directly.

1. Run `which slither` via Bash
2. If not found → display "Slither not detected. Install with `pip install slither-analyzer` for automated static analysis. Continuing without it." → set `{slither_file}` to empty → proceed to Stage 1
3. If found → run `slither . --json /tmp/slither-output.json --exclude-informational --filter-paths "test|script|lib|node_modules" 2>&1 || true`
4. Check if `/tmp/slither-output.json` exists and is non-empty (use Bash: `test -s /tmp/slither-output.json`)
5. If the file doesn't exist or is empty → display "Slither failed to analyze the project (likely a compilation or solc version issue). Continuing without it." → set `{slither_file}` to empty → proceed to Stage 1
6. If the file exists → Read it, map findings (High→HIGH, Medium→MEDIUM, Low→LOW, Informational→INFO), write to `docs/audit/function-audit/stage0/slither-findings.md`
7. Display summary: "Slither found N findings (H high, M medium, L low, I info)"
8. Store path as `{slither_file}` for agent prompts

---

## Stage 1: Foundation Context (3 background agents)

Launch 3 Task agents, ALL with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 15`.

Read the prompt templates from `resources/STAGE_PROMPTS.md` and fill in the placeholders:
- `{output_file}` — the absolute path to the output markdown file
- `{source_file_list}` — the collected source file paths

| Agent | Output File | Prompt Template |
|-------|------------|-----------------|
| 1a: State Variable Map | `docs/audit/function-audit/stage1/state-variable-map.md` | Stage 1a from STAGE_PROMPTS.md |
| 1b: Access Control Map | `docs/audit/function-audit/stage1/access-control-map.md` | Stage 1b from STAGE_PROMPTS.md |
| 1c: External Call Map | `docs/audit/function-audit/stage1/external-call-map.md` | Stage 1c from STAGE_PROMPTS.md |

### Completion Check
After launching all 3:
1. Use `TaskOutput(block: true, timeout: 300000)` on each agent to wait for completion (up to 5 minutes each)
2. Each agent should return ONLY a short confirmation like "Written to {file} -- {N} items analyzed."
3. Use Glob to verify all 3 files exist: `docs/audit/function-audit/stage1/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty and contains at least one markdown heading (`## `). If validation fails for any file, report the issue to the user and note the file as INCOMPLETE in synthesis.
5. Report Stage 1 completion to user before proceeding

---

## Stage 2: Per-Domain Analysis (N background agents)

Launch ONE Task agent per domain, ALL with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 25`.

Read the Stage 2 prompt template from `resources/STAGE_PROMPTS.md` and fill in:
- `{domain_name}` — the domain name
- `{output_file}` — `docs/audit/function-audit/stage2/domain-{slug}.md`
- `{stage1_state_var_file}` — absolute path to stage1/state-variable-map.md
- `{stage1_access_control_file}` — absolute path to stage1/access-control-map.md
- `{stage1_external_call_file}` — absolute path to stage1/external-call-map.md
- `{design_decisions_file}` — absolute path to `stage0/design-decisions.md` (if Stage 0 produced output)
- `{slither_file}` — absolute path to `stage0/slither-findings.md` (empty string if Slither was not run)
- `{source_file_list}` — source files relevant to this domain: include files containing the domain's functions, files containing contracts called by those functions (from Stage 1c external call map), and files containing inherited contracts or imported libraries. Do NOT include all project source files — scope to what this domain needs.
- `{function_list}` — the functions in this domain with their contract and line numbers
- `{template_file}` — absolute path to `resources/FUNCTION_TEMPLATE.md`
- `{example_file}` — absolute path to `resources/EXAMPLE_OUTPUT.md`

### Completion Check
After launching all domain agents:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes each — Stage 2 is the heaviest)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all domain files exist: `docs/audit/function-audit/stage2/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty, contains at least one `## ` heading, contains `## Summary of Findings` or `## Cross-Cutting Analysis`, and has at least one severity tag (`**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, or `**INFO -- `). If validation fails, note the file as INCOMPLETE in synthesis.
5. Report Stage 2 completion to user with domain names and finding counts

---

## Stage 3: Cross-Cutting Analysis (3 background agents)

Launch 3 Task agents, ALL with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 25`.

Read the Stage 3 prompt templates from `resources/STAGE_PROMPTS.md` and fill in:
- `{output_file}` — the absolute path to the output markdown file
- `{stage1_file_list}` — all 3 stage 1 file paths
- `{stage2_file_list}` — all stage 2 domain file paths
- `{design_decisions_file}` — absolute path to `stage0/design-decisions.md` (if Stage 0 produced output)
- `{slither_file}` — absolute path to `stage0/slither-findings.md` (empty string if Slither was not run)
- `{source_file_list}` — all source file paths

| Agent | Output File | Prompt Template |
|-------|------------|-----------------|
| 3a: State Consistency | `docs/audit/function-audit/stage3/state-consistency.md` | Stage 3a from STAGE_PROMPTS.md |
| 3b: Math & Rounding | `docs/audit/function-audit/stage3/math-rounding.md` | Stage 3b from STAGE_PROMPTS.md |
| 3c: Reentrancy & Trust | `docs/audit/function-audit/stage3/reentrancy-trust.md` | Stage 3c from STAGE_PROMPTS.md |

### Completion Check
After launching all 3:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes each — Stage 3 reads the most material)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all files exist: `docs/audit/function-audit/stage3/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty, contains at least one `## ` heading, and has at least one severity tag (`**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, or `**INFO -- `). If validation fails, note the file as INCOMPLETE in synthesis.
5. Report Stage 3 completion to user

---

## Synthesis

After all 3 stages are complete, the orchestrator (you, in the main context) performs synthesis:

### 1. Gather Findings via Grep (do NOT read full files)
Use **Grep** to extract all findings and verdicts in one pass — do NOT read each output file in full:
- `Grep(pattern: "\\*\\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ", path: "docs/audit/function-audit/", output_mode: "content")` — returns all findings with file paths and line numbers
- `Grep(pattern: "\\*\\*Verdict\\*\\*: \\*\\*", path: "docs/audit/function-audit/", output_mode: "content")` — returns all verdicts

### 2. Tally Findings from Grep Results
From the Grep output, count findings per severity per file:
- Count `**CRITICAL --` matches per file
- Count `**HIGH --` matches per file
- Count `**MEDIUM --` matches per file
- Count `**LOW --` matches per file
- Count `**INFO --` matches per file

Count per-function verdicts:
- Count `**Verdict**: **SOUND**` matches
- Count `**Verdict**: **NEEDS_REVIEW**` matches
- Count `**Verdict**: **ISSUE_FOUND**` matches

Do NOT count domain-level overall verdicts (e.g., "Overall Domain Verdict:") in the per-function tally — track those separately.

### 3. Extract Finding Details for Master Table
From the Grep results in step 1, extract each finding's:
- Severity tag (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO`)
- Finding title (text after `-- ` up to `**`)
- Source file path (from Grep output)
- Location: use `Grep(pattern: "### \\w+", path: "{file}")` on each file with findings to map findings to their parent function

Only Read individual files briefly (first/last 10 lines) for executive summary context.

### 4. Write INDEX.md
Write `docs/audit/function-audit/INDEX.md` containing:

```markdown
# Function Audit -- Index

**Generated**: {date}
**Project**: {project_path}

## Stage 0: Design Decisions
| File | Description |
|------|-------------|
| [design-decisions.md](stage0/design-decisions.md) | Developer-confirmed design intent ({N} categories) |

## Stage 1: Foundation Context
| File | Description | Findings |
|------|-------------|----------|
| [state-variable-map.md](stage1/state-variable-map.md) | State variable analysis | {C}C / {H}H / {M}M / {L}L / {I}I |
| ... | ... | ... |

## Stage 2: Per-Domain Analysis
| File | Domain | Functions | Verdict | Findings |
|------|--------|-----------|---------|----------|
| [domain-{slug}.md](stage2/domain-{slug}.md) | {name} | {N} | {verdict} | {C}C / {H}H / {M}M / {L}L / {I}I |
| ... | ... | ... | ... | ... |

## Stage 3: Cross-Cutting Audit
| File | Focus | Findings |
|------|-------|----------|
| [state-consistency.md](stage3/state-consistency.md) | Accounting invariants, divergent tracking | {C}C / {H}H / {M}M / {L}L / {I}I |
| ... | ... | ... |

## All Findings

| # | Severity | Finding | Location | Source File |
|---|----------|---------|----------|-------------|
| 1 | CRITICAL | {title} | `Contract.function()` L{line} | [domain-{slug}.md](stage2/domain-{slug}.md) |
| 2 | HIGH | {title} | `Contract.function()` L{line} | [state-consistency.md](stage3/state-consistency.md) |
| ... | ... | ... | ... | ... |

Sort by severity (CRITICAL first, then HIGH, MEDIUM, LOW, INFO).

## Totals
- **CRITICAL**: {total}
- **HIGH**: {total}
- **MEDIUM**: {total}
- **LOW**: {total}
- **INFO**: {total}
- Functions: **SOUND** {N} | **NEEDS_REVIEW** {N} | **ISSUE_FOUND** {N}
```

### 5. Write SUMMARY.md
Write `docs/audit/function-audit/SUMMARY.md` containing:
- Executive summary (2-3 paragraphs)
- Top CRITICAL and HIGH findings (if any) with file links
- Notable MEDIUM findings with file links
- Cross-cutting themes observed
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

## Stage 4: Human Review (orchestrator-interactive)

Read the review flow from `resources/REVIEW_PROMPTS.md` (Stage 4 section). Execute interactively:

1. **Extract findings**: Parse all stage2/ and stage3/ files for `**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, `**INFO -- ` patterns. Also note `DESIGN_DECISION -- ` tagged findings separately.

2. **Present CRITICALs** (if any): Numbered list with finding title, source function, file link. Ask user to classify each: `BUG`, `DESIGN`, `DISPUTED`, or `DISCUSS`.

3. **Present HIGHs** (if any): Same format.

4. **Present MEDIUMs** (if any): Same format.

5. **Present LOWs and INFOs**: Show count summary (total LOWs, total INFOs, design-decision tagged, other). Ask "Review LOWs and INFOs? [skip/review]". If review, present in batches of 10.

6. **Follow-up on DISPUTED/DISCUSS**: For each, show full finding text + relevant source code, ask user for reasoning, record response.

6. **Write output**: Write `docs/audit/function-audit/review/review-responses.md` using the format from REVIEW_PROMPTS.md.

---

## Stage 5: Re-Evaluation (conditional, 1 background agent)

**Skip this stage entirely** if no findings were classified as DISPUTED or DISCUSS in Stage 4.

If DISPUTED or DISCUSS items exist:

1. Read the Stage 5 agent prompt from `resources/REVIEW_PROMPTS.md`
2. Fill in placeholders:
   - `{output_file}` — `docs/audit/function-audit/review/re-evaluation.md`
   - `{design_decisions_file}` — absolute path to `stage0/design-decisions.md`
   - `{review_responses_file}` — absolute path to `review/review-responses.md`
   - `{source_file_list}` — all source file paths
   - `{disputed_findings}` — the full text of each DISPUTED/DISCUSS finding with developer reasoning
3. Launch ONE Task agent with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 15`
4. Wait with `TaskOutput(block: true, timeout: 600000)`
5. Quick-validate the re-evaluation output: Read the first 5 and last 5 lines of `review/re-evaluation.md`. Verify it is non-empty and contains at least one `## ` heading. If validation fails, report the issue to the user.

### Final Synthesis Update

After Stage 5 completes (or is skipped), update `SUMMARY.md` with a "Human Review" section:

```markdown
## Human Review

| # | Finding | Original | Classification | Final Status |
|---|---------|----------|----------------|-------------|
| 1 | {title} | CRITICAL | BUG | BUG |
| 2 | {title} | HIGH | DISPUTED | UPHELD (HIGH) |
| 3 | {title} | MEDIUM | DISPUTED | WITHDRAWN |

- **Confirmed bugs**: {N}
- **Design decisions**: {N}
- **Upheld after dispute**: {N}
- **Withdrawn after dispute**: {N}
- **Downgraded**: {N}
- **Needs testing**: {N}
```

Also update INDEX.md to include the review section:
```markdown
## Human Review
| File | Description |
|------|-------------|
| [review-responses.md](review/review-responses.md) | Developer classifications ({N} findings reviewed) |
| [re-evaluation.md](review/re-evaluation.md) | Re-evaluation of {N} disputed findings |
```

Display final summary to the user with links to all output files.

---

## Guardrails

- **All agents write to files** — never return analysis in responses. Returns fill the main context window and cause overflow in later stages.
- **Stages are sequential** — Stage 0 → 1 → 2 → 3 → Synthesis → 4 → 5. Only agents *within* each stage run in parallel.
- **Always complete Stage 3** — cross-cutting issues emerge from combining individually-sound functions, even when no CRITICALs are found in Stage 2.
- **Always block on TaskOutput** — use `block: true` and wait for agent completion. Unfinished agents produce incomplete analysis.
- **Stage 0 is best-effort** — if no design signals are detected, write an empty design-decisions.md and proceed. Agents evaluate independently.
- **Stage 4 requires patience** — present findings in severity batches, not one-by-one. Let the user classify at their own pace. Never auto-classify.
- **Stage 5 is conditional** — only runs if DISPUTED or DISCUSS items exist. Do not spawn the re-evaluation agent otherwise.

---

## Notes
- **Agents**: All use `subagent_type: "general-purpose"` with absolute paths in all prompts.
- **Error handling**: If an agent fails or times out, report the failure and continue with remaining agents. Note missing files in INDEX.md as `INCOMPLETE — agent failed`.
- **Previous runs**: Step 0 of Pre-Flight checks for existing output and offers archive, overwrite, or cancel options.
