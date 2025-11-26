// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IRateModel} from "src/interfaces/IRateModel.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol";
import {PositionLib} from "src/libraries/PositionLib.sol";

/// @title IMarket
/// @author Lora Finance
interface IMarket {
    event PositionOpened(
        uint256 indexed id,
        address indexed user,
        uint256 notional,
        uint256 delta,
        uint256 strikePrice,
        int96 flowRate,
        uint256 timestamp
    );
    event PositionClosed(uint256 indexed id, address indexed user, uint256 profit, uint256 timestamp);
    event UserLiquidated(address indexed user, uint256 timestamp);

    error NotionalZero();
    error FlowRateZero();
    error FlowRateTooHigh();
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error FailedToOpenPosition(uint256 notional, uint256 delta);
    error FailedToClosePosition(uint256 positionId);
    error FlowAuthorizedByMarketOnly(address given, address expected);
    error ZeroOtmHalf();
    error BufferTooHigh(uint256 given, uint256 max);
    error InvalidSuperToken(address given, address expected);
    error OnlyPositionOwner(address given, address expected);
    error PositionNotFound(uint256 positionId);
    error PositionNotOpen(uint256 positionId);

    /// @notice Set a new rate model for the market
    /// @dev Only callable by the market owner
    /// @param newRateModel_ The address of the new rate model
    function setRateModel(address newRateModel_) external;

    /// @notice Set a new price oracle for the market
    /// @dev Only callable by the market owner
    /// @param newPriceOracle_ The address of the new price oracle
    function setPriceOracle(address newPriceOracle_) external;

    /// @notice Set a new buffer value for the market
    /// @dev Only callable by the market owner
    /// @param newBuffer_ The new buffer value in WAD (1e18) where 1e18 = 100% and must be <= 1e18
    function setBuffer(uint256 newBuffer_) external;

    /// @notice Set a new out-of-the-money half value for the market
    /// @dev Only callable by the market owner
    /// @param newOtmHalf_ The new out-of-the-money half value in WAD (1e18) where 1e18 = 100% and must be > 0
    function setOtmHalf(uint256 newOtmHalf_) external;

    /// @notice Set a new warm-up period for the market
    /// @dev Only callable by the market owner
    /// @param newWarmUpPeriod_ The new warm-up period in seconds
    function setWarmUpPeriod(uint256 newWarmUpPeriod_) external;

    /// @notice Open a new position with the specified notional and delta
    /// @param notional_ The notional amount for the position
    /// @param delta_ The delta for the position in WAD (1e18) where 1e18 = 100%
    /// @return positionId_ The ID of the newly opened position
    function openPosition(uint256 notional_, uint256 delta_) external returns (uint256 positionId_);

    /// @notice Close an existing position by its ID
    /// @param positionId_ The ID of the position to close
    /// @return payout_ The payout amount to the position owner upon closing
    function closePosition(uint256 positionId_) external returns (uint256 payout_);

    /// @notice Get the rate model used by the market
    /// @return rateModel The rate model contract
    function rateModel() external view returns (IRateModel);

    /// @notice Get the price oracle used by the market
    /// @return priceOracle The price oracle contract
    function priceOracle() external view returns (ISentinelOracle);

    /// @notice Get the total number of positions in the market
    /// @return totalPositions The total number of positions
    function totalPositions() external view returns (uint256);

    /// @notice Get the total locked notional in the market
    /// @return lockedNotional The total locked notional amount
    function lockedNotional() external view returns (uint256);

    /// @notice Get the buffer value used in the market
    /// @return buffer The buffer value in WAD (1e18) where 1e18 = 100%
    function buffer() external view returns (uint256);

    /// @notice Get the out-of-the-money half value used in the market
    /// @return otmHalf The out-of-the-money half value in WAD (1e18) where 1e18 = 100%
    function otmHalf() external view returns (uint256);

    /// @notice Get the warm-up period used in the market
    /// @return warmUpPeriod The warm-up period in seconds
    function warmUpPeriod() external view returns (uint256);

    /// @notice Get details of a specific position by its ID
    /// @param positionId_ The ID of the position to retrieve
    /// @return position The position details
    function positions(uint256 positionId_) external view returns (PositionLib.Position memory);

    /// @notice Preview the flow rate for a given notional and delta
    /// @param notional_ The notional amount
    /// @param delta_ The delta value in WAD (1e18) where 1e18 = 100%
    /// @return flowRate The previewed flow rate
    function previewFlowRate(uint256 notional_, uint256 delta_) external view returns (int96);

    /// @notice Preview the payout for a given position ID
    /// @param positionId_ The ID of the position
    /// @return payout The previewed payout amount
    function previewPayout(uint256 positionId_) external view returns (uint256);
}
