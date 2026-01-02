// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IMarketFeePolicy {
    error InvalidFee(uint256 given, uint256 max);

    /// @notice Set the open position fee
    /// @param fee_ The new open position fee (in WAD 1e18 = 100%)
    function setOpenPositionFee(uint256 fee_) external;

    /// @notice Set the close position fee
    /// @param fee_ The new close position fee (in WAD 1e18 = 100%)
    function setClosePositionFee(uint256 fee_) external;

    /// @notice Set the fee
    /// @param fee_ The new fee (in WAD 1e18 = 100%)
    function setFee(uint256 fee_) external;

    /// @notice Withdraw accrued fees
    /// @param to_ The address to withdraw to
    function withdrawAccruedFees(address to_) external;

    /// @notice Accrued fees in asset tokens
    /// @return The accrued fees
    function accruedFees() external view returns (uint256);

    /// @notice Check if open position fee is enabled
    /// @return True if open position fee is enabled, false otherwise
    function openPositionFeeEnabled() external view returns (bool);

    /// @notice Check if close position fee is enabled
    /// @return True if close position fee is enabled, false otherwise
    function closePositionFeeEnabled() external view returns (bool);

    /// @notice Get the open position fee
    /// @return The open position fee (in WAD 1e18 = 100%)
    function openPositionFee() external view returns (uint256);

    /// @notice Get the close position fee
    /// @return The close position fee (in WAD 1e18 = 100%)
    function closePositionFee() external view returns (uint256);
}
