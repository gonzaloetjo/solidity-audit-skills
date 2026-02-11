# Agent Prompt Templates

All agent prompts follow the same discipline: write COMPLETE analysis to the output file, return only a short confirmation.

---

## Slither Cross-Reference Block

Include this block in Stage 2 and Stage 3 agent prompts when `{slither_file}` is non-empty:

```
## Automated Static Analysis
Read the Slither findings file: {slither_file}

Cross-reference your manual analysis with Slither's automated detections:
- **Agreement**: When you confirm a Slither finding, note it: "Confirmed by Slither: {detector-name}"
- **Slither miss**: When you find something Slither missed, note it: "Not detected by Slither"
- **False positive**: If Slither flagged something incorrectly, explain why: "Slither false positive: {reason}"
```

---

## Stage 1 Prompts

### 1a: State Variable Map

```
You are a Solidity security auditor performing a state variable analysis.

## Task
Analyze all state variables in this project. Write your COMPLETE analysis to the file: {output_file}

## Source Files to Read (one absolute path per line)
{source_file_list}

Read each file using the Read tool before analyzing.

## Instructions
For EVERY storage variable (including those in libraries and inherited contracts), document:
1. Full declaration (name and type)
2. Meaning in the system
3. Writers and readers (with contract and line refs)
4. Invariants (what should always be true)
5. Duplication risk (derivable from other state? could get out of sync?)

Also document constants/immutables separately, storage layout (ERC-7201 namespaces if used), and any unused storage variables.

## Output Format
Write a well-structured markdown document to {output_file} with sections for each contract/library. Use tables where appropriate.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} variables analyzed." Do NOT return analysis text in your response.
```

### 1b: Access Control Map

```
You are a Solidity security auditor performing an access control analysis.

## Task
Map the complete access control surface. Write your COMPLETE analysis to the file: {output_file}

## Source Files to Read (one absolute path per line)
{source_file_list}

Read each file using the Read tool before analyzing.

## Instructions
For EVERY external and public function, document:
1. Full signature with contract name
2. Visibility and all modifiers applied
3. Required role/condition to call
4. State changes it can make
5. Trust assumption (who is trusted to call correctly)

Also analyze: role hierarchy, access control gaps, modifier consistency, pause mechanism coverage, and emergency/admin function power levels.

## Output Format
Write a well-structured markdown document to {output_file}. Group functions by contract, then by role. Include a summary matrix.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} functions analyzed." Do NOT return analysis text in your response.
```

### 1c: External Call Map

```
You are a Solidity security auditor performing an external call analysis.

## Task
Map all external calls and their security implications. Write your COMPLETE analysis to the file: {output_file}

## Source Files to Read (one absolute path per line)
{source_file_list}

Read each file using the Read tool before analyzing.

## Instructions
For EVERY external call (calls to other contracts, low-level calls, delegatecalls), document:
1. Caller function (contract and line ref)
2. Target contract/address and function called
3. Arguments passed and return value handling
4. State changes before and after the call
5. CEI compliance, reentrancy risk, and trust level

Also analyze: delegatecall storage safety, low-level call success checks, ETH transfer failure handling, and callback/reentrancy vectors.

## Output Format
Write a well-structured markdown document to {output_file}. Group by caller contract, then by target. Include a reentrancy risk summary.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} external calls analyzed." Do NOT return analysis text in your response.
```

---

## Stage 2 Prompt (Per-Domain)

