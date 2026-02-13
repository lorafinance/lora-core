// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "chainlink/interfaces/feeds/AggregatorV3Interface.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol";

/// @title MegaEthFastSentinelOracle
/// @author Lora Finance
/// @notice An oracle that fetches and validates price data from a Chainlink compatible Redstone Bolt price feed using high-precision timestamps (down to microseconds)
contract MegaEthTestnetFastSentinelOracle is ISentinelOracle {
    uint256 private constant _MICROSECONDS_IN_MILLISECOND = 1_000;
    uint256 private constant _MINIMUM_FRESHNESS_THRESHOLD = _MICROSECONDS_IN_MILLISECOND * 10;

    address public immutable PRICE_FEED;
    uint256 public immutable FRESHNESS_THRESHOLD;
    uint256 private immutable _PRICE_FEED_DECIMALS;

    error InvalidFreshnessThreshold(uint256 providedThreshold, uint256 minimumThreshold);

    constructor(address priceFeedAddress_) {
        PRICE_FEED = priceFeedAddress_;

        // On testnet, we disable freshness checks by setting an extremely high threshold
        FRESHNESS_THRESHOLD = type(uint256).max;
        _PRICE_FEED_DECIMALS = AggregatorV3Interface(PRICE_FEED).decimals();
    }

    /// @inheritdoc ISentinelOracle
    function getFreshPrice() external view returns (uint256, uint256) {
        (, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(PRICE_FEED).latestRoundData();
        if (price <= 0) {
            revert InvalidPrice();
        }

        uint256 adjustedPrice;
        if (_PRICE_FEED_DECIMALS < 18) {
            // casting to 'uint256' is safe because [price is checked to be positive above]
            // forge-lint: disable-next-line(unsafe-typecast)
            adjustedPrice = uint256(price) * 10 ** (18 - _PRICE_FEED_DECIMALS);
        } else {
            // casting to 'uint256' is safe because [price is checked to be positive above]
            // forge-lint: disable-next-line(unsafe-typecast)
            adjustedPrice = uint256(price) / 10 ** (_PRICE_FEED_DECIMALS - 18);
        }

        return (adjustedPrice, updatedAt);
    }

    // @inheritdoc ISentinelOracle
    function isPriceFresh() external pure returns (bool) {
        // FIXME: Implement high-precision timestamp check on mainnet
        return true;
    }

    /// @inheritdoc ISentinelOracle
    function decimals() external pure returns (uint8) {
        return 18;
    }
}
