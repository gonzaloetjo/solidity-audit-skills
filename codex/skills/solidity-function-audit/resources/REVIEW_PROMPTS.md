# Review Prompts

Prompt templates for Stage 0 (Design Decisions), Stage 4 (Human Review), and Stage 5 (Re-Evaluation).

---

## Stage 0: Design Decision Extraction

### Automated Extraction Patterns

Scan all source files for design intent signals. Group findings by category.

**NatSpec signals** — `@dev` comments explaining "why", not "what":
- Grep: `@dev` tags containing rationale keywords

**Static analysis annotations** — suppression comments with reasons:
- Grep: `// slither-disable`, `// solhint-disable`, `// @audit` with trailing explanation

**Intent keywords** — comments containing:
- `intentional`, `by design`, `trade-off`, `known`, `accepted`, `wontfix`, `deliberate`

**Pattern detection** — code-level heuristics:

| Category | What to detect | Signal |
|----------|---------------|--------|
| Rounding Policy | `mulDiv` direction args, `/ ... + 1` patterns, `Math.Rounding` usage | Which direction, where |
| Access Control Model | `Ownable` vs `AccessControl` vs custom roles, timelocks, multisig | Role hierarchy |
| Upgrade Strategy | `UUPSUpgradeable`, `TransparentProxy`, `initializer`, storage gaps | Pattern and permanence |
| Reentrancy Approach | `nonReentrant` on some but not all external functions | Intentional gaps |
| Pausability | `whenNotPaused` coverage gaps, emergency functions | Which functions skip pause |
| Known Trade-offs | Comments with `trade-off`, `gas optimization`, `simplification` | Developer reasoning |
| Oracle Strategy | `AggregatorV3Interface`, TWAP, custom oracle, heartbeat checks | Price source and staleness handling |
| Token Standard | ERC-4626 vault, `SafeERC20`, fee-on-transfer handling, rebasing | Token assumptions |
| DeFi Integration | Router calls, pool interactions, `IFlashLoanReceiver` | External protocol dependencies |
| MEV Awareness | Slippage params (`minAmountOut`), deadline checks, commit-reveal | Frontrunning protection |
| Value Flow | Fee collection, protocol revenue, treasury patterns | Where value accumulates and exits |

### Interactive Confirmation Script

Present extracted decisions grouped by category. For each category:

1. Show detected items as a numbered table: `# | Source | Location | Description`
2. Ask: "Are these intentional design decisions? Confirm, correct, or add context."
3. Record user response per category

After all categories, ask: "Any additional design decisions or context the auditors should know?"

### Output Format — `stage0/design-decisions.md`

```markdown
# Design Decisions

**Generated**: {date}
**Project**: {project_path}
**Source**: Automated extraction + developer confirmation

## {Category Name}

| # | Decision | Source | Location | Status |
|---|----------|--------|----------|--------|
| 1 | {description} | code-detected / developer-confirmed | {contract}:{line} | Confirmed / Corrected / Added |

Developer notes: {free-form context if provided}

## Additional Context

{Any developer-provided context not tied to a specific category}
```

### Distribution Instructions

Add this block to Stage 1, 2, and 3 agent prompts when `design-decisions.md` exists:

```
## Design Decisions Context
Read the design decisions file: {design_decisions_file}

When evaluating findings, apply these rules:
- Behavior that MATCHES a documented decision → classify as `INFO` with prefix `DESIGN_DECISION -- `
- Behavior that CONTRADICTS a documented decision → classify as MEDIUM or higher and note the contradiction explicitly
- No relevant decision → evaluate independently as before

Do NOT skip analysis of design-decision areas. Still analyze them fully — the decision only affects the severity classification, not whether you investigate.
```

---

## Stage 4: Human Review Script

### Finding Extraction

Parse all findings from stage2/ and stage3/ files using these patterns:
- `**CRITICAL -- ` → extract finding title and file path
- `**HIGH -- ` → extract finding title and file path
- `**MEDIUM -- ` → extract finding title and file path
- `**LOW -- ` → extract finding title and file path
- `**INFO -- ` → extract finding title and file path

Also extract `DESIGN_DECISION -- ` tagged findings separately.

### Review Flow

