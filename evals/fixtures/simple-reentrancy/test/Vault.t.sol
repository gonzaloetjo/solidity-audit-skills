// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Vault.sol";

contract VaultTest is Test {
    Vault vault;
    address alice = makeAddr("alice");

    function setUp() public {
        vault = new Vault();
        vm.deal(alice, 10 ether);
    }

    function test_deposit() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        assertEq(vault.getBalance(alice), 1 ether);
        assertEq(vault.totalDeposited(), 1 ether);
        assertEq(vault.vaultBalance(), 1 ether);
    }

    function test_getBalance_zero_for_unknown() public view {
        assertEq(vault.getBalance(address(0xdead)), 0);
    }

    function test_deposit_multiple() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vault.deposit{value: 2 ether}();
        vm.stopPrank();

        assertEq(vault.getBalance(alice), 3 ether);
        assertEq(vault.totalDeposited(), 3 ether);
    }
}
