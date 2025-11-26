// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SentinelOracle} from "src/SentinelOracle.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol"; 
import {MockAggregatorV3Interface} from "test/mocks/AggregatorV3Interface.sol";

contract SentinelOracleTest is Test {
    SentinelOracle public oracle;
    MockAggregatorV3Interface public mockFeed;

    uint256 public constant FRESHNESS_THRESHOLD = 1 hours;

    function setUp() public {
        mockFeed = new MockAggregatorV3Interface(2000e8, 8);
        oracle = new SentinelOracle(address(mockFeed), FRESHNESS_THRESHOLD);
    }

    function testGetFreshPrice_Valid() public view {
        (uint256 price, uint256 updatedAt) = oracle.getFreshPrice();
        assertEq(price, 2000e18);
        assertEq(updatedAt, block.timestamp);
    }

    function testGetFreshPrice_Stale() public {
        vm.warp(block.timestamp + FRESHNESS_THRESHOLD + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ISentinelOracle.StalePrice.selector, FRESHNESS_THRESHOLD + 1, FRESHNESS_THRESHOLD)
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
        vm.warp(block.timestamp + FRESHNESS_THRESHOLD + 1);

        bool isFresh = oracle.isPriceFresh();
        assertFalse(isFresh);
    }

    function testDecimals() public view {
        uint8 decimals = oracle.decimals();
        assertEq(decimals, 18);
    }
}
