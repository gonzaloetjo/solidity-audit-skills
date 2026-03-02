// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title TokenVault
/// @notice Vault that tracks internal token balance alongside actual ERC20 balance.
///         Internal accounting can diverge from real balance due to a bug in withdraw.
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
    /// @dev VULNERABILITY (HIGH): updates userDeposits but does NOT decrement totalDeposited.
    ///      After each withdrawal, totalDeposited remains inflated relative to the actual
    ///      token balance. This invariant violation — totalDeposited should always equal
    ///      token.balanceOf(address(this)) — causes availableBalance() to underflow or
    ///      return incorrect values, propagating errors to any caller of availableBalance().
    function withdraw(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(userDeposits[msg.sender] >= amount, "insufficient deposit");
        userDeposits[msg.sender] -= amount;
        // BUG: totalDeposited is not decremented here. Should be:
        //   totalDeposited -= amount;
        token.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the token balance available beyond what is tracked as deposited.
    ///         Intended to find "extra" tokens sent directly to the contract.
    /// @dev Returns token.balanceOf(this) - totalDeposited. Because totalDeposited is
    ///      never decremented by withdraw, this value underflows once any withdrawal
    ///      occurs, reverting due to Solidity 0.8 overflow checks.
    function availableBalance() public view returns (uint256) {
        uint256 actual = token.balanceOf(address(this));
        // This underflows when totalDeposited > actual (i.e. after any withdrawal)
        return actual - totalDeposited;
    }

    /// @notice Emergency rescue of tokens accidentally sent to the vault.
    /// @dev VULNERABILITY (MEDIUM): uses availableBalance() to determine how much to
    ///      rescue. Because availableBalance() is broken after any withdrawal (it reverts
    ///      or returns incorrect values), this function becomes unusable or may rescue
    ///      the wrong amount of tokens, depending on the divergence state.
    function emergencyRescue(address token_) external onlyOwner {
        if (token_ == address(token)) {
            // Attempt to rescue only "extra" tokens — but availableBalance() is broken
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
