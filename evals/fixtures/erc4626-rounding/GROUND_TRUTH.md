---
fixture: erc4626-rounding
version: "1.0"
contracts:
  - src/SimpleVault.sol
  - src/MockERC20.sol
known_vulnerabilities:
  - id: V001
    severity: HIGH
    title: "Incorrect rounding direction in convertToAssets favors withdrawer"
    contract: SimpleVault
    function: convertToAssets
    location: "src/SimpleVault.sol:40"
    verification_expected: CONFIRMED
    tags: [rounding, erc4626, math]
  - id: V002
    severity: MEDIUM
    title: "First depositor inflation attack possible due to missing virtual shares"
    contract: SimpleVault
    function: deposit
    location: "src/SimpleVault.sol:61"
    verification_expected: CONFIRMED
    tags: [inflation-attack, erc4626]
known_safe:
  - contract: SimpleVault
    function: convertToShares
  - contract: SimpleVault
    function: previewDeposit
  - contract: MockERC20
    function: transfer
design_decisions_preset:
  upgradeable: false
  token_standard: "ERC4626"
  access_control: none
  oracle_usage: false
  notes: "ERC4626-style vault with manual share math"
---

# Fixture: ERC4626 Rounding

## Overview

An ERC4626-style vault with manual share math containing two vulnerabilities: an incorrect rounding direction in `convertToAssets` and a missing virtual shares/assets defense against the first-depositor inflation attack.

## Vulnerability V001 — HIGH: convertToAssets rounds UP

**Location**: `src/SimpleVault.sol:40` (`convertToAssets`)

`convertToAssets` uses `(shares * totalAssets + totalShares - 1) / totalShares` — this rounds UP. Per ERC4626 convention, conversion from shares to assets during withdrawal/redemption should round DOWN (vault-favorable). Rounding up gives the withdrawer slightly more assets than they're entitled to. Over many redemptions, this extracts value from remaining depositors.

## Vulnerability V002 — MEDIUM: Missing virtual shares (inflation attack)

**Location**: `src/SimpleVault.sol:61` (`deposit`)

The vault has no virtual shares/assets offset (`totalShares` and `totalAssets` start at 0). A first depositor can: deposit 1 wei → get 1 share → donate a large amount directly to the vault → inflate `totalAssets` → subsequent depositors get 0 shares (truncated to 0 by integer division). The mitigation is a virtual offset: `convertToShares` should use `(assets * (totalShares + 1)) / (totalAssets + 1)`.

## Known-Safe Functions

- `convertToShares`: Rounds DOWN, which is correct for deposits.
- `previewDeposit`: Delegates to `convertToShares`, no vulnerability.
- `MockERC20.transfer`: Standard ERC20, no vulnerability.

## Design Notes

This fixture tests DeFi math comprehension. V001 requires understanding ERC4626 rounding conventions. V002 requires knowledge of the inflation attack vector. Both are well-documented in the Solidity security community but require domain expertise to detect.
