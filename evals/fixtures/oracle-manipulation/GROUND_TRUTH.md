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
    title: "Reporter can set arbitrary price enabling over-collateralized borrowing"
    contract: LendingPool
    function: borrow
    location: "src/LendingPool.sol:56"
    verification_expected: CONFIRMED
    tags: [oracle, centralization-risk, trusted-party, price-manipulation]
  - id: V002
    severity: INFO
    title: "No TWAP or time-weighted price smoothing in oracle"
    contract: PriceOracle
    function: getPrice
    location: "src/PriceOracle.sol:39"
    verification_expected: INCONCLUSIVE
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
contamination_notes:
  pattern_risk: high
  reasoning_required: moderate
design_decisions_preset:
  upgradeable: false
  token_standard: null
  access_control: "custom"
  oracle_usage: true
  notes: "Lending pool with custom price oracle"
---

## Fixture: oracle-manipulation

### Overview

This fixture demonstrates a trusted-reporter oracle vulnerability in a DeFi lending protocol. `LendingPool.borrow()` reads a spot price from `PriceOracle` with no time-weighting, staleness protection, or price bounds. The oracle's `setPrice()` is gated to a single `reporter` address — external flash-loan attackers cannot manipulate the price. The real risk is that a compromised or malicious reporter can set an extreme price, enabling a borrower to extract far more value than their collateral warrants.

### Vulnerability V001 — CRITICAL: Reporter can set arbitrary price enabling over-collateralized borrowing

**File**: `src/LendingPool.sol`, line 56

`LendingPool.borrow()` calls `oracle.getPrice()` to compute maximum borrowable amount. The oracle returns `latestPrice` — a value updatable only by the designated `reporter` address. There are no price bounds, rate limits, or deviation checks on `setPrice()`. Attack sequence:

1. Reporter (compromised, malicious, or colluding) calls `setPrice()` with an extreme value (e.g., 100x real price)
2. Attacker deposits a small amount of ETH as collateral via `depositCollateral()`
3. At the inflated price, `collateralValue` is enormous → `maxBorrow` is enormous
4. Attacker calls `borrow()` and drains the lending pool's token reserves
5. Reporter restores the original price (covering tracks)

This is a centralization/trusted-party risk: the protocol's entire collateral valuation depends on a single unvalidated price source. Mitigations include TWAP (time-weighted average price), price deviation bounds, multi-reporter quorum, or Chainlink price feeds with heartbeat checks.

### Vulnerability V002 — INFO: No TWAP in oracle design

**File**: `src/PriceOracle.sol`, line 39

`PriceOracle.getPrice()` returns raw `latestPrice` with no smoothing. This is a design observation rather than a standalone exploitable vulnerability — it is the root cause that enables V001. Flagging it at INFO level tests whether the skill correctly identifies architectural weaknesses distinct from the exploitable instance.

### Safe Functions

- `depositCollateral`: Correctly tracks ETH deposits with no oracle interaction.
- `liquidate`: Uses the same oracle but liquidation benefits the protocol; oracle manipulation at liquidation time is economically self-defeating.
- `getCollateralValue`: View-only, no state changes.
- `PriceOracle.setPrice`: Access-controlled to the designated reporter.

### Design Notes

This fixture primarily tests Stage 3 cross-contract analysis — the vulnerability spans `LendingPool` (caller) and `PriceOracle` (callee). A Stage 2 domain audit of LendingPool should flag the oracle dependency. Stage 3 cross-cutting should trace the external call path and assess trust assumptions. Note that `setPrice()` is access-controlled to the `reporter` address — the threat model is reporter compromise or collusion, not external flash-loan price manipulation. The Verification stage should produce a CONFIRMED verdict for V001 via a Foundry test that pranks the reporter address and demonstrates over-borrowing.
