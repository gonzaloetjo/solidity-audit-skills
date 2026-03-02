---
name: solidity-function-audit-eval
description: Non-interactive eval variant of the per-function Solidity audit. Removes all interactive prompts for automated evaluation via `claude -p` mode. Reads design decisions from GROUND_TRUTH.md, skips Slither, always runs verification, stops after Verification.
disable-model-invocation: true
---

# Function Audit — Eval Mode

## Purpose

Non-interactive variant of solidity-function-audit for automated evaluation. Runs the same 7-stage pipeline but removes all 12 interactive pause points: pre-seeds design decisions from GROUND_TRUTH.md, auto-confirms domains, skips Slither, always runs verification, and stops after Verification (no Stage 4/5).

Designed for invocation via `claude -p` with `--dangerously-skip-permissions`.

---

## Pre-Flight Discovery

### 0. Clear Previous Output
If `docs/audit/function-audit/` exists, delete its contents and proceed (always overwrite — no archive/cancel prompt).

### 1. Identify Project Path
- Use `$ARGUMENTS` as the project path if provided, otherwise use the current working directory.
- Store as `PROJECT_PATH` for all subsequent steps.

### 2. Discover Contracts (lean — Grep only)
Use Glob for `src/**/*.sol` (excluding `src/artifacts/`) to find all source files. Then use Grep for `contract \w+` and `library \w+` to identify contract and library declarations. Do NOT Read entire source files — only Read a specific file when domain grouping is ambiguous. The goal is to know file paths + contract names.

### 3. Discover Functions (lean — Grep only)
Use Grep for `function \w+\(` in each discovered .sol file to find all function declarations. Use Grep context flags (`-A 1` or `-B 1`) to determine visibility:
- Collect all `external` and `public` functions
- Also collect `internal` functions
- Skip auto-generated getters and pure view helpers that just return a constant

### 4. Group Into Domains
Group functions into logical domains using these heuristics (in priority order):
1. **Shared modifiers**: Functions sharing the same access control modifier belong together
2. **Shared state writes**: Functions that write to the same state variables belong together
3. **Lifecycle stages**: Functions that form a sequence (request -> process -> claim) belong together
4. **Name prefixes**: Functions with common prefixes (deposit/withdraw, add/remove)

Target 4-10 domains of 3-15 functions each. If the contract has fewer than 15 functions total, use a single domain. If natural grouping exceeds 10 domains, merge the smallest related domains.

### 5. Create Output Directory
```
mkdir -p docs/audit/function-audit/{stage0,stage1,stage2,stage3,verification}
```

### 6. Collect Source File Paths
Build the list of all .sol source file paths (absolute paths) for `{source_file_list}` placeholders.

### 7. Detect Project Characteristics
Scan source files for DeFi-relevant patterns:
- **Token interfaces**: Grep for `ERC20`, `ERC721`, `ERC1155`, `ERC4626`, `IERC20`, `SafeERC20` → set `{has_tokens}` true/false
- **Proxy/upgrade patterns**: Grep for `UUPSUpgradeable`, `TransparentProxy`, `Initializable` → set `{has_proxies}` true/false
- **Oracle imports**: Grep for `AggregatorV3Interface`, `IOracle`, `TWAP` → set `{has_oracles}` true/false

---

## Session State Checkpoint

After each completed stage, write `{output_root}/stage-checkpoint.md` using the Write tool (full overwrite). Include:
- `PROJECT_PATH`, `OUTPUT_ROOT`
- `STAGE_STATUS`: key=value pairs for each stage. Write as a standalone line starting with `STAGE_STATUS:` — this line is machine-parsed by the PreCompact hook.
- `DOMAINS`: one line per domain with slug, name, and function list
- `FLAGS`: `has_tokens`, `has_proxies`, `has_oracles`
- `PATHS`: `design_decisions_file` and all stage output file paths known so far
- After Synthesis: `FINDING_TOTALS` with severity counts

Before each stage, read the checkpoint file to confirm all paths and domain groupings. If state has been lost, recover via:
1. `Glob(pattern: "**/docs/audit/function-audit/stage-checkpoint.md")`
2. Read the file to restore all session state
3. Resume from the last completed stage

---

## Stage 0: Design Decisions (automated — no interaction)

Read the project's `GROUND_TRUTH.md` file. Extract `design_decisions_preset` from the YAML frontmatter. Use Glob to find `GROUND_TRUTH.md` in the project root or parent directories.

If `design_decisions_preset` is found, write `docs/audit/function-audit/stage0/design-decisions.md` containing the preset values formatted as design decision categories:
- **Upgradeable**: value of `upgradeable`
- **Token Standard**: value of `token_standard`
- **Access Control Model**: value of `access_control`
- **Oracle Usage**: value of `oracle_usage`
- **Notes**: value of `notes`

