// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MintableERC20} from "src/testnet/MintableERC20.sol";

contract MintableERC20Test is Test {
    address constant ALICE = address(0xA11CE);
    address constant OWEN = address(0x0E11);

    MintableERC20 token;

    function setUp() public {
        token = new MintableERC20("Test Token", "TTK", 18, 1 ether, 1 days, OWEN);
        vm.warp(block.timestamp + 2 days);
    }

    function testConstructor() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TTK");
        assertEq(token.decimals(), 18);
        assertEq(token.mintAmount(), 1 ether);
        assertEq(token.cooldown(), 1 days);
        assertEq(token.owner(), OWEN);
        assertTrue(token.hasAnyRole(address(this), token.MINTER_ROLE()));
        assertTrue(token.hasAnyRole(address(this), token.SUPER_MINTER_ROLE()));
        assertTrue(token.hasAllRoles(address(this), token.MINTER_ROLE() | token.SUPER_MINTER_ROLE()));
        assertFalse(token.hasAnyRole(ALICE, token.MINTER_ROLE()));
        assertFalse(token.hasAnyRole(ALICE, token.SUPER_MINTER_ROLE()));
        assertFalse(token.hasAllRoles(ALICE, token.MINTER_ROLE() | token.SUPER_MINTER_ROLE()));
        assertFalse(token.hasAnyRole(OWEN, token.MINTER_ROLE()));
        assertFalse(token.hasAnyRole(OWEN, token.SUPER_MINTER_ROLE()));
        assertFalse(token.hasAllRoles(OWEN, token.MINTER_ROLE() | token.SUPER_MINTER_ROLE()));
    }

    function testMint() public {
        vm.prank(ALICE);
        token.mint();
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function testMintFor() public {
        token.mintFor(ALICE);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function testMintForAmount() public {
        token.mintFor(ALICE, 2 ether);
        assertEq(token.balanceOf(ALICE), 2 ether);
    }

    function testSuperMint() public {
        token.superMint(ALICE, 5 ether);
        assertEq(token.balanceOf(ALICE), 5 ether);
    }

    function testMintFor_NotMinterRole() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        token.mintFor(ALICE);
        vm.stopPrank();
    }

    function testMintForAmount_NotMinterRole() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        token.mintFor(ALICE, 2 ether);
        vm.stopPrank();
    }

    function testSuperMint_NotSuperMinterRole() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        token.superMint(ALICE, 5 ether);
        vm.stopPrank();
    }

    function testSuperMint_MinterRoleButNotSuperMinterRole() public {
        vm.startPrank(OWEN);
        token.grantRoles(ALICE, token.MINTER_ROLE());
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert();
        token.superMint(address(this), 5 ether);
        vm.stopPrank();
    }

    function testOwnerCanSuperMint() public {
        vm.prank(OWEN);
        token.superMint(ALICE, 3 ether);
        assertEq(token.balanceOf(ALICE), 3 ether);
    }

    function testMint_CooldownNotElapsed() public {
        vm.prank(ALICE);
        token.mint();
        assertEq(token.balanceOf(ALICE), 1 ether);

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                MintableERC20.CooldownNotElapsed.selector,
                block.timestamp,
                block.timestamp + token.cooldown(),
                token.cooldown()
            )
        );
        token.mint();
        vm.stopPrank();
    }

    function testSetMintAmount() public {
        vm.prank(OWEN);
        token.setMintAmount(2 ether);
        assertEq(token.mintAmount(), 2 ether);
    }

    function testSetCooldown() public {
        vm.prank(OWEN);
        token.setCooldown(2 days);
        assertEq(token.cooldown(), 2 days);
    }

    function testSetMintAmount_NotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        token.setMintAmount(2 ether);
    }

    function testSetCooldown_NotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        token.setCooldown(2 days);
    }
}

