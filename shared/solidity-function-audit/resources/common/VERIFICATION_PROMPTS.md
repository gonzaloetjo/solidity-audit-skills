# Verification Prompts

Prompt templates for the Verification stage — false-positive filtering and Foundry test confirmation. Runs after Synthesis and before Stage 4 (Human Review).

Verification agents validate CRITICAL, HIGH, and MEDIUM findings from Stage 2/3. CRITICAL/HIGH findings get individual agents with Foundry test generation. MEDIUM findings get a single batch agent with anti-pattern checks only.

## Anti-Pattern Checklist

Six research-backed false-positive patterns. A finding that matches a pattern (without triggering its exception) is tagged `[LIKELY-FP]`.

1. **Reentrancy on guarded code**: The function has a `nonReentrant` modifier or follows the checks-effects-interactions (CEI) pattern completely.
   *Exception*: Cross-contract reentrancy through a different entry point, or read-only reentrancy that bypasses the mutex.

2. **Overflow in Solidity >=0.8**: The contract compiles with Solidity >=0.8.0 and built-in overflow checks are active.
   *Exception*: The arithmetic is inside an `unchecked` block or uses inline assembly (`add`, `mul`, `sub`, `div`).

3. **Access control without exploit path**: The finding reports an access control issue but specifies no concrete attacker identity, attacker benefit, or executable call path.
   *Exception*: None — this pattern always indicates a false positive unless a concrete exploit path is specified.

4. **Pattern without precondition**: A known vulnerability pattern is matched but the specific precondition required for exploitation is absent.
   *Exception*: The precondition is present — e.g., `delegatecall` to a user-controlled address (not hardcoded), or unprotected `selfdestruct`.

5. **Flash loan without economics**: The finding describes a flash loan attack but provides no capital requirement, profit margin estimate, or gas cost analysis.
   *Exception*: The finding includes a concrete economic analysis showing profitable execution.

6. **Front-running on protected code**: The finding describes front-running but the function has slippage protection (`minAmountOut`), deadline checks, or a commit-reveal pattern.
   *Exception*: The protection mechanism is insufficient (e.g., slippage tolerance set too high, or deadline set by caller without validation).

## Verification Verdict Definitions

- `[CONFIRMED]` — Foundry test demonstrates the issue, or investigation confirms exploitability with concrete evidence
- `[REFUTED]` — Foundry test shows the code handles the case correctly, or preconditions are provably impossible
- `[LIKELY-FP]` — Anti-pattern check matched and no exception applies (test skipped)
- `[INCONCLUSIVE]` — Cannot construct a meaningful test (requires mainnet fork, real oracle data, complex multi-protocol state, etc.)

---

## Per-Finding Agent Prompt (CRITICAL and HIGH)

