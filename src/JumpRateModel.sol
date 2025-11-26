// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";

/// @title JumpRateModel
/// @author Lora Finance
/// @notice A jump rate model implementing a two-segment interest rate curve
contract JumpRateModel is IRateModel {
    uint256 public immutable BASE_PER_SECOND;
    uint256 public immutable SLOPER_1_PER_SECOND;
    uint256 public immutable SLOPE_2_PER_SECOND;
    uint256 public immutable KINK;
    uint256 public immutable MIN_PER_SECOND;
    uint256 public immutable MAX_PER_SECOND;

    error InvalidRateModelParameters();

    constructor(
        uint256 _basePerSecond,
        uint256 _sloper1PerSecond,
        uint256 _slope2PerSec,
        uint256 _kink,
        uint256 _minPerSec,
        uint256 _maxPerSec
    ) {
        if (
            _minPerSec > _basePerSecond || _maxPerSec < _basePerSecond || _kink > FixedPointMathLib.WAD
                || _minPerSec > FixedPointMathLib.WAD || _maxPerSec > FixedPointMathLib.WAD
                || _basePerSecond > FixedPointMathLib.WAD || _sloper1PerSecond > FixedPointMathLib.WAD
                || _slope2PerSec > FixedPointMathLib.WAD
        ) {
            revert InvalidRateModelParameters();
        }

        BASE_PER_SECOND = _basePerSecond;
        SLOPER_1_PER_SECOND = _sloper1PerSecond;
        SLOPE_2_PER_SECOND = _slope2PerSec;
        KINK = _kink;
        MIN_PER_SECOND = _minPerSec;
        MAX_PER_SECOND = _maxPerSec;
    }

    /// @inheritdoc IRateModel
    function getRatePerSecond(uint256 utilization_) public view returns (uint256) {
        uint256 rate = 0;
        if (utilization_ < KINK) {
            rate = BASE_PER_SECOND + FixedPointMathLib.mulWad(utilization_, SLOPER_1_PER_SECOND);
        } else {
            uint256 normalRate = BASE_PER_SECOND + FixedPointMathLib.mulWad(KINK, SLOPER_1_PER_SECOND);
            uint256 excessUtil = utilization_ - KINK;
            rate = normalRate + FixedPointMathLib.mulWad(excessUtil, SLOPE_2_PER_SECOND);
        }

        if (rate < MIN_PER_SECOND) {
            return MIN_PER_SECOND;
        } else if (rate > MAX_PER_SECOND) {
            return MAX_PER_SECOND;
        } else {
            return rate;
        }
    }
}