**Step 1 — CRITICALs** (if any):
Present as numbered list with finding title, source function, and file link.
Ask: "Classify each finding — e.g., `1:BUG 2:DESIGN 3:DISCUSS`"

Available statuses:
- **BUG**: Confirmed issue, needs fix
- **DESIGN**: Acknowledged trade-off, won't fix
- **DISPUTED**: Developer disagrees with finding
- **DISCUSS**: Needs more context before classifying

**Step 2 — HIGHs** (if any):
Same format as CRITICALs.

**Step 3 — MEDIUMs** (if any):
Same format as CRITICALs.

**Step 4 — LOWs and INFOs**:
Show summary count (total LOWs, total INFOs, design-decision tagged, other).
Ask: "Review LOWs and INFOs? [skip/review]"
If review: present in batches of 10, same classification format.

**Step 5 — Follow-up for DISPUTED/DISCUSS**:
For each DISPUTED or DISCUSS item:
1. Show the full finding text + relevant source code
2. Ask: "What is your reasoning for disputing/discussing this?"
3. Record the developer's counter-argument

### Output Format — `review/review-responses.md`

```markdown
# Human Review Responses

**Reviewed**: {date}
**Reviewer**: Developer (interactive session)

## Classification Summary

| Original Severity | BUG | DESIGN | DISPUTED | DISCUSS |
|-------------------|-----|--------|----------|---------|
| CRITICAL | {n} | {n} | {n} | {n} |
| HIGH | {n} | {n} | {n} | {n} |
| MEDIUM | {n} | {n} | {n} | {n} |
| LOW | {n} | {n} | {n} | {n} |
| INFO | {n} | {n} | {n} | {n} |

## Detailed Classifications

| # | Severity | Finding | Source | Classification | Reasoning |
|---|----------|---------|--------|----------------|-----------|
| 1 | CRITICAL | {title} | {file}:{function} | BUG | — |
| 2 | HIGH | {title} | {file}:{function} | DISPUTED | {developer reasoning} |

## Disputed/Discussed Items (Full Context)

### Finding #{n}: {title}

**Original finding**: {full finding text}
**Developer response**: {counter-argument}
**Status**: DISPUTED / DISCUSS
```

---

## Stage 5: Re-Evaluation Agent Prompt

```
You are a Solidity security auditor performing a re-evaluation of disputed audit findings.

## Task
Re-evaluate findings that the developer has disputed or flagged for discussion. Write your COMPLETE analysis to the file: {output_file}

## Context Files to Read
- Design decisions: {design_decisions_file}
- Review responses: {review_responses_file}

## Source Files to Read (one absolute path per line)
{source_file_list}

Read each file using the Read tool before analyzing.

## Disputed/Discussed Findings to Re-Evaluate
{disputed_findings}

## Per-Finding Analysis

For EACH disputed/discussed finding:

1. Re-read the original finding and the developer's counter-argument
2. Re-read the relevant source code (specific lines referenced)
3. Check if the developer's reasoning is sound
4. Consider the design decisions context
5. Assign one of these outcomes:

- **UPHELD**: Finding stands. Explain why the developer's argument is insufficient. The original severity holds.
- **WITHDRAWN**: Finding retracted. Explain what the original analysis missed or got wrong.
- **DOWNGRADED**: Severity reduced. State the new severity and explain what changed.
- **NEEDS_TESTING**: Cannot determine statically. Describe the specific test that would resolve it.

## Output Format

Write a complete markdown document to {output_file} with:

### Re-Evaluation Summary

| # | Finding | Original | Developer Says | Outcome | New Severity |
|---|---------|----------|----------------|---------|-------------|
| 1 | {title} | CRITICAL | {brief argument} | UPHELD | CRITICAL |
| 2 | {title} | HIGH | {brief argument} | DOWNGRADED | LOW |

### Per-Finding Re-Evaluation

#### Finding #{n}: {title}

**Original severity**: {severity}
**Original finding**: {brief}
**Developer argument**: {summary}
**Re-evaluation**: {detailed analysis}
**Outcome**: {UPHELD|WITHDRAWN|DOWNGRADED|NEEDS_TESTING}
**Final severity**: {severity or N/A if withdrawn}

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} findings re-evaluated." Do NOT return analysis text in your response.
```
