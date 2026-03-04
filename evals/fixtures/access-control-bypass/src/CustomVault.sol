// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseVault.sol";

/// @title CustomVault
/// @notice Extended vault with fee recipient configuration.
contract CustomVault is BaseVault {
    address public feeRecipient;
    mapping(address => uint256) public balances;
    uint256 public totalDeposits;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event FeeRecipientUpdated(address indexed newRecipient);

    error ZeroAmount();
    error InsufficientDeposit();

    constructor(address _owner, address _feeRecipient) BaseVault(_owner) {
        require(_feeRecipient != address(0), "CustomVault: zero recipient");
        feeRecipient = _feeRecipient;
    }

    /// @notice Override setFeeRate with custom validation.
    /// @param _feeRate New fee rate in basis points.
    function setFeeRate(uint256 _feeRate) external override {
        if (_feeRate > 1000) revert InvalidFeeRate();
        feeRate = _feeRate;
        emit FeeRateUpdated(_feeRate);
    }

    /// @notice Set the fee recipient address.
    /// @param _feeRecipient New recipient address.
    function setFeeRecipient(address _feeRecipient) external {
        require(_feeRecipient != address(0), "CustomVault: zero recipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /// @notice Deposit ETH into the vault.
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the vault. Fee is taken on withdrawal.
    /// @param amount Amount of ETH to withdraw (in wei).
    function withdraw(uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (balances[msg.sender] < amount) revert InsufficientDeposit();

        uint256 fee = (amount * feeRate) / 10000;
        uint256 payout = amount - fee;

        balances[msg.sender] -= amount;
        totalDeposits -= amount;

        if (fee > 0 && feeRecipient != address(0)) {
            (bool feeOk,) = feeRecipient.call{value: fee}("");
            require(feeOk, "CustomVault: fee transfer failed");
        }

        (bool ok,) = msg.sender.call{value: payout}("");
        require(ok, "CustomVault: transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Override pause — safe: retains onlyOwner.
    function pause() external override onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Allow contract to receive ETH.
    receive() external payable {}
}
