// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {TestableCyberScrip} from "./mock/TestableCyberScrip.sol";
import {MockTransferHook} from "./mock/MockTransferHook.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";

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

    event MaxHolderCountUpdated(uint256 maxHolderCount);

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
                        address(new LedgerEntryToken()),
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

    function test_setRestrictionHook_updatesHook() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));

        vm.prank(admin);
        scrip.setRestrictionHook(newHooks);

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

    function test_setFrozen_blocksTransfers() public {
        vm.prank(admin);
        scrip.setFrozen(user1, true);

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSignature("AccountFrozen(address)", user1)
        );
        scrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_setMaxHolderCount_capIsEnforcedWhenSetByAdmin() public {
        // user1 is the sole holder after setUp
        vm.expectEmit(false, false, false, true, address(scrip));
        emit MaxHolderCountUpdated(1);
        vm.prank(admin);
        scrip.setMaxHolderCount(1);
        assertEq(scrip.maxHolderCount(), 1);

        // a partial transfer would create a second holder
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("HolderLimitExceeded(uint256)", 1));
        scrip.transfer(user2, 1 ether);

        // raising the cap through the same path lifts the restriction
        vm.prank(admin);
        scrip.setMaxHolderCount(2);

        vm.prank(user1);
        scrip.transfer(user2, 1 ether);
        assertEq(scrip.balanceOf(user2), 1 ether);
    }

    function test_setMaxHolderCount_callableByIssuanceManager() public {
        vm.prank(address(issuanceManager));
        scrip.setMaxHolderCount(5);
        assertEq(scrip.maxHolderCount(), 5);
    }

    function test_setMaxHolderCount_revertsForNonAdmin() public {
        uint256 adminRole = auth.ADMIN_ROLE();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "BorgAuth_NotAuthorized(uint256,address)",
                adminRole,
                user1
            )
        );
        scrip.setMaxHolderCount(1);
    }

    function test_forceScripBurn_callableViaInterface() public {
        vm.prank(admin);
        IIssuanceManager(address(issuanceManager)).forceScripBurn(address(cert), user1, 5 ether);
        assertEq(scrip.balanceOf(user1), 95 ether);
    }

    function test_forceTransfer_ignoresHookAndFreeze() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));

        vm.startPrank(admin);
        scrip.setRestrictionHook(newHooks);
        scrip.setFrozen(user1, true);
        scrip.setFrozen(user2, true);
        scrip.forceTransfer(user1, user2, 10 ether);
        vm.stopPrank();

        assertEq(scrip.balanceOf(user1), 90 ether);
        assertEq(scrip.balanceOf(user2), 10 ether);
    }

    function test_forceScripBurn_reducesBalance() public {
        vm.prank(admin);
        issuanceManager.forceScripBurn(address(cert), user1, 5 ether);
        assertEq(scrip.balanceOf(user1), 95 ether);
    }

    function test_disableForceTransfer_blocksForceTransfer() public {
        scrip.disableForceTransfer();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        scrip.forceTransfer(user1, user2, 1 ether);
    }

    function test_disableForceBurn_blocksForceBurn() public {
        scrip.disableForceBurn();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        issuanceManager.forceScripBurn(address(cert), user1, 1 ether);
    }

    function test_accessControl_onlyAdmin() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(denyHook));
        bytes memory notAdmin = abi.encodeWithSignature(
            "BorgAuth_NotAuthorized(uint256,address)",
            auth.ADMIN_ROLE(),
            user1
        );

        vm.prank(user1);
        vm.expectRevert(notAdmin);
        scrip.setRestrictionHook(newHooks);

        vm.prank(user1);
        vm.expectRevert(notAdmin);
        scrip.setFrozen(user2, true);

        vm.prank(user1);
        vm.expectRevert(notAdmin);
        scrip.forceTransfer(user1, user2, 1 ether);

        vm.prank(user1);
        vm.expectRevert(notAdmin);
        scrip.disableFreeze();

        vm.prank(user1);
        vm.expectRevert(notAdmin);
        issuanceManager.forceScripBurn(address(cert), user1, 1 ether);
    }
}
