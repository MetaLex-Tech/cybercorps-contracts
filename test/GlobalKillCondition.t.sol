// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {GlobalKillCondition} from "../src/libs/conditions/GlobalKillCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {IERC165} from "openzeppelin-contracts/interfaces/IERC165.sol";

contract GlobalKillConditionTest is Test {
    BorgAuth internal auth;
    GlobalKillCondition internal kill;

    address internal admin;
    address internal coAdmin;
    address internal stranger;

    function setUp() public {
        admin = makeAddr("admin");
        coAdmin = makeAddr("coAdmin");
        stranger = makeAddr("stranger");

        auth = new BorgAuth(admin);

        vm.startPrank(admin);
        auth.updateRole(coAdmin, auth.OWNER_ROLE());
        vm.stopPrank();

        kill = new GlobalKillCondition(address(auth));
    }

    // ─── Kill vote logic ──────────────────────────────────────────────────────

    function test_defaultNotKilled() public view {
        assertFalse(kill.isKilled());
        assertEq(kill.killCount(), 0);
    }

    function test_ownerRaisesKill() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit GlobalKillCondition.KillRaised(admin);
        kill.raiseKill();

        assertTrue(kill.isKilled());
        assertEq(kill.killCount(), 1);
        assertTrue(kill.killVotes(admin));
    }

    function test_coOwnerRaisesKill() public {
        vm.prank(coAdmin);
        kill.raiseKill();

        assertTrue(kill.isKilled());
        assertEq(kill.killCount(), 1);
        assertTrue(kill.killVotes(coAdmin));
    }

    function test_bothRaise_countIsTwo() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(coAdmin);
        kill.raiseKill();

        assertEq(kill.killCount(), 2);
        assertTrue(kill.isKilled());
    }

    function test_ownerClears_coOwnerStillRaised() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(coAdmin);
        kill.raiseKill();

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit GlobalKillCondition.KillLowered(admin);
        kill.lowerKill();

        assertTrue(kill.isKilled());
        assertEq(kill.killCount(), 1);
        assertFalse(kill.killVotes(admin));
        assertTrue(kill.killVotes(coAdmin));
    }

    function test_bothClear_notKilled() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(coAdmin);
        kill.raiseKill();

        vm.prank(admin);
        kill.lowerKill();
        vm.prank(coAdmin);
        kill.lowerKill();

        assertFalse(kill.isKilled());
        assertEq(kill.killCount(), 0);
    }

    function test_raiseIdempotent() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(admin);
        kill.raiseKill();

        assertEq(kill.killCount(), 1);
    }

    function test_lowerIdempotent() public {
        vm.prank(admin);
        kill.lowerKill();

        assertEq(kill.killCount(), 0);
        assertFalse(kill.isKilled());
    }

    function test_lowerOnlyAffectsOwnVote() public {
        vm.prank(coAdmin);
        kill.raiseKill();

        vm.prank(admin);
        kill.lowerKill(); // admin had no vote raised

        assertEq(kill.killCount(), 1);
        assertTrue(kill.isKilled());
    }

    // ─── Access control ───────────────────────────────────────────────────────

    function test_strangerCannotRaise() public {
        bytes memory expectedErr = abi.encodeWithSelector(
            BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), stranger
        );
        vm.prank(stranger);
        vm.expectRevert(expectedErr);
        kill.raiseKill();
    }

    function test_strangerCannotLower() public {
        bytes memory expectedErr = abi.encodeWithSelector(
            BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), stranger
        );
        vm.prank(stranger);
        vm.expectRevert(expectedErr);
        kill.lowerKill();
    }

    // ─── ICondition ───────────────────────────────────────────────────────────

    function test_checkCondition_notKilled() public view {
        assertTrue(kill.checkCondition(address(0), bytes4(0), ""));
    }

    function test_checkCondition_killed() public {
        vm.prank(admin);
        kill.raiseKill();

        assertFalse(kill.checkCondition(address(0), bytes4(0), ""));
    }

    function test_checkCondition_ignoredParams() public {
        // Result depends only on kill state regardless of params
        assertTrue(kill.checkCondition(address(this), bytes4(keccak256("finalizeDeal(bytes32)")), abi.encode(bytes32(0))));

        vm.prank(admin);
        kill.raiseKill();

        assertFalse(kill.checkCondition(address(this), bytes4(keccak256("finalizeDeal(bytes32)")), abi.encode(bytes32(0))));
    }

    // ─── ITransferRestrictionHook ─────────────────────────────────────────────

    function test_transferAllowed_notKilled() public view {
        (bool allowed, string memory reason) = kill.checkTransferRestriction(address(0), address(1), 100, "");
        assertTrue(allowed);
        assertEq(reason, "");
    }

    function test_transferBlocked_oneVote() public {
        vm.prank(admin);
        kill.raiseKill();

        (bool allowed, string memory reason) = kill.checkTransferRestriction(address(0), address(1), 100, "");
        assertFalse(allowed);
        assertEq(reason, "Global kill switch active");
    }

    function test_transferAllowed_afterAllCleared() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(coAdmin);
        kill.raiseKill();

        vm.prank(admin);
        kill.lowerKill();
        vm.prank(coAdmin);
        kill.lowerKill();

        (bool allowed,) = kill.checkTransferRestriction(address(0), address(1), 100, "");
        assertTrue(allowed);
    }

    // ─── ERC165 ───────────────────────────────────────────────────────────────

    function test_supportsICondition() public view {
        assertTrue(kill.supportsInterface(type(ICondition).interfaceId));
    }

    function test_supportsIERC165() public view {
        assertTrue(kill.supportsInterface(type(IERC165).interfaceId));
    }

    // ─── Shared instance (one kill wired to deal + cert + scrip) ─────────────

    function test_shared_noKill_allPass() public view {
        // Simulates all three consumers reading from the same GlobalKillCondition
        assertTrue(kill.checkCondition(address(0), bytes4(0), ""));
        (bool certAllowed,) = kill.checkTransferRestriction(address(0), address(1), 1, ""); // cert (ERC721 tokenId=1)
        (bool scripAllowed,) = kill.checkTransferRestriction(address(0), address(1), 100, ""); // scrip (ERC20 amount=100)
        assertTrue(certAllowed);
        assertTrue(scripAllowed);
    }

    function test_shared_kill_allBlock() public {
        vm.prank(admin);
        kill.raiseKill();

        assertFalse(kill.checkCondition(address(0), bytes4(0), ""));
        (bool certAllowed,) = kill.checkTransferRestriction(address(0), address(1), 1, "");
        (bool scripAllowed,) = kill.checkTransferRestriction(address(0), address(1), 100, "");
        assertFalse(certAllowed);
        assertFalse(scripAllowed);
    }

    function test_shared_lower_allResume() public {
        vm.prank(admin);
        kill.raiseKill();
        vm.prank(admin);
        kill.lowerKill();

        assertTrue(kill.checkCondition(address(0), bytes4(0), ""));
        (bool certAllowed,) = kill.checkTransferRestriction(address(0), address(1), 1, "");
        (bool scripAllowed,) = kill.checkTransferRestriction(address(0), address(1), 100, "");
        assertTrue(certAllowed);
        assertTrue(scripAllowed);
    }

    // ─── Dedicated instances (one per target) ────────────────────────────────

    function test_dedicated_independent_state() public {
        GlobalKillCondition dealKill = new GlobalKillCondition(address(auth));
        GlobalKillCondition certKill = new GlobalKillCondition(address(auth));
        GlobalKillCondition scripKill = new GlobalKillCondition(address(auth));

        vm.prank(admin);
        dealKill.raiseKill();

        assertTrue(dealKill.isKilled());
        assertFalse(certKill.isKilled());
        assertFalse(scripKill.isKilled());
    }

    function test_dedicated_raiseCert_dealUnaffected() public {
        GlobalKillCondition dealKill = new GlobalKillCondition(address(auth));
        GlobalKillCondition certKill = new GlobalKillCondition(address(auth));

        vm.prank(admin);
        certKill.raiseKill();

        assertFalse(dealKill.isKilled());
        assertTrue(certKill.isKilled());
    }

    function test_dedicated_allCanBeRaisedIndependently() public {
        GlobalKillCondition dealKill = new GlobalKillCondition(address(auth));
        GlobalKillCondition certKill = new GlobalKillCondition(address(auth));
        GlobalKillCondition scripKill = new GlobalKillCondition(address(auth));

        vm.prank(admin);
        dealKill.raiseKill();
        vm.prank(admin);
        certKill.raiseKill();
        vm.prank(admin);
        scripKill.raiseKill();

        assertTrue(dealKill.isKilled());
        assertTrue(certKill.isKilled());
        assertTrue(scripKill.isKilled());

        vm.prank(admin);
        dealKill.lowerKill();

        assertFalse(dealKill.isKilled());
        assertTrue(certKill.isKilled());
        assertTrue(scripKill.isKilled());
    }
}
