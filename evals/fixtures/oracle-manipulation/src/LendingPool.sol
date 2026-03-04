// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PriceOracle.sol";
import "./MockToken.sol";

/// @title LendingPool
/// @notice Lending pool using a spot price oracle for collateral valuation.
contract LendingPool {
    PriceOracle public oracle;
    MockToken public lendingToken;

    // Collateral is tracked as ETH (wei)
    mapping(address => uint256) public collateral;
    mapping(address => uint256) public borrowed;
    uint256 public totalBorrowed;

    // Loan-to-value ratio: 75% (borrowable = 75% of collateral value)
    uint256 public constant LTV_NUMERATOR = 75;
    uint256 public constant LTV_DENOMINATOR = 100;

    // Liquidation threshold: 85% (liquidatable when borrowed > 85% of collateral value)
    uint256 public constant LIQUIDATION_THRESHOLD = 85;

    event CollateralDeposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 collateralSeized);

    error InsufficientCollateral();
    error BorrowLimitExceeded();
    error NotLiquidatable();
    error ZeroAmount();
    error InsufficientPoolBalance();

    constructor(address _oracle, address _lendingToken) {
        require(_oracle != address(0), "LendingPool: zero oracle");
        require(_lendingToken != address(0), "LendingPool: zero token");
        oracle = PriceOracle(_oracle);
        lendingToken = MockToken(_lendingToken);
    }

    /// @notice Deposit ETH as collateral.
    function depositCollateral() external payable {
        if (msg.value == 0) revert ZeroAmount();
        collateral[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);
    }

    /// @notice Borrow lending tokens against deposited collateral.
    /// @param amount Amount of lending tokens to borrow.
    function borrow(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (collateral[msg.sender] == 0) revert InsufficientCollateral();

        uint256 price = oracle.getPrice();
        uint256 collateralValue = (collateral[msg.sender] * price) / 1e18;
        uint256 maxBorrow = (collateralValue * LTV_NUMERATOR) / LTV_DENOMINATOR;

        if (borrowed[msg.sender] + amount > maxBorrow) revert BorrowLimitExceeded();
        if (lendingToken.balanceOf(address(this)) < amount) revert InsufficientPoolBalance();

        borrowed[msg.sender] += amount;
        totalBorrowed += amount;

        lendingToken.transfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    /// @notice Liquidate an undercollateralized borrower.
    /// @param borrower Address of the borrower to liquidate.
    function liquidate(address borrower) external {
        uint256 price = oracle.getPrice();
        uint256 collateralValue = (collateral[borrower] * price) / 1e18;
        uint256 threshold = (collateralValue * LIQUIDATION_THRESHOLD) / 100;

        if (borrowed[borrower] <= threshold) revert NotLiquidatable();

        uint256 collateralSeized = collateral[borrower];
        uint256 debtCleared = borrowed[borrower];

        collateral[borrower] = 0;
        borrowed[borrower] = 0;
        totalBorrowed -= debtCleared;

        // Transfer seized collateral to liquidator
        (bool ok,) = msg.sender.call{value: collateralSeized}("");
        require(ok, "LendingPool: ETH transfer failed");

        emit Liquidated(borrower, msg.sender, collateralSeized);
    }

    /// @notice View the USD value of a user's collateral at current oracle price.
    /// @param user Address of the user.
    function getCollateralValue(address user) external view returns (uint256) {
        uint256 price = oracle.getPrice();
        return (collateral[user] * price) / 1e18;
    }

    /// @notice Allow contract to receive ETH (for liquidation repayment etc.).
    receive() external payable {}
}
