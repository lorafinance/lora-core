// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IMarketFeePolicy} from "src/interfaces/IMarketFeePolicy.sol";

/// @title MarketFeePolicy
/// @author Lora Finance
/// @notice An abstract contract implementing the market fee policy
abstract contract MarketFeePolicy is IMarketFeePolicy {
    using SafeTransferLib for address;

    uint256 public constant MAX_FEE = 0.01e18; // 1% in WAD

    /// @custom:storage-location erc7201:lora.market.fee-policy
    struct MarketFeePolicyStorage {
        uint256 openPositionFee;
        uint256 closePositionFee;
        uint256 accruedFees;
    }

    // keccak256(abi.encode(uint256(keccak256("lora.market.fee-policy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MARKET_FEE_POLICY_STORAGE_LOCATION =
        0xef2e10e342787840ae291f5fd73403cfc0c1141bc6b821bb43746a540272de00;

    /// @notice Initialize the fee policy
    /// @param openPositionFee_ The open position fee (in WAD 1e18 = 100%)
    /// @param closePositionFee_ The close position fee (in WAD 1e18 = 100%)
    function _initializeFeePolicy(uint256 openPositionFee_, uint256 closePositionFee_) internal {
        if (openPositionFee_ > MAX_FEE) {
            revert InvalidFee(openPositionFee_, MAX_FEE);
        }
        if (closePositionFee_ > MAX_FEE) {
            revert InvalidFee(closePositionFee_, MAX_FEE);
        }

        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        $.openPositionFee = openPositionFee_;
        $.closePositionFee = closePositionFee_;
    }

    /// @inheritdoc IMarketFeePolicy
    function setOpenPositionFee(uint256 fee_) external onlyOwner {
        if (fee_ > MAX_FEE) {
            revert InvalidFee(fee_, MAX_FEE);
        }

        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        $.openPositionFee = fee_;
    }

    /// @inheritdoc IMarketFeePolicy
    function setClosePositionFee(uint256 fee_) external onlyOwner {
        if (fee_ > MAX_FEE) {
            revert InvalidFee(fee_, MAX_FEE);
        }

        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        $.closePositionFee = fee_;
    }

    /// @inheritdoc IMarketFeePolicy
    function setFee(uint256 fee_) external onlyOwner {
        if (fee_ > MAX_FEE) {
            revert InvalidFee(fee_, MAX_FEE);
        }

        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        $.openPositionFee = fee_;
        $.closePositionFee = fee_;
    }

    /// @inheritdoc IMarketFeePolicy
    function withdrawAccruedFees(address to_) external onlyOwner {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();

        uint256 fees = $.accruedFees;
        $.accruedFees = 0;
        asset().safeTransfer(to_, fees);
    }

    /// @inheritdoc IMarketFeePolicy
    function accruedFees() public view returns (uint256) {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        return $.accruedFees;
    }

    /// @inheritdoc IMarketFeePolicy
    function openPositionFeeEnabled() external view returns (bool) {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        return $.openPositionFee > 0;
    }

    /// @inheritdoc IMarketFeePolicy
    function closePositionFeeEnabled() external view returns (bool) {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        return $.closePositionFee > 0;
    }

    /// @inheritdoc IMarketFeePolicy
    function openPositionFee() external view returns (uint256) {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        return $.openPositionFee;
    }

    /// @inheritdoc IMarketFeePolicy
    function closePositionFee() external view returns (uint256) {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();
        return $.closePositionFee;
    }

    /// @notice Charge open position fee if enabled
    /// @param user_ The user opening the position
    /// @param notional_ The notional amount of the position
    function _chargeOpenPositionFee(address user_, uint256 notional_) internal {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();

        if ($.openPositionFee > 0) {
            uint256 feeAmount = FixedPointMathLib.mulWadUp(notional_, $.openPositionFee);
            $.accruedFees += feeAmount;

            asset().safeTransferFrom(user_, address(this), feeAmount);
        }
    }

    /// @notice Charge close position fee if enabled
    /// @param user_ The user closing the position
    /// @param notional_ The notional amount of the position
    function _chargeClosePositionFee(address user_, uint256 notional_) internal {
        MarketFeePolicyStorage storage $ = _getMarketFeePolicyStorage();

        if ($.closePositionFee > 0) {
            uint256 feeAmount = FixedPointMathLib.mulWadUp(notional_, $.closePositionFee);
            $.accruedFees += feeAmount;

            asset().safeTransferFrom(user_, address(this), feeAmount);
        }
    }

    /// @notice Get the market fee policy storage
    /// @return $ The market fee policy storage
    function _getMarketFeePolicyStorage() internal pure returns (MarketFeePolicyStorage storage $) {
        assembly {
            $.slot := MARKET_FEE_POLICY_STORAGE_LOCATION
        }
    }

    /// @dev From solady/tokens/ERC4626.sol
    function asset() public view virtual returns (address);

    /// @dev From solady/auth/Ownable.sol
    function _checkOwner() internal view virtual;

    /// @dev From solady/auth/Ownable.sol
    modifier onlyOwner() virtual {
        _checkOwner();
        _;
    }
}
