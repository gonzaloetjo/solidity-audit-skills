---
name: solidity-function-audit
description: Run a structured per-function Solidity audit with design-decision capture, staged analysis, and human-reviewed finding triage. Use this when auditing Foundry-style projects under src/**/*.sol.
---

# Solidity Function Audit (Codex)

Use this skill to perform a full per-function security audit for Solidity projects with a staged workflow and file-based outputs.

## Scope

- Target projects with source files under `src/**/*.sol`
- Use shell tools (`rg`, `find`, `sed`, `awk`, `mkdir`) for discovery and report generation
- Write all outputs to markdown files; keep terminal responses concise

## Output Layout

Create and maintain:

```bash
mkdir -p docs/audit/function-audit/{stage0,stage1,stage2,stage3,review}
```

Expected outputs:

- `docs/audit/function-audit/stage0/design-decisions.md`
- `docs/audit/function-audit/stage0/slither-findings.md` (if available)
- `docs/audit/function-audit/stage1/state-variables.md`
- `docs/audit/function-audit/stage1/access-control.md`
- `docs/audit/function-audit/stage1/external-calls.md`
- `docs/audit/function-audit/stage2/domain-*.md`
- `docs/audit/function-audit/stage3/state-consistency.md`
- `docs/audit/function-audit/stage3/math-rounding.md`
- `docs/audit/function-audit/stage3/reentrancy-trust.md`
- `docs/audit/function-audit/stage3/adversarial-sequences.md`
- `docs/audit/function-audit/review/review-responses.md`
- `docs/audit/function-audit/review/re-evaluation.md` (conditional)
- `docs/audit/function-audit/INDEX.md`
- `docs/audit/function-audit/SUMMARY.md`

## Workflow

### 0. Pre-flight

1. Resolve `PROJECT_PATH` from user argument; default to current working directory.
2. If `docs/audit/function-audit/` exists, ask user whether to archive, overwrite, or cancel.
3. Discover contracts and functions with grep-first exploration (`rg`) before full-file reads.
4. Group functions into 4-10 domains (3-15 functions each when possible).
5. Present discovered domains for confirmation.

### 1. Design Decisions (Stage 0)

1. Read `resources/REVIEW_PROMPTS.md` stage-0 guidance.
2. Extract explicit intent markers (NatSpec comments, audit notes, annotations).
3. Ask user to confirm/correct design assumptions.
4. Write `stage0/design-decisions.md` using the template in `resources/REVIEW_PROMPTS.md`.

### 2. Optional Slither Pass

1. Check availability with `which slither`.
2. If available, run Slither and convert findings to markdown with severity mapping:
- High -> HIGH
- Medium -> MEDIUM
- Low -> LOW
- Informational -> INFO
3. Write to `stage0/slither-findings.md`.

### 3. Foundation Reports (Stage 1)

Read `resources/STAGE_PROMPTS.md` and produce:

- `stage1/state-variables.md`
- `stage1/access-control.md`
- `stage1/external-calls.md`

### 4. Domain Reports (Stage 2)

For each confirmed domain:

1. Analyze each function using `resources/FUNCTION_TEMPLATE.md`.
2. Cross-reference Stage 0 design decisions and Slither output (if present).
3. Write one `stage2/domain-{slug}.md` file per domain.

### 5. Cross-Cutting Reports (Stage 3)

Produce 4 dedicated reports using the stage-3 guidance in `resources/STAGE_PROMPTS.md`:

- State consistency and invariants
- Math, precision, and rounding
- Reentrancy and trust boundaries
- Adversarial cross-contract sequence modeling

### 6. Human Review (Stage 4)

1. Aggregate non-INFO findings and present them for user classification:
- BUG
- DESIGN
- DISPUTED
- DISCUSS
2. Save classifications to `review/review-responses.md`.

### 7. Re-evaluation (Stage 5)

If there are DISPUTED/DISCUSS entries:

1. Re-evaluate using user rationale.
2. Mark each as one of:
- UPHELD
- WITHDRAWN
- DOWNGRADED
- NEEDS_TESTING
3. Write `review/re-evaluation.md`.

### 8. Final Synthesis

1. Build `INDEX.md` with links and counts per report.
2. Build `SUMMARY.md` with:
- Severity totals
- Top risks
- Confirmed bugs
- Disputed outcomes
- Recommended fixes and next tests

## Severity + Verdict Rules

Severity:

- CRITICAL: direct theft/loss, unauthorized control, broken core invariant
- HIGH: serious exploit requiring specific preconditions
- MEDIUM: meaningful logic deviation with limited blast radius
- LOW: minor security-relevant weakness or hardening gap
- INFO: observations or confirmations

Verdict:

- SOUND: only INFO or no findings
- NEEDS_REVIEW: LOW/MEDIUM only
- ISSUE_FOUND: any HIGH/CRITICAL

## Quality Guardrails

- Do not skip internal/private helpers used by public flows.
- Do not treat every design trade-off as a bug; check Stage 0 first.
- Keep evidence concrete: point to file path, function, and logic path.
- Explicitly model attacker transaction ordering across contracts, not only isolated function correctness.
- Prefer deterministic shell steps over ad-hoc prose.
- Keep long-form guidance in `resources/`; keep this file focused on process.

## Required Resources

Read these files when executing this skill:

- `resources/STAGE_PROMPTS.md`
- `resources/REVIEW_PROMPTS.md`
- `resources/FUNCTION_TEMPLATE.md`
- `resources/EXAMPLE_OUTPUT.md`
