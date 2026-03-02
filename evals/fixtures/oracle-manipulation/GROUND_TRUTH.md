---
fixture: oracle-manipulation
version: "1.0"
contracts:
  - src/PriceOracle.sol
  - src/LendingPool.sol
  - src/MockToken.sol
known_vulnerabilities:
  - id: V001
    severity: CRITICAL
    title: "Single-block oracle price enables flash loan collateral inflation"
    contract: LendingPool
    function: borrow
    location: "src/LendingPool.sol:56"
    verification_expected: CONFIRMED
    tags: [oracle, flash-loan, price-manipulation]
  - id: V002
    severity: INFO
    title: "No TWAP or time-weighted price smoothing in oracle"
    contract: PriceOracle
    function: getPrice
    location: "src/PriceOracle.sol:39"
    tags: [oracle, design-observation]
known_safe:
  - contract: LendingPool
    function: depositCollateral
  - contract: LendingPool
    function: liquidate
  - contract: LendingPool
    function: getCollateralValue
  - contract: PriceOracle
    function: setPrice
---

## Fixture: oracle-manipulation

### Overview

This fixture demonstrates single-block oracle price manipulation via flash loans — one of the most common CRITICAL vulnerabilities in DeFi lending protocols. `LendingPool.borrow()` reads a spot price from `PriceOracle` with no time-weighting or staleness protection. An attacker with flash loan access can inflate the collateral price in the same transaction, borrow far more than their collateral is worth, and exit with the difference.

### Vulnerability V001 — CRITICAL: Single-block oracle price in borrow()

**File**: `src/LendingPool.sol`, line 56

`LendingPool.borrow()` calls `oracle.getPrice()` to compute maximum borrowable amount. The oracle returns `latestPrice` — a single value updateable by the reporter in any block. Attack sequence:

1. Attacker takes flash loan of a large token amount
2. Attacker (if also the reporter, or via oracle that reads from a DEX pool) sets oracle price very high
3. Attacker calls `depositCollateral()` with a modest ETH amount
4. At the inflated price, `collateralValue` is enormous → `maxBorrow` is enormous
5. Attacker calls `borrow()` and drains the lending pool
6. Flash loan is repaid; attacker keeps profit

Even if the reporter is a trusted off-chain service, the single-block nature means the reporter can be front-run or the oracle can be misconfigured to use an AMM spot price. The correct mitigation is TWAP (time-weighted average price) over a window of multiple blocks, or a Chainlink price feed with deviation thresholds.

### Vulnerability V002 — INFO: No TWAP in oracle design

**File**: `src/PriceOracle.sol`, line 39

`PriceOracle.getPrice()` returns raw `latestPrice` with no smoothing. This is a design observation rather than a standalone exploitable vulnerability — it is the root cause that enables V001. Flagging it at INFO level tests whether the skill correctly identifies architectural weaknesses distinct from the exploitable instance.

### Safe Functions

- `depositCollateral`: Correctly tracks ETH deposits with no oracle interaction.
- `liquidate`: Uses the same oracle but liquidation benefits the protocol; oracle manipulation at liquidation time is economically self-defeating.
- `getCollateralValue`: View-only, no state changes.
- `PriceOracle.setPrice`: Access-controlled to the designated reporter.

### Design Notes

This fixture primarily tests Stage 3 cross-contract analysis — the vulnerability spans `LendingPool` (caller) and `PriceOracle` (callee). A Stage 2 domain audit of LendingPool should flag the oracle dependency. Stage 3 cross-cutting should trace the external call path and assess trust assumptions. The Verification stage should produce a CONFIRMED verdict for V001 via a Foundry test demonstrating collateral inflation.
