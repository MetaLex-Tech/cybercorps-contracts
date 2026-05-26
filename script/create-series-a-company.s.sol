// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {
    ShareExtension,
    ShareCertData,
    SeriesTerms,
    CertificateData,
    MandatoryConversionTrigger,
    MandatoryConversionTriggerType,
    SpecialVotingRight,
    TransferRestriction,
    TransferRestrictionException,
    SplitRecord,
    LiquidationPreferenceType,
    AntiDilutionType,
    DividendType,
    TransferRestrictionType,
    RedemptionType,
    VotingScope,
    ShareRepresentationType
} from "../src/storage/extensions/ShareExtension.sol";
import {CyberCertData} from "../src/storage/RoundManagerStorage.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

// Required env vars:
//   PRIVATE_KEY_MAIN        — deployer / signing officer key
//   SHARE_EXTENSION_ADDRESS — deployed ShareExtension proxy
//
// Optional env vars (defaults shown):
//   COMPANY_NAME            — "Acme Corp"
//   COMPANY_CONTACT         — "contact@acmecorp.com"
//   OFFICER_NAME            — "Jane Smith"
//   OFFICER_TITLE           — "CEO"
//   OFFICER_CONTACT         — "ceo@acmecorp.com"
//
// Run:
//   forge script script/create-series-a-company.s.sol \
//     --rpc-url <RPC> --broadcast --via-ir

