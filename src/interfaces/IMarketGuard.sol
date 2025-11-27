// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

interface IMarketGuard {
    error MarketPaused();
    error MarketLpDepositPaused();
    error MarketLpWithdrawPaused();
    error MarketPositionOpenPaused();

    /// @notice Set the paused state of LP deposit
    /// @param paused_ The new paused state
    function setLpDepositPaused(bool paused_) external;

    /// @notice Set the paused state of LP withdraw
    /// @param paused_ The new paused state
    function setLpWithdrawPaused(bool paused_) external;

    /// @notice Set the paused state of all LP actions
    /// @param paused_ The new paused state
    function setLpPaused(bool paused_) external;

    /// @notice Set the paused state of position opening
    /// @param paused_ The new paused state
    function setPositionOpenPaused(bool paused_) external;

    /// @notice Set the paused state of the market
    /// @param paused_ The new paused state
    function setPaused(bool paused_) external;

    /// @notice Check if LP deposit is paused
    /// @return True if LP deposit is paused, false otherwise
    function isLpDepositPaused() external view returns (bool);

    /// @notice Check if LP withdraw is paused
    /// @return True if LP withdraw is paused, false otherwise
    function isLpWithdrawPaused() external view returns (bool);

    /// @notice Check if position opening is paused
    /// @return True if position opening is paused, false otherwise
    function isPositionOpenPaused() external view returns (bool);
}
