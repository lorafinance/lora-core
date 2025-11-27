// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IRateModel} from "src/interfaces/IRateModel.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol";
import {PositionLib} from "src/libraries/PositionLib.sol";

/// @title MarketStorageLayout
/// @author Lora Finance
/// @notice erc7201 storage layout for Market contract
abstract contract MarketStorageLayout {
    /// @custom:storage-location erc7201:lora.market
    struct MarketStorage {
        IRateModel rateModel;
        ISentinelOracle priceOracle;

        uint256 buffer;
        uint256 cap;

        uint256 otmHalf;
        uint256 warmUpPeriod;

        uint256 totalPositions;
        uint256 lockedNotional;

        mapping(uint256 positionId_ => PositionLib.Position) positions;
        mapping(address user_ => uint256) userLockedNotional;
        mapping(address user_ => int96) userFlowRate;
        mapping(address user_ => uint256) lastFlowLiquidationTimestamp;
    }

    // keccak256(abi.encode(uint256(keccak256("lora.market")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MARKET_STORAGE_LOCATION =
        0x9067d9ed05a68edd9e5bee40c2c5edce2917e7f1f30f78a49b0af121a36b9400;

    /// @notice Get the market storage
    /// @return $ The market storage
    function _getMarketStorage() internal pure returns (MarketStorage storage $) {
        assembly {
            $.slot := MARKET_STORAGE_LOCATION
        }
    }
}
