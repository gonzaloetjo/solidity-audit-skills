---
fixture: clean-contract
version: "1.0"
contracts:
  - src/Treasury.sol
known_vulnerabilities: []
known_safe:
  - contract: Treasury
    function: deposit
  - contract: Treasury
    function: withdraw
  - contract: Treasury
    function: getBalance
  - contract: Treasury
    function: getTotalDeposits
  - contract: Treasury
    function: pause
  - contract: Treasury
    function: unpause
contamination_notes:
  pattern_risk: n/a
  reasoning_required: moderate
design_decisions_preset:
  upgradeable: false
  token_standard: null
  access_control: "ownable"
  oracle_usage: false
  notes: "Simple ETH treasury with proper CEI, owner-only admin"
---

# Fixture: Clean Contract

## Overview

A simple ETH treasury with no vulnerabilities. All functions follow best practices: proper checks-effects-interactions in withdraw, owner-only access control on admin functions, view functions with no state changes.

## Purpose

Tests false positive rate in isolation. A perfect skill should report zero findings against known_safe functions, yielding AYI = 0.0 (no true positives possible, no false positives desired).

## Known-Safe Functions

- `deposit`: Updates state before returning. No external calls.
- `withdraw`: Follows CEI pattern — decrements balance before sending ETH.
- `getBalance`: Pure view function.
- `getTotalDeposits`: Pure view function.
- `pause` / `unpause`: Owner-only admin functions with proper access control.
