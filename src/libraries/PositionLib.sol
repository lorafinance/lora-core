// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";

/// @title PositionLib
/// @author Lora Finance
/// @notice Library for managing positions and quoting flow rates for Lora
library PositionLib {
    int96 constant FLOW_RATE_OVERFLOW_SENTINEL = -1;

    bytes4 constant POSITION_OPEN_STATE_TAG = bytes4(keccak256("Lora.Position.open"));
    bytes4 constant POSITION_CLOSED_STATE_TAG = bytes4(keccak256("Lora.Position.closed"));
    bytes4 constant POSITION_LIQUIDATED_STATE_TAG = bytes4(keccak256("Lora.Position.liquidated"));

    struct Position {
        address owner;
        uint256 notional;
        uint256 openedAt;
        uint256 strikePrice;
        int96 flowRate;
        bytes4 state;
    }

    struct MarketSnapshot {
        IRateModel rateModel;
        uint256 lockedNotional;
        uint256 poolAssets;
        uint256 buffer;
        uint256 otmHalf;
        uint256 warmUpPeriod;
    }

    /// @notice Quote the flow rate for a given notional and delta based on the current market snapshot
    /// @param snapshot_ The current market snapshot
    /// @param notional_ The desired notional amount
    /// @param delta_ The user's delta in WAD (1e18)
    /// @return flowRate The quoted flow rate in underlying asset per second
    function quoteFlowRate(MarketSnapshot memory snapshot_, uint256 notional_, uint256 delta_)
        internal
        view
        returns (int96)
    {
        if (notional_ == 0) {
            return 0;
        }

        uint256 buffer = FixedPointMathLib.mulWad(snapshot_.poolAssets, snapshot_.buffer);
        uint256 assetCap = snapshot_.poolAssets > snapshot_.lockedNotional + buffer
            ? snapshot_.poolAssets - snapshot_.lockedNotional - buffer
            : 0;

        if (assetCap == 0 || notional_ > assetCap) return 0;

        uint256 utilization = snapshot_.poolAssets == 0
            ? 0
            : FixedPointMathLib.divWad(snapshot_.lockedNotional + notional_, snapshot_.poolAssets);

        uint256 baseRate = snapshot_.rateModel.getRatePerSecond(utilization);
        uint256 denominator = snapshot_.otmHalf + delta_;
        uint256 otmDiscountMultiplier =
            denominator == 0 ? FixedPointMathLib.WAD : FixedPointMathLib.divWad(snapshot_.otmHalf, denominator);
        uint256 effectiveRate = FixedPointMathLib.mulWad(baseRate, otmDiscountMultiplier);
        uint256 flowRate = FixedPointMathLib.mulWad(notional_, effectiveRate);

        unchecked {
            if (flowRate == 0) {
                return 0;
            }

            // from Solady [SafeCastLib.sol](https://github.com/Vectorized/solady/blob/73f13dd1483707ef6b4d16cb0543570b7e1715a8/src/utils/SafeCastLib.sol#L529)
            if (flowRate >= 1 << 95) {
                return FLOW_RATE_OVERFLOW_SENTINEL;
            }

            // casting to 'int256' is safe because [flowRate is checked to be less than 2**95 above]
            // forge-lint: disable-next-line(unsafe-typecast)
            return int96(int256(flowRate));
        }
    }

    /// @notice Calculate the payout for a given position based on the current price
    /// @param snapshot_ The current market snapshot
    /// @param position_ The position to calculate the payout for
    /// @param currentPrice_ The current price of the underlying asset
    /// @param priceDecimals_ The number of decimals the price oracle uses
    /// @return payout The payout amount in underlying asset
    function calculatePayout(
        MarketSnapshot memory snapshot_,
        Position memory position_,
        uint256 currentPrice_,
        uint8 priceDecimals_
    ) internal view returns (uint256) {
        if (currentPrice_ == 0 || currentPrice_ <= position_.strikePrice) return 0;

        uint256 spot = currentPrice_;
        uint256 strike = position_.strikePrice;

        if (priceDecimals_ != 18) {
            if (priceDecimals_ < 18) {
                unchecked {
                    uint256 up = 10 ** uint256(18 - priceDecimals_);
                    spot *= up;
                    strike *= up;
                }
            } else {
                uint256 down = 10 ** uint256(priceDecimals_ - 18);
                spot /= down;
                strike /= down;
            }
        }

        uint256 oneMinusStrikeOverSpot = FixedPointMathLib.WAD - FixedPointMathLib.divWad(strike, spot);
        uint256 payout = FixedPointMathLib.mulWad(position_.notional, oneMinusStrikeOverSpot);
        uint256 timeElapsed = block.timestamp - position_.openedAt;
        uint256 payoutScaleFactor = timeElapsed >= snapshot_.warmUpPeriod || snapshot_.warmUpPeriod == 0
            ? FixedPointMathLib.WAD
            : FixedPointMathLib.divWad(timeElapsed, snapshot_.warmUpPeriod);
        uint256 scaledPayout = FixedPointMathLib.mulWad(payout, payoutScaleFactor);

        return scaledPayout;
    }
}
