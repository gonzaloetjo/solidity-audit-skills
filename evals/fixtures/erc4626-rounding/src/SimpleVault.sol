// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC20.sol";

/// @title SimpleVault
/// @notice ERC4626-style vault with manual share math.
/// @dev Contains rounding direction vulnerability and missing virtual shares.
contract SimpleVault {
    MockERC20 public asset;

    uint256 public totalShares;
    uint256 public totalAssets;
    mapping(address => uint256) public shareBalanceOf;

    event Deposit(address indexed caller, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, uint256 assets, uint256 shares);

    error ZeroAmount();
    error InsufficientShares();
    error InsufficientAssets();

    constructor(address _asset) {
        asset = MockERC20(_asset);
    }

    /// @notice Convert asset amount to share amount.
    /// @dev Rounds DOWN — correct for deposit (fewer shares minted = vault-favorable).
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalShares == 0 || totalAssets == 0) return assets;
        return (assets * totalShares) / totalAssets;
    }

    /// @notice Convert share amount to asset amount.
    /// @dev VULNERABILITY (HIGH): Rounds UP instead of DOWN.
    ///      On withdrawal/redemption, the vault should round DOWN (vault-favorable).
    ///      Rounding UP means the withdrawer gets slightly more assets per share,
    ///      extracting value from remaining depositors. Over many small withdrawals,
    ///      this compounds to meaningful loss.
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalShares == 0 || totalAssets == 0) return shares;
        // BUG: rounds UP — should be (shares * totalAssets) / totalShares (round down)
        return (shares * totalAssets + totalShares - 1) / totalShares;
    }

    /// @notice Preview shares minted for a given deposit.
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    /// @notice Preview assets returned for a given redemption.
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Deposit assets and receive shares.
    /// @param assets Amount of underlying tokens to deposit.
    /// @dev VULNERABILITY (MEDIUM): No virtual shares/assets offset.
    ///      First depositor can donate assets directly to inflate share price,
    ///      causing subsequent depositors to receive 0 shares (inflation attack).
    function deposit(uint256 assets) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        shares = convertToShares(assets);
        if (totalShares > 0 && shares == 0) revert ZeroAmount();

        asset.transferFrom(msg.sender, address(this), assets);

        totalAssets += assets;
        totalShares += shares;
        shareBalanceOf[msg.sender] += shares;

        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Redeem shares for underlying assets.
    /// @param shares Amount of shares to redeem.
    function redeem(uint256 shares) external returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (shareBalanceOf[msg.sender] < shares) revert InsufficientShares();

        assets = convertToAssets(shares);

        shareBalanceOf[msg.sender] -= shares;
        totalShares -= shares;
        totalAssets -= assets;

        asset.transfer(msg.sender, assets);
        emit Withdraw(msg.sender, assets, shares);
    }

    /// @notice Withdraw exact assets by burning proportional shares.
    /// @param assets Amount of underlying tokens to withdraw.
    function withdraw(uint256 assets) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        // Convert assets to shares needed — rounds UP to be vault-favorable
        if (totalShares == 0 || totalAssets == 0) {
            shares = assets;
        } else {
            shares = (assets * totalShares + totalAssets - 1) / totalAssets;
        }

        if (shareBalanceOf[msg.sender] < shares) revert InsufficientShares();

        shareBalanceOf[msg.sender] -= shares;
        totalShares -= shares;
        totalAssets -= assets;

        asset.transfer(msg.sender, assets);
        emit Withdraw(msg.sender, assets, shares);
    }
}
