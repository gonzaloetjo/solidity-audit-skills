# Example Output: Stage 2 Domain Analysis

This is a trimmed example from an actual analysis of the Deposit & Exchange Rate domain. Use it as a quality and format reference.

---

# Stage 2: Deposit & Exchange Rate Domain -- Per-Function Audit

**Audit Date**: 2026-02-06
**Domain**: Deposit flow, exchange rate calculation, stake/share conversions, pool accounting
**Contracts Analyzed**:
- `StakingVault.sol` -- `deposit()`, `_getExchangeRate()`, `_stakeToShares()`, `_sharesToStake()`
- `StakingVaultInternals.sol` -- `getTotalPooledStake()`, `getAvailableStake()`

---

## Per-Function Analysis

---

### deposit(uint256 minShares)

- **Rationale**: Entry point for users to deposit native token and receive LST shares. Must correctly convert deposited stake to shares at the current exchange rate, protect against sandwich/frontrunning via slippage, and maintain share supply/pool accounting invariants.

- **State mutations**:
  - `_mint(msg.sender, shares)` -- increases `totalSupply()` and `balanceOf(msg.sender)` by `shares`
  - `address(this).balance` is implicitly increased by `msg.value` at the start of the call

- **Dependencies**:
  - Reads: `getTotalPooledStake()` (via `StakingVaultInternals`), `totalSupply()` (ERC20), `INITIAL_SHARES_OFFSET`
  - Calls: `_stakeToShares(msg.value, preDepositStake)`, `_mint(msg.sender, shares)`
  - Modifiers: `nonReentrant`, `whenNotPaused`

- **Findings**:

  1. **INFO -- preDepositStake calculation is correct**. Line 230: `uint256 preDepositStake = getTotalPooledStake() - msg.value`. Since `address(this).balance` already includes `msg.value` at the point of execution (Solidity semantics for `payable` functions), the subtraction correctly recovers the pre-deposit total pooled stake.

  2. **WARNING -- Underflow revert acts as implicit insolvency guard**. The subtraction `getTotalPooledStake() - msg.value` will revert with arithmetic underflow if `getTotalPooledStake() < msg.value`. The revert reason will be a generic `Panic(0x11)` rather than a descriptive custom error. Consider adding an explicit check for better UX.

  3. **INFO -- Zero-share deposit protection**. Line 232: `if (shares == 0) revert StakingVault__InvalidAmount()` prevents dust deposits that produce zero shares.

  4. **INFO -- Slippage protection**. Lines 234-236: `minShares > 0 && shares < minShares` check allows callers to skip by passing 0.

- **Verdict**: **SOUND**

---

### _stakeToShares(uint256 stakeAmount, uint256 preDepositTotalStake)

- **Rationale**: Converts a native token amount to LST shares. Takes explicit `preDepositTotalStake` to avoid double-counting the depositor's funds. Only called from `deposit()`.

- **State mutations**: None (view function).

- **Dependencies**:
  - Reads: `totalSupply()`, `INITIAL_SHARES_OFFSET`
  - Calls: none
  - Modifiers: none

- **Findings**:

  1. **INFO -- Formula**: `shares = (stakeAmount * (totalSupply + OFFSET)) / (preDepositTotalStake + OFFSET)`. Standard rebasing vault formula with virtual offsets.

  2. **INFO -- Rounding direction is DOWN (protocol-favorable)**. Depositor receives fewer or equal shares. Correct for deposits.

  3. **INFO -- Inverse consistency with _sharesToStake**. Round-trip `_sharesToStake(_stakeToShares(x)) <= x`. System never over-estimates.

  4. **INFO -- No division by zero**. Denominator always >= 1e9 due to OFFSET.

- **Verdict**: **SOUND**

---

## Cross-Cutting Analysis: Key Questions

### Q1: Is the exchange rate math consistent across all callers?

**Yes.** All functions use `(totalStake + OFFSET) / (totalShares + OFFSET)`. `_stakeToShares` uses a parameter for pre-deposit stake instead of calling `getTotalPooledStake()` directly, which is correct.

### Q2: Rounding direction analysis

| Function | Direction | Favors |
|---|---|---|
| `_stakeToShares` (deposit) | DOWN | Protocol |
| `_sharesToStake` (withdrawal) | DOWN | Protocol |
| `_getExchangeRate` (display) | DOWN | Conservative |

All rounding directions are protocol-favorable.

---

## Summary of Findings

| # | Severity | Function | Finding |
|---|----------|----------|---------|
| 1 | WARNING | `deposit()` | Generic `Panic(0x11)` underflow during insolvency instead of custom error |
| 2 | WARNING | `getTotalPooledStake()` | Stale internal stake tracking overestimates pool during slashing |
| 3 | INFO | `_stakeToShares` / `_sharesToStake` | Rounding directions correctly protocol-favorable |

---

## Overall Domain Verdict: **SOUND** (with 2 non-critical warnings)
