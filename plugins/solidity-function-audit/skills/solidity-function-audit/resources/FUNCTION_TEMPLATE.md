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
  1. **{CRITICAL|HIGH|MEDIUM|LOW|INFO} -- {short title}**. Detailed explanation with line references (e.g., "Line 230: ..."). Explain the impact and any mitigations. Each finding should be self-contained.
  2. (continue numbering for additional findings)
  - DO NOT vary the severity format. Always use exactly `**CRITICAL -- `, `**HIGH -- `, `**MEDIUM -- `, `**LOW -- `, or `**INFO -- ` (bold, space-dash-dash-space) so findings can be counted reliably.

- **Verdict**: **{SOUND|NEEDS_REVIEW|ISSUE_FOUND}**

---

## Severity Definitions

- **CRITICAL**: Direct loss of funds, unauthorized access to all funds, broken core invariants. Exploitable now.
- **HIGH**: Conditional loss of funds, significant access control bypass. Requires specific conditions but impact is severe.
- **MEDIUM**: Protocol behavior deviation, incorrect state under edge conditions. Limited direct financial impact.
- **LOW**: Best practices, gas optimizations with security implications, minor issues unlikely to cause harm.
- **INFO**: Observations, design choices, informational notes confirming correct behavior.

## Term Definitions

- **Protocol-favorable rounding**: Rounding in the direction that preserves or increases protocol assets (e.g., rounding shares down on deposit, rounding assets down on withdrawal).

## Verdict Definitions

- **SOUND**: Function is correctly implemented. Only INFO findings or no findings.
- **NEEDS_REVIEW**: Function has MEDIUM or LOW findings (no CRITICAL or HIGH).
- **ISSUE_FOUND**: Function has one or more CRITICAL or HIGH findings.
