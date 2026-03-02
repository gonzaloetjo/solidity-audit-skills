// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SimpleVault.sol";
import "../src/MockERC20.sol";

contract SimpleVaultTest is Test {
    SimpleVault vault;
    MockERC20 token;
    address alice = makeAddr("alice");

    function setUp() public {
        token = new MockERC20("Test Token", "TT");
        vault = new SimpleVault(address(token));
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
    }

    function test_deposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        assertEq(shares, 100e18);
        assertEq(vault.shareBalanceOf(alice), 100e18);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(vault.totalShares(), 100e18);
    }

    function test_previewDeposit() public view {
        uint256 shares = vault.previewDeposit(50e18);
        assertEq(shares, 50e18);
    }

    function test_convertToShares_returns_input_when_empty() public view {
        assertEq(vault.convertToShares(100e18), 100e18);
    }
}
