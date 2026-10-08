// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuthV2} from "../src/BorgAuthV2.sol";

import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer} from "../src/interfaces/ILedgerEntryToken.sol";
import {CorporateAuth} from "../src/libs/CorporateAuth.sol";
import {BorgAuth, BorgAuthACL} from "../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Deliberately unrestricted test actor; never a production board implementation.
contract CorporateExecutor {
    function execute(address target, bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory result) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        return result;
    }
}

contract CorporateAuthTest is Test {
    BorgAuthV2 internal auth;
    CyberCorp internal corp;
    CorporateExecutor internal board;
    address internal officer = address(0xA11CE);
    address internal director = address(0xD1);
    address internal stranger = address(0x5713);
    address internal issuanceManager;
    address internal dealManager;
    address internal roundManager;
    address public borgAuthImplementation;
    address public refImplementation;

    function getRefImplementation() external view returns (address) {
        return refImplementation;
    }

    function setUp() public {
        borgAuthImplementation = address(new BorgAuthV2());
        auth = BorgAuthV2(
            address(
                new ERC1967Proxy(
                    borgAuthImplementation,
                    abi.encodeCall(BorgAuthV2.initializeCorporate, (address(this), address(this)))
                )
            )
        );
        refImplementation = address(new CyberCorp());
        corp = CyberCorp(
            address(
                new ERC1967Proxy(
                    refImplementation,
                    abi.encodeCall(
                        CyberCorp.initialize,
                        (
                            address(auth),
                            "Company",
                            "Corp",
                            "DE",
                            "contact",
                            "dispute",
                            address(this),
                            address(this),
                            CompanyOfficer(officer, "Officer", "contact", "CEO"),
                            address(this),
                            address(0)
                        )
                    )
                )
            )
        );
        board = new CorporateExecutor();
        issuanceManager = address(new CorporateExecutor());
        dealManager = address(new CorporateExecutor());
        roundManager = address(new CorporateExecutor());
        auth.completeSetup(
            address(this), address(board), address(corp), officer, issuanceManager, dealManager, roundManager
        );
        auth.setMembership(director, CorporateAuth.DIRECTOR);
    }

    function testIndependentRolesAndUnknownPermissionDeny() public view {
        assertTrue(auth.hasPermission(CorporateAuth.SIGN_AS_OFFICER, officer));
        assertFalse(auth.hasPermission(CorporateAuth.MANAGE_OFFICERS, officer));
        assertFalse(auth.hasPermission(CorporateAuth.MANAGE_OFFICERS, director));
        assertFalse(auth.hasPermission(CorporateAuth.SIGN_AS_OFFICER, address(this)));
        assertFalse(auth.hasPermission(CorporateAuth.SIGN_AS_OFFICER, address(board)));
        assertFalse(auth.hasPermission(bytes32(uint256(123)), address(this)));
    }

    function testPermissionMatrix() public view {
        // Bit i of an expected mask is actor i: root, board, officer, director, IM, DM, RM, stranger.
        address[8] memory actors =
            [address(this), address(board), officer, director, issuanceManager, dealManager, roundManager, stranger];
        (bytes32[12] memory permissions, uint8[12] memory expected) = _permissionTable();

        for (uint256 p; p < permissions.length; ++p) {
            for (uint256 a; a < actors.length; ++a) {
                bool want = expected[p] & (1 << a) != 0;
                string memory label = string.concat("permission ", vm.toString(p), " actor ", vm.toString(a));
                assertEq(auth.hasPermission(permissions[p], actors[a]), want, label);
            }
        }
    }

    function testNoPermissionBeforeSetup() public {
        BorgAuthV2 fresh = BorgAuthV2(
            address(
                new ERC1967Proxy(
                    borgAuthImplementation,
                    abi.encodeCall(BorgAuthV2.initializeCorporate, (address(this), address(this)))
                )
            )
        );
        (bytes32[12] memory permissions,) = _permissionTable();
        address[3] memory others = [officer, address(board), stranger];

        for (uint256 p; p < permissions.length; ++p) {
            bool rootOnly =
                permissions[p] == CorporateAuth.CONFIGURE_PROTOCOL || permissions[p] == CorporateAuth.APPROVE_UPGRADE;
            assertEq(fresh.hasPermission(permissions[p], address(this)), rootOnly, "temporary root");
            for (uint256 a; a < others.length; ++a) {
                assertFalse(fresh.hasPermission(permissions[p], others[a]), "non-root before setup");
            }
        }
    }

    function testBoardManagesRosterAndRemovalPreservesDirector() public {
        CompanyOfficer memory added = CompanyOfficer(director, "Director officer", "contact", "CFO");
        board.execute(address(corp), abi.encodeCall(CyberCorp.addOfficer, (added)));
        assertTrue(corp.isCyberCORPOfficer(director));
        assertTrue(auth.hasRole(director, CorporateAuth.DIRECTOR | CorporateAuth.OFFICER));
        board.execute(address(corp), abi.encodeCall(CyberCorp.removeOfficer, (director)));
        assertFalse(corp.isCyberCORPOfficer(director));
        assertTrue(auth.hasRole(director, CorporateAuth.DIRECTOR));
    }

    function testOfficerCannotManagePeersOrEscalate() public {
        vm.startPrank(officer);
        vm.expectRevert();
        corp.addOfficer(CompanyOfficer(director, "Director", "", "Director"));
        vm.expectRevert();
        corp.removeOfficer(officer);
        vm.expectRevert();
        corp.removeOfficerAt(0);
        vm.expectRevert();
        corp.updateOfficer(0, CompanyOfficer(director, "Director", "", "CEO"));
        vm.expectRevert();
        auth.setMembership(officer, CorporateAuth.OFFICER | CorporateAuth.BOARD_EXECUTOR);
        vm.expectRevert();
        auth.setOfficerMembership(director, true);
        vm.expectRevert();
        auth.updateRole(officer, type(uint256).max);
        vm.expectRevert();
        auth.setRoleAdapter(99, address(board));
        vm.expectRevert();
        auth.initTransferOwnership(officer);
        vm.expectRevert();
        auth.acceptOwnership();
        vm.expectRevert();
        auth.zeroOwner();
        vm.expectRevert();
        auth.proposeRootTransfer(officer);
        vm.stopPrank();
    }

    function testRootCannotEditOfficerMembershipOutsideRoster() public {
        vm.expectRevert();
        auth.setMembership(officer, 0);
        vm.expectRevert();
        auth.setMembership(director, CorporateAuth.OFFICER);
        corp.addOfficer(CompanyOfficer(director, "Director", "", "CFO"));
        auth.setMembership(director, CorporateAuth.DIRECTOR | CorporateAuth.OFFICER);
        assertTrue(auth.hasRole(director, CorporateAuth.OFFICER | CorporateAuth.DIRECTOR));
    }

    function testConfigurationAndSigningSeparated() public {
        vm.prank(officer);
        corp.addEscrowedOfficerSignature(hex"1234");
        vm.prank(officer);
        vm.expectRevert();
        corp.setCompanyPayable(officer);
        vm.expectRevert();
        corp.addEscrowedOfficerSignature(hex"1234");
        corp.setCompanyPayable(officer);
        assertEq(corp.companyPayable(), officer);
    }

    function testRootTransferRequiresCurrentNomineeAndRevokesOldRoot() public {
        auth.proposeRootTransfer(director);
        auth.proposeRootTransfer(officer);
        vm.prank(director);
        vm.expectRevert();
        auth.acceptRootTransfer();
        vm.prank(officer);
        auth.acceptRootTransfer();
        assertEq(auth.rootAuthority(), officer);
        vm.expectRevert();
        auth.setMembership(director, 0);
        vm.prank(officer);
        auth.setMembership(director, 0);
    }

    function testRootTransferCancellation() public {
        auth.proposeRootTransfer(director);
        auth.proposeRootTransfer(address(0));
        vm.prank(director);
        vm.expectRevert();
        auth.acceptRootTransfer();
    }

    function testAuthUpgradeRequiresRootAndApprovedReleasePreservesState() public {
        address replacement = address(new BorgAuthV2());
        vm.expectRevert();
        auth.upgradeToAndCall(replacement, "");
        borgAuthImplementation = replacement;
        vm.prank(officer);
        vm.expectRevert();
        auth.upgradeToAndCall(replacement, "");
        address stableAddress = address(auth);
        auth.upgradeToAndCall(replacement, "");
        assertEq(address(corp.AUTH()), stableAddress);
        assertEq(auth.rootAuthority(), address(this));
        assertTrue(auth.hasRole(officer, CorporateAuth.OFFICER));
        assertTrue(auth.hasRole(director, CorporateAuth.DIRECTOR));
    }

    function testCorpUpgradeKeepsReferenceGateAndRequiresRoot() public {
        address replacement = address(new CyberCorp());
        vm.expectRevert();
        corp.upgradeToAndCall(replacement, "");
        refImplementation = replacement;
        vm.prank(officer);
        vm.expectRevert();
        corp.upgradeToAndCall(replacement, "");
        corp.upgradeToAndCall(replacement, "");
        assertEq(address(corp.AUTH()), address(auth));
        assertTrue(corp.isCyberCORPOfficer(officer));
    }

    function testInitializersAndBootstrapCannotReplay() public {
        vm.expectRevert();
        auth.initializeCorporate(address(this), address(this));
        vm.expectRevert();
        auth.initialize(officer);
        vm.expectRevert();
        BorgAuthV2(borgAuthImplementation).initializeCorporate(address(this), address(this));
        vm.expectRevert();
        auth.completeSetup(
            officer, address(board), address(corp), officer, address(board), address(board), address(board)
        );
    }

    function testLegacyNumericAuthStillWorks() public {
        BorgAuth legacy = new BorgAuth(address(this));
        legacy.updateRole(officer, 200);
        legacy.onlyRole(99, officer);
        assertEq(legacy.userRoles(officer), 200);
    }

    function testFuzzDirectorNeverInheritsOfficerOrRoot(address account) public {
        vm.assume(
            account != address(0) && account != officer && account != address(this) && account != address(board)
                && auth.memberships(account) == 0
        );
        auth.setMembership(account, CorporateAuth.DIRECTOR);
        assertFalse(auth.hasPermission(CorporateAuth.SIGN_AS_OFFICER, account));
        assertFalse(auth.hasPermission(CorporateAuth.APPROVE_UPGRADE, account));
        assertFalse(auth.hasPermission(CorporateAuth.CONFIGURE_PROTOCOL, account));
    }

    function _permissionTable() internal pure returns (bytes32[12] memory permissions, uint8[12] memory expected) {
        uint8 rootBit = 1 << 0;
        uint8 boardBit = 1 << 1;
        uint8 officerBit = 1 << 2;
        uint8 dealBit = 1 << 5;
        uint8 roundBit = 1 << 6;

        permissions = [
            CorporateAuth.CONFIGURE_PROTOCOL,
            CorporateAuth.APPROVE_UPGRADE,
            CorporateAuth.MANAGE_OFFICERS,
            CorporateAuth.SIGN_AS_OFFICER,
            CorporateAuth.COMPANY_OPERATIONS,
            CorporateAuth.MANAGE_DEALS,
            CorporateAuth.MANAGE_ROUNDS,
            CorporateAuth.TRANSFER_POLICY,
            CorporateAuth.MANAGE_SECURITY_CLASSES,
            CorporateAuth.ISSUE_SECURITIES,
            CorporateAuth.ADMINISTER_CERTIFICATES,
            keccak256("UNKNOWN_PERMISSION")
        ];
        expected = [
            rootBit,
            rootBit,
            rootBit | boardBit,
            officerBit,
            officerBit,
            officerBit,
            officerBit,
            officerBit,
            officerBit | dealBit | roundBit,
            officerBit | dealBit | roundBit,
            officerBit | dealBit | roundBit,
            0
        ];
    }
}
