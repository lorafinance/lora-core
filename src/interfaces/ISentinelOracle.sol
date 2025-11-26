// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

/// @title ISentinelOracle
/// @author Lora Finance
interface ISentinelOracle {
    error StalePrice(uint256 staleness, uint256 threshold);
    error InvalidPrice();

    /// @notice Get the address of the underlying price feed
    /// @return The address of the price feed
    function PRICE_FEED() external view returns (address);

    /// @notice Get the freshness threshold for price data
    /// @return The freshness threshold in seconds
    function FRESHNESS_THRESHOLD() external view returns (uint256);

    /// @notice Get the latest fresh price and its timestamp
    /// @return price The latest fresh price
    /// @return timestamp The timestamp of the latest fresh price
    function getFreshPrice() external view returns (uint256, uint256);

    /// @notice Check if the current price is fresh
    /// @return True if the price is fresh, false otherwise
    function isPriceFresh() external view returns (bool);

    /// @notice Get the number of decimals used by the price feed
    /// @return The number of decimals
    function decimals() external pure returns (uint8);
}
