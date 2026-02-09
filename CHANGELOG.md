# Changelog

## [1.3.0] - 2026-02-09

### Added
- **Slither integration** (both variants): Runs Slither static analysis (if installed) between Stage 0 and Stage 1. Maps findings to CRITICAL/WARNING/INFO, writes to `stage0/slither-findings.md`. All agents cross-reference their manual analysis with Slither's automated detections.
- **Companion skill agents** (both variants): Detects installed companion skills from Trail of Bits' marketplace (`token-integration-analyzer`, `guidelines-advisor`, `entry-point-analyzer`, `variant-analysis`). Spawns additional Stage 3 agents that apply each skill's methodology to the target contracts.
- **DeFi pattern detection** in Stage 0 (both variants): New extraction categories for Oracle Strategy, Token Standard, DeFi Integration, MEV Awareness, and Value Flow.
- **Project characteristic detection** in pre-flight (both variants): Scans source files for token interfaces, proxy/upgrade patterns, and oracle imports to determine companion skill relevance.
- **Companion agent prompt template** in STAGE_PROMPTS.md (both variants): Standard prompt for companion skill agents with design decisions context and severity format.
- **Slither cross-reference block** in STAGE_PROMPTS.md (both variants): Included in all agent prompts when Slither findings are available.

### Changed
- **SKILL.md** (both variants): Pre-flight now includes project characteristic detection (step 8) and companion skill detection (step 9). New Slither integration section between Stage 0 and Stage 1. Stage 3 conditionally spawns companion skill agents alongside the existing 3a/3b/3c agents.
- **SKILL.md** (both): All stage placeholder lists now include `{slither_file}`.
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
