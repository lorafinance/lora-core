// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {ISuperfluid, ISuperToken, IERC20Metadata} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {ISuperApp} from "superfluid/interfaces/superfluid/ISuperApp.sol";
import {SuperTokenV1Library} from "superfluid/apps/SuperTokenV1Library.sol";
import {PositionLib} from "src/libraries/PositionLib.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {IMarketGuard} from "src/interfaces/IMarketGuard.sol";
import {IMarketFeePolicy} from "src/interfaces/IMarketFeePolicy.sol";
import {Market} from "src/Market.sol";
import {MarketFactory} from "src/MarketFactory.sol";
import {JumpRateModel} from "src/JumpRateModel.sol";
import {SentinelOracle} from "src/SentinelOracle.sol";
import {Faucet} from "src/testnet/Faucet.sol";
import {MockAggregatorV3Interface} from "test/mocks/AggregatorV3Interface.sol";
import {Streamer} from "test/helpers/Streamer.sol";
import {console} from "forge-std/console.sol";

contract MarketTest is Test {
    using LibClone for address;
    using SuperTokenV1Library for ISuperToken;

    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CHARLIE = address(0xC11A711E);
    address constant OWEN = address(0x0E11);

    // APR → per-second WAD = APR / 31,536,000 * 1e18
    uint256 constant JRM_BASE_PER_SECOND = 6_341_958_396; //  ~20% APR
    uint256 constant JRM_SLOPER_1_PER_SECOND = 7_927_447_995; //  +25% APR across 0 → kink
    uint256 constant JRM_SLOPE_2_PER_SECOND = 95_129_375_951; //  +300% APR across kink → 1
    uint256 constant JRM_MIN_PER_SECOND = 1_585_489_599; //  ~5% APR floor
    uint256 constant JRM_MAX_PER_SECOND = 63_419_583_967; //  ~200% APR cap
    uint256 constant JRM_KINK = 0.8e18; //  80% utilization

    // assuming asset has 18 decimals
    uint256 constant MARKET_BUFFER = 0.1e18; // 10% buffer; protects solvency on withdrawals
    uint256 constant MARKET_CAP = 1000000e18; // Market cap for deposits
    uint256 constant MARKET_OTM_HALF = 0.35e18; // OTM discount h: m(δ) = h / (h + δ)
    uint256 constant MARKET_WARM_UP_PERIOD = 15 minutes;

    MockAggregatorV3Interface mockFeed;

    ISuperfluid superfluidHost;
    ISuperToken superToken;

    Faucet faucet;
    Market market;
    JumpRateModel rateModel;
    SentinelOracle priceOracle;

    Streamer streamer;

    uint256 initialPrice = 2000e18;

    modifier assertNotJailed() {
        _;
        assertFalse(superfluidHost.isAppJailed(ISuperApp(address(market))), "you are fucked!");
    }

    function setUp() public {
        superfluidHost = ISuperfluid(vm.envAddress("SUPERFLUID_TEST_HOST_ADDRESS"));
        vm.createSelectFork(vm.envString("SUPERFLUID_TEST_RPC_URL"));

        faucet = new Faucet("Test Token", "TTK", 18, 1 ether, 1 days, address(superfluidHost), OWEN);
        superToken = ISuperToken(faucet.SUPER_TOKEN());

        mockFeed = new MockAggregatorV3Interface(int256(initialPrice), 18);
        priceOracle = new SentinelOracle(address(mockFeed), 1 hours);
        rateModel = new JumpRateModel(
            JRM_BASE_PER_SECOND,
            JRM_SLOPER_1_PER_SECOND,
            JRM_SLOPE_2_PER_SECOND,
            JRM_KINK,
            JRM_MIN_PER_SECOND,
            JRM_MAX_PER_SECOND
        );

        address marketImplementation = address(new Market(address(superfluidHost)));
        MarketFactory marketFactory = new MarketFactory(marketImplementation, OWEN);

        bytes memory immutableArgs = abi.encode(address(superToken));
        bytes memory initializerData = abi.encodeCall(
            Market.initialize,
            (
                address(rateModel),
                address(priceOracle),
                MARKET_BUFFER,
                MARKET_CAP,
                MARKET_OTM_HALF,
                MARKET_WARM_UP_PERIOD,
                0,
                0,
                OWEN
            )
        );

        vm.prank(OWEN);
        market = Market(marketFactory.deployMarket(immutableArgs, initializerData));

        streamer = new Streamer(superToken);

        vm.startPrank(OWEN);
        faucet.superMint(ALICE, 1000e18);
        faucet.superMint(BOB, 1000e18);
        faucet.superMint(address(streamer), 1000e18);
        vm.stopPrank();

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.startPrank(BOB);
        superToken.setMaxFlowPermissions(address(market));
        vm.stopPrank();
    }

    function testMarketInitialization() public view assertNotJailed {
        assertEq(market.asset(), address(superToken));
        assertEq(address(market.rateModel()), address(rateModel));
        assertEq(address(market.priceOracle()), address(priceOracle));
        assertEq(market.buffer(), MARKET_BUFFER);
        assertEq(market.cap(), MARKET_CAP);
        assertEq(market.otmHalf(), MARKET_OTM_HALF);
        assertEq(market.owner(), OWEN);
        assertFalse(market.isLpDepositPaused());
        assertFalse(market.isLpWithdrawPaused());
        assertFalse(market.isPositionOpenPaused());
    }

    function testMarketInitialization_Reverts_AlreadyInitialized() public {
        vm.expectRevert();
        market.initialize(
            address(rateModel),
            address(priceOracle),
            MARKET_BUFFER,
            MARKET_CAP,
            MARKET_OTM_HALF,
            MARKET_WARM_UP_PERIOD,
            0,
            0,
            OWEN
        );
    }

    function testMarketImplementation_Reverts_Initialize() public {
        Market marketImpl = new Market(address(superfluidHost));

        vm.expectRevert();
        marketImpl.initialize(
            address(rateModel),
            address(priceOracle),
            MARKET_BUFFER,
            MARKET_CAP,
            MARKET_OTM_HALF,
            MARKET_WARM_UP_PERIOD,
            0,
            0,
            OWEN
        );
    }

    function testDeposit() public assertNotJailed {
        vm.startPrank(ALICE);
        market.deposit(500e18, ALICE);
        vm.stopPrank();

        assertEq(market.totalAssets(), 500e18);
        assertEq(market.balanceOf(ALICE), 500e18);
    }

    function testDeposit_WithoutApproval() public assertNotJailed {
        vm.startPrank(CHARLIE);
        vm.expectRevert();
        market.deposit(500e18, CHARLIE);
        vm.stopPrank();
    }

    function testDeposit_ExceedsCap() public assertNotJailed {
        vm.prank(OWEN);
        faucet.superMint(ALICE, 2 * MARKET_CAP);

        vm.startPrank(ALICE);
        market.deposit(MARKET_CAP, ALICE);

        vm.expectRevert(abi.encodeWithSelector(IMarket.CapExceeded.selector, 1e18, MARKET_CAP + 1e18, MARKET_CAP));
        market.deposit(1e18, ALICE);
        vm.stopPrank();
    }

    function testWithdraw() public assertNotJailed {
        vm.startPrank(ALICE);
        market.deposit(500e18, ALICE);
        market.withdraw(200e18, ALICE, ALICE);
        vm.stopPrank();

        assertEq(market.totalAssets(), 300e18);
        assertEq(market.balanceOf(ALICE), 300e18);
    }

    function testWithdraw_Reverts_InsufficientBalance() public assertNotJailed {
        vm.startPrank(ALICE);
        market.deposit(500e18, ALICE);
        vm.expectRevert();
        market.withdraw(600e18, ALICE, ALICE);
        vm.stopPrank();
    }

    function testWithdraw_WithoutDeposit() public assertNotJailed {
        vm.startPrank(ALICE);
        market.deposit(500e18, ALICE);
        vm.stopPrank();

        vm.startPrank(CHARLIE);
        vm.expectRevert();
        market.withdraw(200e18, CHARLIE, CHARLIE);
        vm.stopPrank();
    }

    function testOpenPosition() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        uint256 notional = 10e18;
        uint256 delta = 0;

        int96 previewFlowRate = market.previewFlowRate(notional, delta);

        vm.startPrank(BOB);
        vm.expectEmit(address(market));
        emit IMarket.PositionOpened(1, BOB, notional, delta, uint256(initialPrice), previewFlowRate, block.timestamp);
        uint256 positionId = market.openPosition(notional, delta);
        vm.stopPrank();

        assertEq(positionId, 1);

        PositionLib.Position memory position = market.positions(positionId);
        int96 toMarketFlowRate = superToken.getFlowRate(BOB, address(market));
        int96 fromMarketFlowRate = superToken.getFlowRate(address(market), BOB);

        assertEq(position.owner, BOB);
        assertEq(position.notional, notional);
        assertEq(position.strikePrice, uint256(initialPrice));
        assertEq(position.flowRate, previewFlowRate);
        assertEq(position.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(position.openedAt, block.timestamp);
        assertEq(market.lockedNotional(), notional);
        assertEq(market.totalPositions(), 1);
        assertEq(toMarketFlowRate, previewFlowRate);
        assertEq(fromMarketFlowRate, 0);
    }

    function testOpenTwoPosition() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        uint256 notional1 = 10e18;
        uint256 delta1 = 0;

        uint256 notional2 = 20e18;
        uint256 delta2 = 0.1e18;

        vm.startPrank(BOB);
        int96 previewFlowRate1 = market.previewFlowRate(notional1, delta1);
        vm.expectEmit(address(market));
        emit IMarket.PositionOpened(1, BOB, notional1, delta1, initialPrice, previewFlowRate1, block.timestamp);
        uint256 positionId1 = market.openPosition(notional1, delta1);

        int96 previewFlowRate2 = market.previewFlowRate(notional2, delta2);
        vm.expectEmit(address(market));
        emit IMarket.PositionOpened(
            2,
            BOB,
            notional2,
            delta2,
            initialPrice + FixedPointMathLib.mulWad(initialPrice, delta2),
            previewFlowRate2,
            block.timestamp
        );
        uint256 positionId2 = market.openPosition(notional2, delta2);
        vm.stopPrank();

        assertEq(positionId1, 1);
        assertEq(positionId2, 2);
        assertEq(market.lockedNotional(), notional1 + notional2);
        assertEq(market.totalPositions(), 2);

        PositionLib.Position memory position1 = market.positions(positionId1);
        PositionLib.Position memory position2 = market.positions(positionId2);
        int96 flowRate = superToken.getFlowRate(BOB, address(market));

        assertEq(position1.notional, notional1);
        assertEq(position2.notional, notional2);
        assertEq(flowRate, previewFlowRate1 + previewFlowRate2);
        assertEq(position1.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(position2.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(position1.openedAt, block.timestamp);
        assertEq(position2.openedAt, block.timestamp);
        assertEq(position1.flowRate, previewFlowRate1);
        assertEq(position2.flowRate, previewFlowRate2);
        assertEq(position1.strikePrice, initialPrice);
        assertEq(position2.strikePrice, initialPrice + FixedPointMathLib.mulWad(initialPrice, delta2));
        assertEq(position1.owner, BOB);
        assertEq(position2.owner, BOB);
    }

    function testOpenPosition_Reverts_InsufficientLiquidity() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(10e18, ALICE);

        vm.startPrank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarket.InsufficientLiquidity.selector, 20e18, 10e18 - FixedPointMathLib.mulWad(10e18, MARKET_BUFFER)
            )
        );
        market.openPosition(20e18, 0);
        vm.stopPrank();

        assertEq(market.totalPositions(), 0);
        assertEq(market.lockedNotional(), 0);
    }

    function testOpenPosition_Reverts_NotionalZero() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IMarket.NotionalZero.selector));
        market.openPosition(0, 0);
        vm.stopPrank();

        assertEq(market.totalPositions(), 0);
        assertEq(market.lockedNotional(), 0);
    }

    function testOpenPosition_Reverts_FlowRateZero() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IMarket.FlowRateZero.selector));
        market.openPosition(900e18, 100000000000000000e18);
        vm.stopPrank();

        assertEq(market.totalPositions(), 0);
        assertEq(market.lockedNotional(), 0);
    }

    function testPreviewFlowRate_Monotonicity() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        uint256 notional = 10e18;

        int96 flowRateAtm = market.previewFlowRate(notional, 0);
        int96 flowRateOtm = market.previewFlowRate(notional, 0.2e18);

        assertLt(uint256(uint96(flowRateOtm)), uint256(uint96(flowRateAtm)));
    }

    function testCreateStreamToMarket_Reverts_InvalidSuperToken() public assertNotJailed {
        Faucet anotherFaucet =
            new Faucet("Another Test Token", "ATT", 18, 1 ether, 1 days, address(superfluidHost), OWEN);
        ISuperToken anotherSuperToken = ISuperToken(anotherFaucet.SUPER_TOKEN());

        vm.prank(OWEN);
        anotherFaucet.superMint(address(streamer), 1000e18);

        Streamer anotherStreamer = new Streamer(anotherSuperToken);
        int96 flowRate = int96(int256(uint256(1e14) / 7 days));

        vm.expectRevert(
            abi.encodeWithSelector(IMarket.InvalidSuperToken.selector, address(anotherSuperToken), address(superToken))
        );
        anotherStreamer.createStream(flowRate, address(market));
    }

    function testCreateStreamToMarket_Reverts_FlowAuthorizedByMarketOnly() public assertNotJailed {
        int96 flowRate = int96(int256(uint256(1e14) / 7 days));

        vm.expectRevert(
            abi.encodeWithSelector(IMarket.FlowAuthorizedByMarketOnly.selector, address(streamer), address(market))
        );
        streamer.createStream(flowRate, address(market));
    }

    function testUpdateStreamToMarket_Reverts_FlowAuthorizedByMarketOnly() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(address(streamer));
        superToken.setMaxFlowPermissions(address(market));
        uint256 positionId = market.openPosition(100e18, 0);
        vm.stopPrank();

        PositionLib.Position memory position = market.positions(positionId);
        int96 flowRate = int96(int256(uint256(1e14) / 7 days));

        vm.expectRevert(
            abi.encodeWithSelector(IMarket.FlowAuthorizedByMarketOnly.selector, address(streamer), address(market))
        );
        streamer.updateStream(position.flowRate + flowRate, address(market));
    }

    function testClosePosition() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        uint256 positionId = market.openPosition(10e18, 0);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedPayout = market.previewPayout(positionId);

        vm.expectEmit(address(market));
        emit IMarket.PositionClosed(positionId, BOB, expectedPayout, block.timestamp);
        uint256 payout = market.closePosition(positionId);
        vm.stopPrank();

        PositionLib.Position memory position = market.positions(positionId);
        int96 toMarketFlowRate = superToken.getFlowRate(BOB, address(market));
        int96 fromMarketFlowRate = superToken.getFlowRate(address(market), BOB);

        assertEq(position.state, PositionLib.POSITION_CLOSED_STATE_TAG);
        assertEq(market.lockedNotional(), 0);
        assertEq(payout, expectedPayout);
        assertEq(toMarketFlowRate, 0);
        assertEq(fromMarketFlowRate, 0);
    }

    function testOpenTwoCloseOnePosition() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        uint256 positionId1 = market.openPosition(10e18, 0);
        uint256 positionId2 = market.openPosition(20e18, 0);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedPayout1 = market.previewPayout(positionId1);

        vm.expectEmit(address(market));
        emit IMarket.PositionClosed(positionId1, BOB, expectedPayout1, block.timestamp);
        uint256 payout1 = market.closePosition(positionId1);
        vm.stopPrank();

        PositionLib.Position memory position1 = market.positions(positionId1);
        PositionLib.Position memory position2 = market.positions(positionId2);
        int96 toMarketFlowRate = superToken.getFlowRate(BOB, address(market));
        int96 fromMarketFlowRate = superToken.getFlowRate(address(market), BOB);

        assertEq(position1.state, PositionLib.POSITION_CLOSED_STATE_TAG);
        assertEq(position2.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(market.lockedNotional(), 20e18);
        assertEq(payout1, expectedPayout1);
        assertEq(toMarketFlowRate, position2.flowRate);
        assertEq(fromMarketFlowRate, 0);
    }

    function testOpenAndCloseTwoPositions() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        uint256 positionId1 = market.openPosition(10e18, 0);
        uint256 positionId2 = market.openPosition(20e18, 0);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedPayout1 = market.previewPayout(positionId1);
        uint256 expectedPayout2 = market.previewPayout(positionId2);

        vm.expectEmit(address(market));
        emit IMarket.PositionClosed(positionId1, BOB, expectedPayout1, block.timestamp);
        uint256 payout1 = market.closePosition(positionId1);

        vm.expectEmit(address(market));
        emit IMarket.PositionClosed(positionId2, BOB, expectedPayout2, block.timestamp);
        uint256 payout2 = market.closePosition(positionId2);
        vm.stopPrank();

        PositionLib.Position memory position1 = market.positions(positionId1);
        PositionLib.Position memory position2 = market.positions(positionId2);
        int96 toMarketFlowRate = superToken.getFlowRate(BOB, address(market));
        int96 fromMarketFlowRate = superToken.getFlowRate(address(market), BOB);

        assertEq(position1.state, PositionLib.POSITION_CLOSED_STATE_TAG);
        assertEq(position2.state, PositionLib.POSITION_CLOSED_STATE_TAG);
        assertEq(market.lockedNotional(), 0);
        assertEq(payout1, expectedPayout1);
        assertEq(payout2, expectedPayout2);
        assertEq(toMarketFlowRate, 0);
        assertEq(fromMarketFlowRate, 0);
    }

    function testClosePosition_Reverts_PositionNotFound() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IMarket.PositionNotFound.selector, 1));
        market.closePosition(1);
        vm.stopPrank();
    }

    function testClosePosition_Reverts_OnlyPositionOwner() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        uint256 positionId = market.openPosition(10e18, 0);
        vm.stopPrank();

        vm.startPrank(CHARLIE);
        vm.expectRevert(abi.encodeWithSelector(IMarket.OnlyPositionOwner.selector, CHARLIE, BOB));
        market.closePosition(positionId);
        vm.stopPrank();
    }

    function testClosePosition_Reverts_PositionNotOpen() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(BOB);
        uint256 positionId = market.openPosition(10e18, 0);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        market.closePosition(positionId);

        vm.expectRevert(abi.encodeWithSelector(IMarket.PositionNotOpen.selector, positionId));
        market.closePosition(positionId);
        vm.stopPrank();
    }

    function testDeleteStreamLiquidatesUser() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(address(streamer));
        superToken.setMaxFlowPermissions(address(market));
        uint256 positionId = market.openPosition(100e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(address(market));
        emit IMarket.UserLiquidated(address(streamer), block.timestamp);
        streamer.deleteStream(address(streamer), address(market));

        PositionLib.Position memory position = market.positions(positionId);
        assertEq(position.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
    }

    function testDeleteStreamMultiplePositionsLiquidated() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(address(streamer));
        superToken.setMaxFlowPermissions(address(market));
        uint256 positionId1 = market.openPosition(100e18, 0);
        uint256 positionId2 = market.openPosition(200e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(address(market));
        emit IMarket.UserLiquidated(address(streamer), block.timestamp);
        streamer.deleteStream(address(streamer), address(market));

        PositionLib.Position memory position1 = market.positions(positionId1);
        PositionLib.Position memory position2 = market.positions(positionId2);
        assertEq(position1.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
        assertEq(position2.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
    }

    function testLiquidateAnotherUser() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        int96 flowRate = market.previewFlowRate(100e18, 0);
        uint256 streamDuration = 1 hours;
        uint256 bufferAmount = superToken.getBufferAmountByFlowRate(flowRate);

        vm.startPrank(OWEN);
        faucet.superMint(CHARLIE, (uint256(uint96(flowRate)) * streamDuration) + bufferAmount);

        vm.startPrank(CHARLIE);
        superToken.setMaxFlowPermissions(address(market));

        uint256 positionId = market.openPosition(100e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + streamDuration + 1);

        vm.expectEmit(address(market));
        emit IMarket.UserLiquidated(CHARLIE, block.timestamp);
        streamer.deleteStream(CHARLIE, address(market));

        PositionLib.Position memory position = market.positions(positionId);
        assertEq(position.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
        assertEq(position.owner, CHARLIE);
        assertEq(market.lockedNotional(), 0);
    }

    function testLiquidateOneUserWithMultipleUsersPositions() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.prank(BOB);
        uint256 positionIdBob = market.openPosition(100e18, 0);

        int96 flowRateCharlie = market.previewFlowRate(200e18, 0);
        uint256 streamDuration = 1 hours;
        uint256 bufferAmountCharlie = superToken.getBufferAmountByFlowRate(flowRateCharlie);

        vm.startPrank(OWEN);
        faucet.superMint(CHARLIE, (uint256(uint96(flowRateCharlie)) * streamDuration) + bufferAmountCharlie);

        vm.startPrank(CHARLIE);
        superToken.setMaxFlowPermissions(address(market));
        uint256 positionIdCharlie = market.openPosition(200e18, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + streamDuration + 1);

        vm.expectEmit(address(market));
        emit IMarket.UserLiquidated(CHARLIE, block.timestamp);
        streamer.deleteStream(CHARLIE, address(market));

        PositionLib.Position memory positionBob = market.positions(positionIdBob);
        PositionLib.Position memory positionCharlie = market.positions(positionIdCharlie);

        assertEq(positionBob.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(positionCharlie.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
        assertEq(positionBob.owner, BOB);
        assertEq(positionCharlie.owner, CHARLIE);
        assertEq(market.lockedNotional(), 100e18);
    }

    function testLiquidateSelfWithMultiplePositions() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(address(streamer));
        superToken.setMaxFlowPermissions(address(market));
        market.openPosition(100e18, 0);
        market.openPosition(200e18, 0);
        vm.stopPrank();

        vm.prank(BOB);
        market.openPosition(150e18, 0);

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(address(market));
        emit IMarket.UserLiquidated(address(streamer), block.timestamp);
        streamer.deleteStream(address(streamer), address(market));

        PositionLib.Position memory position1 = market.positions(1);
        PositionLib.Position memory position2 = market.positions(2);
        PositionLib.Position memory position3 = market.positions(3);

        assertEq(position1.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
        assertEq(position2.state, PositionLib.POSITION_LIQUIDATED_STATE_TAG);
        assertEq(position3.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(position1.owner, address(streamer));
        assertEq(position2.owner, address(streamer));
        assertEq(position3.owner, BOB);
        assertEq(market.lockedNotional(), 150e18);
    }

    function testStrikeWithHigherDelta() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        uint256 notional = 10e18;
        uint256 delta = 0.2e18;

        vm.startPrank(BOB);
        uint256 positionId = market.openPosition(notional, delta);
        vm.stopPrank();

        PositionLib.Position memory position = market.positions(positionId);
        assertEq(position.strikePrice, initialPrice + FixedPointMathLib.mulWad(initialPrice, delta));
    }

    function testSetRateModel_OnlyOwner() public assertNotJailed {
        JumpRateModel newRateModel = new JumpRateModel(
            JRM_BASE_PER_SECOND,
            JRM_SLOPER_1_PER_SECOND,
            JRM_SLOPE_2_PER_SECOND,
            JRM_KINK,
            JRM_MIN_PER_SECOND,
            JRM_MAX_PER_SECOND
        );

        vm.prank(OWEN);
        market.setRateModel(address(newRateModel));

        assertEq(address(market.rateModel()), address(newRateModel));
    }

    function testSetRateModel_Reverts_NotOwner() public assertNotJailed {
        JumpRateModel newRateModel = new JumpRateModel(
            JRM_BASE_PER_SECOND,
            JRM_SLOPER_1_PER_SECOND,
            JRM_SLOPE_2_PER_SECOND,
            JRM_KINK,
            JRM_MIN_PER_SECOND,
            JRM_MAX_PER_SECOND
        );

        vm.prank(ALICE);
        vm.expectRevert();
        market.setRateModel(address(newRateModel));
    }

    function testSetPriceOracle_OnlyOwner() public assertNotJailed {
        SentinelOracle newPriceOracle = new SentinelOracle(address(mockFeed), 1 hours);

        vm.prank(OWEN);
        market.setPriceOracle(address(newPriceOracle));

        assertEq(address(market.priceOracle()), address(newPriceOracle));
    }

    function testSetPriceOracle_Reverts_NotOwner() public assertNotJailed {
        SentinelOracle newPriceOracle = new SentinelOracle(address(mockFeed), 1 hours);

        vm.prank(ALICE);
        vm.expectRevert();
        market.setPriceOracle(address(newPriceOracle));
    }

    function testSetOtmHalf() public assertNotJailed {
        uint256 newOtmHalf = 0.5e18;

        vm.prank(OWEN);
        market.setOtmHalf(newOtmHalf);

        assertEq(market.otmHalf(), newOtmHalf);
    }

    function testSetOtmHalf_Reverts_NotOwner() public assertNotJailed {
        uint256 newOtmHalf = 0.5e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setOtmHalf(newOtmHalf);
    }

    function testSetBuffer() public assertNotJailed {
        uint256 newBuffer = 0.2e18;

        vm.prank(OWEN);
        market.setBuffer(newBuffer);
        assertEq(market.buffer(), newBuffer);
    }

    function testSetBuffer_Reverts_NotOwner() public assertNotJailed {
        uint256 newBuffer = 0.2e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setBuffer(newBuffer);
    }

    function testSetCap() public assertNotJailed {
        uint256 newCap = 2_000_000e18;

        vm.prank(OWEN);
        market.setCap(newCap);
        assertEq(market.cap(), newCap);
    }

    function testSetCap_Reverts_NotOwner() public assertNotJailed {
        uint256 newCap = 2_000_000e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setCap(newCap);
    }

    function testSetOpenPositionFee() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(OWEN);
        market.setOpenPositionFee(newFee);
        assertEq(market.openPositionFee(), newFee);
    }

    function testSetOpenPositionFee_Reverts_NotOwner() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setOpenPositionFee(newFee);
    }

    function testSetOpenPositionFee_Reverts_InvalidFee() public assertNotJailed {
        uint256 newFee = 1.5e18;
        uint256 maxFee = market.MAX_FEE();

        vm.prank(OWEN);
        vm.expectRevert(abi.encodeWithSelector(IMarketFeePolicy.InvalidFee.selector, newFee, maxFee));
        market.setOpenPositionFee(newFee);
    }

    function testSetClosePositionFee() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(OWEN);
        market.setClosePositionFee(newFee);
        assertEq(market.closePositionFee(), newFee);
    }

    function testSetClosePositionFee_Reverts_NotOwner() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setClosePositionFee(newFee);
    }

    function testSetClosePositionFee_Reverts_InvalidFee() public assertNotJailed {
        uint256 newFee = 1.5e18;
        uint256 maxFee = market.MAX_FEE();

        vm.prank(OWEN);
        vm.expectRevert(abi.encodeWithSelector(IMarketFeePolicy.InvalidFee.selector, newFee, maxFee));
        market.setClosePositionFee(newFee);
    }

    function testSetFee() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(OWEN);
        market.setFee(newFee);
        assertEq(market.openPositionFee(), newFee);
        assertEq(market.closePositionFee(), newFee);
    }

    function testSetFee_Reverts_NotOwner() public assertNotJailed {
        uint256 newFee = 0.01e18;

        vm.prank(ALICE);
        vm.expectRevert();
        market.setFee(newFee);
    }

    function testSetFee_Reverts_InvalidFee() public assertNotJailed {
        uint256 newFee = 1.5e18;
        uint256 maxFee = market.MAX_FEE();

        vm.prank(OWEN);
        vm.expectRevert(abi.encodeWithSelector(IMarketFeePolicy.InvalidFee.selector, newFee, maxFee));
        market.setFee(newFee);
    }

    function testMaxWithdrawableNoOpenPositions() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        uint256 maxWithdrawable = market.maxWithdraw(ALICE);

        assertEq(maxWithdrawable, 1000e18 - FixedPointMathLib.mulWad(1000e18, market.buffer()));
    }

    function testMaxWithdrawableWithOpenPosition() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.prank(BOB);
        market.openPosition(200e18, 0);

        uint256 maxWithdrawable = market.maxWithdraw(ALICE);
        uint256 expectedLocked = FixedPointMathLib.mulWad(1000e18, market.buffer()) + market.lockedNotional();

        assertEq(maxWithdrawable, 1000e18 - expectedLocked);
    }

    function testDeposit_Reverts_LpDepositPaused() public assertNotJailed {
        vm.prank(OWEN);
        market.setLpDepositPaused(true);

        vm.expectRevert(IMarketGuard.LpDepositPaused.selector);
        vm.startPrank(ALICE);
        market.deposit(100e18, ALICE);
        vm.stopPrank();
    }

    function testDeposit_Reverts_LpWithdrawPaused() public assertNotJailed {
        vm.prank(OWEN);
        market.setLpWithdrawPaused(true);

        vm.prank(ALICE);
        market.deposit(500e18, ALICE);

        vm.prank(OWEN);
        market.setLpWithdrawPaused(true);

        vm.expectRevert(IMarketGuard.LpWithdrawPaused.selector);
        vm.startPrank(ALICE);
        market.withdraw(100e18, ALICE, ALICE);
        vm.stopPrank();
    }

    function testDeposit_Reverts_PositionOpenPaused() public assertNotJailed {
        vm.prank(OWEN);
        market.setPositionOpenPaused(true);

        vm.prank(ALICE);
        market.deposit(500e18, ALICE);

        vm.prank(BOB);
        vm.expectRevert(IMarketGuard.PositionOpenPaused.selector);
        market.openPosition(100e18, 0);
    }

    function testLpActionsPaused_Reverts_All() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(500e18, ALICE);

        vm.prank(OWEN);
        market.setLpPaused(true);

        vm.prank(ALICE);
        vm.expectRevert(IMarketGuard.LpDepositPaused.selector);
        market.deposit(100e18, ALICE);

        vm.prank(ALICE);
        vm.expectRevert(IMarketGuard.LpWithdrawPaused.selector);
        market.withdraw(100e18, ALICE, ALICE);
    }

    function testPauseAllMarketActions_Reverts_All() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(500e18, ALICE);

        vm.prank(OWEN);
        market.setPaused(true);

        vm.prank(ALICE);
        vm.expectRevert(IMarketGuard.LpDepositPaused.selector);
        market.deposit(100e18, ALICE);

        vm.prank(ALICE);
        vm.expectRevert(IMarketGuard.LpWithdrawPaused.selector);
        market.withdraw(100e18, ALICE, ALICE);

        vm.prank(BOB);
        vm.expectRevert(IMarketGuard.PositionOpenPaused.selector);
        market.openPosition(100e18, 0);
    }

    function testLpDepositPausedEvent() public assertNotJailed {
        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(true);
        market.setLpDepositPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(false);
        market.setLpDepositPaused(false);
    }

    function testLpWithdrawPausedEvent() public assertNotJailed {
        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(true);
        market.setLpWithdrawPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(false);
        market.setLpWithdrawPaused(false);
    }

    function testPositionOpenPausedEvent() public assertNotJailed {
        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.PositionOpenPausedUpdated(true);
        market.setPositionOpenPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.PositionOpenPausedUpdated(false);
        market.setPositionOpenPaused(false);
    }

    function testLpPausedEvent() public assertNotJailed {
        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(true);
        market.setLpPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(true);
        market.setLpPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(false);
        market.setLpPaused(false);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(false);
        market.setLpPaused(false);
    }

    function testPausedEvent() public assertNotJailed {
        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(true);
        market.setPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpDepositPausedUpdated(true);
        market.setPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.PositionOpenPausedUpdated(true);
        market.setPaused(true);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.PositionOpenPausedUpdated(false);
        market.setPaused(false);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(false);
        market.setPaused(false);

        vm.prank(OWEN);
        vm.expectEmit(address(market));
        emit IMarketGuard.LpWithdrawPausedUpdated(false);
        market.setPaused(false);
    }

    function testFuzz_Deposit(uint256 depositAmount_) public assertNotJailed {
        vm.assume(depositAmount_ > 0 && depositAmount_ <= 1_000_000e18);

        vm.prank(OWEN);
        faucet.superMint(ALICE, depositAmount_);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(depositAmount_, ALICE);

        assertEq(market.totalAssets(), depositAmount_);
        assertEq(market.balanceOf(ALICE), depositAmount_);
    }

    function testFuzz_MultipleDeposits(uint256 numberOfDeposits) public assertNotJailed {
        vm.assume(numberOfDeposits > 0 && numberOfDeposits <= 1000);

        uint256 totalDeposited;
        for (uint256 i; i < numberOfDeposits; ++i) {
            uint256 depositAmount = (i + 1) * 1e18;

            vm.prank(OWEN);
            faucet.superMint(ALICE, depositAmount);

            vm.prank(ALICE);
            superToken.approve(address(market), type(uint256).max);

            vm.prank(ALICE);
            market.deposit(depositAmount, ALICE);

            totalDeposited += depositAmount;
        }

        assertEq(market.totalAssets(), totalDeposited);
        assertEq(market.balanceOf(ALICE), totalDeposited);
    }

    function testFuzz_Withdraw(uint256 depositAmount_, uint256 withdrawAmount_) public assertNotJailed {
        vm.assume(depositAmount_ > 0 && depositAmount_ <= 1_000_000e18);
        vm.assume(
            withdrawAmount_ > 0
                && withdrawAmount_ <= depositAmount_ - FixedPointMathLib.mulWad(depositAmount_, market.buffer())
        );

        vm.prank(OWEN);
        faucet.superMint(ALICE, depositAmount_);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(depositAmount_, ALICE);

        vm.prank(ALICE);
        market.withdraw(withdrawAmount_, ALICE, ALICE);

        assertEq(market.totalAssets(), depositAmount_ - withdrawAmount_);
        assertEq(market.balanceOf(ALICE), depositAmount_ - withdrawAmount_);
    }

    function testFuzz_MultipleWithdrawals(uint256 depositAmount_, uint256 numberOfWithdrawals) public assertNotJailed {
        vm.assume(depositAmount_ > 0 && depositAmount_ <= 1_000_000e18);
        vm.assume(numberOfWithdrawals > 0 && numberOfWithdrawals <= 1000);

        vm.prank(OWEN);
        faucet.superMint(ALICE, depositAmount_);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(depositAmount_, ALICE);

        uint256 totalWithdrawn;
        for (uint256 i; i < numberOfWithdrawals; ++i) {
            uint256 withdrawAmount = (i + 1) * 1e18;

            if (
                totalWithdrawn + withdrawAmount
                    > depositAmount_ - FixedPointMathLib.mulWad(depositAmount_, market.buffer())
            ) {
                break;
            }

            vm.prank(ALICE);
            market.withdraw(withdrawAmount, ALICE, ALICE);

            totalWithdrawn += withdrawAmount;
        }

        assertEq(market.totalAssets(), depositAmount_ - totalWithdrawn);
        assertEq(market.balanceOf(ALICE), depositAmount_ - totalWithdrawn);
    }

    function testFuzz_OpenPosition(uint256 notional_, uint256 delta_) public assertNotJailed {
        vm.assume(notional_ > 0.0001e18 && notional_ <= 1000e18);
        vm.assume(delta_ >= 0 && delta_ <= 1e18);

        vm.prank(OWEN);
        faucet.superMint(ALICE, 1_000_000e18);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(1_000_000e18, ALICE);

        int96 expectedFlowRate = market.previewFlowRate(notional_, delta_);

        vm.prank(BOB);
        uint256 positionId = market.openPosition(notional_, delta_);

        PositionLib.Position memory position = market.positions(positionId);

        assertEq(position.owner, BOB);
        assertEq(position.notional, notional_);
        assertEq(position.flowRate, expectedFlowRate);
        assertEq(position.state, PositionLib.POSITION_OPEN_STATE_TAG);
        assertEq(market.lockedNotional(), notional_);
    }

    function testFuzz_OpenMultiplePositions(uint256 notional_, uint256 delta_, uint256 numberOfPositions)
        public
        assertNotJailed
    {
        notional_ = bound(notional_, 0.0001e18 + 1, 1000e18);
        delta_ = bound(delta_, 0, 1e18);
        numberOfPositions = bound(numberOfPositions, 1, 100);

        vm.prank(OWEN);
        faucet.superMint(ALICE, 1_000_000e18);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(1_000_000e18, ALICE);

        uint256 totalNotional;
        for (uint256 i; i < numberOfPositions; ++i) {
            vm.prank(BOB);
            uint256 positionId = market.openPosition(notional_, delta_);

            PositionLib.Position memory position = market.positions(positionId);

            assertEq(position.owner, BOB);
            assertEq(position.notional, notional_);
            assertEq(position.state, PositionLib.POSITION_OPEN_STATE_TAG);

            totalNotional += notional_;
        }

        assertEq(market.lockedNotional(), totalNotional);
    }

    function testFuzz_OpenPosition_Reverts_InsufficientLiquidity(uint256 notional_) public assertNotJailed {
        vm.assume(notional_ > 10e18 && notional_ <= 1000e18);

        vm.prank(OWEN);
        faucet.superMint(ALICE, 10e18);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(10e18, ALICE);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarket.InsufficientLiquidity.selector,
                notional_,
                10e18 - FixedPointMathLib.mulWad(10e18, MARKET_BUFFER)
            )
        );
        market.openPosition(notional_, 0);
    }

    function testFuzz_ClosePosition(uint256 notional_, uint256 delta_, uint256 timeTravel_) public assertNotJailed {
        notional_ = bound(notional_, 0.0001e18 + 1, 1000e18);
        delta_ = bound(delta_, 0, 1e18);
        timeTravel_ = bound(timeTravel_, 1 days, 30 days);

        vm.prank(OWEN);
        faucet.superMint(ALICE, 1_000_000e18);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(1_000_000e18, ALICE);

        vm.prank(BOB);
        uint256 positionId = market.openPosition(notional_, delta_);

        vm.warp(block.timestamp + timeTravel_);
        mockFeed.setPrice(2500e18);

        uint256 expectedPayout = market.previewPayout(positionId);

        vm.prank(BOB);
        uint256 payout = market.closePosition(positionId);

        PositionLib.Position memory position = market.positions(positionId);

        assertEq(position.state, PositionLib.POSITION_CLOSED_STATE_TAG);
        assertEq(payout, expectedPayout);
        assertEq(market.lockedNotional(), 0);
    }

    function testFuzz_CloseMultiplePositions(
        uint256 notional_,
        uint256 delta_,
        uint256 numberOfPositions,
        uint256 timeTravel_
    ) public assertNotJailed {
        notional_ = bound(notional_, 0.0001e18 + 1, 1000e18);
        delta_ = bound(delta_, 0, 1e18);
        numberOfPositions = bound(numberOfPositions, 1, 50);
        timeTravel_ = bound(timeTravel_, 1 days, 30 days);

        vm.prank(OWEN);
        faucet.superMint(ALICE, 1_000_000e18);

        vm.prank(ALICE);
        superToken.approve(address(market), type(uint256).max);

        vm.prank(ALICE);
        market.deposit(1_000_000e18, ALICE);

        uint256[] memory positionIds = new uint256[](numberOfPositions);
        for (uint256 i; i < numberOfPositions; ++i) {
            vm.prank(BOB);
            uint256 positionId = market.openPosition(notional_, delta_);
            positionIds[i] = positionId;
        }

        vm.warp(block.timestamp + timeTravel_);
        mockFeed.setPrice(2500e18);

        for (uint256 i; i < numberOfPositions; ++i) {
            uint256 positionId = positionIds[i];
            uint256 expectedPayout = market.previewPayout(positionId);

            vm.prank(BOB);
            uint256 payout = market.closePosition(positionId);

            PositionLib.Position memory position = market.positions(positionId);

            assertEq(position.state, PositionLib.POSITION_CLOSED_STATE_TAG);
            assertEq(payout, expectedPayout);
            assertEq(market.lockedNotional(), notional_ * (numberOfPositions - i - 1));
        }

        assertEq(market.lockedNotional(), 0);
    }

    function test_OpenPositionWithFee() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.prank(OWEN);
        market.setOpenPositionFee(0.001e18);

        uint256 openPositionFee = market.openPositionFee();
        uint256 bobBalanceBefore = superToken.balanceOf(BOB);

        vm.startPrank(BOB);
        superToken.approve(address(market), type(uint256).max);
        uint256 positionId = market.openPosition(100e18, 0);
        vm.stopPrank();

        PositionLib.Position memory position = market.positions(positionId);
        uint256 expectedFee = FixedPointMathLib.mulWadUp(100e18, openPositionFee);
        uint256 bobBalanceAfter = superToken.balanceOf(BOB);

        assertGt(expectedFee, 0);

        assertEq(
            bobBalanceAfter, bobBalanceBefore - expectedFee - superToken.getBufferAmountByFlowRate(position.flowRate)
        );
    }

    function test_ClosePositionWithFee() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.prank(OWEN);
        market.setClosePositionFee(0.001e18);

        uint256 closePositionFee = market.closePositionFee();

        vm.startPrank(BOB);
        superToken.approve(address(market), type(uint256).max);

        uint256 positionId = market.openPosition(100e18, 0);
        PositionLib.Position memory position = market.positions(positionId);

        uint256 bobBalanceBefore = superToken.balanceOf(BOB);
        uint256 expectedFee = FixedPointMathLib.mulWadUp(100e18, closePositionFee);

        uint256 payout = market.closePosition(positionId);
        vm.stopPrank();

        uint256 bobBalanceAfter = superToken.balanceOf(BOB);

        assertGt(expectedFee, 0);
        assertEq(
            bobBalanceAfter,
            (bobBalanceBefore + payout + superToken.getBufferAmountByFlowRate(position.flowRate)) - expectedFee
        );
    }

    function test_AccuredFees() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(OWEN);
        market.setOpenPositionFee(0.001e18);
        market.setClosePositionFee(0.001e18);
        vm.stopPrank();

        uint256 openPositionFee = market.openPositionFee();
        uint256 closePositionFee = market.closePositionFee();

        vm.startPrank(BOB);
        superToken.approve(address(market), type(uint256).max);

        uint256 positionId = market.openPosition(100e18, 0);
        uint256 expectedOpenFee = FixedPointMathLib.mulWadUp(100e18, openPositionFee);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedCloseFee = FixedPointMathLib.mulWadUp(100e18, closePositionFee);
        market.closePosition(positionId);
        vm.stopPrank();

        uint256 totalExpectedFees = expectedOpenFee + expectedCloseFee;
        uint256 accruedFees = market.accruedFees();

        assertEq(accruedFees, totalExpectedFees);
    }

    function test_WithdrawAccruedFees() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(OWEN);
        market.setOpenPositionFee(0.001e18);
        market.setClosePositionFee(0.001e18);
        vm.stopPrank();

        uint256 openPositionFee = market.openPositionFee();
        uint256 closePositionFee = market.closePositionFee();

        vm.startPrank(BOB);
        superToken.approve(address(market), type(uint256).max);

        uint256 positionId = market.openPosition(100e18, 0);
        uint256 expectedOpenFee = FixedPointMathLib.mulWadUp(100e18, openPositionFee);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedCloseFee = FixedPointMathLib.mulWadUp(100e18, closePositionFee);
        market.closePosition(positionId);
        vm.stopPrank();

        uint256 totalExpectedFees = expectedOpenFee + expectedCloseFee;
        uint256 accruedFeesBefore = market.accruedFees();

        assertEq(accruedFeesBefore, totalExpectedFees);

        uint256 ownerBalanceBefore = superToken.balanceOf(OWEN);

        vm.prank(OWEN);
        market.withdrawAccruedFees(OWEN);

        uint256 ownerBalanceAfter = superToken.balanceOf(OWEN);
        uint256 accruedFeesAfter = market.accruedFees();

        assertEq(ownerBalanceAfter - ownerBalanceBefore, totalExpectedFees);
        assertEq(accruedFeesAfter, 0);
    }

    function test_WithdrawAccruedFees_Reverts_NotOwner() public assertNotJailed {
        vm.prank(ALICE);
        market.deposit(1000e18, ALICE);

        vm.startPrank(OWEN);
        market.setOpenPositionFee(0.001e18);
        market.setClosePositionFee(0.001e18);
        vm.stopPrank();

        uint256 openPositionFee = market.openPositionFee();
        uint256 closePositionFee = market.closePositionFee();

        vm.startPrank(BOB);
        superToken.approve(address(market), type(uint256).max);

        uint256 positionId = market.openPosition(100e18, 0);
        uint256 expectedOpenFee = FixedPointMathLib.mulWadUp(100e18, openPositionFee);

        vm.warp(block.timestamp + 7 days);
        mockFeed.setPrice(2500e18);

        uint256 expectedCloseFee = FixedPointMathLib.mulWadUp(100e18, closePositionFee);
        market.closePosition(positionId);
        vm.stopPrank();

        uint256 totalExpectedFees = expectedOpenFee + expectedCloseFee;
        uint256 accruedFeesBefore = market.accruedFees();

        assertEq(accruedFeesBefore, totalExpectedFees);

        vm.prank(ALICE);
        vm.expectRevert();
        market.withdrawAccruedFees(ALICE);
    }
}
