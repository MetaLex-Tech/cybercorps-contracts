// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {DealManager} from "../src/DealManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {CyberCertData, EOI, LexChexDetails} from "../src/storage/RoundManagerStorage.sol";
import {
    AcceptOfferParams,
    ExemptionPathway,
    HostingMode,
    Offer,
    OfferSide,
    PostOfferParams
} from "../src/storage/SecondaryTradeStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";

struct CyberCertDataV4 {
    string name;
    string symbol;
    string uri;
    SecurityClass securityClass;
    SecuritySeries securitySeries;
    address extension;
    string[] defaultLegend;
}

interface IRoundManagerV4 {
    function createRound(Round memory roundDraft, CyberCertDataV4[] memory certData) external returns (bytes32);
}

/// @notice Mixed-version Base fork regressions for Issue #218 (Section 1: Case 1).
/// @dev Forks Base (`8453`) at block `61900000`, builds live round and secondary-offer state against
///      the deployed Base `CyberAgreementRegistry` (`0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`,
///      implementation `0x239Ef1C2F037e0AE2ED4c2c9B4196d8ffe738ea9`), verifies in a snapshot that
///      settlement succeeds before upgrading the registry, then upgrades ONLY `CyberAgreementRegistry`
///      to `38e92baa` while leaving deployed company `RoundManager` and `DealManager` proxies at their
///      live implementations (`RoundManager` v4 `0xF9768520048Fe1289F5f68bf7258b9BF5345F23D`,
///      `RoundManager` 5.1 `0x2d282dB929bf095B1F9a97469b090f7A4f92Bd1a`, and `DealManager` 5
///      `0xF791E85C9D6c140891DF59C56bf093E298cfc7C7`).
///      Requires `RPC_URL_BASE`; skipped when `RPC_URL_BASE` is unset.
contract Issue218MixedVersionEscrowForkTest is Test {
    using RoundLib for Round;

    uint256 internal constant FORK_BLOCK = 61_900_000;
    bytes32 internal constant ERC1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev Existing live v4 company on Base (`notes/ai/tasks/base-packet-signing.md:34`).
    address internal constant LIVE_V4_CORP = 0x3C60411a819597A10893C85FeC6262843e4dE990;
    address internal constant LIVE_V4_ROUND_MANAGER = 0xF9768520048Fe1289F5f68bf7258b9BF5345F23D;

    /// @dev Live Base factory reference implementations at `FORK_BLOCK`.
    address internal constant LIVE_BASE_RM_51_IMPL = 0x2d282dB929bf095B1F9a97469b090f7A4f92Bd1a;
    address internal constant LIVE_BASE_DM_5_IMPL = 0xF791E85C9D6c140891DF59C56bf093E298cfc7C7;

    bytes32 internal constant TEST_TEMPLATE_ID = keccak256("Issue218.ForkTemplate");
    string internal constant TEST_TEMPLATE_URI = "ipfs://issue-218-fork-template";

    DeploymentConstants.CoreDeployment internal core;
    CyberAgreementRegistry internal registry;

    address internal officer;
    uint256 internal officerKey;
    address internal investor;
    uint256 internal investorKey;
    address internal buyer;
    uint256 internal buyerKey;

    address internal v5Corp;
    address internal v5Issuance;
    address internal v5DealManager;
    address internal v5RoundManager;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_URL_BASE", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);

        core = DeploymentConstants.coreV2(DeploymentConstants.BASE);
        registry = CyberAgreementRegistry(core.cyberAgreementRegistry);

        (officer, officerKey) = makeAddrAndKey("issue218-fork-officer");
        (investor, investorKey) = makeAddrAndKey("issue218-fork-investor");
        (buyer, buyerKey) = makeAddrAndKey("issue218-fork-buyer");

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        vm.prank(core.metalexSafe);
        registry.createTemplate(TEST_TEMPLATE_ID, "Issue 218 Template", TEST_TEMPLATE_URI, globalFields, partyFields);

        // Deploy a v5 company through the live Base CyberCorpFactory before any registry upgrade.
        (v5Corp,, v5Issuance, v5DealManager, v5RoundManager) = CyberCorpHelper.deployCorp(
            CyberCorpFactory(core.cyberCorpFactory),
            "Issue 218 Live Base V5 Corp",
            officer,
            officer
        );

        assertEq(
            address(uint160(uint256(vm.load(v5RoundManager, ERC1967_IMPL_SLOT)))),
            LIVE_BASE_RM_51_IMPL,
            "v5 RoundManager proxy must run live Base 5.1 implementation"
        );
        assertEq(
            address(uint160(uint256(vm.load(v5DealManager, ERC1967_IMPL_SLOT)))),
            LIVE_BASE_DM_5_IMPL,
            "v5 DealManager proxy must run live Base 5 implementation"
        );

        deal(BASE_USDC, investor, 500_000e6);
        deal(BASE_USDC, buyer, 500_000e6);
    }

    function _upgradeRegistryOnly() internal {
        CyberAgreementUtils.upgradeRegistry(vm, address(registry), core.metalexSafe);
    }

    function _createRoundOn(address rm, address corpAddr, RoundType roundType) internal returns (bytes32 roundId) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Restricted";
        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Seed Equity",
            symbol: "SEED",
            uri: "ipfs://seed",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;
        uint256 cap = 500_000e6;
        uint256 minTicket = 1_000e6;
        uint256 maxTicket = 50_000e6;
        uint256 pricePerUnit = 1e18;
        uint256 valuation = 10_000_000e18;

        (bytes memory escrowedSig,) = CyberCorpHelper.computeEscrowSignature(
            rm,
            SecuritySeries.SeriesSeed,
            cap,
            minTicket,
            maxTicket,
            roundType,
            startTime,
            endTime,
            TEST_TEMPLATE_ID,
            BASE_USDC,
            pricePerUnit,
            valuation,
            officerKey,
            corpAddr
        );

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        Round memory draft = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                roundType,
                false,
                false,
                false,
                cap,
                minTicket,
                maxTicket,
                BASE_USDC,
                pricePerUnit,
                valuation,
                startTime,
                endTime
            )
            .setAgreement(
                TEST_TEMPLATE_ID,
                officer,
                "Alice Officer",
                "CEO",
                new string[](1),
                roundPartyValues,
                new bytes[](1),
                new address[](0),
                escrowedSig
            );

        vm.prank(officer);
        roundId = RoundManager(rm).createRound(draft, certData);
    }

    function _createRoundOnV4(address rm, address corpAddr, RoundType roundType) internal returns (bytes32 roundId) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Restricted";
        CyberCertDataV4[] memory certData = new CyberCertDataV4[](1);
        certData[0] = CyberCertDataV4({
            name: "Seed Equity",
            symbol: "SEED",
            uri: "ipfs://seed",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;
        uint256 cap = 500_000e6;
        uint256 minTicket = 1_000e6;
        uint256 maxTicket = 50_000e6;
        uint256 pricePerUnit = 1e18;
        uint256 valuation = 10_000_000e18;

        (bytes memory escrowedSig,) = CyberCorpHelper.computeEscrowSignature(
            rm,
            SecuritySeries.SeriesSeed,
            cap,
            minTicket,
            maxTicket,
            roundType,
            startTime,
            endTime,
            TEST_TEMPLATE_ID,
            BASE_USDC,
            pricePerUnit,
            valuation,
            officerKey,
            corpAddr
        );

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        Round memory draft = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                roundType,
                false,
                false,
                false,
                cap,
                minTicket,
                maxTicket,
                BASE_USDC,
                pricePerUnit,
                valuation,
                startTime,
                endTime
            )
            .setAgreement(
                TEST_TEMPLATE_ID,
                officer,
                "Alice Officer",
                "CEO",
                new string[](1),
                roundPartyValues,
                new bytes[](1),
                new address[](0),
                escrowedSig
            );

        vm.prank(officer);
        roundId = IRoundManagerV4(rm).createRound(draft, certData);
    }

    function _submitInvestorEOI(address rm, bytes32 roundId, uint256 salt, uint256 amount)
        internal
        returns (bytes32 agreementId)
    {
        Round memory r = RoundManager(rm).getRound(roundId);
        address[] memory parties = new address[](2);
        parties[0] = r.authorityOfficer;
        parties[1] = investor;

        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";

        string[] memory globalValues = new string[](1);
        globalValues[0] = "10000";
        string[] memory investorPartyValues = new string[](2);
        investorPartyValues[0] = "Bob Investor";
        investorPartyValues[1] = "Subscriber";

        bytes32 predictedId =
            keccak256(abi.encode(TEST_TEMPLATE_ID, salt, globalValues, parties, bytes32(0), rm));

        bytes memory sig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            predictedId,
            TEST_TEMPLATE_URI,
            globalFields,
            partyFields,
            globalValues,
            investorPartyValues,
            investorKey
        );

        EOI memory eoi = EOI({
            name: "Bob Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "bob@example.com",
            minAmount: amount,
            maxAmount: amount,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        vm.startPrank(investor);
        IERC20(BASE_USDC).approve(rm, amount);
        (agreementId,) = RoundManager(rm).submitEOI(
            roundId, eoi, globalValues, investorPartyValues, sig, salt, new address[](0), bytes32(0)
        );
        vm.stopPrank();
    }

    /// @notice Un-upgraded live Base 5.1 `RoundManager` FCFS `submitEOI` succeeds before registry upgrade
    ///         and reverts after upgrading only `CyberAgreementRegistry` to `38e92baa`.
    function test_Case1a_UnupgradedLiveV51RoundManager_FCFSSubmitEOI() public {
        bytes32 roundId = _createRoundOn(v5RoundManager, v5Corp, RoundType.FCFS);

        uint256 snap = vm.snapshotState();
        bytes32 preUpgradeId = _submitInvestorEOI(v5RoundManager, roundId, 101, 10_000e6);
        assertTrue(registry.isFinalized(preUpgradeId), "FCFS submitEOI succeeds before registry upgrade");
        vm.revertToState(snap);

        _upgradeRegistryOnly();
        bytes32 postUpgradeId = _submitInvestorEOI(v5RoundManager, roundId, 101, 10_000e6);
        assertTrue(registry.isFinalized(postUpgradeId), "FCFS submitEOI on un-upgraded 5.1 RoundManager");
    }

    /// @notice Un-upgraded live Base 5.1 `RoundManager` FounderApproved `allocate` (with investor USDC already
    ///         escrowed prior to the registry upgrade) succeeds before registry upgrade and reverts after `38e92baa`.
    function test_Case1b_UnupgradedLiveV51RoundManager_AllocateEscrowedEOI() public {
        bytes32 roundId = _createRoundOn(v5RoundManager, v5Corp, RoundType.FounderApproved);
        bytes32 agreementId = _submitInvestorEOI(v5RoundManager, roundId, 202, 10_000e6);

        uint256 snap = vm.snapshotState();
        vm.prank(officer);
        RoundManager(v5RoundManager).allocate(agreementId, 10_000e6);
        assertTrue(registry.isFinalized(agreementId), "allocate succeeds before registry upgrade");
        vm.revertToState(snap);

        _upgradeRegistryOnly();
        vm.prank(officer);
        RoundManager(v5RoundManager).allocate(agreementId, 10_000e6);
        assertTrue(registry.isFinalized(agreementId), "allocate on un-upgraded 5.1 RoundManager");
    }

    /// @notice Existing live Base v4 company (`0x3c60411a819597a10893c85fec6262843e4de990`, `RoundManager`
    ///         `0xF9768520048Fe1289F5f68bf7258b9BF5345F23D`) `allocate` succeeds before registry upgrade and
    ///         reverts after upgrading only `CyberAgreementRegistry` to `38e92baa`.
    function test_Case1c_UnupgradedExistingLiveV4RoundManager_AllocateEscrowedEOI() public {
        assertEq(RoundManager(LIVE_V4_ROUND_MANAGER).DEPLOY_VERSION(), "4");
        (address existingFounder,,,) = CyberCorp(LIVE_V4_CORP).companyOfficers(0);
        BorgAuth v4Auth = CyberCorp(LIVE_V4_CORP).AUTH();
        vm.startPrank(existingFounder);
        v4Auth.updateRole(officer, v4Auth.OWNER_ROLE());
        CyberCorp(LIVE_V4_CORP).addOfficer(
            CompanyOfficer({eoa: officer, name: "Alice Officer", contact: "", title: "CEO"})
        );
        vm.stopPrank();

        bytes32 roundId = _createRoundOnV4(LIVE_V4_ROUND_MANAGER, LIVE_V4_CORP, RoundType.FounderApproved);
        bytes32 agreementId = _submitInvestorEOI(LIVE_V4_ROUND_MANAGER, roundId, 303, 10_000e6);

        uint256 snap = vm.snapshotState();
        vm.prank(officer);
        RoundManager(LIVE_V4_ROUND_MANAGER).allocate(agreementId, 10_000e6);
        assertTrue(registry.isFinalized(agreementId), "v4 allocate succeeds before registry upgrade");
        vm.revertToState(snap);

        _upgradeRegistryOnly();
        vm.prank(officer);
        RoundManager(LIVE_V4_ROUND_MANAGER).allocate(agreementId, 10_000e6);
        assertTrue(registry.isFinalized(agreementId), "v4 allocate on un-upgraded live RoundManager");
    }

    /// @notice Un-upgraded live Base v5 `DealManager` (`0xF791E85C9D6c140891DF59C56bf093E298cfc7C7`) secondary
    ///         `acceptOffer` (on an offer posted with `offerorAgreementSig = ""` as `metalex-webapp` `production`
    ///         `625bc5fa8c1` `secondaryOfferCall.ts` sends) succeeds before registry upgrade and reverts after `38e92baa`.
    function test_Case1d_UnupgradedLiveV5DealManager_AcceptSecondaryOffer() public {
        bytes32 secTemplateId = keccak256("Issue218.SecondaryTemplate");
        vm.prank(core.metalexSafe);
        registry.createTemplate(secTemplateId, "Secondary SPA", "ipfs://sec-spa", new string[](0), new string[](0));

        vm.startPrank(officer);
        DealManager(v5DealManager).setPathwayThresholdConditions(
            ExemptionPathway.SECTION_4A7, new address[](0), true
        );
        address printer = IssuanceManager(v5Issuance).createCertPrinter(
            new string[](0),
            "Common Stock",
            "CS",
            "ipfs://cs",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0),
            bytes("")
        );
        uint256 tokenId = IssuanceManager(v5Issuance).createCertAndAssign(
            printer,
            investor,
            CertificateDetails({
                signingOfficerName: "Alice Officer",
                signingOfficerTitle: "CEO",
                investmentAmountUSD: 10_000,
                issuerUSDValuationAtTimeOfInvestment: 1_000_000,
                unitsRepresented: 100,
                legalDetails: "",
                extensionData: bytes("")
            })
        );
        ILedgerEntryToken(printer).setGlobalLegalTransferable(true);
        vm.stopPrank();

        // Seller posts offer prior to upgrade with `offerorAgreementSig: ""` (matches production webapp).
        PostOfferParams memory postParams = PostOfferParams({
            side: OfferSide.SELL,
            certPrinter: printer,
            tokenId: tokenId,
            units: 100,
            paymentToken: BASE_USDC,
            consideration: 10_000e6,
            exemptionPathway: ExemptionPathway.NONE,
            validUntil: block.timestamp + 7 days,
            counterpartyRestrictions: "",
            additionalTerms: "",
            integrator: address(0),
            templateId: secTemplateId,
            salt: 404,
            globalValues: new string[](0),
            offerorPartyValues: new string[](0),
            offerorAgreementSig: "",
            openEndorsementSig: "endorsement",
            buyerName: "",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0)
        });
        vm.prank(investor);
        bytes32 offerId = DealManager(v5DealManager).postOffer(postParams);

        Offer memory o = DealManager(v5DealManager).getOffer(offerId);
        bytes32 settlementSalt = keccak256(abi.encodePacked(o.salt, uint256(0)));
        address[] memory parties = new address[](2);
        parties[0] = investor;
        parties[1] = buyer;
        bytes32 settlementId =
            keccak256(abi.encode(secTemplateId, uint256(settlementSalt), new string[](0), parties, bytes32(0), v5DealManager));

        bytes memory acceptorSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            settlementId,
            "ipfs://sec-spa",
            new string[](0),
            new string[](0),
            new string[](0),
            new string[](0),
            buyerKey
        );

        AcceptOfferParams memory acceptParams = AcceptOfferParams({
            offerId: offerId,
            units: 100,
            exemptionPathway: ExemptionPathway.SECTION_4A7,
            buyerName: "Buyer LLC",
            buyerHostingMode: HostingMode.DIRECT,
            adminMultisig: address(0),
            sellerTokenId: 0,
            acceptorPartyValues: new string[](0),
            acceptorAgreementSig: acceptorSig,
            openEndorsementSig: ""
        });

        uint256 snap = vm.snapshotState();
        vm.startPrank(buyer);
        IERC20(BASE_USDC).approve(v5DealManager, 10_000e6);
        bytes32 preUpgradeSettlement = DealManager(v5DealManager).acceptOffer(acceptParams);
        vm.stopPrank();
        assertEq(preUpgradeSettlement, settlementId, "acceptOffer succeeds before registry upgrade");
        vm.revertToState(snap);

        _upgradeRegistryOnly();
        vm.startPrank(buyer);
        IERC20(BASE_USDC).approve(v5DealManager, 10_000e6);
        bytes32 postUpgradeSettlement = DealManager(v5DealManager).acceptOffer(acceptParams);
        vm.stopPrank();
        assertEq(postUpgradeSettlement, settlementId, "acceptOffer on un-upgraded live v5 DealManager");
    }
}
