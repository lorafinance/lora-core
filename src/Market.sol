// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC4626} from "solady/tokens/ERC4626.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {CFASuperAppBase, SuperTokenV1Library} from "superfluid/apps/CFASuperAppBase.sol";
import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions,
    IGeneralDistributionAgreementV1
} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {MarketStorageLayout} from "src/MarketStorageLayout.sol";
import {MarketGuard} from "src/MarketGuard.sol";
import {PositionLib} from "src/libraries/PositionLib.sol";
import {IRateModel} from "src/interfaces/IRateModel.sol";
import {ISentinelOracle} from "src/interfaces/ISentinelOracle.sol";
import {IMarket} from "src/interfaces/IMarket.sol";

/// @title Market
/// @author Lora Finance
/// @notice A market contract for managing lp and user positions
contract Market is
    IMarket,
    MarketStorageLayout,
    MarketGuard,
    ERC4626,
    CFASuperAppBase,
    ReentrancyGuard,
    UUPSUpgradeable,
    Initializable
{
    using SafeTransferLib for address;
    using LibClone for address;
    using SuperTokenV1Library for ISuperToken;

    /*=========================== Constructor =========================*/

    constructor(address superfluidHost_) CFASuperAppBase(ISuperfluid(superfluidHost_)) {
        _disableInitializers();
    }

    /*=========================== Initialization =========================*/

    /// @notice Initializes the Market contract

    /// @param rateModel_ The address of the rate model contract
    /// @param priceOracle_ The address of the price oracle contract
    /// @param buffer_ The buffer ratio for liquidity management
    /// @param otmHalf_ The out-of-the-money half-life parameter
    /// @param warmUpPeriod_ The warm-up period for positions
    /// @param cap_ The cap for the market
    /// @param owner_ The address of the contract owner
    function initialize(
        address rateModel_,
        address priceOracle_,
        uint256 buffer_,
        uint256 cap_,
        uint256 otmHalf_,
        uint256 warmUpPeriod_,
        address owner_
    ) external initializer {
        if (otmHalf_ == 0) {
            revert ZeroOtmHalf();
        }
        if (buffer_ > FixedPointMathLib.WAD) {
            revert BufferTooHigh(buffer_, FixedPointMathLib.WAD);
        }

        MarketStorage storage $ = _getMarketStorage();

        $.rateModel = IRateModel(rateModel_);
        $.priceOracle = ISentinelOracle(priceOracle_);

        $.buffer = buffer_;
        $.cap = cap_;

        $.otmHalf = otmHalf_;
        $.warmUpPeriod = warmUpPeriod_;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL;
        HOST.registerApp(configWord);

        _initializeOwner(owner_);

        // from CFASuperAppBase constructor
        IGeneralDistributionAgreementV1 gda = IGeneralDistributionAgreementV1(
            address(
                ISuperfluid(HOST)
                    .getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))
            )
        );
        gda.setConnectPermission(false);
    }

    /*=========================== Setters =========================*/

    /// @inheritdoc IMarket
    function setRateModel(address newRateModel_) external onlyOwner {
        MarketStorage storage $ = _getMarketStorage();
        $.rateModel = IRateModel(newRateModel_);
    }

    /// @inheritdoc IMarket
    function setPriceOracle(address newPriceOracle_) external onlyOwner {
        MarketStorage storage $ = _getMarketStorage();
        $.priceOracle = ISentinelOracle(newPriceOracle_);
    }

    /// @inheritdoc IMarket
    function setBuffer(uint256 newBuffer_) external onlyOwner {
        if (newBuffer_ > FixedPointMathLib.WAD) {
            revert BufferTooHigh(newBuffer_, FixedPointMathLib.WAD);
        }

        MarketStorage storage $ = _getMarketStorage();
        $.buffer = newBuffer_;
    }

    /// @inheritdoc IMarket
    function setCap(uint256 newCap_) external onlyOwner {
        MarketStorage storage $ = _getMarketStorage();
        $.cap = newCap_;
    }

    /// @inheritdoc IMarket
    function setOtmHalf(uint256 newOtmHalf_) external onlyOwner {
        if (newOtmHalf_ == 0) {
            revert ZeroOtmHalf();
        }

        MarketStorage storage $ = _getMarketStorage();
        $.otmHalf = newOtmHalf_;
    }

    // @inheritdoc IMarket
    function setWarmUpPeriod(uint256 newWarmUpPeriod_) external override onlyOwner {
        MarketStorage storage $ = _getMarketStorage();
        $.warmUpPeriod = newWarmUpPeriod_;
    }

    /*=========================== External Functions =========================*/

    /// @inheritdoc IMarket
    function openPosition(uint256 notional_, uint256 delta_)
        external
        override
        nonReentrant
        whenPositionOpenNotPaused
        returns (uint256)
    {
        if (notional_ == 0) {
            revert NotionalZero();
        }

        MarketStorage storage $ = _getMarketStorage();

        if (notional_ > totalAssets() - $.lockedNotional - FixedPointMathLib.mulWad(totalAssets(), $.buffer)) {
            revert InsufficientLiquidity(
                notional_, totalAssets() - $.lockedNotional - FixedPointMathLib.mulWad(totalAssets(), $.buffer)
            );
        }

        PositionLib.MarketSnapshot memory snapshot = PositionLib.MarketSnapshot({
            rateModel: $.rateModel,
            lockedNotional: $.lockedNotional,
            poolAssets: totalAssets(),
            buffer: $.buffer,
            otmHalf: $.otmHalf,
            warmUpPeriod: $.warmUpPeriod
        });

        int96 flowRate = PositionLib.quoteFlowRate(snapshot, notional_, delta_);
        if (flowRate == 0) {
            revert FlowRateZero();
        }
        if (flowRate == PositionLib.FLOW_RATE_OVERFLOW_SENTINEL) {
            revert FlowRateTooHigh();
        }

        (uint256 spotPrice,) = $.priceOracle.getFreshPrice();
        uint256 strikePrice = delta_ > 0 ? spotPrice + FixedPointMathLib.mulWad(spotPrice, delta_) : spotPrice;

        uint256 positionId = ++$.totalPositions;
        $.positions[positionId] = PositionLib.Position({
            owner: msg.sender,
            notional: notional_,
            openedAt: block.timestamp,
            strikePrice: strikePrice,
            flowRate: flowRate,
            state: PositionLib.POSITION_OPEN_STATE_TAG
        });

        $.lockedNotional += notional_;
        $.userLockedNotional[msg.sender] += notional_;
        $.userFlowRate[msg.sender] += flowRate;

        bool success = ISuperToken(asset()).flowFrom(msg.sender, address(this), $.userFlowRate[msg.sender]);
        if (!success) {
            revert FailedToOpenPosition(notional_, delta_);
        }

        emit PositionOpened(positionId, msg.sender, notional_, delta_, strikePrice, flowRate, block.timestamp);

        return positionId;
    }

    /// @inheritdoc IMarket
    function closePosition(uint256 positionId_) external override nonReentrant returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        PositionLib.Position storage position = $.positions[positionId_];

        if (position.owner == address(0)) {
            revert PositionNotFound(positionId_);
        }
        if (position.owner != msg.sender) {
            revert OnlyPositionOwner(msg.sender, position.owner);
        }
        if (
            position.state != PositionLib.POSITION_OPEN_STATE_TAG
                || position.openedAt < $.lastFlowLiquidationTimestamp[msg.sender]
        ) {
            revert PositionNotOpen(positionId_);
        }

        PositionLib.MarketSnapshot memory snapshot = PositionLib.MarketSnapshot({
            rateModel: $.rateModel,
            lockedNotional: $.lockedNotional,
            poolAssets: totalAssets(),
            buffer: $.buffer,
            otmHalf: $.otmHalf,
            warmUpPeriod: $.warmUpPeriod
        });

        (uint256 spotPrice,) = $.priceOracle.getFreshPrice();
        uint256 payout = PositionLib.calculatePayout(snapshot, position, spotPrice, $.priceOracle.decimals());

        position.state = PositionLib.POSITION_CLOSED_STATE_TAG;
        $.lockedNotional -= position.notional;
        $.userLockedNotional[msg.sender] -= position.notional;
        $.userFlowRate[msg.sender] -= position.flowRate;

        bool success = ISuperToken(asset()).flowFrom(msg.sender, address(this), $.userFlowRate[msg.sender]);
        if (!success) {
            revert FailedToClosePosition(positionId_);
        }

        if (payout > 0) {
            asset().safeTransfer(msg.sender, payout);
        }

        emit PositionClosed(positionId_, msg.sender, payout, block.timestamp);

        return payout;
    }

    /*=========================== Superfluid Callbacks =========================*/

    /// @inheritdoc CFASuperAppBase
    function onFlowCreated(ISuperToken superToken_, address, int96, bytes calldata ctx_)
        internal
        view
        override
        returns (bytes memory)
    {
        if (address(superToken_) != asset()) {
            revert InvalidSuperToken(address(superToken_), asset());
        }

        ISuperfluid.Context memory context = HOST.decodeCtx(ctx_);
        if (context.msgSender != address(this)) {
            revert FlowAuthorizedByMarketOnly(context.msgSender, address(this));
        }

        return ctx_;
    }

    /// @inheritdoc CFASuperAppBase
    function onFlowUpdated(ISuperToken superToken_, address, int96, int96, uint256, bytes calldata ctx_)
        internal
        view
        override
        returns (bytes memory)
    {
        if (address(superToken_) != asset()) {
            revert InvalidSuperToken(address(superToken_), asset());
        }

        ISuperfluid.Context memory context = HOST.decodeCtx(ctx_);
        if (context.msgSender != address(this)) {
            revert FlowAuthorizedByMarketOnly(context.msgSender, address(this));
        }

        return ctx_;
    }

    /// @inheritdoc CFASuperAppBase
    /// @dev Liquidates all positions of the sender_ upon flow deletion
    function onInFlowDeleted(ISuperToken superToken_, address sender_, int96, uint256, bytes calldata ctx_)
        internal
        override
        returns (bytes memory)
    {
        if (address(superToken_) != asset()) {
            return ctx_;
        }

        ISuperfluid.Context memory context = HOST.decodeCtx(ctx_);
        if (context.msgSender == address(this)) {
            return ctx_;
        }

        MarketStorage storage $ = _getMarketStorage();

        $.lockedNotional -= $.userLockedNotional[sender_];
        $.userLockedNotional[sender_] = 0;
        $.userFlowRate[sender_] = 0;
        $.lastFlowLiquidationTimestamp[sender_] = block.timestamp;

        emit UserLiquidated(sender_, block.timestamp);

        return ctx_;
    }

    /*=========================== View Functions =========================*/

    /// @inheritdoc IMarket
    function positions(uint256 positionId_) external view override returns (PositionLib.Position memory) {
        MarketStorage storage $ = _getMarketStorage();
        PositionLib.Position memory position = $.positions[positionId_];

        bytes4 state = position.state;
        if (
            state == PositionLib.POSITION_OPEN_STATE_TAG
                && position.openedAt < $.lastFlowLiquidationTimestamp[position.owner]
        ) {
            state = PositionLib.POSITION_LIQUIDATED_STATE_TAG;
        }

        return PositionLib.Position({
            owner: position.owner,
            notional: position.notional,
            flowRate: position.flowRate,
            openedAt: position.openedAt,
            strikePrice: position.strikePrice,
            state: state
        });
    }

    /// @inheritdoc IMarket
    function previewFlowRate(uint256 notional_, uint256 delta_) external view returns (int96) {
        MarketStorage storage $ = _getMarketStorage();
        PositionLib.MarketSnapshot memory snapshot = PositionLib.MarketSnapshot({
            rateModel: $.rateModel,
            lockedNotional: $.lockedNotional,
            poolAssets: totalAssets(),
            buffer: $.buffer,
            otmHalf: $.otmHalf,
            warmUpPeriod: $.warmUpPeriod
        });

        return PositionLib.quoteFlowRate(snapshot, notional_, delta_);
    }

    /// @inheritdoc IMarket
    function previewPayout(uint256 positionId_) external view returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        PositionLib.Position memory position = $.positions[positionId_];

        if (position.owner == address(0)) {
            return 0;
        }
        if (!$.priceOracle.isPriceFresh()) {
            return 0;
        }

        PositionLib.MarketSnapshot memory snapshot = PositionLib.MarketSnapshot({
            rateModel: $.rateModel,
            lockedNotional: $.lockedNotional,
            poolAssets: totalAssets(),
            buffer: $.buffer,
            otmHalf: $.otmHalf,
            warmUpPeriod: $.warmUpPeriod
        });

        (uint256 currentPrice,) = $.priceOracle.getFreshPrice();
        return PositionLib.calculatePayout(snapshot, position, currentPrice, $.priceOracle.decimals());
    }

    /// @inheritdoc IMarket
    function rateModel() external view override returns (IRateModel) {
        MarketStorage storage $ = _getMarketStorage();
        return $.rateModel;
    }

    /// @inheritdoc IMarket
    function priceOracle() external view override returns (ISentinelOracle) {
        MarketStorage storage $ = _getMarketStorage();
        return $.priceOracle;
    }

    /// @inheritdoc IMarket
    function totalPositions() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.totalPositions;
    }

    /// @inheritdoc IMarket
    function lockedNotional() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.lockedNotional;
    }

    /// @inheritdoc IMarket
    function buffer() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.buffer;
    }

    /// @inheritdoc IMarket
    function cap() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.cap;
    }

    /// @inheritdoc IMarket
    function otmHalf() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.otmHalf;
    }

    /// @inheritdoc IMarket
    function warmUpPeriod() external view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();
        return $.warmUpPeriod;
    }

    /*=========================== Overrides =========================*/

    /// @inheritdoc ERC4626
    function maxWithdraw(address owner_) public view override returns (uint256) {
        MarketStorage storage $ = _getMarketStorage();

        uint256 liquid = totalAssets() - $.lockedNotional - FixedPointMathLib.mulWad(totalAssets(), $.buffer);
        uint256 rawMax = super.maxWithdraw(owner_);
        return liquid < rawMax ? liquid : rawMax;
    }

    /// @inheritdoc ERC4626
    function maxRedeem(address owner_) public view override returns (uint256) {
        return convertToShares(maxWithdraw(owner_));
    }

    /// @inheritdoc ERC4626
    function asset() public view override returns (address) {
        bytes memory args = address(this).argsOnERC1967();
        return abi.decode(args, (address));
    }

    /// @inheritdoc ERC20
    function name() public view override returns (string memory) {
        return string.concat("Lora ", IERC20(asset()).name());
    }

    /// @inheritdoc ERC20
    function symbol() public view override returns (string memory) {
        return string.concat("l", IERC20(asset()).symbol());
    }

    /// @inheritdoc ERC4626
    function _underlyingDecimals() internal view override returns (uint8) {
        return IERC20(asset()).decimals();
    }

    /// @inheritdoc ERC4626
    function _deposit(address by_, address to_, uint256 assets_, uint256 shares_)
        internal
        override
        whenLpDepositNotPaused
    {
        MarketStorage storage $ = _getMarketStorage();
        if (totalAssets() + assets_ > $.cap) {
            revert CapExceeded(assets_, totalAssets() + assets_, $.cap);
        }

        super._deposit(by_, to_, assets_, shares_);
    }

    /// @inheritdoc ERC4626
    function _withdraw(address by_, address to_, address owner_, uint256 assets_, uint256 shares_)
        internal
        override
        whenLpWithdrawNotPaused
    {
        super._withdraw(by_, to_, owner_, assets_, shares_);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