```
You are a Solidity security auditor performing a per-function audit.

## Task
Analyze every function in the "{domain_name}" domain. Write your COMPLETE analysis to the file: {output_file}

## Prior Analysis to Read (Stage 1 Context)
Read these files first for foundation context:
- {stage1_state_var_file}
- {stage1_access_control_file}
- {stage1_external_call_file}

## Design Decisions Context
Read the design decisions file: {design_decisions_file}

When evaluating findings, apply these rules:
- Behavior that MATCHES a documented decision → classify as `INFO` with prefix `DESIGN_DECISION -- `
- Behavior that CONTRADICTS a documented decision → classify as MEDIUM or higher and note the contradiction explicitly
- No relevant decision → evaluate independently as before

Do NOT skip analysis of design-decision areas. Still analyze them fully — the decision only affects the severity classification, not whether you investigate.

## Source Files to Read (one absolute path per line)
{source_file_list}

These are the source files relevant to your domain. Read each file using the Read tool before analyzing.
If you need additional files referenced by imports or inheritance that are not listed, read them as needed.

If a domain spans multiple contracts, analyze all functions together to catch cross-contract interactions.

## Functions to Analyze
{function_list}

## Per-Function Template
Read and follow the template exactly: {template_file}

The template has 5 sections: Rationale, State mutations, Dependencies, Findings, Verdict.
When analyzing each function, also consider the following and capture them as numbered Findings:
- **Access control**: Who can call it, is it appropriate, gaps
- **Edge cases**: Zero values, overflow, empty arrays, first/last element
- **Arithmetic**: Rounding direction, precision loss, overflow potential

These should appear as INFO/LOW/MEDIUM/HIGH/CRITICAL findings in the Findings section, NOT as separate sections.

## Quality Reference
For an example of the expected quality and depth, see: {example_file}

## Cross-Cutting Questions
After all per-function analyses, add a "Cross-Cutting Analysis" section:
- Are related functions consistent in their state handling?
- Do inverse operations (deposit/withdraw, add/remove) correctly mirror each other?
- Are rounding directions consistently protocol-favorable?
- Are there any invariants that span multiple functions in this domain?

## Token Integration Patterns (if project imports token interfaces)
If the source files import ERC20/ERC721/ERC4626/IERC20/SafeERC20, check each function that handles tokens for:
- Fee-on-transfer tokens: does the function use balance-before/after or trust transfer amounts?
- Rebasing tokens: does internal accounting assume static balances?
- Tokens with no return value (USDT): does the function use SafeERC20?
- Pausable/blocklist tokens: can a paused/blocked token brick the protocol?
- Permit/approval race conditions: is the approval pattern safe?
- Tokens with hooks (ERC777): reentrancy via token transfer callbacks?
Note relevant findings as LOW/MEDIUM/HIGH or INFO in the Findings section.

## Output Format
Write a complete markdown document to {output_file} with:
- Header with audit date, domain description, contracts analyzed
- Per-function analysis sections (use the template)
- Cross-cutting analysis section
- Summary table of findings (# | Severity | Function | Finding)
- Overall domain verdict

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} functions analyzed, {M} findings." Do NOT return analysis text in your response.
```

---

## Stage 3 Prompts

### 3a: State Consistency Audit

```
You are a Solidity security auditor performing a cross-domain state consistency audit.

## Task
Analyze state consistency across all domains. Write your COMPLETE analysis to the file: {output_file}

## Prior Analysis to Read
Read ALL of these files:
- Stage 1 files: {stage1_file_list}
- Stage 2 files: {stage2_file_list}

## Design Decisions Context
Read the design decisions file: {design_decisions_file}

When evaluating findings, apply these rules:
- Behavior that MATCHES a documented decision → classify as `INFO` with prefix `DESIGN_DECISION -- `
- Behavior that CONTRADICTS a documented decision → classify as MEDIUM or higher and note the contradiction explicitly
- No relevant decision → evaluate independently as before

## Source Files to Read (one absolute path per line)
{source_file_list}

Read source files as needed for line references. Focus on files referenced by Stage 2 findings.

## Analysis Focus

Analyze these four areas, using specific contract references and line numbers:

1. **Accounting Invariants** — For every tracked balance/amount: what is the invariant, which functions maintain it, can any operation sequence violate it?
2. **Divergent State Tracking** — Values tracked in multiple places (e.g., internal accounting vs actual balances): can they diverge, what's the impact, are sync mechanisms sufficient?
3. **Stale State** — State that no longer reflects reality because the source of truth was updated elsewhere (e.g., a cached exchange rate read after a deposit changes total assets). Identify what triggers staleness, what reads the stale value, and the impact.
4. **State Transition Completeness** — For every state machine: are all transitions covered, can any state get stuck, are there missing recovery paths?

## Output Format
Write a complete markdown document to {output_file} with sections for each analysis focus area, specific findings with severity and line references, and a summary table.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} invariants checked, {M} findings." Do NOT return analysis text in your response.
```

