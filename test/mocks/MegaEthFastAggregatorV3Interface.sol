// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

contract MockMegaEthFastAggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    uint256 private _updatedAt;

    constructor(int256 initialPrice_, uint8 decimals_) {
        _price = initialPrice_;
        _decimals = decimals_;
        _updatedAt = _getMicrosecondTimestamp();
    }

    function setPrice(int256 newPrice_) external {
        _price = newPrice_;
        _updatedAt = _getMicrosecondTimestamp();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, 0, _updatedAt, 0);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function _getMicrosecondTimestamp() private view returns (uint256) {
        return block.timestamp * 1_000_000; // microseconds
    }
}
