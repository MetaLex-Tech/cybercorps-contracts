// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CyberCorp} from "../src/CyberCorp.sol";
import {
    CompanyDirector,
    CompanyOfficer
} from "../src/CyberCorpConstants.sol";
import {IAuthAdapter} from "../src/interfaces/IAuthAdapter.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract BoardAuthorityAdapterMock is IAuthAdapter {
    mapping(address => uint256) internal roles;

    function setRole(address account, uint256 role) external {
        roles[account] = role;
    }

    function isAuthorized(
        address account
    ) external view returns (uint256) {
        return roles[account];
    }
}

contract CyberCorpBoardAuthorityTest is Test {
    address internal founder = address(0xF0);
    address internal officer = address(0x0F);
    address internal director = address(0xD1);
    address internal stockholderExecutor = address(0x57);

    BorgAuth internal auth;
    CyberCorp internal corp;

    function setUp() public {
        auth = new BorgAuth(address(this));
        auth.updateRole(founder, auth.OFFICER_ROLE());

        CompanyOfficer memory initialOfficer = CompanyOfficer({
            eoa: founder,
            name: "Founder",
            contact: "founder@example.com",
            title: "President"
        });
        corp = CyberCorp(
            address(
                new ERC1967Proxy(
                    address(new CyberCorp()),
                    abi.encodeCall(
                        CyberCorp.initialize,
                        (
                            address(auth),
                            "Test Corp, Inc.",
                            "Corporation",
                            "Delaware",
                            "contact@example.com",
                            "Delaware courts",
                            address(0x1),
                            address(0x2),
                            initialOfficer,
                            address(0x3),
                            address(0x4)
                        )
                    )
                )
            )
        );
        auth.updateRole(address(corp), auth.OFFICER_ROLE());
        auth.setRoleManager(address(corp));
        corp.activateBoardGovernance();
    }

    function test_ActivationSeatsFounderAsDirectorAndOfficer() public view {
        assertTrue(corp.boardGovernanceEnforced());
        assertTrue(corp.isCyberCORPDirector(founder));
        assertTrue(corp.isCyberCORPOfficer(founder));
        assertEq(corp.getCompanyDirectorCount(), 1);
        assertEq(corp.getCompanyOfficerCount(), 1);
        assertEq(auth.userRoles(founder), auth.BOARD_ROLE());
        assertEq(auth.roleManager(), address(corp));
    }

    function test_OfficerCannotMutateAuthOrAppointOfficers() public {
        vm.prank(founder);
        corp.addOfficer(_officer(officer));
        assertEq(auth.userRoles(officer), auth.OFFICER_ROLE());

        uint256 boardRole = auth.BOARD_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotRoleManager.selector,
                officer
            )
        );
        vm.prank(officer);
        auth.updateRole(officer, boardRole);

        vm.expectRevert();
        vm.prank(officer);
        corp.addOfficer(_officer(address(0x22)));
    }

    function test_BoardControlsOfficersAndLastOfficerGuard() public {
        vm.startPrank(founder);
        corp.addOfficer(_officer(officer));
        corp.removeOfficer(officer);
        assertEq(auth.userRoles(officer), 0);

        vm.expectRevert(CyberCorp.LastOfficer.selector);
        corp.removeOfficer(founder);
        vm.stopPrank();
    }

    function test_BoardSelfManagementPreservesOfficerRoleOnRemoval() public {
        vm.startPrank(founder);
        corp.addOfficer(_officer(director));
        corp.addDirector(_director(director));
        assertEq(auth.userRoles(director), auth.BOARD_ROLE());

        corp.removeDirector(director);
        assertFalse(corp.isCyberCORPDirector(director));
        assertTrue(corp.isCyberCORPOfficer(director));
        assertEq(auth.userRoles(director), auth.OFFICER_ROLE());

        vm.expectRevert(CyberCorp.LastDirector.selector);
        corp.removeDirector(founder);
        vm.stopPrank();
    }

    function test_StockholderAdapterCanExecuteBoardReplacement() public {
        BoardAuthorityAdapterMock adapter =
            new BoardAuthorityAdapterMock();
        adapter.setRole(stockholderExecutor, auth.BOARD_ROLE());

        vm.prank(founder);
        corp.setBoardAuthorityAdapter(address(adapter));

        vm.prank(stockholderExecutor);
        corp.addDirector(_director(director));
        assertTrue(corp.isCyberCORPDirector(director));
        assertEq(auth.userRoles(director), auth.BOARD_ROLE());
    }

    function test_RootConfigurationIsBoardOnlyWhenEnforced() public {
        vm.prank(founder);
        corp.addOfficer(_officer(officer));

        uint256 boardRole = auth.BOARD_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                boardRole,
                officer
            )
        );
        vm.prank(officer);
        corp.setCompanyPayable(address(0xCAFE));

        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                boardRole,
                officer
            )
        );
        vm.prank(officer);
        corp.setIssuanceManager(address(0xBEEF));

        vm.prank(founder);
        corp.setCompanyPayable(address(0xCAFE));
        assertEq(corp.companyPayable(), address(0xCAFE));
    }

    function test_RoleManagerLockIsOneWay() public {
        vm.expectRevert(BorgAuth.BorgAuth_RoleManagerAlreadySet.selector);
        auth.setRoleManager(address(0x999));
    }

    function _officer(
        address account
    ) internal pure returns (CompanyOfficer memory) {
        return CompanyOfficer({
            eoa: account,
            name: "Officer",
            contact: "officer@example.com",
            title: "Secretary"
        });
    }

    function _director(
        address account
    ) internal pure returns (CompanyDirector memory) {
        return CompanyDirector({
            eoa: account,
            name: "Director",
            contact: "director@example.com"
        });
    }
}
