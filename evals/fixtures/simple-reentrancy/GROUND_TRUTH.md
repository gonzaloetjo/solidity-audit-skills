---
fixture: simple-reentrancy
version: "1.0"
contracts:
  - src/Vault.sol
known_vulnerabilities:
  - id: V001
    severity: CRITICAL
    title: "Reentrancy in withdraw allows full vault drain"
    contract: Vault
    function: withdraw
    location: "src/Vault.sol:41"
    verification_expected: CONFIRMED
    tags: [reentrancy, cei-violation]
  - id: V002
    severity: HIGH
    title: "Missing reentrancy guard on emergencyWithdraw"
    contract: Vault
    function: emergencyWithdraw
    location: "src/Vault.sol:60"
    verification_expected: CONFIRMED
    tags: [reentrancy, missing-guard]
known_safe:
  - contract: Vault
    function: deposit
  - contract: Vault
    function: getBalance
design_decisions_preset:
  upgradeable: false
  token_standard: null
  access_control: none
  oracle_usage: false
  notes: "Simple ETH vault with deposit/withdraw"
---

# Fixture: Simple Reentrancy

## Overview

Classic checks-effects-interactions (CEI) violation in an ETH vault. The `withdraw` function sends ETH via a low-level call before updating the sender's balance, allowing a malicious contract to re-enter and drain the vault.

## Vulnerability V001 — CRITICAL: Reentrancy in withdraw

**Location**: `src/Vault.sol:41` (`withdraw`)

`withdraw` sends ETH to `msg.sender` via `call{value: amount}` on line 46 before decrementing `balances[msg.sender]` on line 50. An attacking contract's `receive()` function can re-enter `withdraw` — the balance check still passes because state hasn't been updated yet. Each re-entrant call withdraws `amount` again until the vault is drained.

## Vulnerability V002 — HIGH: Missing reentrancy guard on emergencyWithdraw

**Location**: `src/Vault.sol:60` (`emergencyWithdraw`)

Same CEI violation pattern as V001 but for the full user balance. Rated HIGH instead of CRITICAL because it requires the attacker to have a non-zero balance first. A ReentrancyGuard modifier would prevent both V001 and V002.

## Known-Safe Functions

- `deposit`: Updates state before returning. No external calls.
- `getBalance`: Pure view function, no state changes.

## Design Notes

Baseline "canary" fixture — if the skill cannot detect a textbook reentrancy, something is broken. Both vulnerabilities should be caught by Stage 2 domain analysis.
