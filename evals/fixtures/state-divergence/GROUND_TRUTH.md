---
fixture: state-divergence
version: "1.0"
contracts:
  - src/TokenVault.sol
  - src/MockERC20.sol
known_vulnerabilities:
  - id: V001
    severity: HIGH
    title: "withdraw does not decrement totalDeposited causing accounting divergence"
    contract: TokenVault
    function: withdraw
    location: "src/TokenVault.sol:53"
    verification_expected: CONFIRMED
    tags: [state-divergence, accounting, invariant-violation]
  - id: V002
    severity: MEDIUM
    title: "emergencyRescue uses diverged availableBalance allowing incorrect fund extraction"
    contract: TokenVault
    function: emergencyRescue
    location: "src/TokenVault.sol:79"
    tags: [state-divergence, dependent-bug]
known_safe:
  - contract: TokenVault
    function: deposit
  - contract: TokenVault
    function: getDeposit
  - contract: MockERC20
    function: transfer
---

# State-Divergence Fixture

## Overview

`TokenVault` maintains an internal accounting variable (`totalDeposited`) that is intended
to mirror the vault's actual ERC20 token balance. A missing decrement in `withdraw` causes
these two values to diverge after any withdrawal, breaking dependent logic.

## Vulnerability Details

### V001 — HIGH: withdraw does not decrement totalDeposited

**Location**: `src/TokenVault.sol:53` (`withdraw`)

`withdraw` correctly decrements `userDeposits[msg.sender]` but never decrements
`totalDeposited`. After one or more withdrawals, `totalDeposited` is permanently inflated
relative to `token.balanceOf(address(this))`.

**Impact**: The invariant `totalDeposited == token.balanceOf(address(this))` is violated
after every withdrawal. Any logic that depends on `totalDeposited` being accurate (such as
`availableBalance()`) will produce wrong results or revert.

**Exploit path**: User deposits 100 tokens → withdraws 50 → `totalDeposited` stays at 100,
real balance is 50. `availableBalance()` now reverts (underflow: 50 - 100).

### V002 — MEDIUM: emergencyRescue uses broken availableBalance

**Location**: `src/TokenVault.sol:79` (`emergencyRescue`)

`emergencyRescue` calls `availableBalance()` to determine how many tokens to rescue from
the vault's primary token. Because `availableBalance()` underflows after any withdrawal
(see V001), `emergencyRescue` becomes permanently unusable for the primary token, preventing
the owner from recovering any accidentally-sent tokens.

**Dependent bug**: V002 is a consequence of V001. Fixing V001 fixes V002.

## Known-Safe Functions

- `deposit`: correctly updates both `userDeposits` and `totalDeposited`.
- `getDeposit`: simple view, no state mutation.
- `MockERC20.transfer`: standard ERC20, no vulnerability.

## Fixture Design Notes

This fixture specifically exercises **Stage 3a stale-state / accounting-divergence analysis**.
A strong audit should:
1. Identify the missing `totalDeposited -= amount` in `withdraw`.
2. Trace the invariant violation to `availableBalance()`.
3. Identify `emergencyRescue` as a dependent caller that inherits the bug.
4. Mark `deposit` and `getDeposit` as safe despite operating on the same state variable.
