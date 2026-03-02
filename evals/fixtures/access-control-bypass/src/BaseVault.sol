// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BaseVault
/// @notice A base vault contract with owner-controlled fee rate and pause mechanism.
contract BaseVault {
    address public owner;
    uint256 public feeRate; // basis points (e.g. 100 = 1%)
    bool public paused;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeeRateUpdated(uint256 newFeeRate);
    event Paused(address account);
    event Unpaused(address account);

    error Unauthorized();
    error InvalidFeeRate();
    error ContractPaused();

    constructor(address _owner) {
        require(_owner != address(0), "BaseVault: zero owner");
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /// @notice Update the fee rate. Only callable by owner.
    /// @param _feeRate New fee rate in basis points (max 1000 = 10%).
    function setFeeRate(uint256 _feeRate) external virtual onlyOwner {
        if (_feeRate > 1000) revert InvalidFeeRate();
        feeRate = _feeRate;
        emit FeeRateUpdated(_feeRate);
    }

    /// @notice Pause the vault. Only callable by owner.
    function pause() external virtual onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the vault. Only callable by owner.
    function unpause() external virtual onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership. Only callable by owner.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BaseVault: zero owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