contract CreateSeriesACompanyScript is Script {
    using RoundLib for Round;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 internal constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    // Template for the Series A subscription agreement.
    // Using a unique hash avoids colliding with any existing template.
    bytes32 internal constant SERIES_A_TEMPLATE_ID = keccak256("MetaLex.SeriesAPreferredSubscription.v1");

    // Round economics — edit before deploying to mainnet.
    uint256 internal constant RAISE_CAP       = 10_000_000e18; // $10M
    uint256 internal constant MIN_TICKET      = 10_000e18;     // $10K
    uint256 internal constant MAX_TICKET      = 1_000_000e18;  // $1M
    uint256 internal constant PRICE_PER_SHARE = 10e18;         // $10/share
    uint256 internal constant VALUATION       = 25_000_000e18; // $25M pre-money
    uint256 internal constant ROUND_DURATION  = 90 days;

    // Share terms
    uint256 internal constant AUTHORIZED_SHARES = 10_000_000;
    uint256 internal constant PAR_VALUE         = 0.01e18;
    uint256 internal constant DIVIDEND_RATE     = 0.08e18; // 8% annual
    uint256 internal constant LIQ_PREF_MULTIPLE = 1e18;    // 1x
    uint256 internal constant PARTICIPATION_CAP  = 3e18;   // 3x cap
    uint256 internal constant REDEMPTION_PRICE   = 12e18;  // $12/share

    function run() external {
        uint256 privKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privKey);
        address shareExtensionAddr = vm.envAddress("SHARE_EXTENSION_ADDRESS");

        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        address paymentToken = _resolveStable();

        CyberCorpFactory corpFactory = CyberCorpFactory(core.cyberCorpFactory);
        CyberAgreementRegistry registry = CyberAgreementRegistry(core.cyberAgreementRegistry);
        ShareExtension shareExtension = ShareExtension(shareExtensionAddr);

        string memory companyName = vm.envOr("COMPANY_NAME", string("Acme Corp"));
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: deployer,
            name: vm.envOr("OFFICER_NAME", string("Jane Smith")),
            contact: vm.envOr("OFFICER_CONTACT", string("ceo@acmecorp.com")),
            title: vm.envOr("OFFICER_TITLE", string("CEO"))
        });

        // Salt incorporates the company name and timestamp so re-runs produce distinct corps.
        bytes32 corpSalt = keccak256(abi.encodePacked(companyName, ".SeriesA.dev0"));

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + ROUND_DURATION;

        vm.startBroadcast(privKey);

        // 1. Register the subscription agreement template (no-op if it already exists).
        _createTemplate(registry);

        // 2. Deploy the company and its peripheral contracts.
        (
            address corpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress
        ) = corpFactory.deployCyberCorp(
            corpSalt,
            companyName,
            "corporation",
            "DE",
            vm.envOr("COMPANY_CONTACT", string("contact@acmecorp.com")),
            "Delaware",
            deployer,
            officer
        );
        console2.log("roundManagerAddress: %s", roundManagerAddress);

        // 3. Build the default share certificate data for this round.
        bytes memory shareData = _buildShareData(shareExtension, startTime);

        // 4. Sign the round parameters as the authority officer.
        bytes memory escrowSig = _computeEscrowSignature(
            roundManagerAddress,
            corpAddress,
            startTime,
            endTime,
            paymentToken,
            privKey
        );

        // 5. Create the Series A preferred stock round.
        CyberCertData[] memory certData = _buildCertData(shareExtensionAddr);
        bytes[] memory extensionDataArray = new bytes[](1);
        extensionDataArray[0] = shareData;
        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Series A Preferred Stock Certificate";
        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = officer.name;
        roundPartyValues[1] = officer.title;

        bytes32 roundId = RoundManager(roundManagerAddress).createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesA,
                    RoundType.FCFS,
                    false, // private round
                    true,  // allow timed offers
                    false, // allow end time reduction
                    RAISE_CAP,
                    MIN_TICKET,
                    MAX_TICKET,
                    paymentToken,
                    PRICE_PER_SHARE,
                    VALUATION,
                    startTime,
                    endTime
                )
                .setAgreement(
                    SERIES_A_TEMPLATE_ID,
                    officer.eoa,
                    officer.name,
                    officer.title,
                    legalDetails,
                    roundPartyValues,
                    extensionDataArray,
                    new address[](0),
                    escrowSig
                ),
            certData
        );

        vm.stopBroadcast();

        console2.log("=== Series A Round Deployed ===");
        console2.log("CyberCorp:        ", corpAddress);
        console2.log("Auth:             ", authAddress);
        console2.log("IssuanceManager:  ", issuanceManagerAddress);
        console2.log("DealManager:      ", dealManagerAddress);
        console2.log("RoundManager:     ", roundManagerAddress);
        console2.log("ShareExtension:   ", shareExtensionAddr);
        console2.log("PaymentToken:     ", paymentToken);
        console2.log("Round ID:");
        console2.logBytes32(roundId);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _createTemplate(CyberAgreementRegistry registry) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Subscription Terms";

        string[] memory partyFields = new string[](2);
        partyFields[0] = "Signatory Name";
        partyFields[1] = "Signatory Title";

        try registry.createTemplate(
            SERIES_A_TEMPLATE_ID,
            "Series A Preferred Stock Subscription",
            "ipfs://series-a-preferred-subscription",
            globalFields,
            partyFields
        ) {} catch {}
    }

    function _buildCertData(address shareExtensionAddr) internal pure returns (CyberCertData[] memory certData) {
        string[] memory legend = new string[](1);
        legend[0] =
            "THESE SECURITIES HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED, "
            "OR APPLICABLE STATE SECURITIES LAWS. THE SECURITIES MAY NOT BE OFFERED FOR SALE, SOLD, "
            "TRANSFERRED OR ASSIGNED IN THE ABSENCE OF REGISTRATION OR AN EXEMPTION THEREFROM.";

        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Series A Preferred Stock Certificate",
            symbol: "SRSA",
            uri: "ipfs://series-a-preferred-cert",
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesA,
            extension: shareExtensionAddr,
            defaultLegend: legend
        });
    }

    function _buildShareData(ShareExtension shareExtension, uint256 effectiveDate)
        internal
        view
        returns (bytes memory)
    {
        TransferRestrictionException[] memory exceptions = new TransferRestrictionException[](1);
        exceptions[0] = TransferRestrictionException({
            exceptionType: keccak256("ESTATE_PLANNING_TRANSFER"),
            exceptionText: "Transfers to immediate family members and revocable trusts for estate planning purposes are permitted.",
            requiresEvidence: true
        });

        TransferRestriction[] memory restrictions = new TransferRestriction[](1);
        restrictions[0] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: shareExtension.SECURITIES_ACT_LEGEND(),
            sourceAgreement: "Securities Act of 1933",
            isRemovable: true,
            exceptions: exceptions
        });

        MandatoryConversionTrigger[] memory conversionTriggers = new MandatoryConversionTrigger[](1);
        conversionTriggers[0] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.QualifiedIPO,
            primaryThreshold: 15e18,       // $15/share minimum IPO price
            secondaryThreshold: 75_000_000e18, // $75M minimum aggregate proceeds
            additionalConditions: "Listed on NYSE, NASDAQ, or another nationally recognized exchange",
            description: "Automatically converts to common stock upon a qualified IPO"
        });

        SpecialVotingRight[] memory votingRights = new SpecialVotingRight[](1);
        votingRights[0] = SpecialVotingRight({
            matterType: keccak256("MERGER_ACQUISITION"),
            votesPerShare: 1e18,
            threshold: 6666, // 66.66%
            isVetoRight: true,
            scope: VotingScope.SeriesSpecific,
            description: "Series A veto right on merger or acquisition transactions"
        });

        ShareCertData memory shareData = ShareCertData({
            terms: SeriesTerms({
                shareClassKey: keccak256("SERIES_A_PREFERRED"),
                seriesName: "Series A Preferred",
                parValue: PAR_VALUE,
                authorizedShares: AUTHORIZED_SHARES,
                originalIssuePrice: PRICE_PER_SHARE,
                effectiveDate: effectiveDate,
                sourceAuthorityURI: "ipfs://series-a-board-authorization",
                liquidationPreferenceMultiple: LIQ_PREF_MULTIPLE,
                liquidationPreferenceType: LiquidationPreferenceType.CappedParticipating,
                participationCap: PARTICIPATION_CAP,
                seniorityRank: 1,
                dividendType: DividendType.Cumulative,
                dividendRate: DIVIDEND_RATE,
                dividendAccrualStartDate: effectiveDate,
                dividendCompounding: false,
                dividendIncreasesLiquidationAmount: true,
                isConvertible: true,
                targetConversionSeriesId: bytes32("COMMON"),
                conversionPrice: PRICE_PER_SHARE,
                antiDilutionType: AntiDilutionType.BroadBasedWeightedAverage,
                allowsFractionalConversion: false,
                hasMandatoryConversion: true,
                votesPerShare: 1e18,
                designatedBoardSeats: 1,
                hasClassVotingRights: true,
                hasSeriesVotingRights: true,
                isRedeemable: true,
                redemptionType: RedemptionType.CompanyOptional,
                redemptionPrice: REDEMPTION_PRICE,
                redemptionSchedule: "Redeemable at company election after the fifth anniversary of issuance",
                redemptionTriggerDescription: "Company election exercisable after five years from issuance date",
                hasPayToPlay: true,
                payToPlayTermsURI: "ipfs://series-a-pay-to-play",
                hasRegistrationRights: true,
                registrationRightsURI: "ipfs://series-a-registration-rights",
                hasProRataRights: true,
                hasInformationRights: true,
                hasDragAlongRights: true,
                dragAlongTermsURI: "ipfs://series-a-drag-along"
            }),
            certificateData: CertificateData({
                isPartlyPaid: false,
                amountPaid: MAX_TICKET,
                totalConsideration: MAX_TICKET,
                sourceAuthorityURI: "ipfs://series-a-board-approval",
                representationType: ShareRepresentationType.Certificated,
                holdingPeriodTackingApplied: false
            }),
            mandatoryConversionTriggers: conversionTriggers,
            specialVotingRights: votingRights,
            transferRestrictions: restrictions,
            splitHistory: new SplitRecord[](0)
        });

        return shareExtension.encodeExtensionData(shareData);
    }

    function _computeEscrowSignature(
        address roundManagerAddress,
        address corpAddress,
        uint256 startTime,
        uint256 endTime,
        address paymentToken,
        uint256 signerPrivKey
    ) internal view returns (bytes memory sig) {
        bytes32 roundId = keccak256(
            abi.encodePacked(
                SecuritySeries.SeriesA,
                RAISE_CAP,
                MIN_TICKET,
                MAX_TICKET,
                uint8(RoundType.FCFS),
                startTime,
                endTime,
                SERIES_A_TEMPLATE_ID,
                paymentToken,
                PRICE_PER_SHARE,
                VALUATION,
                corpAddress
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("RoundManager")),
                keccak256(bytes("1")),
                block.chainid,
                roundManagerAddress
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                ESCROWEDSIGNATUREDATA_TYPEHASH,
                roundId,
                uint8(SecuritySeries.SeriesA),
                RAISE_CAP,
                MIN_TICKET,
                MAX_TICKET,
                uint8(RoundType.FCFS),
                startTime,
                endTime,
                SERIES_A_TEMPLATE_ID,
                paymentToken,
                PRICE_PER_SHARE,
                VALUATION,
                corpAddress
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _resolveStable() internal view returns (address) {
        uint256 chainId = block.chainid;
        if (chainId == 1)        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet USDC
        if (chainId == 42161)    return 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum USDC
        if (chainId == 8453)     return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base USDC
        if (chainId == 84532)    return 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC
        if (chainId == 11155111) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC
        revert("CreateSeriesACompanyScript: unsupported chain");
    }
}
