// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {JumpRateModel} from "src/JumpRateModel.sol";

contract JumpRateModelTest is Test {
    JumpRateModel public jumpRateModel;

    function setUp() public {
        jumpRateModel = new JumpRateModel(0.000001e18, 0.000002e18, 0.000005e18, 0.8e18, 0.0000005e18, 0.00001e18);
    }

    function testGetRatePerSecond_BelowKink() public view {
        uint256 utilization = 0.5e18;
        uint256 rate = jumpRateModel.getRatePerSecond(utilization);
        uint256 expectedRate = 0.000001e18 + (utilization * 0.000002e18) / 1e18;
        assertEq(rate, expectedRate);
    }

    function testGetRatePerSecond_AboveKink() public view {
        uint256 utilization = 0.9e18;
        uint256 rate = jumpRateModel.getRatePerSecond(utilization);
        uint256 normalRate = 0.000001e18 + (0.8e18 * 0.000002e18) / 1e18;
        uint256 excessUtil = utilization - 0.8e18;
        uint256 expectedRate = normalRate + (excessUtil * 0.000005e18) / 1e18;
        assertEq(rate, expectedRate);
    }
}
