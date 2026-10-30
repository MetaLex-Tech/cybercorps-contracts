// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;
import {ICyberAgreementRegistry} from "../src/interfaces/ICyberAgreementRegistry.sol";
import {CompanyOfficer, CyberCertData, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CertificateDetails} from "../src/interfaces/ILedgerEntryToken.sol";
import {CorpFactoryMetadataLib} from "../src/libs/CorpFactoryMetadataLib.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Escrow, Token} from "../src/storage/LexScrowStorage.sol";
import {EOI} from "../src/storage/RoundManagerStorage.sol";
import {SAFOData, SAFOExtension} from "../src/storage/extensions/SAFOExtension.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

contract SAFOIntegrationTest is Test {
    using RoundLib for Round;
    uint256 constant OFFICER_KEY = 0xCAD;
    uint256 constant INVESTOR_KEY = 0xA11CE;
    ICyberAgreementRegistry registry;
    CyberCorpFactory companyFactory;
    RoundManager manager;
    DealManager dealManager;
    MockPaymentToken usdc;
    SAFOExtension extension;
    address corp;
    address officer;
    address investor;
    bytes payload;

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        officer = vm.addr(OFFICER_KEY);
        investor = vm.addr(INVESTOR_KEY);
        CyberCorpFactory factory;
        (registry, factory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(address(this));
        companyFactory = factory;
        address rm;
        address dm;
        (corp,,, dm, rm) = CyberCorpHelper.deployCorp(factory, "SAFO Company", officer, officer);
        dealManager = DealManager(dm);
        manager = RoundManager(rm);
        usdc = new MockPaymentToken();
        usdc.transfer(investor, 20_000e6);
        vm.prank(investor);
        usdc.approve(rm, type(uint256).max);
        vm.prank(investor);
        usdc.approve(dm, type(uint256).max);
        extension = SAFOExtension(
            address(
                new ERC1967Proxy(
                    address(new SAFOExtension()),
                    abi.encodeCall(SAFOExtension.initialize, (address(new BorgAuth(address(this)))))
                )
            )
        );
        SAFOData memory terms;
        terms.schemaVersion = 1;
        terms.minProjectReserve = 200_000;
        terms.maxUnlockingCliffPeriod = 365 days;
        terms.maxUnlockingPeriod = 4 * 365 days;
        terms.outsideDateEnabled = true;
        terms.outsideDate = 0; // enabled-zero is intentionally preserved
        payload = extension.encodeExtensionData(terms);
    }

    function _template(bool regS) internal virtual returns (bytes32 id) {
        id = regS ? bytes32("mlx_safo_reg_s_v1_0") : bytes32("mlx_safo_reg_d_v1_0");
        string[19] memory ordered = [
            "purchaseAmount",
            "projectValuation",
            "governingJurisdiction",
            "disputeResolution",
            "schemaVersion",
            "minProjectReserve",
            "maxUnlockingCliffPeriod",
            "maxUnlockingPeriod",
            "requiresTokenholderGovernance",
            "outsideDateEnabled",
            "outsideDate",
            "hasUnlockParameters",
            "unlockStartTimeType",
            "unlockStartTime",
            "unlockingPeriod",
            "unlockingCliffPeriod",
            "unlockingCliffPercentage",
            "unlockingIntervalType",
            "customProvisions"
        ];
        string[] memory fields = new string[](19);
        for (uint256 i; i < 19; i++) {
            fields[i] = ordered[i];
        }
        string[] memory parties = new string[](5);
        parties[0] = "name";
        parties[1] = "evmAddress";
        parties[2] = "contactDetails";
        parties[3] = "investorType";
        parties[4] = "investorJurisdiction";
        registry.createTemplate(
            id,
            regS ? "SAFO Reg S" : "SAFO Reg D",
            regS ? "ipfs://reg-s-local-fixture" : "ipfs://reg-d-local-fixture",
            fields,
            parties
        );
    }

    function _round(bytes32 template, RoundType kind) internal returns (bytes32 id) {
        (bytes memory signature,) = CyberCorpHelper.computeEscrowSignature(
            address(manager),
            SecuritySeries.SeriesSeed,
            100_000e6,
            100e6,
            10_000e6,
            kind,
            block.timestamp,
            block.timestamp + 30 days,
            template,
            address(usdc),
            1e18,
            1_000_000e18,
            OFFICER_KEY,
            corp
        );
        CyberCertData[] memory printers = new CyberCertData[](1);
        printers[0] = CyberCertData({
            name: "SAFO",
            symbol: "SAFO",
            uri: "ipfs://safo-local-fixture",
            securityClass: SecurityClass.SAFO,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(extension),
            seriesData: hex"",
            defaultLegend: new string[](0)
        });
        bytes[] memory extensions = new bytes[](1);
        extensions[0] = payload;
        vm.prank(officer);
        id = manager.createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesSeed,
                    kind,
                    false,
                    true,
                    false,
                    100_000e6,
                    100e6,
                    10_000e6,
                    address(usdc),
                    1e18,
                    1_000_000e18,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    template,
                    officer,
                    "Officer",
                    "CEO",
                    new string[](1),
                    new string[](5),
                    extensions,
                    new address[](0),
                    signature
                ),
            printers
        );
        assertEq(uint8(manager.getRound(id).primarySecurityClass), 14);
    }

    function _globals(string memory principal) internal pure returns (string[] memory globals) {
        globals = new string[](19);
        globals[0] = principal;
        globals[1] = "1000000";
        globals[2] = "Delaware";
        globals[3] = "Arbitration";
        globals[4] = "1";
        globals[5] = "200000";
        globals[6] = "31536000";
        globals[7] = "126144000";
        globals[8] = "false";
        globals[9] = "true";
        globals[10] = "0";
        globals[11] = "false";
        for (uint256 i = 12; i < 18; i++) {
            globals[i] = "0";
        }
    }

    function _subscribe(bytes32 template, bytes32 round, bool regS) internal returns (bytes32 agreement) {
        EOI memory eoi = EOI({
            name: "Investor",
            investorType: "Individual",
            jurisdiction: regS ? "GB" : "US",
            contact: "investor@example.com",
            minAmount: 5000e6,
            maxAmount: 10000e6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        string[] memory globals = _globals("between 5000 and 10000 USD");
        string[] memory parties = new string[](5);
        parties[0] = "Investor";
        parties[1] = vm.toString(investor);
        parties[2] = "investor@example.com";
        parties[3] = "Individual";
        parties[4] = regS ? "GB" : "US";
        bytes memory signature = CyberCorpHelper.computeEOISignature(
            registry, template, 1, globals, parties, officer, INVESTOR_KEY, address(manager), eoi.expiry, bytes32(0)
        );
        vm.prank(investor);
        (agreement,) = manager.submitEOI(round, eoi, globals, parties, signature, 1, new address[](0), bytes32(0));
    }

    function _allocation(bool regS) internal {
        bytes32 template = _template(regS);
        bytes32 round = _round(template, RoundType.FounderApproved);
        bytes32 agreement = _subscribe(template, round, regS);
        uint256 beforeRefund = usdc.balanceOf(investor);
        vm.warp(block.timestamp + 2 days);
        vm.prank(officer);
        manager.allocate(agreement, 7500e6);
        Escrow memory escrow = manager.getEscrowDetails(agreement);
        assertEq(escrow.corpAssets.length, 1);
        Token memory token = escrow.corpAssets[0];
        LedgerEntryToken printer = LedgerEntryToken(token.tokenAddress);
        CertificateDetails memory details = printer.getCertificateDetails(token.tokenId);
        assertEq(printer.ownerOf(token.tokenId), investor);
        assertEq(uint8(printer.securityType()), 14);
        assertEq(details.investmentAmountUSD, 7500e18);
        assertEq(details.issuerUSDValuationAtTimeOfInvestment, 1_000_000e18);
        assertEq(details.unitsRepresented, 7500e18);
        assertEq(details.extensionData, payload);
        assertEq(printer.issueTimestamp(token.tokenId), block.timestamp);
        assertEq(usdc.balanceOf(investor) - beforeRefund, 2500e6);
        assertEq(extension.decodeExtensionData(details.extensionData).outsideDate, 0);
        assertTrue(extension.decodeExtensionData(details.extensionData).outsideDateEnabled);
        assertGt(bytes(printer.tokenURI(token.tokenId)).length, 0);
        vm.expectRevert();
        vm.prank(officer);
        manager.allocate(agreement, 7500e6);
    }

    function test_RegD_AllocationUsesGrossActualPrincipalAndRefundsRemainder() public {
        _allocation(false);
    }

    function test_RegS_AllocationUsesGrossActualPrincipalAndRefundsRemainder() public {
        _allocation(true);
    }

    /// @dev Fork suites keep the real factory payment asset and override this fixture-only setter.
    function _configureFactoryStable() internal virtual {
        companyFactory.setStable(address(usdc));
    }

    function _ticket(bool regS, bool newCompany) internal {
        CompanyOfficer memory officerInfo = CompanyOfficer(officer, "Officer", "officer@example.com", "CEO");
        if (newCompany) {
            bytes32 deploySalt = companyFactory.computeDeploymentSalt(
                keccak256(abi.encodePacked(uint256(42))),
                "New SAFO Ticket Company",
                "corporation",
                "DE",
                "contact",
                "arbitration",
                officer,
                officerInfo
            );
            dealManager = DealManager(
                DealManagerFactory(companyFactory.dealManagerFactory())
                    .computeDealManagerAddress(deploySalt, address(companyFactory))
            );
            _configureFactoryStable();
            vm.prank(investor);
            usdc.approve(address(dealManager), type(uint256).max);
        }
        bytes32 template = _template(regS);
        string[] memory globals = _globals("10000");
        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        string[][] memory values = new string[][](2);
        values[0] = new string[](5);
        values[1] = new string[](5);
        values[0][0] = "Officer";
        values[0][1] = vm.toString(officer);
        values[0][2] = "officer@example.com";
        values[0][3] = "CEO";
        values[0][4] = "DE";
        values[1][0] = "Investor";
        values[1][1] = vm.toString(investor);
        values[1][2] = "investor@example.com";
        values[1][3] = "Individual";
        values[1][4] = regS ? "GB" : "US";
        (string memory uri,, string[] memory fields, string[] memory partyFields) =
            registry.getTemplateDetails(template);
        bytes32 id = keccak256(abi.encode(template, uint256(42), globals, parties, bytes32(0), address(dealManager)));
        bytes memory officerSignature = CyberAgreementUtils.signAgreementTypedData(
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
        CyberCertData[] memory printers = new CyberCertData[](1);
        printers[0] = CyberCertData({
            name: "SAFO",
            symbol: "SAFO",
            uri: "ipfs://safo-local-fixture",
            securityClass: SecurityClass.SAFO,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(extension),
            seriesData: hex"",
            defaultLegend: new string[](0)
        });
        CertificateDetails[] memory certs = new CertificateDetails[](1);
        certs[0] = CertificateDetails("Officer", "CEO", 10000e18, 1000000e18, 10000e18, "", payload);
        uint256 proposalTime = vm.getBlockTimestamp();
        address[] memory addresses;
        bytes32 actualId;
        uint256[] memory ids;
        vm.prank(officer);
        if (newCompany) {
            address deployedManager;
            (corp,,, deployedManager,, addresses, actualId, ids) = companyFactory.deployCyberCorpAndCreateOffer(
                42,
                "New SAFO Ticket Company",
                "corporation",
                "DE",
                "contact",
                "arbitration",
                officer,
                officerInfo,
                printers,
                template,
                globals,
                parties,
                10000e6,
                values,
                officerSignature,
                certs,
                new address[](0),
                bytes32(0),
                block.timestamp + 7 days
            );
            assertEq(deployedManager, address(dealManager));
        } else {
            (addresses, actualId, ids) = dealManager.proposeAndSignNewCertsDeal(
                42,
                printers,
                template,
                globals,
                parties,
                10000e6,
                values,
                officerSignature,
                certs,
                new address[](0),
                bytes32(0),
                block.timestamp + 7 days,
                address(usdc)
            );
        }
        assertEq(actualId, id);
        LedgerEntryToken printer = LedgerEntryToken(addresses[0]);
        assertEq(printer.issueTimestamp(ids[0]), proposalTime);
        bytes memory investorSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            id,
            uri,
            fields,
            partyFields,
            globals,
            values[1],
            INVESTOR_KEY
        );
        vm.warp(block.timestamp + 1 days);
        uint256 beforeBalance = usdc.balanceOf(investor);
        vm.prank(investor);
        dealManager.signAndFinalizeDeal(investor, id, values[1], investorSignature, false, "Investor", "");
        assertEq(printer.ownerOf(ids[0]), investor);
        assertEq(printer.issueTimestamp(ids[0]), proposalTime, "Settlement must not restart Issue Date");
        assertEq(beforeBalance - usdc.balanceOf(investor), 10000e6);
        assertEq(printer.getCertificateDetails(ids[0]).investmentAmountUSD, 10000e18);
        assertEq(printer.getCertificateDetails(ids[0]).extensionData, payload);
        assertTrue(registry.isFinalized(id));
        vm.expectRevert();
        vm.prank(investor);
        dealManager.signAndFinalizeDeal(investor, id, values[1], investorSignature, false, "Investor", "");
    }

    function test_RegD_TicketSignPayFinalizePreservesOriginalIssueDate() public {
        _ticket(false, false);
    }

    function test_RegS_TicketSignPayFinalizePreservesOriginalIssueDate() public {
        _ticket(true, false);
    }

    function test_RegD_CombinedFactoryTicketSignPayFinalize() public {
        _ticket(false, true);
    }

    function test_RegS_CombinedFactoryTicketSignPayFinalize() public {
        _ticket(true, true);
    }

    function _fcfs(bool regS) internal {
        bytes32 template = _template(regS);
        bytes32 round = _round(template, RoundType.FCFS);
        bytes32 agreement = _subscribe(template, round, regS);
        Escrow memory escrow = manager.getEscrowDetails(agreement);
        assertEq(escrow.corpAssets.length, 1);
        LedgerEntryToken printer = LedgerEntryToken(escrow.corpAssets[0].tokenAddress);
        CertificateDetails memory details = printer.getCertificateDetails(escrow.corpAssets[0].tokenId);
        assertEq(details.investmentAmountUSD, 10000e18);
        assertEq(details.unitsRepresented, 10000e18);
        assertEq(details.extensionData, payload);
        assertEq(printer.ownerOf(escrow.corpAssets[0].tokenId), investor);
        assertTrue(registry.isFinalized(agreement));
    }

    function test_RegD_FcfsSignsPaysAndAllocatesAtomically() public {
        _fcfs(false);
    }

    function test_RegS_FcfsSignsPaysAndAllocatesAtomically() public {
        _fcfs(true);
    }

    function _newCompanyRound(bool regS, bool tamper) internal {
        bytes32 template = _template(regS);
        CompanyOfficer memory officerInfo = CompanyOfficer(officer, "Officer", "officer@example.com", "CEO");
        uint256 salt = 42;
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        bytes32 deploySalt = companyFactory.computeDeploymentSalt(
            corpSalt, "New SAFO Company", "corporation", "DE", "contact", "arbitration", officer, officerInfo
        );
        address predictedCorp = CyberCorpSingleFactory(companyFactory.cyberCorpSingleFactory())
            .computeCyberCorpSingleAddress(deploySalt, address(companyFactory));
        address predictedManager = RoundManagerFactory(companyFactory.roundManagerFactory())
            .computeRoundManagerAddress(deploySalt, address(companyFactory));
        (bytes memory escrowSignature, bytes32 expectedRound) = CyberCorpHelper.computeEscrowSignature(
            predictedManager,
            SecuritySeries.SeriesSeed,
            100000e6,
            100e6,
            10000e6,
            RoundType.FCFS,
            block.timestamp,
            block.timestamp + 30 days,
            template,
            address(usdc),
            1e18,
            1000000e18,
            OFFICER_KEY,
            predictedCorp
        );
        CyberCertData[] memory printers = new CyberCertData[](1);
        printers[0] = CyberCertData(
            "SAFO",
            "SAFO",
            "ipfs://safo-local-fixture",
            SecurityClass.SAFO,
            SecuritySeries.SeriesSeed,
            address(extension),
            hex"",
            new string[](0)
        );
        bytes[] memory extensions = new bytes[](1);
        extensions[0] = payload;
        string[] memory legal = new string[](1);
        legal[0] = "Governing law: DE";
        string[] memory officerValues = new string[](5);
        officerValues[0] = "Officer";
        officerValues[1] = vm.toString(officer);
        officerValues[2] = "officer@example.com";
        officerValues[3] = "CEO";
        officerValues[4] = "DE";
        CorpFactoryMetadataLib.RoundSupplementalData memory supplement = CorpFactoryMetadataLib.RoundSupplementalData({
            corpSalt: corpSalt,
            companyPayable: officer,
            publicRound: true,
            allowTimedOffers: false,
            restrictEndTimeReduction: false,
            officer: officerInfo,
            companyName: "New SAFO Company",
            companyType: "corporation",
            companyJurisdiction: "DE",
            companyContactDetails: "contact",
            defaultDisputeResolution: "arbitration",
            extensionData: extensions,
            roundPartyValues: officerValues,
            legalDetails: legal,
            certData: printers,
            conditionAddresses: new address[](0)
        });
        bytes memory metadataSignature =
            CyberCorpHelper.computeMetadataSignature(address(companyFactory), supplement, OFFICER_KEY);
        if (tamper) {
            extensions[0] = hex"1234";
            vm.expectRevert();
        }
        (address newCorp,,,, address newManager, bytes32 round) = companyFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "New SAFO Company",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            officer,
            officerInfo,
            legal,
            extensions,
            printers,
            template,
            address(usdc),
            1e18,
            1000000e18,
            officerValues,
            escrowSignature,
            metadataSignature,
            RoundType.FCFS,
            new address[](0),
            100000e6,
            100e6,
            10000e6,
            block.timestamp,
            block.timestamp + 30 days,
            true,
            false,
            false
        );
        if (tamper) {
            assertEq(predictedCorp.code.length, 0);
            return;
        }
        assertEq(newCorp, predictedCorp);
        assertEq(newManager, predictedManager);
        assertEq(round, expectedRound);
        corp = newCorp;
        manager = RoundManager(newManager);
        vm.prank(investor);
        usdc.approve(newManager, type(uint256).max);
        bytes32 agreement = _subscribe(template, round, regS);
        Escrow memory escrow = manager.getEscrowDetails(agreement);
        LedgerEntryToken printer = LedgerEntryToken(escrow.corpAssets[0].tokenAddress);
        assertEq(uint8(printer.securityType()), 14);
        assertEq(printer.getCertificateDetails(escrow.corpAssets[0].tokenId).extensionData, payload);
        assertEq(printer.ownerOf(escrow.corpAssets[0].tokenId), investor);
    }

    function test_RegD_CombinedFactoryThenInvestorSettlement() public {
        _newCompanyRound(false, false);
    }

    function test_RegS_CombinedFactoryThenInvestorSettlement() public {
        _newCompanyRound(true, false);
    }

    function test_CombinedFactoryRefusesChangedSAFOTermsAfterMetadataSignature() public {
        _newCompanyRound(false, true);
    }
}
