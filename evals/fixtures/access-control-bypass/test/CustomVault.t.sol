// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseVault.sol";
import "../src/CustomVault.sol";

contract CustomVaultTest is Test {
    CustomVault vault;
    address owner = address(0x1);
    address feeRecipient = address(0x2);
    address user = address(0x3);

    function setUp() public {
        vault = new CustomVault(owner, feeRecipient);
        vm.deal(user, 10 ether);
    }

    function test_ownerIsSet() public view {
        assertEq(vault.owner(), owner);
    }

    function test_feeRecipientIsSet() public view {
        assertEq(vault.feeRecipient(), feeRecipient);
    }

    function test_initialFeeRateIsZero() public view {
        assertEq(vault.feeRate(), 0);
    }

    function test_depositIncreasesBalance() public {
        vm.prank(user);
        vault.deposit{value: 1 ether}();
        assertEq(vault.balances(user), 1 ether);
        assertEq(vault.totalDeposits(), 1 ether);
    }

    function test_depositRevertsWhenZero() public {
        vm.prank(user);
        vm.expectRevert(CustomVault.ZeroAmount.selector);
        vault.deposit{value: 0}();
    }

    function test_withdrawAfterDeposit() public {
        vm.startPrank(user);
        vault.deposit{value: 2 ether}();
        uint256 balanceBefore = user.balance;
        vault.withdraw(1 ether);
        vm.stopPrank();
        // No fee set, so full amount returned
        assertEq(user.balance, balanceBefore + 1 ether);
        assertEq(vault.balances(user), 1 ether);
    }

    function test_withdrawRevertsInsufficientDeposit() public {
        vm.prank(user);
        vm.expectRevert(CustomVault.InsufficientDeposit.selector);
        vault.withdraw(1 ether);
    }

    function test_ownerCanPause() public {
        vm.prank(owner);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_ownerCanUnpause() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(owner);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_depositRevertsWhenPaused() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(user);
        vm.expectRevert(BaseVault.ContractPaused.selector);
        vault.deposit{value: 1 ether}();
    }

    function test_ownerCanSetFeeRate() public {
        vm.prank(owner);
        vault.setFeeRate(100);
        assertEq(vault.feeRate(), 100);
    }
}
