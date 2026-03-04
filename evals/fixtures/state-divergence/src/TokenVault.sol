// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title TokenVault
/// @notice Vault that tracks internal token balance alongside actual ERC20 balance.
contract TokenVault {
    address public owner;
    IERC20 public token;

    /// @dev Internal accounting of total deposited tokens — should mirror token.balanceOf(address(this))
    uint256 public totalDeposited;

    /// @dev Per-user deposit tracking
    mapping(address => uint256) public userDeposits;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Rescued(address indexed token_, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address token_) {
        owner = msg.sender;
        token = IERC20(token_);
    }

    /// @notice Deposit tokens into the vault.
    ///         Updates userDeposits and totalDeposited correctly.
    function deposit(uint256 amount) external {
        require(amount > 0, "zero amount");
        token.transferFrom(msg.sender, address(this), amount);
        userDeposits[msg.sender] += amount;
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw tokens from the vault.
    function withdraw(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(userDeposits[msg.sender] >= amount, "insufficient deposit");
        userDeposits[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the token balance available beyond what is tracked as deposited.
    ///         Intended to find "extra" tokens sent directly to the contract.
    function availableBalance() public view returns (uint256) {
        uint256 actual = token.balanceOf(address(this));
        return actual - totalDeposited;
    }

    /// @notice Emergency rescue of tokens accidentally sent to the vault.
    function emergencyRescue(address token_) external onlyOwner {
        if (token_ == address(token)) {
            uint256 rescuable = availableBalance();
            require(rescuable > 0, "nothing to rescue");
            IERC20(token_).transfer(owner, rescuable);
            emit Rescued(token_, rescuable);
        } else {
            // For other tokens, rescue entire balance
            uint256 bal = IERC20(token_).balanceOf(address(this));
            require(bal > 0, "nothing to rescue");
            IERC20(token_).transfer(owner, bal);
            emit Rescued(token_, bal);
        }
    }

    /// @notice Returns the recorded deposit amount for a user.
    function getDeposit(address user) external view returns (uint256) {
        return userDeposits[user];
    }
}