If `GROUND_TRUTH.md` is not found or has no preset, run the automated extraction from `resources/REVIEW_PROMPTS.md` (Stage 0 section) using Grep patterns — but skip the interactive confirmation. Write whatever is detected.

Store the absolute path as `{design_decisions_file}`.

Update the session state checkpoint (Stage 0 complete). Proceed immediately to Stage 1 (skip Slither entirely).

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
1. Use `TaskOutput(block: true, timeout: 300000)` on each agent to wait for completion
2. Each agent should return ONLY a short confirmation like "Written to {file} -- {N} items analyzed."
3. Use Glob to verify all 3 files exist: `docs/audit/function-audit/stage1/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty and contains at least one markdown heading (`## `). If validation fails, note the file as INCOMPLETE in synthesis.
5. Update the session state checkpoint (Stage 1 complete, add stage1 file paths).

---

## Stage 2: Per-Domain Analysis (N background agents)

Launch ONE Task agent per domain, ALL with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 25`.

Read the Stage 2 prompt template from `resources/STAGE_PROMPTS.md` and fill in:
- `{domain_name}` — the domain name
- `{output_file}` — `docs/audit/function-audit/stage2/domain-{slug}.md`
- `{stage1_state_var_file}` — absolute path to stage1/state-variable-map.md
- `{stage1_access_control_file}` — absolute path to stage1/access-control-map.md
- `{stage1_external_call_file}` — absolute path to stage1/external-call-map.md
- `{design_decisions_file}` — absolute path to `stage0/design-decisions.md`
- `{slither_file}` — empty string (Slither is skipped in eval mode)
- `{source_file_list}` — source files relevant to this domain only
- `{function_list}` — the functions in this domain with their contract and line numbers
- `{template_file}` — absolute path to `resources/FUNCTION_TEMPLATE.md`
- `{example_file}` — absolute path to `resources/EXAMPLE_OUTPUT.md`

### Completion Check
After launching all domain agents:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all domain files exist: `docs/audit/function-audit/stage2/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty, contains at least one `## ` heading, contains `## Summary of Findings` or `## Cross-Cutting Analysis`, and has at least one severity tag. If validation fails, note the file as INCOMPLETE.
5. Update the session state checkpoint (Stage 2 complete, add stage2 file paths).

---

## Stage 3: Cross-Cutting Analysis (4 background agents)

Launch 4 Task agents, ALL with `run_in_background: true`, `subagent_type: "general-purpose"`, and `max_turns: 25`.

Read the Stage 3 prompt templates from `resources/STAGE_PROMPTS.md` and fill in:
- `{output_file}` — the absolute path to the output markdown file
- `{stage1_file_list}` — all 3 stage 1 file paths
- `{stage2_file_list}` — all stage 2 domain file paths
- `{design_decisions_file}` — absolute path to `stage0/design-decisions.md`
- `{slither_file}` — empty string (Slither skipped)
- `{source_file_list}` — all source file paths

| Agent | Output File | Prompt Template |
|-------|------------|-----------------|
| 3a: State Consistency | `docs/audit/function-audit/stage3/state-consistency.md` | Stage 3a from STAGE_PROMPTS.md |
| 3b: Math & Rounding | `docs/audit/function-audit/stage3/math-rounding.md` | Stage 3b from STAGE_PROMPTS.md |
| 3c: Reentrancy & Trust | `docs/audit/function-audit/stage3/reentrancy-trust.md` | Stage 3c from STAGE_PROMPTS.md |
| 3d: Adversarial Sequences | `docs/audit/function-audit/stage3/adversarial-sequences.md` | Stage 3d from STAGE_PROMPTS.md |

### Completion Check
After launching all 4:
1. Use `TaskOutput(block: true, timeout: 600000)` on each agent (up to 10 minutes)
2. Each agent should return ONLY a short confirmation
3. Use Glob to verify all files exist: `docs/audit/function-audit/stage3/*.md`
4. Quick-validate each output file: Read the first 5 and last 5 lines. Verify the file is non-empty, contains at least one `## ` heading, and has at least one severity tag. If validation fails, note the file as INCOMPLETE.
5. Update the session state checkpoint (Stage 3 complete, add stage3 file paths).

---

## Synthesis

After all 3 stages complete, perform synthesis (identical to the solo variant):

### 1. Gather Findings via Grep (do NOT read full files)
- `Grep(pattern: "\\*\\*(CRITICAL|HIGH|MEDIUM|LOW|INFO) -- ", path: "docs/audit/function-audit/", output_mode: "content")` — all findings
- `Grep(pattern: "\\*\\*Verdict\\*\\*: \\*\\*", path: "docs/audit/function-audit/", output_mode: "content")` — all verdicts

