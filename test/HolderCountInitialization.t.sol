// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {LedgerEntryTokenStorage} from "../src/storage/LedgerEntryTokenStorage.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract HolderCountHarness is LedgerEntryToken {
    constructor(address manager) {
        LedgerEntryTokenStorage.cyberCertStorage().issuanceManager = manager;
        LedgerEntryTokenStorage.cyberCertStorage().transferable = true;
    }

    function seedLegacy(address holder, uint256 id) external {
        _mint(holder, id);
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        s.holderTokenCount[holder] = 0;
        s.uniqueHolderCount = 0;
    }

    function burn(uint256 id) external { _burn(id); }

    function counts(address holder) external view returns (uint256, uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return (s.holderTokenCount[holder], s.uniqueHolderCount);
    }
}

contract HolderCountInitializationTest is Test {
    BorgAuth public AUTH;
    HolderCountHarness printer;
    address admin = address(0xA);
    address holder = address(0xB);

    function setUp() public {
        AUTH = new BorgAuth(address(this));
        AUTH.updateRole(admin, AUTH.ADMIN_ROLE());
        printer = new HolderCountHarness(address(this));
        printer.seedLegacy(holder, 1);
        printer.seedLegacy(holder, 2);
    }

    function test_AdminInitializesActualBalanceAndBurnsLegacyTokens() public {
        vm.expectRevert(stdError.arithmeticError);
        printer.burn(1);
        vm.prank(admin);
        printer.initializeHolderCount(holder);
        (uint256 balance, uint256 unique) = printer.counts(holder);
        assertEq(balance, 2);
        assertEq(unique, 1);
        printer.burn(1);
        (balance, unique) = printer.counts(holder);
        assertEq(balance, 1);
        assertEq(unique, 1);
        printer.burn(2);
        (balance, unique) = printer.counts(holder);
        assertEq(balance, 0);
        assertEq(unique, 0);
    }

    function test_ManagerCanInitializeButCannotOverwriteNonzeroCount() public {
        printer.initializeHolderCount(holder);
        vm.expectRevert(ILedgerEntryToken.HolderCountAlreadyInitialized.selector);
        printer.initializeHolderCount(holder);
    }

    function test_TransferToInitializedLegacyHolderKeepsCountsCorrect() public {
        address recipient = address(0xC);
        printer.seedLegacy(recipient, 3);
        printer.initializeHolderCount(holder);
        printer.initializeHolderCount(recipient);
        vm.startPrank(holder);
        printer.transferFrom(holder, recipient, 1);
        printer.transferFrom(holder, recipient, 2);
        vm.stopPrank();
        (uint256 balance, uint256 unique) = printer.counts(recipient);
        assertEq(balance, 3);
        assertEq(unique, 1);
        assertEq(printer.ownerOf(1), recipient);
        assertEq(printer.ownerOf(2), recipient);
    }

    function test_StrangerCannotInitialize() public {
        uint256 role = AUTH.ADMIN_ROLE();
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, role, address(0xBAD)));
        printer.initializeHolderCount(holder);
    }

    function test_EmptyHolderDoesNotIncreaseUniqueCount() public {
        printer.initializeHolderCount(address(0xC));
        printer.initializeHolderCount(address(0xC));
        (uint256 balance, uint256 unique) = printer.counts(address(0xC));
        assertEq(balance, 0);
        assertEq(unique, 0);
    }
}