```
You are a Solidity security verification agent. Your task is to verify a single audit finding using anti-pattern filtering, upstream investigation, and Foundry test generation.

## Finding Under Verification

- **Number**: #{finding_number}
- **Severity**: {finding_severity}
- **Title**: {finding_title}
- **Source file**: {finding_source_file}
- **Function**: {finding_function}

## Source Files to Read (one absolute path per line)
{source_file_list}

## Stage 1 Reference Files
{stage1_file_list}

## Design Decisions
{design_decisions_file}

## Step 1 — Anti-Pattern Check

Read the Anti-Pattern Checklist from resources/VERIFICATION_PROMPTS.md. Check the finding against all 6 patterns:

1. If ANY pattern matches AND no exception applies → verdict is [LIKELY-FP]. Write output file with the anti-pattern match explanation and STOP. Do not generate a test.
2. If no pattern matches, or an exception applies → proceed to Step 2.

## Step 2 — Upstream Trace

Use Grep to find all callers of the vulnerable function. For each caller:
- Check if the caller adds protection (access control, reentrancy guard, validation) that mitigates the finding
- Trace the call chain up to 3 levels deep

## Step 3 — Cross-Contract Verification

Read the external contracts referenced by the finding. Verify:
- External contract behavior matches the finding's assumptions
- Interface implementations match expected signatures
- Return values are handled as the finding claims

## Step 4 — Parent Contract Check

Read inherited contracts and libraries. Verify:
- Modifier implementations match assumed behavior
- Virtual function overrides don't change security properties
- Storage layout assumptions are correct for proxy patterns

## Step 5 — Foundry Test Generation

Write a Foundry test file to {test_dir}/{test_name}.t.sol with:
- SPDX-License-Identifier: MIT and pragma solidity ^0.8.0
- Import forge-std/Test.sol and the contract(s) under test using relative paths from project root
- A test contract named {test_name} inheriting from Test
- setUp() deploying contracts with realistic state (use vm.deal(), vm.prank() for setup)
- test_{test_name}() that arranges the conditions from the finding, executes the vulnerable operation, and asserts the vulnerability manifests
- Use vm.expectRevert() if testing that code should revert
- Use vm.prank() for attacker impersonation, vm.warp() for time manipulation, vm.deal() for ETH balances
- The test should PASS if the vulnerability exists, FAIL/REVERT if the code is safe
- Keep the test focused on one finding — no unrelated assertions

## Step 6 — Run Test

Execute via Bash: forge test --match-test test_{test_name} -vvv

Interpret results:
- Test passes → [CONFIRMED] (vulnerability demonstrated)
- Test reverts/fails → [REFUTED] (code handles the case correctly)
- Compilation error → attempt ONE fix. If still fails → [INCONCLUSIVE]

## Output Format

Write your COMPLETE analysis to the file: {output_file}

    # Verification: Finding #{finding_number} — {finding_title}

    **Severity**: {finding_severity}
    **Source**: {finding_source_file} — {finding_function}

    ## Anti-Pattern Check

    | # | Pattern | Match? | Exception? |
    |---|---------|--------|------------|
    | 1 | Reentrancy on guarded code | Yes/No | N/A or description |
    | 2 | Overflow in Solidity >=0.8 | Yes/No | N/A or description |
    | 3 | Access control without exploit path | Yes/No | N/A or description |
    | 4 | Pattern without precondition | Yes/No | N/A or description |
    | 5 | Flash loan without economics | Yes/No | N/A or description |
    | 6 | Front-running on protected code | Yes/No | N/A or description |

    **Result**: No match / Match — pattern #{N} ({pattern name})

    ## Investigation

    ### Upstream Trace
    {callers found, protection mechanisms, trace depth}

    ### Cross-Contract Verification
    {external contract behavior, interface checks}

    ### Parent Contract Check
    {inheritance chain, modifier implementations, storage layout}

    ## Foundry Test

    **Test file**: {test_dir}/{test_name}.t.sol

    **Forge output**:
    {paste forge test -vvv output}

    **Interpretation**: {explanation of test result}

    ## Verdict: [{verdict}]

    {One paragraph explaining why this verdict was reached, referencing specific evidence.}

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- Finding #{finding_number} verdict: [{verdict}]." Do NOT return analysis text in your response.
```

---

## MEDIUM Batch Agent Prompt

```
You are a Solidity security verification agent. Your task is to batch-verify all MEDIUM-severity audit findings using anti-pattern filtering and contextual investigation. You do NOT write Foundry tests for MEDIUM findings.

## MEDIUM Findings to Verify

{medium_findings_list}

## Source Files to Read (one absolute path per line)
{source_file_list}

## Stage 1 Reference Files
{stage1_file_list}

## Design Decisions
{design_decisions_file}

## Anti-Pattern Checklist

Read the Anti-Pattern Checklist from resources/VERIFICATION_PROMPTS.md. For each finding, check against all 6 patterns.

## Per-Finding Verification (NO Foundry tests)

For each MEDIUM finding:

### Step 1 — Anti-Pattern Check
Check the finding against all 6 anti-pattern rules. If a pattern matches and no exception applies → [LIKELY-FP].

### Step 2 — Upstream + Contextual Check
- Use Grep to find callers of the vulnerable function (up to 3 levels)
- Read external contracts referenced by the finding
- Read inherited contracts and check modifier implementations
- Verify the finding's assumptions against actual code behavior

### Step 3 — Verdict Assignment
- [CONFIRMED] — Investigation found concrete evidence supporting the finding
- [LIKELY-FP] — Anti-pattern matched, or investigation shows assumptions are wrong
- [INCONCLUSIVE] — Cannot determine without dynamic testing

Note: [REFUTED] is NOT available for MEDIUM batch verification — without a Foundry test, absence of evidence is not evidence of absence.

## Output Format

Write your COMPLETE analysis to the file: {output_file}

    # Verification: MEDIUM Findings (Batch)

    **Findings verified**: {N}
    **Date**: {date}

    ## Summary

    | # | Finding | Function | Anti-Pattern? | Verdict |
    |---|---------|----------|---------------|---------|
    | {n} | {title} | {function} | Pattern #{n} / None | [{verdict}] |

    **Totals**: CONFIRMED: {N} | LIKELY-FP: {N} | INCONCLUSIVE: {N}

    ---

    ## Finding #{n}: {title}

    **Source**: {source_file} — {function}

    ### Anti-Pattern Check
    | # | Pattern | Match? | Exception? |
    |---|---------|--------|------------|
    | 1 | Reentrancy on guarded code | Yes/No | N/A or description |
    | ... | ... | ... | ... |

    ### Investigation
    {upstream trace, external contracts, parent contracts — concise}

    ### Verdict: [{verdict}]
    {One paragraph with evidence.}

    ---
    (repeat for each finding)

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} MEDIUM findings verified." Do NOT return analysis text in your response.
```
