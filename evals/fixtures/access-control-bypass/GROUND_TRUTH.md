---
fixture: access-control-bypass
version: "1.0"
contracts:
  - src/BaseVault.sol
  - src/CustomVault.sol
known_vulnerabilities:
  - id: V001
    severity: HIGH
    title: "setFeeRate override drops onlyOwner modifier, allowing arbitrary fee manipulation"
    contract: CustomVault
    function: setFeeRate
    location: "src/CustomVault.sol:30"
    verification_expected: CONFIRMED
    tags: [access-control, modifier-bypass, inheritance]
  - id: V002
    severity: LOW
    title: "setFeeRecipient has no access control — any caller can redirect fee payments"
    contract: CustomVault
    function: setFeeRecipient
    location: "src/CustomVault.sol:39"
    verification_expected: CONFIRMED
    tags: [access-control, fee-redirection]
known_safe:
  - contract: CustomVault
    function: deposit
  - contract: CustomVault
    function: withdraw
  - contract: CustomVault
    function: pause
  - contract: BaseVault
    function: setFeeRate
  - contract: BaseVault
    function: pause
  - contract: BaseVault
    function: unpause
  - contract: BaseVault
    function: transferOwnership
---

## Fixture: access-control-bypass

### Overview

This fixture demonstrates a common inheritance-based access control vulnerability in Solidity: a child contract overrides a `virtual` function from the parent but omits the parent's `onlyOwner` modifier. The vulnerability is subtle — both contracts compile cleanly and the function signature is identical, but the security constraint is silently dropped.

### Vulnerability V001 — HIGH: setFeeRate override drops onlyOwner

**File**: `src/CustomVault.sol`, line 30

`BaseVault.setFeeRate` is declared `virtual` with `onlyOwner`. `CustomVault` overrides this function but does not apply `onlyOwner`, so any external address can call it and change the fee rate to any value up to 10% (1000 bps). A malicious actor could:

1. Set feeRate to the maximum (1000 bps = 10%) before a large withdrawal
2. Set feeRate to 0 to avoid paying protocol fees
3. Combine with V002 to first redirect the fee recipient and then inflate the fee rate

The Solidity compiler does not warn about dropped modifiers in overrides — this is a silent behavioral change.

### Vulnerability V002 — LOW: setFeeRecipient has no access control

**File**: `src/CustomVault.sol`, line 39

`CustomVault.setFeeRecipient` sets the address that receives fee payments on every withdrawal. There is no `onlyOwner` or any other access guard. Any caller can redirect protocol fees to their own address. Standalone this is a LOW severity issue (requires timing a call before a withdrawal), but in combination with V001 it becomes a higher-impact attack vector.

### Safe Functions

- `deposit` / `withdraw`: Correctly respect the `whenNotPaused` modifier; withdrawal math is sound.
- `pause` (CustomVault override): Correctly retains `onlyOwner`.
- `BaseVault.setFeeRate`: The parent implementation is safe — the vulnerability only exists in the override.

### Design Notes

The fixture intentionally uses a two-contract inheritance structure to test whether the auditing skill detects modifier omission across a contract hierarchy. Stage 1 (foundation analysis) should identify the public state mutability. Stage 2 (domain audit) should flag the missing modifier. Stage 3 cross-cutting analysis is not the primary target here, though V001+V002 combination could be noted.
