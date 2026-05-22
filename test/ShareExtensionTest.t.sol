// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
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
import {ShareExtensionLogic} from "../src/storage/extensions/ShareExtensionLogic.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ShareExtensionTest is Test {
    using RoundLib for Round;

    bytes32 internal constant TEMPLATE_ID = bytes32(uint256(777));
    bytes32 internal constant TEST_SALT = keccak256("ShareExtensionTest");

    uint256 internal constant OFFER_AMOUNT = 100_000e18;
    uint256 internal constant PRICE_PER_SHARE = 10e18;
    uint256 internal constant RAISE_CAP = 1_000_000e18;
    uint256 internal constant VALUATION = 25_000_000e18;

    uint256 internal officerPrivKey = 0xA11CE;
    uint256 internal investorPrivKey = 0xB0B;
    address internal officer;
    address internal investor;

    BorgAuth internal bootstrapAuth;
    BorgAuth internal extensionAuth;
    BorgAuth internal lexchexAuth;
    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    RoundManager internal roundManager;
    IIssuanceManager internal issuanceManager;
    CyberCertPrinter internal certPrinter;
    CertificateUriBuilder internal uriBuilder;
    ShareExtension internal shareExtension;
    ShareExtensionLogic internal shareLogic;
    MockPaymentToken internal paymentToken;

    address internal corpAddress;
    bytes32 internal roundId;
    bytes32 internal agreementId;
    uint256 internal tokenId;
    bytes internal initialShareData;

    function setUp() public {
        officer = vm.addr(officerPrivKey);
        investor = vm.addr(investorPrivKey);
        vm.etch(officer, bytes(""));
        vm.etch(investor, bytes(""));

        _deployFactories();
        _deployShareContracts();
        _createTemplate();
        _deployCorp();
        _mintSeriesAShareCertificate();
    }

    function testSetUp_MintsSeriesAShareCertThroughFactoryRoundFlow() public {
        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.getExtension(tokenId), address(shareExtension));
        assertEq(keccak256(certPrinter.getExtensionData(tokenId)), keccak256(initialShareData));

        CertificateDetails memory details = certPrinter.getCertificateDetails(tokenId);
        assertEq(details.signingOfficerName, "Series A Officer");
        assertEq(details.signingOfficerTitle, "CEO");
        assertEq(details.investmentAmountUSD, OFFER_AMOUNT);
        assertEq(details.issuerUSDValuationAtTimeOfInvestment, VALUATION);
        assertEq(details.unitsRepresented, (OFFER_AMOUNT * 1e18) / PRICE_PER_SHARE);
        assertEq(details.legalDetails, "Series A Preferred Stock Certificate");

        string memory shareJson = shareExtension.getExtensionURI(details.extensionData);
        assertTrue(_contains(shareJson, '"shareDetails": {'));
        assertTrue(_contains(shareJson, '"seriesName": "Series A Preferred"'));
        assertTrue(_contains(shareJson, '"issuerName": "Test CyberCorp"'));
        assertTrue(_contains(certPrinter.tokenURI(tokenId), "data:application/json;base64,"));
    }

    function testLogic_DecodeAndValidateLiveSharePayload() public {
        bytes memory storedData = certPrinter.getExtensionData(tokenId);

        ShareCertData memory formatterDecoded = shareExtension.decodeExtensionData(storedData);
        ShareCertData memory logicDecoded = shareLogic.decodeExtensionData(storedData);
        (bool valid, string memory error) = shareLogic.validateShareData(storedData);

        assertTrue(valid);
        assertEq(error, "");
        assertEq(formatterDecoded.terms.seriesName, "Series A Preferred");
        assertEq(logicDecoded.issuerName, "Test CyberCorp");
        assertEq(logicDecoded.transferRestrictions.length, 1);
        assertEq(logicDecoded.specialVotingRights.length, 1);
        assertEq(logicDecoded.mandatoryConversionTriggers.length, 1);
    }

    function testLogic_UpdateConversionPriceAndRatio() public {
        bytes memory updatedData = shareLogic.updateConversionPrice(certPrinter.getExtensionData(tokenId), 8e18);
        ShareCertData memory decoded = shareLogic.decodeExtensionData(updatedData);
        uint256 ratio = shareLogic.getConversionRatio(updatedData);

        assertEq(decoded.terms.conversionPrice, 8e18);
        assertEq(ratio, (decoded.terms.originalIssuePrice * 1e18) / 8e18);

        string memory json = shareExtension.getExtensionURI(updatedData);
        assertTrue(_contains(json, '"conversionPrice": "8000000000000000000"'));
    }

    function testLogic_RecordStockSplitAdjustsSharePayload() public {
        bytes memory updatedData =
            shareLogic.recordStockSplit(certPrinter.getExtensionData(tokenId), 2, 1, "ipfs://split-board-consent", block.timestamp);

        ShareCertData memory decoded = shareLogic.decodeExtensionData(updatedData);

        assertEq(decoded.terms.authorizedShares, 20_000_000);
        assertEq(decoded.certificateData.numberOfShares, 20_000);
        assertEq(decoded.terms.originalIssuePrice, 5e18);
        assertEq(decoded.terms.parValue, 5e15);
        assertEq(decoded.terms.conversionPrice, 5e18);
        assertEq(decoded.terms.redemptionPrice, 6e18);
        assertEq(decoded.mandatoryConversionTriggers[0].primaryThreshold, 6e18);
        assertEq(decoded.splitHistory.length, 1);
        assertEq(decoded.splitHistory[0].numerator, 2);
        assertEq(decoded.splitHistory[0].denominator, 1);
    }

    function testLogic_ComputesAccruedDividendsForCumulativeSeries() public {
        uint256 accrued = shareLogic.computeAccruedDividends(certPrinter.getExtensionData(tokenId), block.timestamp + 365 days);

        assertEq(accrued, 10_000e18);
    }

    function testLogic_ManagesDynamicArrayPayloadSections() public {
        bytes memory workingData = certPrinter.getExtensionData(tokenId);

        MandatoryConversionTrigger memory trigger = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.Custom,
            primaryThreshold: 0,
            secondaryThreshold: 0,
            additionalConditions: "Board approved recapitalization",
            description: "Automatic conversion on recapitalization"
        });
        workingData = shareLogic.addConversionTrigger(workingData, trigger);

        SpecialVotingRight memory votingRight = SpecialVotingRight({
            matterType: keccak256("NEW_BOARD_SEAT"),
            votesPerShare: 2e18,
            threshold: 6000,
            isVetoRight: false,
            scope: VotingScope.SeriesSpecific,
            description: "Series vote to add a board seat"
        });
        workingData = shareLogic.addSpecialVotingRight(workingData, votingRight);

        TransferRestrictionException[] memory exceptions = new TransferRestrictionException[](1);
        exceptions[0] = TransferRestrictionException({
            exceptionType: keccak256("AFFILIATE_TRANSFER"),
            exceptionText: "Transfers to affiliates are permitted",
            requiresEvidence: true
        });

        TransferRestriction memory restriction = TransferRestriction({
            restrictionType: TransferRestrictionType.CustomRestriction,
            restrictionText: "Subject to side letter transfer limits",
            sourceAgreement: "Side Letter",
            isRemovable: true,
            exceptions: exceptions
        });
        workingData = shareLogic.addTransferRestriction(workingData, restriction);

        ShareCertData memory expanded = shareLogic.decodeExtensionData(workingData);
        assertEq(expanded.mandatoryConversionTriggers.length, 2);
        assertEq(expanded.specialVotingRights.length, 2);
        assertEq(expanded.transferRestrictions.length, 2);

        workingData = shareLogic.removeConversionTrigger(workingData, 1);
        workingData = shareLogic.removeSpecialVotingRight(workingData, 1);
        workingData = shareLogic.removeTransferRestriction(workingData, 1);

        ShareCertData memory collapsed = shareLogic.decodeExtensionData(workingData);
        assertEq(collapsed.mandatoryConversionTriggers.length, 1);
        assertEq(collapsed.specialVotingRights.length, 1);
        assertEq(collapsed.transferRestrictions.length, 1);
    }

    function testLogic_RejectsInvalidSeriesTerms() public {
        ShareCertData memory shareData = shareLogic.decodeExtensionData(certPrinter.getExtensionData(tokenId));
        shareData.terms.isConvertible = false;
        shareData.terms.conversionPrice = 1e18;
        shareData.terms.targetConversionSeriesId = bytes32(0);
        shareData.terms.hasMandatoryConversion = false;

        (bool valid, string memory error) = shareLogic.validateSeriesTerms(shareData.terms);
        assertFalse(valid);
        assertEq(error, "ShareExtensionLogic: conversionPrice must be 0 when not convertible");

        vm.expectRevert(bytes("ShareExtensionLogic: conversionPrice must be 0 when not convertible"));
        shareLogic.updateSeriesTerms(certPrinter.getExtensionData(tokenId), shareData.terms);
    }

    function _deployFactories() internal {
        bootstrapAuth = new BorgAuth(address(this));

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(bootstrapAuth))
                )
            )
        );

        uriBuilder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(bootstrapAuth))
                )
            )
        );
        uriBuilder.setImageBuilder(address(new CertificateImageBuilderContract()));

        address issuanceManagerFactory = address(
            new ERC1967Proxy(
                address(new IssuanceManagerFactory()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(new IssuanceManager()),
                    address(new CyberCertPrinter()),
                    address(new CyberScrip())
                )
            )
        );

        address cyberCorpSingleFactory = address(
            new ERC1967Proxy(
                address(new CyberCorpSingleFactory()),
                abi.encodeWithSelector(
                    CyberCorpSingleFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(new CyberCorp())
                )
            )
        );

        address dealManagerFactory = address(
            new ERC1967Proxy(
                address(new DealManagerFactory()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector, address(bootstrapAuth), address(new DealManager())
                )
            )
        );

        address roundManagerFactory = address(
            new ERC1967Proxy(
                address(new RoundManagerFactory()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector, address(bootstrapAuth), address(new RoundManager())
                )
            )
        );

        corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy(
                    address(new CyberCorpFactory()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(bootstrapAuth),
                        address(registry),
                        issuanceManagerFactory,
                        cyberCorpSingleFactory,
                        dealManagerFactory,
                        roundManagerFactory,
                        address(uriBuilder)
                    )
                )
            )
        );

        // Local tests cannot use the factory's default deployed LeXcheX auth.
        lexchexAuth = new BorgAuth(address(corpFactory));
        corpFactory.setLexchexAuth(address(lexchexAuth));
    }

    function _deployShareContracts() internal {
        extensionAuth = new BorgAuth(address(this));
        shareExtension = new ShareExtension();
        shareExtension.initialize(address(extensionAuth));
        shareLogic = new ShareExtensionLogic();
    }

    function _createTemplate() internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Subscription Terms";

        string[] memory partyFields = new string[](2);
        partyFields[0] = "Investor Name";
        partyFields[1] = "Investor Title";

        registry.createTemplate(
            TEMPLATE_ID, "Series A Subscription", "ipfs://series-a-template", globalFields, partyFields
        );
    }

    function _deployCorp() internal {
        CompanyOfficer memory companyOfficer =
            CompanyOfficer({eoa: officer, name: "Series A Officer", contact: "ceo@test.com", title: "CEO"});

        address issuanceManagerAddress;
        address dealManagerAddress;
        address roundManagerAddress;
        (
            corpAddress,
            ,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress
        ) = corpFactory.deployCyberCorp(
            TEST_SALT,
            "Test CyberCorp",
            "corporation",
            "DE",
            "contact@test.com",
            "Delaware",
            address(this),
            companyOfficer
        );

        issuanceManager = IIssuanceManager(issuanceManagerAddress);
        roundManager = RoundManager(roundManagerAddress);

        dealManagerAddress;
    }

    function _mintSeriesAShareCertificate() internal {
        paymentToken = new MockPaymentToken();
        paymentToken.mint(investor, OFFER_AMOUNT * 2);

        initialShareData = _buildInitialShareData();
        roundId = _createSeriesARound(initialShareData);

        vm.startPrank(investor);
        paymentToken.approve(address(roundManager), type(uint256).max);
        (agreementId, tokenId) = roundManager.submitEOI(
            roundId,
            _buildEoi(),
            _globalValues(),
            _partyValues(),
            _computeEoiSignature(1),
            1,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Round memory round = roundManager.getRound(roundId);
        certPrinter = CyberCertPrinter(round.certPrinter[0]);
    }

    function _createSeriesARound(bytes memory extensionData) internal returns (bytes32 createdRoundId) {
        string[] memory legend = new string[](1);
        legend[0] = "Series A legend";

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Series A Certificate",
            symbol: "SRSA",
            uri: "ipfs://series-a-cert",
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(shareExtension),
            defaultLegend: legend
        });

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Series A Preferred Stock Certificate";

        bytes[] memory extensionDataArray = new bytes[](1);
        extensionDataArray[0] = extensionData;

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Series A Officer";
        roundPartyValues[1] = "CEO";

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;
        bytes memory escrowSignature = _computeEscrowSignature(startTime, endTime);

        vm.prank(officer);
        createdRoundId = roundManager.createRound(
            RoundLib.draft().setTickets(
                SecuritySeries.SeriesA,
                RoundType.FCFS,
                false,
                true,
                RAISE_CAP,
                OFFER_AMOUNT,
                OFFER_AMOUNT,
                address(paymentToken),
                PRICE_PER_SHARE,
                VALUATION,
                startTime,
                endTime
            ).setAgreement(
                TEMPLATE_ID,
                officer,
                "Series A Officer",
                "CEO",
                legalDetails,
                roundPartyValues,
                extensionDataArray,
                new address[](0),
                escrowSignature
            ),
            certData
        );
    }

    function _buildInitialShareData() internal view returns (bytes memory) {
        TransferRestrictionException[] memory exceptions = new TransferRestrictionException[](1);
        exceptions[0] = TransferRestrictionException({
            exceptionType: keccak256("ESTATE_PLANNING_TRANSFER"),
            exceptionText: "Permitted estate planning transfer",
            requiresEvidence: true
        });

        TransferRestriction[] memory restrictions = new TransferRestriction[](1);
        restrictions[0] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: shareExtension.SECURITIES_ACT_LEGEND(),
            sourceAgreement: "Securities Act",
            isRemovable: true,
            exceptions: exceptions
        });

        MandatoryConversionTrigger[] memory conversionTriggers = new MandatoryConversionTrigger[](1);
        conversionTriggers[0] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.QualifiedIPO,
            primaryThreshold: 12e18,
            secondaryThreshold: 50_000_000e18,
            additionalConditions: "Listed on NYSE or NASDAQ",
            description: "Auto-converts upon a qualified IPO"
        });

        SpecialVotingRight[] memory votingRights = new SpecialVotingRight[](1);
        votingRights[0] = SpecialVotingRight({
            matterType: keccak256("MERGER_APPROVAL"),
            votesPerShare: 1e18,
            threshold: 6000,
            isVetoRight: true,
            scope: VotingScope.SeriesSpecific,
            description: "Series A veto on merger approval"
        });

        SplitRecord[] memory splitHistory = new SplitRecord[](0);

        ShareCertData memory shareData = ShareCertData({
            terms: SeriesTerms({
                shareClassKey: keccak256("PREFERRED"),
                seriesName: "Series A Preferred",
                parValue: 0.01e18,
                authorizedShares: 10_000_000,
                originalIssuePrice: 10e18,
                effectiveDate: block.timestamp,
                sourceAuthorityURI: "ipfs://charter-series-a",
                liquidationPreferenceMultiple: 1e18,
                liquidationPreferenceType: LiquidationPreferenceType.CappedParticipating,
                participationCap: 3e18,
                seniorityRank: 1,
                dividendType: DividendType.Cumulative,
                dividendRate: 0.1e18,
                dividendAccrualStartDate: block.timestamp,
                dividendCompounding: false,
                dividendIncreasesLiquidationAmount: true,
                isConvertible: true,
                targetConversionSeriesId: bytes32("COMMON"),
                conversionPrice: 10e18,
                antiDilutionType: AntiDilutionType.BroadBasedWeightedAverage,
                allowsFractionalConversion: true,
                hasMandatoryConversion: true,
                votesPerShare: 1e18,
                designatedBoardSeats: 1,
                hasClassVotingRights: true,
                hasSeriesVotingRights: true,
                isRedeemable: true,
                redemptionType: RedemptionType.CompanyOptional,
                redemptionPrice: 12e18,
                redemptionSchedule: "Redeemable after year 5",
                redemptionTriggerDescription: "Company election after five years",
                hasPayToPlay: true,
                payToPlayTermsURI: "ipfs://pay-to-play",
                hasRegistrationRights: true,
                registrationRightsURI: "ipfs://registration-rights",
                hasProRataRights: true,
                hasInformationRights: true,
                hasDragAlongRights: true,
                dragAlongTermsURI: "ipfs://drag-along"
            }),
            certificateData: CertificateData({
                seriesId: bytes32("SERIES_A_2026"),
                numberOfShares: 10_000,
                issueDate: block.timestamp,
                isPartlyPaid: true,
                amountPaid: 50_000e18,
                totalConsideration: 100_000e18,
                sourceAuthorityURI: "ipfs://board-approval",
                representationType: ShareRepresentationType.Certificated,
                holdingPeriodStartDate: block.timestamp - 30 days,
                holdingPeriodTackingApplied: false
            }),
            mandatoryConversionTriggers: conversionTriggers,
            specialVotingRights: votingRights,
            transferRestrictions: restrictions,
            splitHistory: splitHistory,
            issuerName: "Test CyberCorp",
            stateOfIncorporation: "Delaware"
        });

        return shareExtension.encodeExtensionData(shareData);
    }

    function _buildEoi() internal view returns (EOI memory) {
        return EOI({
            name: "Series A Investor",
            investorType: "Institution",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: OFFER_AMOUNT,
            maxAmount: OFFER_AMOUNT,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });
    }

    function _globalValues() internal pure returns (string[] memory values) {
        values = new string[](1);
        values[0] = "Series A Preferred Stock Subscription";
    }

    function _partyValues() internal pure returns (string[] memory values) {
        values = new string[](2);
        values[0] = "Series A Investor";
        values[1] = "Managing Member";
    }

    function _computeEscrowSignature(uint256 startTime, uint256 endTime) internal view returns (bytes memory sig) {
        bytes32 computedRoundId = keccak256(
            abi.encodePacked(
                SecuritySeries.SeriesA,
                RAISE_CAP,
                OFFER_AMOUNT,
                OFFER_AMOUNT,
                uint8(RoundType.FCFS),
                startTime,
                endTime,
                TEMPLATE_ID,
                address(paymentToken),
                PRICE_PER_SHARE,
                VALUATION,
                corpAddress
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("RoundManager")),
                keccak256(bytes("1")),
                block.chainid,
                address(roundManager)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
                ),
                computedRoundId,
                uint8(SecuritySeries.SeriesA),
                RAISE_CAP,
                OFFER_AMOUNT,
                OFFER_AMOUNT,
                uint8(RoundType.FCFS),
                startTime,
                endTime,
                TEMPLATE_ID,
                address(paymentToken),
                PRICE_PER_SHARE,
                VALUATION,
                corpAddress
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(officerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _computeEoiSignature(uint256 salt) internal view returns (bytes memory) {
        (string memory legalUri,, string[] memory globalFields, string[] memory partyFields) =
            registry.getTemplateDetails(TEMPLATE_ID);

        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;

        bytes32 contractId = keccak256(abi.encode(TEMPLATE_ID, salt, _globalValues(), parties));

        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            legalUri,
            globalFields,
            partyFields,
            _globalValues(),
            _partyValues(),
            investorPrivKey
        );
    }

    function _emptyLex() internal pure returns (LexChexDetails memory) {
        return LexChexDetails({
            request: MintRequest({
                uuid: 0,
                owner: address(0),
                investorName: "",
                investorType: "",
                investorJurisdiction: "",
                investorContact: "",
                mintPrice: 0,
                expiry: 0,
                paymentToken: address(0)
            }),
            templateId: bytes32(0),
            salt: 0,
            globalValues: new string[](0),
            parties: new address[](0),
            partyValues: new string[][](0),
            agreementSignature: ""
        });
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0) return true;
        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool matchFound = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) return true;
        }

        return false;
    }
}
