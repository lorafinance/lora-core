// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IHighPrecisionTimestampOracle {
    /// @notice Get high-precision timestamp (microsecond) of the transaction execution.
    function timestamp() external view returns (uint256);
}
