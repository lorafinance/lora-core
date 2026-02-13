// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IHighPrecisionTimestampOracle} from "src/interfaces/IHighPrecisionTimestampOracle.sol";

contract MockHighPrecisionTimestampOracle is IHighPrecisionTimestampOracle {
    function timestamp() external view override returns (uint256) {
        return block.timestamp * 1_000_000; // microseconds
    }
}
