// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

/// @title IRateModel
/// @author Lora Finance
interface IRateModel {
    /// @notice Get the interest rate per second based on the utilization rate
    /// @dev all rates and utilization are expressed in wad (1e18)
    /// @param utilization_ The current utilization rate of the pool
    /// @return rate The interest rate per second in wad (1e18)
    function getRatePerSecond(uint256 utilization_) external view returns (uint256 rate);
}
