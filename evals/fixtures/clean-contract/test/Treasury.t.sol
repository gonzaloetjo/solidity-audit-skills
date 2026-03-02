// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury public treasury;
    address public owner;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        treasury = new Treasury();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // --- deposit ---

    function test_Deposit_UpdatesBalance() public {
        vm.prank(alice);
        treasury.deposit{value: 1 ether}();

        assertEq(treasury.getBalance(alice), 1 ether);
    }

    function test_Deposit_UpdatesTotalDeposits() public {
        vm.prank(alice);
        treasury.deposit{value: 1 ether}();

        vm.prank(bob);
        treasury.deposit{value: 2 ether}();

        assertEq(treasury.getTotalDeposits(), 3 ether);
    }

    function test_Deposit_RevertsOnZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.deposit{value: 0}();
    }

    function test_Deposit_RevertsWhenPaused() public {
        treasury.pause();

        vm.prank(alice);
        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.deposit{value: 1 ether}();
    }

    // --- withdraw ---

    function test_Withdraw_DecreasesBalance() public {
        vm.startPrank(alice);
        treasury.deposit{value: 2 ether}();
        treasury.withdraw(1 ether);
        vm.stopPrank();

        assertEq(treasury.getBalance(alice), 1 ether);
    }

    function test_Withdraw_DecreasesTotalDeposits() public {
        vm.startPrank(alice);
        treasury.deposit{value: 2 ether}();
        treasury.withdraw(1 ether);
        vm.stopPrank();

        assertEq(treasury.getTotalDeposits(), 1 ether);
    }

    function test_Withdraw_SendsETH() public {
        vm.startPrank(alice);
        treasury.deposit{value: 2 ether}();
        uint256 balanceBefore = alice.balance;
        treasury.withdraw(1 ether);
        vm.stopPrank();

        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    function test_Withdraw_RevertsOnInsufficientBalance() public {
        vm.prank(alice);
        treasury.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Treasury.InsufficientBalance.selector, 2 ether, 1 ether));
        treasury.withdraw(2 ether);
    }

    function test_Withdraw_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.withdraw(0);
    }

    function test_Withdraw_RevertsWhenPaused() public {
        vm.prank(alice);
        treasury.deposit{value: 1 ether}();

        treasury.pause();

        vm.prank(alice);
        vm.expectRevert(Treasury.ContractPaused.selector);
        treasury.withdraw(1 ether);
    }

    // --- getBalance ---

    function test_GetBalance_ReturnsZeroForNewAccount() public view {
        assertEq(treasury.getBalance(alice), 0);
    }

    function test_GetBalance_ReflectsDepositAndWithdraw() public {
        vm.startPrank(alice);
        treasury.deposit{value: 3 ether}();
        treasury.withdraw(1 ether);
        vm.stopPrank();

        assertEq(treasury.getBalance(alice), 2 ether);
    }

    // --- pause / unpause ---

    function test_Pause_SetsPausedFlag() public {
        treasury.pause();
        assertTrue(treasury.paused());
    }

    function test_Unpause_ClearsPausedFlag() public {
        treasury.pause();
        treasury.unpause();
        assertFalse(treasury.paused());
    }

    function test_Pause_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.pause();
    }

    function test_Unpause_RevertsForNonOwner() public {
        treasury.pause();

        vm.prank(alice);
        vm.expectRevert(Treasury.NotOwner.selector);
        treasury.unpause();
    }

    function test_OwnerCanDepositAndWithdrawAfterUnpause() public {
        treasury.pause();
        treasury.unpause();

        vm.startPrank(alice);
        treasury.deposit{value: 1 ether}();
        treasury.withdraw(1 ether);
        vm.stopPrank();

        assertEq(treasury.getBalance(alice), 0);
    }
}
