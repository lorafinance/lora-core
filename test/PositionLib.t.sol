// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {PositionLib} from "src/libraries/PositionLib.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {JumpRateModel} from "src/JumpRateModel.sol";

contract PositionLibTest is Test {
    IRateModel rateModel;
    PositionLib.MarketSnapshot mockSnapshot;

    function setUp() public {
        vm.warp(1_000_000);

        uint256 baseRate = 1e16;
        JumpRateModel jumpRateModel = new JumpRateModel({
            _basePerSecond: baseRate,
            _sloper1PerSecond: 0,
            _slope2PerSec: 0,
            _kink: 0.8e18,
            _minPerSec: baseRate,
            _maxPerSec: baseRate
        });
        rateModel = IRateModel(address(jumpRateModel));

        mockSnapshot = PositionLib.MarketSnapshot({
            rateModel: IRateModel(address(rateModel)),
            lockedNotional: 0,
            poolAssets: 1_000_000e18,
            buffer: 0.1e18,
            otmHalf: 500e18,
            warmUpPeriod: 15 minutes
        });
    }

    function testQuoteFlowRate_Basic_IncludesOTMDiscount() public view {
        uint256 notional = 10_000e18;
        uint256 delta = 0.1e18;

        int96 flow = PositionLib.quoteFlowRate(mockSnapshot, notional, delta);

        uint256 u = FixedPointMathLib.divWad(mockSnapshot.lockedNotional + notional, mockSnapshot.poolAssets);
        uint256 rBase = rateModel.getRatePerSecond(u);
        uint256 m = FixedPointMathLib.divWad(mockSnapshot.otmHalf, mockSnapshot.otmHalf + delta);
        uint256 rEff = FixedPointMathLib.mulWad(rBase, m);
        uint256 expected = FixedPointMathLib.mulWad(notional, rEff);

        assertEq(uint256(uint96(flow)), expected);
    }

    function testQuoteFlowRate_ZeroNotional_ReturnsZero() public view {
        int96 flow = PositionLib.quoteFlowRate(mockSnapshot, 0, 0);
        assertEq(flow, int96(0));
    }

    function testQuoteFlowRate_OverCap_ReturnsZero() public view {
        uint256 cap = mockSnapshot.poolAssets - FixedPointMathLib.mulWad(mockSnapshot.poolAssets, mockSnapshot.buffer);
        assertEq(cap, 900_000e18);

        int96 flow = PositionLib.quoteFlowRate(mockSnapshot, cap + 1, 0);
        assertEq(flow, int96(0));
    }

    function testQuoteFlowRate_BufferEnforced_ReturnsZeroWhenNoHeadroom() public {
        mockSnapshot.lockedNotional = 900_000e18;
        int96 flow = PositionLib.quoteFlowRate(mockSnapshot, 1e18, 0);
        assertEq(flow, int96(0));
    }

    function testQuoteFlowRate_OTMDiscount_Monotonic() public view {
        uint256 notional = 10_000e18;

        int96 flowAtm = PositionLib.quoteFlowRate(mockSnapshot, notional, 0);
        int96 flowOtm = PositionLib.quoteFlowRate(mockSnapshot, notional, 0.2e18);

        assertLt(uint256(uint96(flowOtm)), uint256(uint96(flowAtm)));
    }

    function testCalculatePayout_Basic() public view {
        PositionLib.Position memory p = PositionLib.Position({
            owner: address(this),
            notional: 100e18,
            openedAt: block.timestamp - mockSnapshot.warmUpPeriod,
            closedAt: 0,
            strikePrice: 2000e18,
            flowRate: int96(0),
            profit: 0,
            state: PositionLib.POSITION_OPEN_STATE_TAG
        });

        uint256 spot = 2500e18;
        uint256 payout = PositionLib.calculatePayout(mockSnapshot, p, spot, 18);

        assertEq(payout, 20e18);
    }

    function testCalculatePayout_RescalesOracleDecimals() public view {
        PositionLib.Position memory p = PositionLib.Position({
            owner: address(this),
            notional: 50e18,
            openedAt: block.timestamp - mockSnapshot.warmUpPeriod,
            closedAt: 0,
            strikePrice: 2000e8,
            flowRate: int96(0),
            profit: 0,
            state: PositionLib.POSITION_OPEN_STATE_TAG
        });

        uint256 spot8 = 2500 * 1e8;
        uint256 payout = PositionLib.calculatePayout(mockSnapshot, p, spot8, 8);

        assertEq(payout, 10e18);
    }

    function testCalculatePayout_WarmupScaling() public view {
        uint256 halfWarmup = mockSnapshot.warmUpPeriod / 2;

        PositionLib.Position memory p = PositionLib.Position({
            owner: address(this),
            notional: 100e18,
            openedAt: block.timestamp - halfWarmup,
            closedAt: 0,
            strikePrice: 2000e18,
            flowRate: int96(0),
            profit: 0,
            state: PositionLib.POSITION_OPEN_STATE_TAG
        });

        uint256 spot = 2500e18;
        uint256 payout = PositionLib.calculatePayout(mockSnapshot, p, spot, 18);

        assertEq(payout, 10e18);
    }
}