### 3b: Math & Rounding Audit

```
You are a Solidity security auditor performing a math and rounding analysis.

## Task
Analyze all arithmetic operations for correctness. Write your COMPLETE analysis to the file: {output_file}

## Prior Analysis to Read
Read ALL of these files:
- Stage 1 files: {stage1_file_list}
- Stage 2 files: {stage2_file_list}

## Design Decisions Context
Read the design decisions file: {design_decisions_file}

When evaluating findings, apply these rules:
- Behavior that MATCHES a documented decision → classify as `INFO` with prefix `DESIGN_DECISION -- `
- Behavior that CONTRADICTS a documented decision → classify as MEDIUM or higher and note the contradiction explicitly
- No relevant decision → evaluate independently as before

## Source Files to Read (one absolute path per line)
{source_file_list}

Read source files as needed for line references. Focus on files with arithmetic operations.

## Analysis Focus

Analyze these five areas, using specific contract references and line numbers:

1. **Overflow/Underflow** — Realistic overflow potential (consider max ETH supply ~120M), unchecked block safety, intermediate multiplication overflow
2. **Rounding Direction** — For every division: direction, who benefits, appropriateness. Create a complete rounding direction table.
3. **Precision Loss** — Multiply-then-divide vs divide-then-multiply patterns, maximum precision loss per calculation, accumulation across operations
4. **Exchange Rate Manipulation** — Donation attacks, flash loans, sandwich attacks, first-depositor attacks. Existing protections (virtual offsets, minimum deposits) and sufficiency.
5. **Fee Arithmetic** — Basis point/percentage correctness, zero-fee edge cases on small amounts, fee accumulation overflow

## Output Format
Write a complete markdown document to {output_file} with sections for each analysis area, specific findings with line references and severity, and a summary table.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} operations checked, {M} findings." Do NOT return analysis text in your response.
```

### 3c: Reentrancy & Trust Boundaries

```
You are a Solidity security auditor performing a reentrancy and trust boundary analysis.

## Task
Analyze reentrancy risks and trust boundaries across the system. Write your COMPLETE analysis to the file: {output_file}

## Prior Analysis to Read
Read ALL of these files:
- Stage 1 files: {stage1_file_list}
- Stage 2 files: {stage2_file_list}

## Design Decisions Context
Read the design decisions file: {design_decisions_file}

When evaluating findings, apply these rules:
- Behavior that MATCHES a documented decision → classify as `INFO` with prefix `DESIGN_DECISION -- `
- Behavior that CONTRADICTS a documented decision → classify as MEDIUM or higher and note the contradiction explicitly
- No relevant decision → evaluate independently as before

## Source Files to Read (one absolute path per line)
{source_file_list}

Read source files as needed for line references. Focus on files with external calls and access control.

## Analysis Focus

Analyze these five areas, using specific contract references and line numbers:

1. **CEI Compliance** — For every function with external calls: CEI adherence, reentrancy protection, cross-function reentrancy risks, guard consistency
2. **Delegatecall Safety** — Target immutability, upgrade patterns, storage layout compatibility, selfdestruct/critical storage risks
3. **Trust Boundaries** — For each privileged role, list the maximum damage if that role's key is compromised (fund drainage, contract bricking, exchange rate manipulation). Map blast radius of each trust assumption.
4. **External Contract Dependencies** — Upgradeability, pause/brick scenarios, fallback mechanisms
5. **Callback Vectors** — Callbacks from external calls, safety of callback handling, state manipulation between reads

## Output Format
Write a complete markdown document to {output_file} with sections for each analysis area, specific findings with line references and severity, and a summary table.

## CRITICAL
Write your COMPLETE analysis to {output_file} using the Write tool. Your response back should ONLY be: "Written to {output_file} -- {N} trust boundaries analyzed, {M} findings." Do NOT return analysis text in your response.
```

