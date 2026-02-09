# Per-Function Analysis Template

Use this exact format for every function analyzed. Do not omit sections. Use line references from the source code.

---

### function_name(arg1, arg2, ...)

- **Rationale**: Why this function exists and what it should accomplish in the system. One paragraph.

- **State mutations**:
  - `variableName` -- what is written and why
  - (include implicit mutations like balance changes, ERC20 mint/burn effects)
  - (if none: "None (view/pure function).")

- **Dependencies**:
  - Reads: list all storage reads (state variables, `address(this).balance`, etc.)
  - Calls: list all internal/external function calls
  - Modifiers: list all modifiers applied to this function

- **Findings**:
  1. **{CRITICAL|WARNING|INFO} -- {short title}**. Detailed explanation with line references (e.g., "Line 230: ..."). Explain the impact and any mitigations. Each finding should be self-contained.
  2. (continue numbering for additional findings)

- **Verdict**: **{SOUND|NEEDS_REVIEW|ISSUE_FOUND}**

---

## Severity Definitions

- **CRITICAL**: Could lead to loss of funds, unauthorized access, or broken invariants. Must be addressed.
- **WARNING**: Non-critical issue with potential impact under specific conditions. Should be reviewed.
- **INFO**: Observation confirming correct behavior, documenting a design choice, or noting a benign edge case.

## Verdict Definitions

- **SOUND**: Function is correctly implemented. No issues found beyond informational notes.
- **NEEDS_REVIEW**: Function works but has warnings that should be evaluated by the team.
- **ISSUE_FOUND**: Function has one or more CRITICAL findings that need to be addressed.
