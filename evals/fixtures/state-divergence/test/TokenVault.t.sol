// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenVault.sol";
import "../src/MockERC20.sol";

contract TokenVaultTest is Test {
    MockERC20 token;
    TokenVault vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockERC20("Test Token", "TST", 18);
        vault = new TokenVault(address(token));

        token.mint(alice, 1000 ether);
        token.mint(bob, 1000 ether);
    }

    function test_deposit() public {
        vm.startPrank(alice);
        token.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vm.stopPrank();

        assertEq(vault.userDeposits(alice), 100 ether);
        assertEq(vault.totalDeposited(), 100 ether);
        assertEq(token.balanceOf(address(vault)), 100 ether);
    }

    function test_getDeposit() public {
        vm.startPrank(alice);
        token.approve(address(vault), 200 ether);
        vault.deposit(200 ether);
        vm.stopPrank();

        assertEq(vault.getDeposit(alice), 200 ether);
        assertEq(vault.getDeposit(bob), 0);
    }

    function test_multipleDeposits() public {
        vm.startPrank(alice);
        token.approve(address(vault), 300 ether);
        vault.deposit(100 ether);
        vault.deposit(200 ether);
        vm.stopPrank();

        assertEq(vault.userDeposits(alice), 300 ether);
        assertEq(vault.totalDeposited(), 300 ether);
    }

    function test_withdraw_basic() public {
        vm.startPrank(alice);
        token.approve(address(vault), 100 ether);
        vault.deposit(100 ether);
        vault.withdraw(50 ether);
        vm.stopPrank();

        // userDeposits correctly decremented
        assertEq(vault.userDeposits(alice), 50 ether);
        // token balance correctly reduced
        assertEq(token.balanceOf(alice), 950 ether);
    }
}
