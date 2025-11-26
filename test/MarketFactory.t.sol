// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Market} from "src/Market.sol";
import {MarketFactory} from "src/MarketFactory.sol";
import {MockAggregatorV3Interface} from "test/mocks/AggregatorV3Interface.sol";
import {SentinelOracle} from "src/SentinelOracle.sol";
import {JumpRateModel} from "src/JumpRateModel.sol";
import {Faucet} from "src/testnet/Faucet.sol";

contract MarketFactoryTest is Test {
    address constant ALICE = address(0xA1CE);
    address constant OWEN = address(0x011E11);

    address superfluidHost;
    MarketFactory factory;
    address superToken;
    address implementation;

    function setUp() public {
        superfluidHost = vm.envAddress("SUPERFLUID_TEST_HOST_ADDRESS");
        vm.createSelectFork(vm.envString("SUPERFLUID_TEST_RPC_URL"));

        Faucet faucet = new Faucet("Test Token", "TTK", 18, 1 ether, 1 days, superfluidHost, OWEN);
        superToken = faucet.SUPER_TOKEN();
        implementation = address(new Market(superfluidHost));
        factory = new MarketFactory(implementation, OWEN);
    }

    function testInitialImplementation() public view {
        assertEq(factory.implementation(), implementation);
        assertEq(factory.owner(), OWEN);
    }

    function testSetImplementation() public {
        address newImplementation = address(new Market(superfluidHost));

        vm.prank(OWEN);
        factory.setImplementation(newImplementation);

        assertEq(factory.implementation(), newImplementation);
    }

    function testSetImplementation_NotOwner() public {
        address newImplementation = address(new Market(superfluidHost));

        vm.prank(ALICE);
        vm.expectRevert();
        factory.setImplementation(newImplementation);
    }

    function testDeployMarket() public {
        JumpRateModel rateModel = new JumpRateModel({
            _basePerSecond: 1e16,
            _sloper1PerSecond: 2e16,
            _slope2PerSec: 5e16,
            _kink: 0.8e18,
            _minPerSec: 1e16,
            _maxPerSec: 1e17
        });
        MockAggregatorV3Interface mockFeed = new MockAggregatorV3Interface(2000e8, 8);
        SentinelOracle priceOracle = new SentinelOracle(address(mockFeed), 1 hours);

        bytes memory immutableArgs = abi.encode(address(superToken));
        bytes memory initializerData = abi.encodeCall(
            Market.initialize, (address(rateModel), address(priceOracle), 0.1e18, 500e18, 15 minutes, OWEN)
        );

        vm.prank(OWEN);
        address marketAddress = factory.deployMarket(immutableArgs, initializerData);

        Market market = Market(marketAddress);
        assertEq(market.asset(), address(superToken));
        assertEq(address(market.rateModel()), address(rateModel));
        assertEq(address(market.priceOracle()), address(priceOracle));
        assertEq(market.buffer(), 0.1e18);
        assertEq(market.otmHalf(), 500e18);
        assertEq(market.owner(), OWEN);
    }

    function testDeployMarket_NotOwner() public {
        bytes memory immutableArgs = abi.encode(address(superToken));
        bytes memory initializerData = abi.encodeCall(Market.initialize, (address(0), address(0), 0, 0, 0, OWEN));

        vm.prank(ALICE);
        vm.expectRevert();
        factory.deployMarket(immutableArgs, initializerData);
    }

    function testInitializeMarketAfterDeplyment_Revert() public {
        JumpRateModel rateModel = new JumpRateModel({
            _basePerSecond: 1e16,
            _sloper1PerSecond: 2e16,
            _slope2PerSec: 5e16,
            _kink: 0.8e18,
            _minPerSec: 1e16,
            _maxPerSec: 1e17
        });
        MockAggregatorV3Interface mockFeed = new MockAggregatorV3Interface(2000e8, 8);
        SentinelOracle priceOracle = new SentinelOracle(address(mockFeed), 1 hours);

        bytes memory immutableArgs = abi.encode(address(superToken));
        bytes memory initializerData = abi.encodeCall(
            Market.initialize, (address(rateModel), address(priceOracle), 0.1e18, 500e18, 15 minutes, OWEN)
        );

        vm.prank(OWEN);
        address marketAddress = factory.deployMarket(immutableArgs, initializerData);

        Market market = Market(marketAddress);

        vm.expectRevert();
        market.initialize(address(rateModel), address(priceOracle), 0.1e18, 500e18, 15 minutes, OWEN);
    }
}
