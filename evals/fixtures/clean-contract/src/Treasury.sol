// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Treasury
/// @notice Simple ETH treasury with deposit/withdraw, owner-only admin, and pause functionality.
///         Follows checks-effects-interactions pattern throughout.
contract Treasury {
    address public immutable owner;
    bool public paused;

    mapping(address => uint256) private balances;
    uint256 private totalDeposits;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    error NotOwner();
    error ContractPaused();
    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error ZeroAmount();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Deposit ETH into the treasury. Caller's balance is credited.
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        // Effects before any state reads — update both mappings atomically
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the treasury.
    /// @param amount The amount to withdraw in wei.
    function withdraw(uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        uint256 userBalance = balances[msg.sender];
        if (amount > userBalance) revert InsufficientBalance(amount, userBalance);

        // Checks-Effects-Interactions: update state BEFORE external call
        balances[msg.sender] = userBalance - amount;
        totalDeposits -= amount;

        emit Withdrawn(msg.sender, amount);

        // Interaction last — after all state has been updated
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Returns the ETH balance credited to `account`.
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @notice Returns the total ETH deposited across all accounts.
    function getTotalDeposits() external view returns (uint256) {
        return totalDeposits;
    }

    /// @notice Pause the contract. Only callable by owner.
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract. Only callable by owner.
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
