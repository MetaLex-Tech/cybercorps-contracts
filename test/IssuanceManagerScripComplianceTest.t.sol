// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {TestableCyberScrip} from "./mock/TestableCyberScrip.sol";
import {MockTransferHook} from "./mock/MockTransferHook.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";

contract MockCertPrinterBasic {
    string private _name;
    string private _symbol;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => CertificateDetails) private _details;
    mapping(uint256 => uint256) private _reserved;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }

    function mockMintCert(uint256 id, address owner_, uint256 units) external {
        _owners[id] = owner_;
        _details[id].unitsRepresented = units;
    }

    function mockSetReserved(uint256 id, uint256 units) external { _reserved[id] = units; }

    function isVoided(uint256) external pure returns (bool) { return false; }
    function unitsReserved(uint256 id) external view returns (uint256) { return _reserved[id]; }
    function legalOwnerOf(uint256 id) external view returns (address) { return _owners[id]; }
    function getActiveCertificateDetails(uint256 id) external view returns (CertificateDetails memory) { return _details[id]; }
    function updateCertificateDetails(uint256 id, CertificateDetails calldata det) external { _details[id] = det; }
}

contract IssuanceManagerScripComplianceTest is Test {
    bytes32 private constant SALT = keccak256("IssuanceManagerScripComplianceTest");

    IssuanceManager public issuanceManager;
    IssuanceManagerFactory public imFactory;
    BorgAuth public auth;
    MockCertPrinterBasic public cert;
    TestableCyberScrip public scrip;
    MockTransferHook public allowHook;
    MockTransferHook public denyHook;

    address public admin;
    address public user1;
    address public user2;

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        auth = new BorgAuth(address(this));
        auth.updateRole(admin, auth.ADMIN_ROLE());

        imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        address(new IssuanceManager()),
                        address(new CyberCertPrinter()),
                        address(new TestableCyberScrip())
                    )
                )
            )
        );

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(0xC0DE),
            address(0xBEEF),
            address(imFactory)
        );

        cert = new MockCertPrinterBasic("Mock Cert", "MCRT");
        allowHook = new MockTransferHook();
        denyHook = new MockTransferHook();
        denyHook.setAllowTransfers(false);

        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](1);
        hooks[0] = ITransferRestrictionHook(address(allowHook));
        ICondition[] memory emptyConditions = new ICondition[](0);

        uint256[] memory emptyIds = new uint256[](0);
        address scripAddr = issuanceManager.deployCyberScrip(
            address(cert),
            hooks,
            emptyConditions,
            emptyConditions,
            0,
            1,
            1,
            emptyIds,
            false,
            true,
            true,
            true
        );
        scrip = TestableCyberScrip(scripAddr);

        cert.mockMintCert(0, user1, 100 ether);
        vm.prank(user1);
        issuanceManager.scripifyCert(address(cert), 0, 100 ether, address(0));
    }

    function test_scripifyCert_revertsWhenAmountExceedsFreeUnits() public {
        cert.mockMintCert(1, user1, 100 ether);
        cert.mockSetReserved(1, 60 ether); // only 40 free

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("AmountExceedsAvailableUnits()"));
        issuanceManager.scripifyCert(address(cert), 1, 41 ether, address(0));
    }

    function test_scripifyCert_succeedsUpToFreeUnits() public {
        cert.mockMintCert(2, user1, 100 ether);
        cert.mockSetReserved(2, 60 ether); // 40 free

        vm.prank(user1);
        issuanceManager.scripifyCert(address(cert), 2, 40 ether, address(0));

        CertificateDetails memory det = cert.getActiveCertificateDetails(2);
        assertEq(det.unitsRepresented, 60 ether);
    }

    function test_setScripRestrictionHooks_updatesHook() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));

        vm.prank(admin);
        issuanceManager.setScripRestrictionHooks(address(cert), newHooks);

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "RestrictedTransfer(string)",
                "Transfers disabled in mock hook"
            )
        );
        scrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_setScripFrozen_blocksTransfers() public {
        vm.prank(admin);
        issuanceManager.setScripFrozen(address(cert), user1, true);

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSignature("AccountFrozen(address)", user1)
        );
        scrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_forceScripTransfer_ignoresHookAndFreeze() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));
        vm.prank(admin);
        issuanceManager.setScripRestrictionHooks(address(cert), newHooks);

        vm.startPrank(admin);
        issuanceManager.setScripFrozen(address(cert), user1, true);
        issuanceManager.setScripFrozen(address(cert), user2, true);
        issuanceManager.forceScripTransfer(address(cert), user1, user2, 10 ether);
        vm.stopPrank();

        assertEq(scrip.balanceOf(user1), 90 ether);
        assertEq(scrip.balanceOf(user2), 10 ether);
    }

    function test_forceScripBurn_reducesBalance() public {
        vm.prank(admin);
        issuanceManager.forceScripBurn(address(cert), user1, 5 ether);
        assertEq(scrip.balanceOf(user1), 95 ether);
    }

    function test_disableScripForceTransfer_blocksForceTransfer() public {
        issuanceManager.disableScripForceTransfer(address(cert));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        issuanceManager.forceScripTransfer(address(cert), user1, user2, 1 ether);
    }

    function test_disableScripForceBurn_blocksForceBurn() public {
        issuanceManager.disableScripForceBurn(address(cert));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        issuanceManager.forceScripBurn(address(cert), user1, 1 ether);
    }

    function test_accessControl_onlyAdmin_onlyOwner() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));
        uint256 adminRole = auth.ADMIN_ROLE();
        uint256 ownerRole = auth.OWNER_ROLE();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "BorgAuth_NotAuthorized(uint256,address)",
                adminRole,
                user1
            )
        );
        issuanceManager.setScripRestrictionHooks(address(cert), newHooks);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "BorgAuth_NotAuthorized(uint256,address)",
                ownerRole,
                user1
            )
        );
        issuanceManager.disableScripFreeze(address(cert));
    }
}
