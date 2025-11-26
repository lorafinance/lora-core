// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ERC20} from "solady/tokens/ERC20.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

contract MintableERC20 is ERC20, OwnableRoles {
    uint256 public constant MINTER_ROLE = _ROLE_0;
    uint256 public constant SUPER_MINTER_ROLE = _ROLE_1;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public mintAmount;
    uint256 public cooldown;
    mapping(address user_ => uint256) public lastMintedAt;

    error CooldownNotElapsed(uint256 lastMintedAt, uint256 nextMintAllowedAt, uint256 cooldown);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 mintAmount_,
        uint256 cooldown_,
        address owner_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        mintAmount = mintAmount_;
        cooldown = cooldown_;

        _initializeOwner(owner_);
        _setRoles(msg.sender, MINTER_ROLE | SUPER_MINTER_ROLE);
    }

    function setMintAmount(uint256 newMintAmount_) external onlyOwner {
        mintAmount = newMintAmount_;
    }

    function setCooldown(uint256 newCooldown_) external onlyOwner {
        cooldown = newCooldown_;
    }

    function mint() external {
        _mintFor(msg.sender, mintAmount);
    }

    function mintFor(address to_) public onlyRoles(MINTER_ROLE) {
        _mintFor(to_, mintAmount);
    }

    function mintFor(address to_, uint256 amount_) public onlyRoles(MINTER_ROLE) {
        _mintFor(to_, amount_);
    }

    function mintFor(address for_, address to_, uint256 amount_) public onlyRoles(MINTER_ROLE) {
        _mintFor(for_, to_, amount_);
    }

    function mintFor(address for_, address to_) public onlyRoles(MINTER_ROLE) {
        _mintFor(for_, to_, mintAmount);
    }

    function superMint(address to_, uint256 amount_) external onlyRolesOrOwner(SUPER_MINTER_ROLE) {
        _mint(to_, amount_);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _mintFor(address to_, uint256 amount_) internal {
        _mintFor(to_, to_, amount_);
    }

    function _mintFor(address for_, address to_, uint256 amount_) internal {
        uint256 lastMinted = lastMintedAt[for_];
        uint256 nextMintAllowedAt = lastMinted + cooldown;
        if (block.timestamp < nextMintAllowedAt) {
            revert CooldownNotElapsed(lastMinted, nextMintAllowedAt, cooldown);
        }

        lastMintedAt[for_] = block.timestamp;
        _mint(to_, amount_);
    }
}
