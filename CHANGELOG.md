# Changelog

## [1.4.1] - 2026-02-11

### Fixed
- **Plan mode deadlock** (team): Replaced `mode: "plan"` with `mode: "bypassPermissions"` for Stage 2 teammates. Plan mode caused a circular dependency where the lead waits for task completion while teammates wait for plan approval, but messages only deliver between turns ([#24108](https://github.com/anthropics/claude-code/issues/24108)). Stage 2 teammates now use prompt-based planning: design plan → send as message to lead → proceed without waiting for approval.

## [1.4.0] - 2026-02-11

### Added
- **Output validation hooks** (both variants): New `hooks/hooks.json` and `hooks/validate-output.sh` per plugin. Solo uses `SubagentStop` hook; team uses `TaskCompleted` hook. Validates agent output files are non-empty, contain markdown headings, and have required sections/severity tags for Stage 2 and Stage 3. Exit code 2 blocks completion and feeds error to the agent.
- **Context compaction guidance** (both variants): New section in SKILL.md instructing the orchestrator to preserve critical values (paths, domain groupings, placeholders, stage status) if auto-compaction occurs during long sessions.
- **Post-completion content verification** (both variants): After each stage's file existence check, the orchestrator reads the first/last 5 lines of each output file to verify structure. Malformed files are noted as INCOMPLETE in synthesis.

### Changed
- **SKILL.md** (both): Added `max_turns` caps to all agent spawn instructions — Stage 1/5: 15 turns, Stage 2/3: 25 turns. Prevents stuck agents from burning context until timeout.
- **SKILL.md** (both): Stage 2 `{source_file_list}` placeholder now scoped to domain-relevant files only (domain contracts, externally called contracts, inherited contracts/libraries) instead of all project source files.
- **SKILL.md** (both): Removed `{design_decisions_file}` from Stage 1 placeholder list — Stage 1 prompts don't use it. Clarified it's only distributed to Stage 2 and Stage 3 agents.
- **STAGE_PROMPTS.md** (both): Stage 2 source file instruction now clarifies files are domain-scoped and agents should read additional imports/inheritance as needed.

## [1.3.0] - 2026-02-10

### Added
- **Slither integration** (both variants): Runs Slither static analysis (if installed) between Stage 0 and Stage 1. Maps findings to CRITICAL/WARNING/INFO, writes to `stage0/slither-findings.md`. Stage 2 and Stage 3 agents cross-reference their manual analysis with Slither's automated detections.
- **DeFi pattern detection** in Stage 0 (both variants): New extraction categories for Oracle Strategy, Token Standard, DeFi Integration, MEV Awareness, and Value Flow.
- **Project characteristic detection** in pre-flight (both variants): Scans source files for token interfaces, proxy/upgrade patterns, and oracle imports to condition Stage 2/3 prompts.
- **Token integration checklist** in Stage 2 prompt (both variants): When the project imports token interfaces, Stage 2 agents check for fee-on-transfer, rebasing, no-return-value (USDT), pausable/blocklist, permit race conditions, and ERC777 hook reentrancy.
- **Slither cross-reference block** in STAGE_PROMPTS.md (both variants): Included in Stage 2 and Stage 3 agent prompts when Slither findings are available.

### Changed
- **SKILL.md** (both variants): Pre-flight now includes project characteristic detection (step 8). New Slither integration section between Stage 0 and Stage 1 with proper error handling (checks for output file existence before reading).
- **SKILL.md** (both): Stage 2 and Stage 3 placeholder lists include `{slither_file}`. Stage 1 does not (structural mapping doesn't need finding-level cross-reference).
- **REVIEW_PROMPTS.md** (both): Stage 0 pattern detection table extended with 5 DeFi-related categories.

## [1.2.0] - 2026-02-09

### Added
- **Stage 0: Design Decisions** (both variants): Pre-audit interactive stage that extracts design intent from NatSpec comments, static analysis annotations, and code patterns, then presents to developer for confirmation. Output feeds into Stages 1-3 to prevent design trade-offs from being flagged as bugs.
- **Stage 4: Human Review** (both variants): Post-synthesis interactive review. Presents findings grouped by severity for developer classification (BUG, DESIGN, DISPUTED, DISCUSS). Records reasoning for disputed items.
- **Stage 5: Re-Evaluation** (both variants): Conditional stage that re-evaluates DISPUTED/DISCUSS findings with developer's counter-reasoning. Outcomes: UPHELD, WITHDRAWN, DOWNGRADED, NEEDS_TESTING. Only runs when disputed items exist.
- **REVIEW_PROMPTS.md** (both variants): New resource file containing Stage 0 extraction patterns, Stage 4 review flow, and Stage 5 agent prompt.
- **Design decisions context** in STAGE_PROMPTS.md (both variants): Stage 2 and Stage 3 agent prompts now include `{design_decisions_file}` placeholder and evaluation rules for `DESIGN_DECISION --` tagged findings.
- **Final synthesis update**: SUMMARY.md and INDEX.md now include Human Review sections with before/after classification tables.

### Changed
- **SKILL.md** (both variants): Pipeline extended from 3 stages to 6 stages (0-5). Output directory now includes `stage0/` and `review/`. Guardrails updated for new stages.
- **SKILL.md** (both): Pre-flight "Confirm with User" step now includes design decisions summary alongside domain groupings.
- **SKILL.md** (both): Synthesis "Report to User" now asks whether to proceed to human review before stopping.

## [1.1.0] - 2026-02-09

### Changed
- **README.md**: Rewritten — leads with findings table (CRITICAL/WARNING/INFO), collapsible per-function detail, pipeline table, team variant workflow as numbered steps.
- **STAGE_PROMPTS.md** (both variants): Stripped redundant Solidity concept explanations from Stage 1 and Stage 3 prompts (~25-30% reduction). Kept task definitions, scope, output format, and project-specific constraints.
- **STAGE_PROMPTS.md** (both): Replaced verbose sub-section checklists in Stage 3 with concise numbered area summaries.
- **STAGE_PROMPTS.md** (both): Defined "stale state" (Stage 3a) and replaced vague "power analysis" with explicit instruction (Stage 3c).
- **STAGE_PROMPTS.md** (both): Added multi-contract domain guidance to Stage 2.
- **STAGE_PROMPTS.md** (team): Added message priority guidance — only message for CRITICAL findings or cross-domain state dependencies.
- **STAGE_PROMPTS.md** (team): Fixed messaging timing — teammates now write to output file and message only if the relevant teammate is still active.
- **SKILL.md** (both): Replaced 9/11-row rationalizations table with 4-5 concise guardrail bullets.
- **SKILL.md** (both): Tightened domain grouping heuristic with explicit edge-case handling for <15 functions or >10 domains.
- **SKILL.md** (both): Improved error handling guidance — synthesis notes missing files as `INCOMPLETE — agent failed`.
- **SKILL.md** (solo): Removed duplicate timeout mentions from Notes section.
- **SKILL.md** (team): Removed plan mode instructions from shared teammate prompt (already handled by `mode: "plan"` Task parameter).
- **FUNCTION_TEMPLATE.md** (both): Added severity format strictness note to prevent finding count breakage.
- **FUNCTION_TEMPLATE.md** (both): Added "protocol-favorable rounding" definition.

### Renamed
- `solidity-function-rationality` → `solidity-function-audit`
- `solidity-function-rationality-team` → `solidity-function-audit-team`
- Output directory `docs/audit/function-rationality/` → `docs/audit/function-audit/`

## [1.0.0] - 2026-02-09

### Added
- `solidity-function-audit` — 3-stage parallelized per-function audit
- `solidity-function-audit-team` — agent team variant with inter-agent messaging
