// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuthV2} from "../src/BorgAuthV2.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CertificateDetails, CompanyOfficer} from "../src/interfaces/ILedgerEntryToken.sol";
import {CorporateAuth} from "../src/libs/CorporateAuth.sol";
import {RoundType} from "../src/libs/RoundLib.sol";
import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberCertData} from "../src/storage/RoundManagerStorage.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    Offer,
    OfferSide,
    PostOfferParams,
    SecondaryEscrowStatus
} from "../src/storage/SecondaryTradeStorage.sol";
import {CorporateExecutor} from "./CorporateAuth.t.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Each manager of a v2 company holds the permissions its workflow needs, and no more.
/// Coverage map: specs/analysis/auth-v2.md, "Manager permission coverage (v2)".
contract CorporateAuthManagerFlowsTest is Test {
    bytes32 constant SECONDARY_TEMPLATE_ID = bytes32(uint256(888));
    string constant SECONDARY_TEMPLATE_URI = "ipfs://secondary-template";
    string constant DEAL_TEMPLATE_URI = "ipfs://template";

    uint256 constant MIN_TICKET = 1_000e9;
    uint256 constant MAX_TICKET = 100_000e9;
    uint256 constant RAISE_CAP = 1_000_000e9;
    uint256 constant PRICE_PER_UNIT = 10e18;
    uint256 constant VALUATION = 10_000_000e18;
    uint256 constant PAYMENT = 1_000e9;
    uint256 constant UNITS = 100;

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    MockERC20 internal usdc;
    CorporateExecutor internal board;

    address internal platformOwner;
    address internal root;
    address internal officer;
    uint256 internal officerKey;
    address internal buyer;
    uint256 internal buyerKey;
    address internal seller;
    address internal stranger;

    address internal corp;
    IssuanceManager internal issuance;
    DealManager internal dealManager;
    RoundManager internal roundManager;
    LedgerEntryToken internal printer;

    function setUp() public {
        platformOwner = makeAddr("platformOwner");
        root = makeAddr("root");
        (officer, officerKey) = makeAddrAndKey("officer");
        (buyer, buyerKey) = makeAddrAndKey("buyer");
        seller = makeAddr("seller");
        stranger = makeAddr("stranger");

        (registry, corpFactory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(platformOwner);
        board = new CorporateExecutor();
        usdc = new MockERC20("USD Coin", "USDC", 9);

        vm.startPrank(platformOwner);
        CyberCorpHelper.createTemplate(registry);
        registry.createTemplate(
            SECONDARY_TEMPLATE_ID, "Secondary", SECONDARY_TEMPLATE_URI, new string[](0), new string[](0)
        );
        corpFactory.setBorgAuthImplementation(address(new BorgAuthV2()));
        vm.stopPrank();

        address issuanceAddr;
        address dealAddr;
        address roundAddr;
        (corp,, issuanceAddr, dealAddr, roundAddr) = corpFactory.deployCyberCorpWithGovernance(
            keccak256("CorporateAuthManagerFlowsTest"),
            "Test Corp",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            officer,
            CompanyOfficer(officer, "Officer", "officer@example.com", "CEO"),
            root,
            address(board)
        );
        issuance = IssuanceManager(issuanceAddr);
        dealManager = DealManager(dealAddr);
        roundManager = RoundManager(roundAddr);

        vm.prank(officer);
        printer = LedgerEntryToken(
            issuance.createCertPrinter(
                new string[](0),
                "Shares",
                "SH",
                "uri",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                ""
            )
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deal Manager workflows
    // ─────────────────────────────────────────────────────────────────────────

    function testDealProposeSignPayFinalize() public {
        (bytes32 agreementId, uint256 certId) = _proposeDeal(1, block.timestamp + 1 days);

        string[] memory buyerValues = _partyValues("Buyer", "Investor");
        bytes memory buyerSig = _dealSig(agreementId, buyerValues, buyerKey);
        usdc.mint(buyer, PAYMENT);
        vm.startPrank(buyer);
        usdc.approve(address(dealManager), PAYMENT);
        dealManager.signDealAndPay(buyer, agreementId, buyerSig, buyerValues, false, "Buyer", "");
        vm.stopPrank();

        dealManager.finalizeDeal(agreementId);

        assertEq(uint8(dealManager.getEscrowDetails(agreementId).status), uint8(EscrowStatus.FINALIZED));
        assertEq(printer.ownerOf(certId), buyer);
    }

    function testDealVoidExpiredVoidsCert() public {
        (bytes32 agreementId, uint256 certId) = _proposeDeal(2, block.timestamp + 1 days);
        bytes memory voidSig = CyberAgreementUtils.signVoidAgreementTypedData(
            vm, registry.DOMAIN_SEPARATOR(), registry.VOIDSIGNATUREDATA_TYPEHASH(), agreementId, officer, officerKey
        );
        vm.warp(block.timestamp + 1 days + 1);

        dealManager.voidExpiredDeal(agreementId, officer, voidSig);

        assertTrue(printer.isVoided(certId));
    }

    function testNewCertsDealCreatesPrinters() public {
        uint256 salt = 3;
        string[] memory globalValues = _globalValues();
        address[] memory parties = _dealParties();
        string[][] memory partyValues = _dealPartyValues();
        bytes32 agreementId = _agreementId(salt, globalValues, parties);
        bytes memory officerSig = _dealSig(agreementId, partyValues[0], officerKey);

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            seriesData: "",
            defaultLegend: new string[](0)
        });
        CertificateDetails[] memory details = new CertificateDetails[](1);
        details[0] = _certDetails(UNITS);

        vm.prank(officer);
        (address[] memory printers,,) = dealManager.proposeAndSignNewCertsDeal(
            salt,
            certData,
            CyberCorpHelper.TEMPLATE_ID,
            globalValues,
            parties,
            PAYMENT,
            partyValues,
            officerSig,
            details,
            new address[](0),
            bytes32(0),
            block.timestamp + 1 days,
            address(usdc)
        );

        assertEq(printers.length, 1);
        assertGt(printers[0].code.length, 0);
    }

    function testSecondarySellPostAcceptFinalize() public {
        vm.startPrank(officer);
        uint256 sellerTokenId = issuance.createCertAndAssign(address(printer), seller, _certDetails(UNITS));
        printer.setGlobalLegalTransferable(true);
        dealManager.setPathwayThresholdConditions(ExemptionPathway.SECTION_4A7, new address[](0), true);
        vm.stopPrank();

        vm.prank(seller);
        bytes32 offerId = dealManager.postOffer(_sellOfferParams(sellerTokenId));
        assertEq(printer.unitsReserved(sellerTokenId), UNITS, "units reserved at post");

        usdc.mint(buyer, PAYMENT);
        vm.prank(buyer);
        usdc.approve(address(dealManager), PAYMENT);
        AcceptOfferParams memory accept = AcceptOfferParams({
            offerId: offerId,
            units: UNITS,
            exemptionPathway: ExemptionPathway.SECTION_4A7,
            buyerName: "Buyer",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: _acceptorSig(offerId),
            openEndorsementSig: ""
        });
        vm.prank(buyer);
        bytes32 settlementId = dealManager.acceptOffer(accept);

        vm.prank(stranger);
        dealManager.finalizeSecondaryTradeAgreement(settlementId);

        assertEq(uint8(dealManager.getSecondaryEscrow(settlementId).status), uint8(SecondaryEscrowStatus.FINALIZED));
        assertEq(printer.unitsReserved(sellerTokenId), 0, "reservation consumed at finalize");
        assertEq(printer.balanceOf(buyer), 1, "buyer cert issued by secondaryTransfer");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Round Manager workflow
    // ─────────────────────────────────────────────────────────────────────────

    function testRoundCreateSubmitAllocate() public {
        vm.prank(officer);
        bytes32 roundId = CyberCorpHelper.createRound(
            roundManager,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            officerKey,
            corp,
            false
        );

        usdc.mint(buyer, 10_000e9);
        vm.startPrank(buyer);
        usdc.approve(address(roundManager), type(uint256).max);
        (bytes32 agreementId,) =
            CyberCorpHelper.submitEOI(roundManager, registry, roundId, 1, 5_000e9, 10_000e9, officer, buyerKey);
        vm.stopPrank();

        vm.prank(officer);
        roundManager.allocate(agreementId, 7_500e9);

        Escrow memory escrow = roundManager.getEscrowDetails(agreementId);
        assertEq(uint8(escrow.status), uint8(EscrowStatus.FINALIZED));
        LedgerEntryToken roundPrinter = LedgerEntryToken(escrow.corpAssets[0].tokenAddress);
        assertEq(roundPrinter.ownerOf(escrow.corpAssets[0].tokenId), buyer);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Refusals at real gates
    // ─────────────────────────────────────────────────────────────────────────

    function testRoundManagerCannotConfigure() public {
        bytes memory denied = abi.encodeWithSelector(
            BorgAuthV2.PermissionDenied.selector, CorporateAuth.CONFIGURE_PROTOCOL, address(roundManager)
        );
        vm.prank(address(roundManager));
        vm.expectRevert(denied);
        issuance.setUriBuilder(stranger);
    }

    function testDealManagerCannotManageRounds() public {
        bytes memory denied = abi.encodeWithSelector(
            BorgAuthV2.PermissionDenied.selector, CorporateAuth.MANAGE_ROUNDS, address(dealManager)
        );
        vm.prank(address(dealManager));
        vm.expectRevert(denied);
        roundManager.closeRoundNow(bytes32(uint256(1)));
    }

    function testIssuanceManagerCannotSetPolicy() public {
        bytes memory denied = abi.encodeWithSelector(
            BorgAuthV2.PermissionDenied.selector, CorporateAuth.TRANSFER_POLICY, address(issuance)
        );
        vm.prank(address(issuance));
        vm.expectRevert(denied);
        dealManager.setSettlementWindow(1 days);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _proposeDeal(uint256 salt, uint256 expiry) internal returns (bytes32 agreementId, uint256 certId) {
        string[] memory globalValues = _globalValues();
        address[] memory parties = _dealParties();
        string[][] memory partyValues = _dealPartyValues();
        bytes32 expectedId = _agreementId(salt, globalValues, parties);
        bytes memory officerSig = _dealSig(expectedId, partyValues[0], officerKey);

        address[] memory printers = new address[](1);
        printers[0] = address(printer);
        CertificateDetails[] memory details = new CertificateDetails[](1);
        details[0] = _certDetails(UNITS);

        vm.prank(officer);
        uint256[] memory certIds;
        (agreementId, certIds) = dealManager.proposeAndSignDeal(
            printers,
            address(usdc),
            PAYMENT,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            parties,
            details,
            officer,
            officerSig,
            partyValues,
            new address[](0),
            bytes32(0),
            expiry
        );
        assertEq(agreementId, expectedId, "agreement id");
        certId = certIds[0];
    }

    function _agreementId(uint256 salt, string[] memory globalValues, address[] memory parties)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(CyberCorpHelper.TEMPLATE_ID, salt, globalValues, parties, bytes32(0), address(dealManager))
        );
    }

    function _dealSig(bytes32 agreementId, string[] memory partyValues, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_TEMPLATE_URI,
            globalFields,
            partyFields,
            _globalValues(),
            partyValues,
            key
        );
    }

    function _globalValues() internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = "Global Value";
    }

    function _dealParties() internal view returns (address[] memory parties) {
        parties = new address[](2);
        parties[0] = officer;
        parties[1] = buyer;
    }

    function _dealPartyValues() internal pure returns (string[][] memory values) {
        values = new string[][](2);
        values[0] = _partyValues("Officer", "CEO");
        values[1] = _partyValues("Buyer", "Investor");
    }

    function _partyValues(string memory name, string memory title) internal pure returns (string[] memory values) {
        values = new string[](2);
        values[0] = name;
        values[1] = title;
    }

    function _certDetails(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 1_000,
            issuerUSDValuationAtTimeOfInvestment: 10_000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });
    }

    function _sellOfferParams(uint256 sellerTokenId) internal view returns (PostOfferParams memory) {
        return PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: address(printer),
            tokenId: sellerTokenId,
            units: UNITS,
            paymentToken: address(usdc),
            consideration: PAYMENT,
            exemptionPathway: ExemptionPathway.NONE,
            validUntil: block.timestamp + 1 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: SECONDARY_TEMPLATE_ID,
            salt: 1,
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "sellerEndorsement",
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
    }

    function _acceptorSig(bytes32 offerId) internal view returns (bytes memory) {
        Offer memory o = dealManager.getOffer(offerId);
        bytes32 settlementSalt = keccak256(abi.encodePacked(o.salt, o.settlementAgreementIds.length));
        address[] memory parties = new address[](2);
        parties[0] = o.offeror;
        parties[1] = buyer;
        bytes32 settlementId = keccak256(
            abi.encode(o.templateId, uint256(settlementSalt), o.globalValues, parties, bytes32(0), address(dealManager))
        );
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            settlementId,
            SECONDARY_TEMPLATE_URI,
            new string[](0),
            new string[](0),
            new string[](0),
            new string[](0),
            buyerKey
        );
    }
}
