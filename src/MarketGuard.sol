// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IMarketGuard} from "src/interfaces/IMarketGuard.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/// @title MarketGuard
/// @author Lora Finance
/// @notice A contract module which allows children to implement an emergency stop
abstract contract MarketGuard is IMarketGuard, Ownable {
    /// @custom:storage-location erc7201:lora.market.guard
    struct MarketGuardStorage {
        bool lpDepositPaused;
        bool lpWithdrawPaused;
        bool positionOpenPaused;
    }

    // keccak256(abi.encode(uint256(keccak256("lora.market.guard")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MARKET_GUARD_STORAGE_LOCATION =
        0xee30673c728756e4585bad5ce5b3da1b0c796d92fbf3ba38ee6c0ff4b71ec800;

    /// @dev Modifier to make a function callable only when LP deposit are not paused.
    modifier whenLpDepositNotPaused() {
        _checkMarketLpDepositNotPaused();
        _;
    }

    /// @dev Modifier to make a function callable only when LP withdraw are not paused.
    modifier whenLpWithdrawNotPaused() {
        _checkMarketLpWithdrawNotPaused();
        _;
    }

    /// @dev Modifier to make a function callable only when position opening is not paused.
    modifier whenPositionOpenNotPaused() {
        _checkMarketPositionOpenNotPaused();
        _;
    }

    /// @inheritdoc IMarketGuard
    function setLpDepositPaused(bool paused_) external onlyOwner {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        $.lpDepositPaused = paused_;

        emit LpDepositPausedUpdated(paused_);
    }

    /// @inheritdoc IMarketGuard
    function setLpWithdrawPaused(bool paused_) external onlyOwner {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        $.lpWithdrawPaused = paused_;

        emit LpWithdrawPausedUpdated(paused_);
    }

    /// @inheritdoc IMarketGuard
    function setLpPaused(bool paused_) external onlyOwner {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        $.lpDepositPaused = paused_;
        $.lpWithdrawPaused = paused_;

        emit LpDepositPausedUpdated(paused_);
        emit LpWithdrawPausedUpdated(paused_);
    }

    /// @inheritdoc IMarketGuard
    function setPositionOpenPaused(bool paused_) external onlyOwner {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        $.positionOpenPaused = paused_;

        emit PositionOpenPausedUpdated(paused_);
    }

    /// @inheritdoc IMarketGuard
    function setPaused(bool paused_) external onlyOwner {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        $.lpDepositPaused = paused_;
        $.lpWithdrawPaused = paused_;
        $.positionOpenPaused = paused_;

        emit LpDepositPausedUpdated(paused_);
        emit LpWithdrawPausedUpdated(paused_);
        emit PositionOpenPausedUpdated(paused_);
    }

    /// @inheritdoc IMarketGuard
    function isLpDepositPaused() external view returns (bool) {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        return $.lpDepositPaused;
    }

    /// @inheritdoc IMarketGuard
    function isLpWithdrawPaused() external view returns (bool) {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        return $.lpWithdrawPaused;
    }

    /// @inheritdoc IMarketGuard
    function isPositionOpenPaused() external view returns (bool) {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        return $.positionOpenPaused;
    }

    /// @notice Get the MarketGuard storage
    /// @return $ The MarketGuard storage
    function _getMarketGuardStorage() internal pure returns (MarketGuardStorage storage $) {
        assembly {
            $.slot := MARKET_GUARD_STORAGE_LOCATION
        }
    }

    /// @notice Check if LP deposit is not paused
    function _checkMarketLpDepositNotPaused() internal view {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        if ($.lpDepositPaused) {
            revert LpDepositPaused();
        }
    }

    /// @notice Check if LP withdraw is not paused
    function _checkMarketLpWithdrawNotPaused() internal view {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        if ($.lpWithdrawPaused) {
            revert LpWithdrawPaused();
        }
    }

    /// @notice Check if position opening is not paused
    function _checkMarketPositionOpenNotPaused() internal view {
        MarketGuardStorage storage $ = _getMarketGuardStorage();
        if ($.positionOpenPaused) {
            revert PositionOpenPaused();
        }
    }
}
