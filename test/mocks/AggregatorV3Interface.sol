// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

contract MockAggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;

    constructor(int256 initialPrice_, uint8 decimals_) {
        _price = initialPrice_;
        _decimals = decimals_;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 newPrice_) external {
        _price = newPrice_;
        _updatedAt = block.timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, 0, _updatedAt, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