### 2. Tally Findings
Count findings per severity per file. Count per-function verdicts (SOUND, NEEDS_REVIEW, ISSUE_FOUND). Do NOT count domain-level overall verdicts in the per-function tally.

### 3. Extract Finding Details for Master Table
From the Grep results, extract each finding's severity, title, source file path, and parent function.

### 4. Write INDEX.md
Write `docs/audit/function-audit/INDEX.md` with the standard format: stage sections, All Findings master table sorted by severity, totals.

### 5. Write SUMMARY.md
Write `docs/audit/function-audit/SUMMARY.md` with executive summary, top findings, cross-cutting themes, and action items.

Update the session state checkpoint (Synthesis complete, add finding tallies). Proceed immediately to Verification.

---

## Verification (sequential background agents)

Using the "All Findings" master table from INDEX.md, collect all CRITICAL, HIGH, and MEDIUM findings. Always run verification — no opt-in prompt.

### Setup
```
mkdir -p docs/audit/function-audit/verification
mkdir -p test/audit-verification
```

### Per-Finding Agents (CRITICAL and HIGH — sequential)

For each CRITICAL/HIGH finding (CRITICALs first, then HIGHs):

1. Read the per-finding prompt from `resources/VERIFICATION_PROMPTS.md` and fill in placeholders:
   - `{finding_number}`, `{finding_severity}`, `{finding_title}`, `{finding_source_file}`, `{finding_function}`
   - `{output_file}` — `docs/audit/function-audit/verification/finding-{NNN}.md`
   - `{test_dir}` — absolute path to `{PROJECT_PATH}/test/audit-verification/`
   - `{test_name}` — `AuditVerify_{NNN}_{ContractName}`
   - `{source_file_list}`, `{stage1_file_list}`, `{design_decisions_file}`
2. Launch ONE Task agent: `subagent_type: "solidity-function-audit-eval:solidity-verifier"`, `max_turns: 20`
3. **Wait**: `TaskOutput(block: true, timeout: 480000)` — do NOT launch next agent until complete
4. Quick-validate: verify `finding-{NNN}.md` is non-empty and contains one of `[CONFIRMED]`, `[REFUTED]`, `[LIKELY-FP]`, `[INCONCLUSIVE]`

### MEDIUM Batch Agent

If MEDIUM findings exist:
1. Read the batch prompt from `resources/VERIFICATION_PROMPTS.md` and fill in `{medium_findings_list}`, `{output_file}` (`verification/medium-findings.md`), `{source_file_list}`, `{stage1_file_list}`, `{design_decisions_file}`
2. Launch ONE Task agent: `subagent_type: "solidity-function-audit-eval:solidity-verifier"`, `max_turns: 25`
3. Wait: `TaskOutput(block: true, timeout: 600000)`
4. Quick-validate: verify `medium-findings.md` is non-empty and contains `## ` heading

### Write Verification Summary

Write `docs/audit/function-audit/verification/verification-summary.md` with results table and verdict counts.

Update INDEX.md: add "Verification" section and "Verified" column to "All Findings" table.
Update SUMMARY.md: add "Verification" section with verdict counts.
Update session state checkpoint (Verification complete, add verdict tallies).

---

## Completion

Write `EVAL_COMPLETE` as the final line in `stage-checkpoint.md`.

Output a one-line completion message: "Eval complete. INDEX.md and SUMMARY.md written to docs/audit/function-audit/."

**Do NOT proceed to Stage 4 or Stage 5.** Eval mode stops after Verification.

---

## Guardrails

- **All agents write to files** — never return analysis in responses. Returns fill the main context and cause overflow.
- **Stages are sequential** — Stage 0 → 1 → 2 → 3 → Synthesis → Verification. Only agents *within* each stage run in parallel.
- **Always complete Stage 3** — cross-cutting issues emerge from combining individually-sound functions.
- **Always block on TaskOutput** — use `block: true` and wait for agent completion.
- **Verification is sequential** — never run more than one verification agent at a time (forge compilation lock conflicts).
- **No interactive prompts** — this skill must run end-to-end without any user input. Never use AskUserQuestion.
- **Slither is skipped** — eval fixtures are self-contained, no Slither needed.

---

## Notes
- **Agents**: Stages 1-3 use `subagent_type: "general-purpose"`. Verification uses `solidity-function-audit-eval:solidity-verifier`. All prompts use absolute paths.
- **Error handling**: If an agent fails or times out, report the failure and continue with remaining agents. Note missing files in INDEX.md as `INCOMPLETE — agent failed`.
- **GROUND_TRUTH.md**: The eval skill reads this file for design decision presets. It does NOT read vulnerability data — findings are measured post-hoc by `grade.sh`.
