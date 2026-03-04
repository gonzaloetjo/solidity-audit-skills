// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PriceOracle
/// @notice Simple price oracle with a single designated reporter.
/// @dev Reports spot price — no time-weighted averaging (TWAP).
contract PriceOracle {
    address public reporter;
    uint256 public latestPrice;
    uint256 public lastUpdated;

    event PriceUpdated(uint256 price, uint256 timestamp);
    event ReporterUpdated(address indexed newReporter);

    error Unauthorized();
    error InvalidPrice();

    constructor(address _reporter, uint256 _initialPrice) {
        require(_reporter != address(0), "PriceOracle: zero reporter");
        require(_initialPrice > 0, "PriceOracle: zero price");
        reporter = _reporter;
        latestPrice = _initialPrice;
        lastUpdated = block.timestamp;
        emit PriceUpdated(_initialPrice, block.timestamp);
    }

    /// @notice Update the price. Only callable by the designated reporter.
    /// @param _price New price (18 decimal precision).
    function setPrice(uint256 _price) external {
        if (msg.sender != reporter) revert Unauthorized();
        if (_price == 0) revert InvalidPrice();
        latestPrice = _price;
        lastUpdated = block.timestamp;
        emit PriceUpdated(_price, block.timestamp);
    }

    /// @notice Returns the latest price.
    function getPrice() external view returns (uint256) {
        return latestPrice;
    }

    /// @notice Update the reporter address. Only callable by current reporter.
    function setReporter(address _reporter) external {
        if (msg.sender != reporter) revert Unauthorized();
        require(_reporter != address(0), "PriceOracle: zero reporter");
        reporter = _reporter;
        emit ReporterUpdated(_reporter);
    }
}
