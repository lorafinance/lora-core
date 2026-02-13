// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MegaEthFastSentinelOracle} from "src/MegaEthFastSentinelOracle.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol";
import {MockMegaEthFastAggregatorV3Interface} from "test/mocks/MegaEthFastAggregatorV3Interface.sol";
import {MockHighPrecisionTimestampOracle} from "test/mocks/HighPrecisionTimestampOracle.sol";

contract MegaEthFastSentinelOracleTest is Test {
    MegaEthFastSentinelOracle public oracle;
    MockMegaEthFastAggregatorV3Interface public mockFeed;

    uint256 public constant FRESHNESS_THRESHOLD = 10 seconds * 1_000_000; // microseconds

    function setUp() public {
        address highPrecisionTimestampOracleAddress = address(new MockHighPrecisionTimestampOracle());
        // Address of the HighPrecisionTimestampOracle system contract deployed on MegaEth
        vm.etch(0x6342000000000000000000000000000000000002, address(highPrecisionTimestampOracleAddress).code);

        mockFeed = new MockMegaEthFastAggregatorV3Interface(2000e8, 8);
        oracle = new MegaEthFastSentinelOracle(address(mockFeed), FRESHNESS_THRESHOLD);
    }

    function testGetFreshPrice_Valid() public view {
        (uint256 price, uint256 updatedAt) = oracle.getFreshPrice();
        assertEq(price, 2000e18);
        assertEq(updatedAt, _getMicrosecondTimestamp(block.timestamp));
    }

    function testGetFreshPrice_Stale() public {
        vm.warp(block.timestamp + (FRESHNESS_THRESHOLD / 1_000_000) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISentinelOracle.StalePrice.selector,
                _getMicrosecondTimestamp((FRESHNESS_THRESHOLD / 1_000_000) + 1),
                FRESHNESS_THRESHOLD
            )
        );
        oracle.getFreshPrice();
    }

    function testGetFreshPrice_InvalidPrice() public {
        mockFeed.setPrice(0);

        vm.expectRevert(abi.encodeWithSelector(ISentinelOracle.InvalidPrice.selector));
        oracle.getFreshPrice();
    }

    function testIsPriceFresh_True() public view {
        bool isFresh = oracle.isPriceFresh();
        assertTrue(isFresh);
    }

    function testIsPriceFresh_False() public {
        vm.warp(block.timestamp + (FRESHNESS_THRESHOLD / 1_000_000) + 1);

        bool isFresh = oracle.isPriceFresh();
        assertFalse(isFresh);
    }

    function testDecimals() public view {
        uint8 decimals = oracle.decimals();
        assertEq(decimals, 18);
    }

    function testConstructor_InvalidFreshnessThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(MegaEthFastSentinelOracle.InvalidFreshnessThreshold.selector, 10 seconds, 10_000)
        );
        new MegaEthFastSentinelOracle(address(mockFeed), 10 seconds);
    }

    function _getMicrosecondTimestamp(uint256 timestampInSeconds) private pure returns (uint256) {
        return timestampInSeconds * 1_000_000;
    }
}
