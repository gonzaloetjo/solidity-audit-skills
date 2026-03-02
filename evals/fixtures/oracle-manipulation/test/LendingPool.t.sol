// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/MockToken.sol";

contract LendingPoolTest is Test {
    PriceOracle oracle;
    LendingPool pool;
    MockToken token;

    address reporter = address(0x1);
    address user = address(0x2);
    address liquidator = address(0x3);

    // Initial ETH price: 2000 USD, 18 decimal precision
    uint256 constant INITIAL_PRICE = 2000e18;

    function setUp() public {
        oracle = new PriceOracle(reporter, INITIAL_PRICE);
        token = new MockToken("USDC", "USDC", 18);
        pool = new LendingPool(address(oracle), address(token));

        // Seed pool with lending tokens (18 decimals to match collateral value math)
        token.mint(address(pool), 1_000_000e18);

        vm.deal(user, 10 ether);
        vm.deal(liquidator, 10 ether);
    }

    function test_deploymentValues() public view {
        assertEq(address(pool.oracle()), address(oracle));
        assertEq(address(pool.lendingToken()), address(token));
        assertEq(oracle.latestPrice(), INITIAL_PRICE);
        assertEq(oracle.reporter(), reporter);
    }

    function test_depositCollateral() public {
        vm.prank(user);
        pool.depositCollateral{value: 1 ether}();
        assertEq(pool.collateral(user), 1 ether);
    }

    function test_depositCollateralRevertsZero() public {
        vm.prank(user);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.depositCollateral{value: 0}();
    }

    function test_getCollateralValue() public {
        vm.prank(user);
        pool.depositCollateral{value: 1 ether}();
        // 1 ETH * 2000 USD/ETH = 2000 USD (in 18 decimal token units)
        uint256 value = pool.getCollateralValue(user);
        assertEq(value, 2000e18);
    }

    function test_borrowWithinLimit() public {
        vm.prank(user);
        pool.depositCollateral{value: 1 ether}();

        // Max borrow: 2000e18 * 75% = 1500e18
        // Borrow 1000 USDC (1000e6 in token, but pool uses 18 decimal)
        // token is 6 decimals but LTV calc uses 18 decimal — test the relationship
        uint256 maxBorrowAllowed = (2000e18 * 75) / 100; // 1500e18

        vm.prank(user);
        pool.borrow(maxBorrowAllowed);

        assertEq(pool.borrowed(user), maxBorrowAllowed);
        assertEq(token.balanceOf(user), maxBorrowAllowed);
    }

    function test_borrowRevertsExceedingLimit() public {
        vm.prank(user);
        pool.depositCollateral{value: 1 ether}();

        uint256 overLimit = (2000e18 * 75) / 100 + 1;
        vm.prank(user);
        vm.expectRevert(LendingPool.BorrowLimitExceeded.selector);
        pool.borrow(overLimit);
    }

    function test_borrowRevertsNoCollateral() public {
        vm.prank(user);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        pool.borrow(100e18);
    }

    function test_oraclePriceUpdate() public {
        vm.prank(reporter);
        oracle.setPrice(3000e18);
        assertEq(oracle.getPrice(), 3000e18);
    }

    function test_collateralValueUpdatesWithPrice() public {
        vm.prank(user);
        pool.depositCollateral{value: 1 ether}();

        vm.prank(reporter);
        oracle.setPrice(3000e18);

        uint256 value = pool.getCollateralValue(user);
        assertEq(value, 3000e18);
    }
}
