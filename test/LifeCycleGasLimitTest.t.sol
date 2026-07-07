// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {RoundLib, Round, RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {
    ShareExtension,
    ShareCertData,
    SeriesTerms,
    CertificateData,
    MandatoryConversionTrigger,
    MandatoryConversionTriggerType,
    SpecialVotingRight,
    VotingScope,
    TransferRestriction,
    TransferRestrictionType,
    TransferRestrictionException,
    SplitRecord,
    ShareRepresentationType,
    LiquidationPreferenceType,
    AntiDilutionType,
    DividendType,
    RedemptionType
} from "../src/storage/extensions/ShareExtension.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {MockERC20} from "./mock/MockERC20.sol";

/// @notice Gas regression guard for the three most gas-intensive RoundManager operations.
///         Parameters emulate real mainnet transactions:
///           createRound — block 25202917 (13,003,119 gas, 77.5% of block limit)
///           submitEOI   — block 25203564 (1,485,634 gas)
///           allocate    — block 25215285 (13,859,243 gas, 82.6% of block limit)
///         Each test asserts gas ≤ EIP-7825 block gas limit (16,777,216).
contract LifeCycleGasLimitTest is Test {
    using RoundLib for Round;

    uint256 constant EIP7825_GAS_LIMIT     = 16_777_216;
    uint256 constant GAS_LIMIT_90_PCT      = 15_099_494; // 90% of EIP-7825 block gas limit

    // ── Template ─────────────────────────────────────────────────────────────
    bytes32 constant TEMPLATE_ID = bytes32("metalex_cyberstock_reg_d_v1_0");

    // ── Round numeric params (real tx, USDC 6 decimals) ──────────────────────
    uint256 constant RAISE_CAP      = 1_772_019_147_600;
    uint256 constant MIN_TICKET     =     2_000_000_000;
    uint256 constant MAX_TICKET     =   500_000_000_000;
    uint256 constant PRICE_PER_UNIT = 26_213_301_000_000_000_000;
    uint256 constant VALUATION      = 35_000_000_000_000_000_000_000_000;
    uint256 constant EOI_AMOUNT     =     2_000_000_000;

    // IPFS URI used in certData.uri and template (66 chars, matches real certData[0].uri)
    string constant IPFS_URI = "ipfs://bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";
    // Pinata gateway URI used in all ShareCertData URI fields (113 chars, matches real extensionData)
    string constant PINATA_URI = "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

    // ── Six restricted-securities legends (real cert printer content) ─────────
    string constant L0 =
        "RESTRICTED SECURITIES LEGEND. THE STOCK LEDGER ENTRY TOKEN, THE TOKENIZED SHARES "
        "REPRESENTED HEREBY, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO "
        "(INCLUDING UPON CONVERSION) ARE \"RESTRICTED SECURITIES\" AS DEFINED IN SEC RULE 144.";

    string constant L1 =
        "SECURITIES ACT LEGEND. THE STOCK LEDGER ENTRY TOKEN, THE TOKENIZED SHARES "
        "REPRESENTED HEREBY, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT "
        "BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE \"SECURITIES ACT\"), "
        "OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, "
        "SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS "
        "AGREEMENT, THE COI, THE BYLAWS AND THE TRANSACTION AGREEMENTS, AND UNDER THE SECURITIES "
        "ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT "
        "OR AN EXEMPTION THEREFROM.";

    string constant L2 =
        "BOARD CONSENT TRANSFER RESTRICTION LEGEND. THE TOKENIZED SHARES REPRESENTED HEREBY AND "
        "THE STOCK LEDGER ENTRY TOKEN MAY NOT BE TRANSFERRED, PLEDGED OR HYPOTHECATED WITHOUT THE "
        "PRIOR WRITTEN CONSENT OF THE BOARD OF DIRECTORS OF THE CORPORATION AS REQUIRED BY THE "
        "BYLAWS, EXCEPT IN CIRCUMSTANCES EXPRESSLY PERMITTED BY THE BYLAWS WITHOUT SUCH CONSENT.";

    string constant L3 =
        "STOCKHOLDER AGREEMENTS LEGEND. THE TOKENIZED SHARES REPRESENTED HEREBY AND THE STOCK "
        "LEDGER ENTRY TOKEN ARE SUBJECT TO, AND ANY TRANSFER OR OTHER DISPOSITION HEREOF OR "
        "THEREOF IS RESTRICTED BY AND SUBJECT TO, THE TERMS AND CONDITIONS OF THE TRANSACTION "
        "AGREEMENTS, INCLUDING THE INVESTORS' RIGHTS AGREEMENT, THE VOTING AGREEMENT, AND THE "
        "RIGHT OF FIRST REFUSAL AND CO-SALE AGREEMENT, EACH AS IN EFFECT FROM TIME TO TIME. "
        "COPIES OF THE TRANSACTION AGREEMENTS ARE AVAILABLE FROM THE CORPORATION UPON REQUEST AT NO CHARGE.";

    string constant L4 =
        "TOKENIZED STOCK LEDGER LEGEND. THIS STOCK LEDGER ENTRY TOKEN CONSTITUTES, AND IS THE "
        "CORPORATION'S OFFICIAL RECORD OF, AN ENTRY IN THE CORPORATION'S OFFICIAL STOCK LEDGER "
        "MAINTAINED IN THE TOKENIZED STOCK LEDGER SYSTEM IN ACCORDANCE WITH SECTIONS 219 AND 224 "
        "OF THE DGCL, ARTICLE FOURTEENTH OF THE COI AND ARTICLE 8 OF THE BYLAWS. THE TOKENIZED "
        "SHARES REPRESENTED HEREBY ARE UNCERTIFICATED SHARES; NO PAPER STOCK CERTIFICATE WILL BE "
        "ISSUED UNLESS AND UNTIL THE BOARD OF DIRECTORS SO DETERMINES IN ACCORDANCE WITH THE BYLAWS.";

    string constant L5 =
        "MATERIAL ADVERSE EXCEPTION EVENT LEGEND. UPON THE OCCURRENCE OR REASONABLY EXPECTED "
        "OCCURRENCE OF A MATERIAL ADVERSE EXCEPTION EVENT (AS SUCH TERM IS DEFINED IN THE BYLAWS), "
        "THE CORPORATION MAY, IN ITS SOLE AND ABSOLUTE DISCRETION AND IN ACCORDANCE WITH THE BYLAWS, "
        "SUSPEND THE REGISTRATION OF TRANSFERS OF THIS STOCK LEDGER ENTRY TOKEN AND THE TOKENIZED "
        "SHARES REPRESENTED HEREBY, DETERMINE THE AUTHORITATIVE CHAIN, VERSION OR STATE OF THE "
        "DESIGNATED BLOCKCHAIN SYSTEM, AND TREAT AS VOID OR VOIDABLE ANY PURPORTED TRANSFER OF THIS "
        "STOCK LEDGER ENTRY TOKEN OR THE TOKENIZED SHARES REPRESENTED HEREBY EFFECTED OR ATTEMPTED "
        "TO BE EFFECTED IN CONNECTION WITH OR AS A RESULT OF SUCH MATERIAL ADVERSE EXCEPTION EVENT, "
        "NOTWITHSTANDING SECTION 8-303 OF THE UCC. NO COPY OF THIS STOCK LEDGER ENTRY TOKEN MAY BE "
        "OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED BY THE "
        "BYLAWS, AND ONLY THE COPY ON THE CHAIN, VERSION OR STATE OF THE DESIGNATED BLOCKCHAIN SYSTEM "
        "DETERMINED BY THE CORPORATION TO BE AUTHORITATIVE MAY BE SO OFFERED, SOLD OR TRANSFERRED.";

    string constant L6_LOCKUP =
        "180 day market stand-off re: IPO in Investors Rights Agreement Sec. 2.11\n\n"
        "this is a summary only and is non-binding; for actual binding terms, see "
        "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

    // ── State ─────────────────────────────────────────────────────────────────
    CyberAgreementRegistry registry;
    CyberCorpFactory corpFactory;
    MockERC20 usdc;
    ShareExtension shareExtension;

    address officer;
    uint256 officerKey;
    address investor;
    uint256 investorKey;

    function setUp() public {
        (registry, corpFactory,,,,,,) = CyberCorpHelper.deployRegistryAndFactories(address(this));
        _createTemplate();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        (officer, officerKey) = makeAddrAndKey("officer");
        (investor, investorKey) = makeAddrAndKey("investor");

        BorgAuth shareAuth = new BorgAuth(address(this));
        shareExtension = ShareExtension(address(new ERC1967Proxy(
            address(new ShareExtension()),
            abi.encodeWithSelector(ShareExtension.initialize.selector, address(shareAuth))
        )));
    }

    // ── template / helpers ────────────────────────────────────────────────────

    function _createTemplate() internal {
        string[] memory globalFields = new string[](5);
        globalFields[0] = "Price per share";
        globalFields[1] = "Number of shares";
        globalFields[2] = "Governing law";
        globalFields[3] = "";
        globalFields[4] = "";
        string[] memory partyFields = new string[](5);
        partyFields[0] = "Investor name";
        partyFields[1] = "Investor address";
        partyFields[2] = "Investor contact";
        partyFields[3] = "Investor type";
        partyFields[4] = "";
        registry.createTemplate(
            TEMPLATE_ID,
            "MetaLeX CyberStock Reg D v1.0",
            IPFS_URI,
            globalFields,
            partyFields
        );
    }

    function _buildSeriesTerms() internal pure returns (SeriesTerms memory) {
        return SeriesTerms({
            seriesName: "Series Seed 2",
            parValue: 10_000_000_000_000,
            authorizedShares: 67_600_000_000_000_000_000_000,
            originalIssuePrice: 26_213_301_000_000_000_000,
            effectiveDate: 1_780_075_297,
            sourceAuthorityURI: PINATA_URI,
            liquidationPreferenceMultiple: 1e18,
            liquidationPreferenceType: LiquidationPreferenceType.NonParticipating,
            participationCap: 0,
            seniorityRank: 1,
            dividendType: DividendType.None,
            dividendRate: 0,
            dividendAccrualStartDate: 0,
            dividendCompounding: false,
            dividendIncreasesLiquidationAmount: false,
            isConvertible: true,
            targetConversionSeriesId: "",
            conversionPrice: 26_213_301_000_000_000_000,
            antiDilutionType: AntiDilutionType.BroadBasedWeightedAverage,
            allowsFractionalConversion: false,
            hasMandatoryConversion: true,
            votesPerShare: 1e18,
            designatedBoardSeats: 1,
            hasClassVotingRights: true,
            hasSeriesVotingRights: true,
            isRedeemable: false,
            redemptionType: RedemptionType.None,
            redemptionPrice: 0,
            redemptionSchedule: "",
            redemptionTriggerDescription: "",
            hasPayToPlay: false,
            payToPlayTermsURI: "",
            hasRegistrationRights: true,
            registrationRightsURI: PINATA_URI,
            hasProRataRights: true,
            proRataRightsURI: PINATA_URI,
            hasInformationRights: true,
            informationRightsURI: PINATA_URI,
            hasDragAlongRights: true,
            dragAlongTermsURI: PINATA_URI
        });
    }

    function _buildConversionTriggers()
        internal pure returns (MandatoryConversionTrigger[] memory triggers)
    {
        triggers = new MandatoryConversionTrigger[](2);
        triggers[0] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.ClassVote,
            primaryThreshold: 0,
            secondaryThreshold: 50_000_000e18,
            additionalConditions: "",
            description: "**Primary threshold: $50.00 per share**\n"
                "- Closing of sale of Common Stock to the public at a price of at least $50.00 per share\n"
                "- Subject to anti-dilution adjustment for splits/dividends/combinations\n\n"
                "**Secondary threshold: $5,000,000**\n"
                "- Gross proceeds to the Corporation\n\n"
                "**Structural conditions (no numeric threshold):**\n"
                "- Form: firm-commitment underwritten public offering\n"
                "- Registration: effective registration statement under Securities Act of 1933\n"
                "- Listing: Nasdaq National Market, NYSE, or Board-approved exchange/marketplace\n\n"
                "this is a summary only and is non-binding; for actual binding terms, see "
                "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
        triggers[1] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.ClassVote,
            primaryThreshold: 1,
            secondaryThreshold: 50_100_000_000_000_000_000,
            additionalConditions:
                "**Primary threshold: 50.1%**\n"
                "- Vote or written consent of the Requisite Preferred Holders\n"
                "- Requisite Preferred Holders = holders of at least 50.1% of then-outstanding "
                "shares of Preferred Stock (Series Seed + Series Seed 2 combined)\n"
                "- Voting together as a single class on an as-converted to Common Stock basis\n\n"
                "**Secondary threshold: N/A (0)**\n"
                "- ClassVote has no secondary numeric threshold; 50.1% is the sole voting requirement\n"
                "- Specifies a date/time/event to trigger conversion\n\n"
                "this is a summary only and is non-binding; for actual binding terms, see "
                "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne",
            description:
                "**Primary threshold: 50.1%**\n"
                "- Vote or written consent of the Requisite Preferred Holders\n\n"
                "this is a summary only and is non-binding; for actual binding terms, see "
                "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
    }

    function _buildVotingRights()
        internal pure returns (SpecialVotingRight[] memory rights)
    {
        rights = new SpecialVotingRight[](2);
        rights[0] = SpecialVotingRight({
            matterType: "Series Seed 2 Protective Provisions",
            votesPerShare: 1e18,
            threshold: 5_010,
            isVetoRight: true,
            scope: VotingScope.SeriesSpecific,
            description:
                "Series Seed 2-specific protective provisions. Acts affecting Series Seed 2 in these "
                "matters are void without written consent or affirmative vote of at least 50.1% of "
                "Series Seed 2 holders.\n\n"
                "This is a summary only and is non-binding; for actual binding terms, see "
                "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
        rights[1] = SpecialVotingRight({
            matterType: "Joint Preferred Protective Provisions",
            votesPerShare: 1e18,
            threshold: 5_010,
            isVetoRight: true,
            scope: VotingScope.ClassWide,
            description:
                "Joint preferred protective provisions requiring written consent or affirmative vote "
                "of holders of at least 50.1% of the then-outstanding shares of Preferred Stock "
                "(Series Seed + Series Seed 2 combined), voting together as a single class on an "
                "as-converted to Common Stock basis. Listed matters cannot be undertaken without "
                "such consent:\n"
                "- Liquidation, dissolution, or Deemed Liquidation Event\n"
                "- Creation or authorization of new preferred classes\n"
                "- Redemption, dividend declarations, or capital structure changes\n"
                "- Debt or liens exceeding $500,000\n"
                "- Board size changes\n\n"
                "This is a summary only and is non-binding; for actual binding terms, see "
                "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
    }

    function _buildTransferRestrictions()
        internal pure returns (TransferRestriction[] memory restrictions)
    {
        TransferRestrictionException[] memory noExc = new TransferRestrictionException[](0);
        restrictions = new TransferRestriction[](7);

        // L2: Board Consent
        restrictions[0] = TransferRestriction({
            restrictionType: TransferRestrictionType.BoardConsentRequired,
            restrictionText: L2,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L1: Securities Act
        restrictions[1] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: L1,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L0: Restricted Securities
        restrictions[2] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: L0,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L3: Stockholder Agreements
        restrictions[3] = TransferRestriction({
            restrictionType: TransferRestrictionType.ROFRAndCoSale,
            restrictionText: L3,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L4: Tokenized Stock Ledger
        restrictions[4] = TransferRestriction({
            restrictionType: TransferRestrictionType.CustomRestriction,
            restrictionText: L4,
            sourceAgreement: PINATA_URI,
            isRemovable: false,
            exceptions: noExc
        });
        // L5: Material Adverse Exception
        restrictions[5] = TransferRestriction({
            restrictionType: TransferRestrictionType.CustomRestriction,
            restrictionText: L5,
            sourceAgreement: PINATA_URI,
            isRemovable: false,
            exceptions: noExc
        });
        // 180-day lockup
        restrictions[6] = TransferRestriction({
            restrictionType: TransferRestrictionType.LockUp,
            restrictionText: L6_LOCKUP,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
    }

    function _buildShareCertData() internal pure returns (bytes memory) {
        SplitRecord[] memory splits = new SplitRecord[](1);
        splits[0] = SplitRecord({
            numerator: 1,
            denominator: 1,
            timestamp: 1_780_075_297,
            sourceAuthorityURI: PINATA_URI
        });

        ShareCertData memory scd = ShareCertData({
            terms: _buildSeriesTerms(),
            certificateData: CertificateData({
                isPartlyPaid: false,
                amountPaid: 0,
                totalConsideration: 0,
                sourceAuthorityURI: PINATA_URI,
                representationType: ShareRepresentationType.Tokenized,
                holdingPeriodTackingApplied: true
            }),
            mandatoryConversionTriggers: _buildConversionTriggers(),
            specialVotingRights: _buildVotingRights(),
            transferRestrictions: _buildTransferRestrictions(),
            splitHistory: splits
        });
        return abi.encode(scd);
    }

    function _makeCertData() internal view returns (CyberCertData[] memory certData) {
        string[] memory legend = new string[](6);
        legend[0] = L0; legend[1] = L1; legend[2] = L2;
        legend[3] = L3; legend[4] = L4; legend[5] = L5;

        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Seed Preferred Stock - MetaLeX Labs, Inc.",
            symbol: "MLI-SEED-PREFSTCK",
            uri: IPFS_URI,
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(shareExtension),
            defaultLegend: legend
        });
    }

    function _buildRound(address corp, address rmAddr)
        internal returns (Round memory round, CyberCertData[] memory certData)
    {
        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Dispute resolution method: Binding Arbitration|Governing law: Delaware";

        string[] memory roundPartyValues = new string[](5);
        roundPartyValues[0] = "Test Officer Name";
        roundPartyValues[1] = vm.toString(officer);
        roundPartyValues[2] = "contact@example.com (email), @handle_tg (Telegram)";
        roundPartyValues[3] = "";
        roundPartyValues[4] = "";

        bytes[] memory extData = new bytes[](1);
        extData[0] = _buildShareCertData();

        (bytes memory escrowedSig,) = CyberCorpHelper.computeEscrowSignature(
            rmAddr,
            SecuritySeries.SeriesSeed,
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            TEMPLATE_ID,
            address(usdc),
            PRICE_PER_UNIT,
            VALUATION,
            officerKey,
            corp
        );

        round = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                RoundType.FounderApproved,
                false, true, false,
                RAISE_CAP, MIN_TICKET, MAX_TICKET,
                address(usdc),
                PRICE_PER_UNIT,
                VALUATION,
                block.timestamp,
                block.timestamp + 30 days
            )
            .setAgreement(
                TEMPLATE_ID,
                officer,
                "Test Officer Name",
                "CEO",
                legalDetails,
                roundPartyValues,
                extData,
                new address[](0),
                escrowedSig
            );

        certData = _makeCertData();
    }

    function _buildEOICall(address rmAddr)
        internal
        returns (EOI memory eoi, string[] memory globalValues, string[] memory partyValues, bytes memory sig, uint256 salt)
    {
        eoi = EOI({
            name: "teh investOOOr",
            investorType: "Natural person",
            jurisdiction: "",
            contact: "@investOOOr (TG)",
            minAmount: EOI_AMOUNT,
            maxAmount: EOI_AMOUNT,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        globalValues = new string[](5);
        globalValues[0] = "26.213301";
        globalValues[1] = "76.29714395756566485";
        globalValues[2] = "Delaware";
        globalValues[3] = "";
        globalValues[4] = "";

        partyValues = new string[](5);
        partyValues[0] = "teh investOOOr";
        partyValues[1] = vm.toString(investor);
        partyValues[2] = "@investOOOr (TG)";
        partyValues[3] = "Natural person";
        partyValues[4] = "";

        salt = 0x19e75873baf;
        sig = CyberCorpHelper.computeEOISignature(
            registry,
            TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officer,
            investorKey
        );

        usdc.mint(investor, EOI_AMOUNT * 2);
        vm.prank(investor);
        usdc.approve(rmAddr, type(uint256).max);
    }

    // ── tests ─────────────────────────────────────────────────────────────────

    /// @notice Emulates createRound tx (block 25202917, 13,003,119 gas).
    ///         1 cert printer with 6 full legends + ShareCertData extension (13 KB).
    function test_gasLimit_createRound() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).createRound(round, certData);
        uint256 gasUsed = gasStart - gasleft();

        console2.log("createRound gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "createRound exceeds 90% of EIP-7825 block gas limit");
    }

    /// @notice Emulates submitEOI tx (block 25203564, 1,485,634 gas).
    ///         Investor submits on a FounderApproved round with real-world field values.
    function test_gasLimit_submitEOI() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        bytes32 roundId = RoundManager(rmAddr).createRound(round, certData);

        (
            EOI memory eoi,
            string[] memory globalValues,
            string[] memory partyValues,
            bytes memory sig,
            uint256 salt
        ) = _buildEOICall(rmAddr);

        vm.prank(investor);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).submitEOI(
            roundId, eoi, globalValues, partyValues, sig, salt, new address[](0), bytes32(0)
        );
        uint256 gasUsed = gasStart - gasleft();

        console2.log("submitEOI gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "submitEOI exceeds 90% of EIP-7825 block gas limit");
    }

    /// @notice Emulates allocate tx (block 25215285, 13,859,243 gas).
    ///         Officer allocates full EOI amount; cert stores the 13 KB ShareCertData.
    function test_gasLimit_allocate() public {
        (address corp,,,, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory, "MetaLeX Labs Inc.", officer, officer
        );
        (Round memory round, CyberCertData[] memory certData) = _buildRound(corp, rmAddr);

        vm.prank(officer);
        bytes32 roundId = RoundManager(rmAddr).createRound(round, certData);

        (
            EOI memory eoi,
            string[] memory globalValues,
            string[] memory partyValues,
            bytes memory sig,
            uint256 salt
        ) = _buildEOICall(rmAddr);

        vm.prank(investor);
        (bytes32 agreementId,) = RoundManager(rmAddr).submitEOI(
            roundId, eoi, globalValues, partyValues, sig, salt, new address[](0), bytes32(0)
        );

        vm.prank(officer);
        uint256 gasStart = gasleft();
        RoundManager(rmAddr).allocate(agreementId, EOI_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();

        console2.log("allocate gas:", gasUsed);
        assertLe(gasUsed, GAS_LIMIT_90_PCT, "allocate exceeds 90% of EIP-7825 block gas limit");
    }
}
