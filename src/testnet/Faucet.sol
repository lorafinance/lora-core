// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {
    ISuperToken,
    ISuperfluid,
    ISuperTokenFactory,
    IERC20Metadata
} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {MintableERC20} from "src/testnet/MintableERC20.sol";

contract Faucet is OwnableRoles {
    using SafeTransferLib for address;

    uint256 public constant MINTER_ROLE = _ROLE_0;
    uint256 public constant SUPER_MINTER_ROLE = _ROLE_1;

    address public immutable TOKEN;
    address public immutable SUPER_TOKEN;

    constructor(
        string memory erc20Name_,
        string memory erc20Symbol_,
        uint8 erc20Decimals_,
        uint256 erc20MintAmount_,
        uint256 erc20Cooldown_,
        address superfluidHost_,
        address owner_
    ) {
        TOKEN = address(
            new MintableERC20(erc20Name_, erc20Symbol_, erc20Decimals_, erc20MintAmount_, erc20Cooldown_, owner_)
        );

        ISuperTokenFactory superTokenFactory = ISuperfluid(superfluidHost_).getSuperTokenFactory();
        SUPER_TOKEN = address(
            superTokenFactory.createERC20Wrapper(
                IERC20Metadata(TOKEN),
                ISuperTokenFactory.Upgradability.FULL_UPGRADABLE,
                string.concat("Super ", erc20Name_),
                string.concat(erc20Symbol_, "x")
            )
        );

        TOKEN.safeApprove(SUPER_TOKEN, type(uint256).max);

        _initializeOwner(owner_);
    }

    function mint() external {
        uint256 amount = MintableERC20(TOKEN).mintAmount();

        MintableERC20(TOKEN).mintFor(msg.sender, address(this));
        ISuperToken(SUPER_TOKEN).upgrade(amount);
        SUPER_TOKEN.safeTransfer(msg.sender, amount);
    }

    function mintFor(address to_) external onlyRoles(MINTER_ROLE) {
        uint256 amount = MintableERC20(TOKEN).mintAmount();

        MintableERC20(TOKEN).mintFor(to_, address(this));
        ISuperToken(SUPER_TOKEN).upgrade(amount);
        SUPER_TOKEN.safeTransfer(to_, amount);
    }

    function mintFor(address to_, uint256 amount_) external onlyRoles(MINTER_ROLE) {
        MintableERC20(TOKEN).mintFor(to_, address(this), amount_);
        ISuperToken(SUPER_TOKEN).upgrade(amount_);
        SUPER_TOKEN.safeTransfer(to_, amount_);
    }

    function superMint(address to_, uint256 amount_) external onlyRolesOrOwner(SUPER_MINTER_ROLE) {
        MintableERC20(TOKEN).superMint(address(this), amount_);
        ISuperToken(SUPER_TOKEN).upgrade(amount_);
        SUPER_TOKEN.safeTransfer(to_, amount_);
    }

    function mintAmount() external view returns (uint256) {
        return MintableERC20(TOKEN).mintAmount();
    }

    function cooldown() external view returns (uint256) {
        return MintableERC20(TOKEN).cooldown();
    }

    function nextMintAllowedAt(address user_) external view returns (uint256) {
        return MintableERC20(TOKEN).lastMintedAt(user_) + MintableERC20(TOKEN).cooldown();
    }
}
