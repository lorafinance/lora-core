// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {ISuperfluid} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {Faucet} from "src/testnet/Faucet.sol";
import {MintableERC20} from "src/testnet/MintableERC20.sol";

contract FaucetTest is Test {
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant OWEN = address(0x0E11);

    ISuperfluid superfluidHost;
    Faucet faucet;

    function setUp() public {
        superfluidHost = ISuperfluid(vm.envAddress("SUPERFLUID_TEST_HOST_ADDRESS"));
        vm.createSelectFork(vm.envString("SUPERFLUID_TEST_RPC_URL"));

        faucet = new Faucet("Test Token", "TTK", 18, 1 ether, 1 days, address(superfluidHost), OWEN);

        vm.startPrank(OWEN);
        faucet.grantRoles(ALICE, faucet.MINTER_ROLE());
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
    }

    function testConstructor() public view {
        MintableERC20 erc20 = MintableERC20(faucet.TOKEN());
        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());

        assertEq(faucet.owner(), OWEN);
        assertEq(erc20.owner(), OWEN);
        assertGt(faucet.TOKEN().code.length, 0);
        assertGt(faucet.SUPER_TOKEN().code.length, 0);
        assertEq(erc20.name(), "Test Token");
        assertEq(erc20.symbol(), "TTK");
        assertEq(erc20.decimals(), 18);
        assertEq(superToken.name(), "Super Test Token");
        assertEq(superToken.symbol(), "TTKx");
        assertEq(superToken.decimals(), 18);
        assertEq(erc20.mintAmount(), 1 ether);
        assertEq(erc20.cooldown(), 1 days);
        assertEq(faucet.mintAmount(), erc20.mintAmount());
        assertEq(faucet.cooldown(), erc20.cooldown());
        assertTrue(erc20.hasAnyRole(address(faucet), erc20.MINTER_ROLE()));
        assertTrue(erc20.hasAnyRole(address(faucet), erc20.SUPER_MINTER_ROLE()));
        assertTrue(erc20.hasAllRoles(address(faucet), erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
        assertFalse(erc20.hasAnyRole(address(this), erc20.MINTER_ROLE()));
        assertFalse(erc20.hasAnyRole(address(this), erc20.SUPER_MINTER_ROLE()));
        assertFalse(erc20.hasAllRoles(address(this), erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
        assertFalse(erc20.hasAnyRole(OWEN, erc20.MINTER_ROLE()));
        assertFalse(erc20.hasAnyRole(OWEN, erc20.SUPER_MINTER_ROLE()));
        assertFalse(erc20.hasAllRoles(OWEN, erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
        assertTrue(faucet.hasAnyRole(ALICE, erc20.MINTER_ROLE()));
        assertFalse(faucet.hasAnyRole(ALICE, erc20.SUPER_MINTER_ROLE()));
        assertFalse(faucet.hasAllRoles(ALICE, erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
        assertFalse(faucet.hasAnyRole(BOB, erc20.MINTER_ROLE()));
        assertFalse(faucet.hasAnyRole(BOB, erc20.SUPER_MINTER_ROLE()));
        assertFalse(faucet.hasAllRoles(BOB, erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
        assertFalse(faucet.hasAnyRole(OWEN, erc20.MINTER_ROLE()));
        assertFalse(faucet.hasAnyRole(OWEN, erc20.SUPER_MINTER_ROLE()));
        assertFalse(faucet.hasAllRoles(OWEN, erc20.MINTER_ROLE() | erc20.SUPER_MINTER_ROLE()));
    }

    function testMint() public {
        vm.prank(ALICE);
        faucet.mint();

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(ALICE), 1 ether);
    }

    function testMintFor() public {
        vm.prank(ALICE);
        faucet.mintFor(BOB);

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(BOB), 1 ether);
    }

    function testMintForAmount() public {
        vm.prank(ALICE);
        faucet.mintFor(BOB, 2 ether);

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(BOB), 2 ether);
    }

    function testMintFor_NotMinterRole() public {
        vm.startPrank(BOB);
        vm.expectRevert();
        faucet.mintFor(BOB);
        vm.stopPrank();
    }

    function testMintForAmount_NotMinterRole() public {
        vm.startPrank(BOB);
        vm.expectRevert();
        faucet.mintFor(BOB, 2 ether);
        vm.stopPrank();
    }

    function testSuperMint_Owner() public {
        vm.prank(OWEN);
        faucet.superMint(BOB, 5 ether);

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(BOB), 5 ether);
    }

    function testSuperMint_SuperMinterRole() public {
        vm.startPrank(OWEN);
        faucet.grantRoles(BOB, faucet.SUPER_MINTER_ROLE());
        vm.stopPrank();

        vm.prank(BOB);
        faucet.superMint(BOB, 5 ether);

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(BOB), 5 ether);
    }

    function testSuperMint_NotSuperMinterRole() public {
        vm.startPrank(BOB);
        vm.expectRevert();
        faucet.superMint(BOB, 5 ether);
        vm.stopPrank();
    }

    function testSuperMint_MinterRoleButNotSuperMinterRole() public {
        vm.startPrank(ALICE);
        vm.expectRevert();
        faucet.superMint(ALICE, 5 ether);
        vm.stopPrank();
    }

    function testMint_CooldownNotElapsed() public {
        vm.prank(ALICE);
        faucet.mint();

        vm.startPrank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                MintableERC20.CooldownNotElapsed.selector,
                block.timestamp,
                block.timestamp + faucet.cooldown(),
                faucet.cooldown()
            )
        );
        faucet.mint();
        vm.stopPrank();
    }

    function testMintMultipleMultipleUsers() public {
        vm.prank(ALICE);
        faucet.mint();
        vm.prank(BOB);
        faucet.mint();

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(ALICE), 1 ether);
        assertEq(superToken.balanceOf(BOB), 1 ether);
    }

    function testMintAfterCooldown() public {
        vm.prank(ALICE);
        faucet.mint();

        vm.warp(block.timestamp + faucet.cooldown() + 1);

        vm.prank(ALICE);
        faucet.mint();

        IERC20 superToken = IERC20(faucet.SUPER_TOKEN());
        assertEq(superToken.balanceOf(ALICE), 2 ether);
    }
}
