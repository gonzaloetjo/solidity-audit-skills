// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Vault
/// @notice Simple ETH vault with deposit and withdrawal functionality.
/// @dev Contains classic reentrancy vulnerabilities for evaluation purposes.
contract Vault {
    mapping(address => uint256) private balances;
    uint256 public totalDeposited;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    /// @notice Deposit ETH into the vault.
    /// @dev Safe — updates state before any external interaction.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        totalDeposited += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Get the deposited balance of an address.
    /// @param account The address to query.
    /// @return The ETH balance deposited by account.
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @notice Withdraw ETH from the vault.
    /// @param amount The amount of ETH (in wei) to withdraw.
    /// @dev VULNERABILITY (CRITICAL): Sends ETH before updating state.
    ///      Classic checks-effects-interactions violation — an attacker
    ///      can re-enter withdraw() via a receive() callback and drain
    ///      the entire vault balance.
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance();

        // External call BEFORE state update — reentrancy vector
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        // State update AFTER external call — too late if re-entered
        balances[msg.sender] -= amount;
        totalDeposited -= amount;
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Emergency withdrawal of full balance.
    /// @dev VULNERABILITY (HIGH): No reentrancy guard and sends ETH before
    ///      clearing state. Same CEI violation as withdraw() but for the
    ///      entire user balance. A reentrancy guard (e.g., OpenZeppelin's
    ///      ReentrancyGuard) would mitigate both functions.
    function emergencyWithdraw() external {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert InsufficientBalance();

        // External call BEFORE state update — reentrancy vector
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        // State cleared AFTER external call
        balances[msg.sender] = 0;
        totalDeposited -= amount;
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    /// @notice Returns the total ETH held by the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Allow contract to receive ETH.
    receive() external payable {}
}
