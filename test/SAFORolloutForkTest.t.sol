// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CertificateDetails} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SAFOData, SAFOExtension} from "../src/storage/extensions/SAFOExtension.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {SAFOIntegrationTest} from "./SAFOIntegrationTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

/// @notice Executes the existing signed Reg D/S ticket and round acceptance cases against
/// the actual forked factories, registry, reused libraries and proposed rollout bytecode.
/// The operator harness deploys/upgrades/registers on loopback Anvil before this suite.
/// No source-deployed manager, extension, payment token or registry replaces the targets.
contract SAFORolloutForkTest is SAFOIntegrationTest {
    bytes32 internal constant EXPECTED_FIELDS_HASH = 0xceb721acf3de8f04d17e2a834720641b45febaa61f0ec733d5556bf7b5cfbf15;
    string internal plan;

    function setUp() public override {
        string memory path = vm.envOr("SAFO_PLAN", string(""));
        if (bytes(path).length == 0) {
            vm.skip(true);
            return;
        }
        plan = vm.readFile(path);
        assertEq(block.chainid, vm.parseJsonUint(plan, ".chainId"));
        registry = CyberAgreementRegistry(vm.parseJsonAddress(plan, ".targets.registry"));
        companyFactory = CyberCorpFactory(vm.parseJsonAddress(plan, ".targets.factory"));
        extension = SAFOExtension(vm.parseJsonAddress(plan, ".addresses.SAFOExtensionProxy"));
        assertEq(address(extension.AUTH()), vm.parseJsonAddress(plan, ".before.auth"));
        usdc = MockPaymentToken(companyFactory.stable());
        assertEq(address(usdc), vm.parseJsonAddress(plan, ".before.paymentToken"));
        assertEq(usdc.decimals(), 6);
        officer = vm.addr(OFFICER_KEY);
        investor = vm.addr(INVESTOR_KEY);
        // These published fixture keys can carry live EIP-7702 delegations. Clear
        // only the two synthetic accounts inside this disposable fork.
        vm.etch(officer, hex"");
        vm.etch(investor, hex"");
        // Test fixture funding changes token storage only inside the disposable fork.
        deal(address(usdc), investor, 20_000e6);
        address rm;
        address dm;
        (corp,,, dm, rm) =
            CyberCorpHelper.deployCorp(companyFactory, "TEST ONLY SAFO rollout acceptance", officer, officer);
        dealManager = DealManager(dm);
        manager = RoundManager(rm);
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(address(uint160(uint256(vm.load(dm, slot)))), vm.parseJsonAddress(plan, ".addresses.DealManager"));
        assertEq(address(uint160(uint256(vm.load(rm, slot)))), vm.parseJsonAddress(plan, ".addresses.RoundManager"));
        vm.prank(investor);
        usdc.approve(rm, type(uint256).max);
        vm.prank(investor);
        usdc.approve(dm, type(uint256).max);
        SAFOData memory terms;
        terms.schemaVersion = 1;
        terms.minProjectReserve = 200_000;
        terms.maxUnlockingCliffPeriod = 365 days;
        terms.maxUnlockingPeriod = 4 * 365 days;
        terms.outsideDateEnabled = true;
        terms.outsideDate = 0;
        payload = extension.encodeExtensionData(terms);
    }

    function test_RejectsInvestorWithNonReceiverCode() public {
        vm.etch(investor, hex"60006000fd");
        (bool success, bytes memory result) =
            address(this).call(abi.encodeCall(this.test_RegD_TicketSignPayFinalizePreservesOriginalIssueDate, ()));
        assertFalse(success);
        assertEq(bytes4(result), bytes4(keccak256("ERC721InvalidReceiver(address)")));
    }

    /// @dev Diagnostic only: a passing reproduction is an OPEN release blocker, not acceptance.
    function test_Diagnostic_F295271_RegDCoOwnerChangesNativeSafoPayment() public {
        _reproduceChangedNativePayment(false);
    }

    function test_Diagnostic_F295271_RegSCoOwnerChangesNativeSafoPayment() public {
        _reproduceChangedNativePayment(true);
    }

    function _reproduceChangedNativePayment(bool regS) internal {
        bytes32 template = _template(regS);
        IssuanceManager im = IssuanceManager(address(dealManager.issuanceManager()));
        vm.prank(officer);
        address printer = im.createCertPrinter(
            new string[](0),
            "SAFO diagnostic",
            "SAFO",
            "ipfs://test-only",
            SecurityClass.SAFO,
            SecuritySeries.SeriesSeed,
            address(extension),
            hex""
        );
        address[] memory printers = new address[](1);
        printers[0] = printer;
        string[] memory globals = _globals("10000");
        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        string[][] memory values = new string[][](2);
        values[0] = new string[](5);
        values[1] = new string[](5);
        values[0][0] = "Officer";
        values[1][0] = "Investor";
        (string memory uri,, string[] memory fields, string[] memory partyFields) =
            registry.getTemplateDetails(template);
        bytes32 id = keccak256(abi.encode(template, uint256(111), globals, parties, bytes32(0), address(dealManager)));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            id,
            uri,
            fields,
            partyFields,
            globals,
            values[0],
            OFFICER_KEY
        );
        CertificateDetails[] memory certs = new CertificateDetails[](1);
        certs[0] = CertificateDetails("Officer", "CEO", 10000e18, 1000000e18, 10000e18, "", payload);
        address coOwner = address(0xC0);
        BorgAuth auth = dealManager.AUTH();
        uint256 role = auth.OWNER_ROLE();
        vm.prank(corp);
        auth.updateRole(coOwner, role);
        vm.prank(coOwner);
        (bytes32 actualId,) = dealManager.proposeAndSignDeal(
            printers,
            address(usdc),
            20000e6,
            template,
            111,
            globals,
            parties,
            certs,
            officer,
            signature,
            values,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days
        );
        assertEq(actualId, id);
        assertTrue(registry.hasSigned(id, officer));
        assertEq(dealManager.getEscrowDetails(id).buyerAssets[0].amount, 20000e6);
        assertEq(globals[0], "10000");
    }

    function _template(bool regS) internal view override returns (bytes32 id) {
        id = regS ? bytes32("mlx_safo_reg_s_v1_1") : bytes32("mlx_safo_reg_d_v1_1");
        (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
            registry.getTemplateDetails(id);
        assertEq(
            uri,
            regS
                ? "ipfs://bafybeihq7knnav6watytknp7yf6bm4wsnkzlvsiqoey4kanisbn3x5gf5i"
                : "ipfs://bafybeiapwuvzzumyoaxpglczsu2kmlxmor6arvl6337pfnbcguvit2sqsu"
        );
        assertEq(title, regS ? "mlx_safo_reg_s_v1_1" : "mlx_safo_reg_d_v1_1");
        _validateRegisteredFields(globals, parties);
    }

    function assertRegisteredTemplate(bool regS) external view {
        _template(regS);
    }

    function _validateRegisteredFields(string[] memory globals, string[] memory parties) internal pure {
        // keccak256(abi.encode(globalFields, partyFields)) from the approved
        // templates/releases/safo-v1.1.json, identical for Reg D and Reg S.
        require(keccak256(abi.encode(globals, parties)) == EXPECTED_FIELDS_HASH, "Unapproved SAFO fields/order");
    }

    function test_RejectsOmittedSubstitutedOrReorderedRegisteredFields() public {
        for (uint256 variant; variant < 2; variant++) {
            bool regS = variant == 1;
            bytes32 id = _template(regS);
            for (uint256 mutation; mutation < 3; mutation++) {
                (string memory uri, string memory title, string[] memory globals, string[] memory parties) =
                    registry.getTemplateDetails(id);
                if (mutation == 0) globals[5] = "";
                if (mutation == 1) parties[0] = "unapprovedField";
                if (mutation == 2) (globals[0], globals[1]) = (globals[1], globals[0]);
                vm.mockCall(
                    address(registry),
                    abi.encodeCall(registry.getTemplateDetails, (id)),
                    abi.encode(uri, title, globals, parties)
                );
                vm.expectRevert(bytes("Unapproved SAFO fields/order"));
                this.assertRegisteredTemplate(regS);
                vm.clearMockedCalls();
            }
        }
    }

    function _configureFactoryStable() internal view override {
        assertEq(companyFactory.stable(), address(usdc));
    }
}
