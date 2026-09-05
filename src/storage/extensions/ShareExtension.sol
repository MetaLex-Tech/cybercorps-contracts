/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o



ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



  .oooooo.                .o8                            .oooooo.
 d8P'  `Y8b              "888                           d8P'  `Y8b
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
             .o..P'                                                                     888
             `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import "../../libs/auth.sol";
import "../../libs/JsonLib.sol";
import "./ICertificateExtension.sol";

enum LiquidationPreferenceType {
    NonParticipating,
    Participating,
    CappedParticipating
}

enum AntiDilutionType {
    None,
    BroadBasedWeightedAverage,
    NarrowBasedWeightedAverage,
    FullRatchet
}

enum DividendType {
    None,
    NonCumulative,
    Cumulative
}

enum TransferRestrictionType {
    None,
    BoardConsentRequired,
    ROFRAndCoSale,
    LockUp,
    SecuritiesActRestriction,
    CustomRestriction
}

enum RedemptionType {
    None,
    HolderOptional,
    CompanyOptional,
    Mandatory,
    EventTriggered
}

enum MandatoryConversionTriggerType {
    QualifiedIPO,
    ClassVote,
    DeemedLiquidation,
    Custom
}

enum VotingScope {
    ClassWide,
    SeriesSpecific
}

enum ShareRepresentationType {
    Certificated,
    Uncertificated,
    Tokenized
}

struct MandatoryConversionTrigger {
    MandatoryConversionTriggerType triggerType;
    uint256 primaryThreshold;
    uint256 secondaryThreshold;
    string additionalConditions;
    string description;
}

struct SpecialVotingRight {
    string matterType;
    uint256 votesPerShare;
    uint256 threshold;
    bool isVetoRight;
    VotingScope scope;
    string description;
}

struct TransferRestrictionException {
    string exceptionType;
    string exceptionText;
    bool requiresEvidence;
}

struct TransferRestriction {
    TransferRestrictionType restrictionType;
    string restrictionText;
    string sourceAgreement;
    bool isRemovable;
    TransferRestrictionException[] exceptions;
}

struct SplitRecord {
    uint256 numerator;
    uint256 denominator;
    uint256 timestamp;
    string sourceAuthorityURI;
}

struct SeriesTerms {
    string seriesName;
    uint256 parValue;
    uint256 authorizedShares;
    uint256 originalIssuePrice;
    uint256 effectiveDate;
    string sourceAuthorityURI;
    uint256 liquidationPreferenceMultiple;
    LiquidationPreferenceType liquidationPreferenceType;
    uint256 participationCap;
    uint256 seniorityRank;
    DividendType dividendType;
    uint256 dividendRate;
    uint256 dividendAccrualStartDate;
    bool dividendCompounding;
    bool dividendIncreasesLiquidationAmount;
    bool isConvertible;
    string targetConversionSeriesId;
    uint256 conversionPrice;
    AntiDilutionType antiDilutionType;
    bool allowsFractionalConversion;
    bool hasMandatoryConversion;
    uint256 votesPerShare;
    uint8 designatedBoardSeats;
    bool hasClassVotingRights;
    bool hasSeriesVotingRights;
    bool isRedeemable;
    RedemptionType redemptionType;
    uint256 redemptionPrice;
    string redemptionSchedule;
    string redemptionTriggerDescription;
    bool hasPayToPlay;
    string payToPlayTermsURI;
    bool hasRegistrationRights;
    string registrationRightsURI;
    bool hasProRataRights;
    string proRataRightsURI;
    bool hasInformationRights;
    string informationRightsURI;
    bool hasDragAlongRights;
    string dragAlongTermsURI;
}

struct CertificateData {
    /// @notice Flags the cert as partly paid stock under DGCL §156.
    /// @dev Switches `_getPaymentPercentage` between the fully paid early return
    ///      (`PERCENTAGE_PRECISION`) and the `amountPaid`/`totalConsideration` ratio.
    bool isPartlyPaid;
    /// @notice Consideration received to date for the cert.
    /// @dev Ignored when the cert is fully paid (i.e. `isPartlyPaid is false`). The
    ///      difference `totalConsideration - amountPaid` is the unpaid subscription
    ///      balance.
    uint256 amountPaid;
    /// @notice Full subscription price agreed for the cert under the issuance terms.
    /// @dev Ignored when the cert is fully paid (i.e. `isPartlyPaid is false`).
    /// @dev Pairs with `amountPaid` and `isPartlyPaid` to model DGCL §156 partly paid
    ///      stock. Distinct from `CertificateDetails.investmentAmountUSD` (defined in
    ///      `src/CertificateUriBuilder.sol`), which records the USD amount actually
    ///      paid at issuance and is the value consumed by converters such as
    ///      `SafeCertificateConverter` for share-count math.
    /// @dev Fully paid cert invariant: `amountPaid == totalConsideration`, and both
    ///      are expected to equal the base `CertificateDetails.investmentAmountUSD`.
    ///      Partly paid cert: `amountPaid < totalConsideration`; the gap is the
    ///      outstanding subscription liability callable by the corporation under §156.
    /// @dev Seam: consumers reading the base `CertificateDetails` alone see only the
    ///      paid-to-date amount and miss the unpaid subscription balance. Tooling that
    ///      needs full subscription context must read the share extension data.
    uint256 totalConsideration;
    string sourceAuthorityURI;
    ShareRepresentationType representationType;
    bool holdingPeriodTackingApplied;
}

struct ShareCertData {
    SeriesTerms terms;
    CertificateData certificateData;
    MandatoryConversionTrigger[] mandatoryConversionTriggers;
    SpecialVotingRight[] specialVotingRights;
    TransferRestriction[] transferRestrictions;
    SplitRecord[] splitHistory;
}

contract ShareExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;
    string public constant SECURITIES_ACT_LEGEND =
        "THE SECURITIES REPRESENTED HEREBY HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, "
        "AS AMENDED (THE \"ACT\"), OR UNDER THE SECURITIES LAWS OF ANY STATE. THESE SECURITIES ARE "
        "SUBJECT TO RESTRICTIONS ON TRANSFERABILITY AND RESALE AND MAY NOT BE TRANSFERRED OR RESOLD "
        "EXCEPT AS PERMITTED UNDER THE ACT AND APPLICABLE STATE SECURITIES LAWS, PURSUANT TO "
        "REGISTRATION OR EXEMPTION THEREFROM.";

    uint256[30] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(bytes memory data) external pure returns (ShareCertData memory) {
        return abi.decode(data, (ShareCertData));
    }

    function encodeExtensionData(ShareCertData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    /// @notice Returns the canonical class-level portion of share extension data.
    /// @dev LedgerEntryToken hashes `termsData` and stores it once per printer.
    ///      CertificateData and the variable-length rights/history arrays remain
    ///      certificate-specific and are intentionally excluded.
    function getSeriesTermsData(
        bytes calldata data
    ) external pure returns (bytes memory termsData, uint256 authorizedShares) {
        ShareCertData memory share = abi.decode(data, (ShareCertData));
        termsData = abi.encode(share.terms);
        authorizedShares = share.terms.authorizedShares;
    }

    function supportsExtensionType(bytes32 extensionType) external pure virtual override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external pure override returns (string memory) {
        if (data.length == 0) return "";

        ShareCertData memory share = abi.decode(data, (ShareCertData));

        return string(
            abi.encodePacked(
                ', "shareDetails": {',
                _buildSeriesJson(share.terms),
                _buildCertificateJson(share.certificateData),

                // remaining fields
                abi.encodePacked(
                    '"mandatoryConversionTriggers": ', _buildMandatoryConversionTriggersJson(share.mandatoryConversionTriggers),
                    ', "specialVotingRights": ', _buildSpecialVotingRightsJson(share.specialVotingRights),
                    ', "transferRestrictions": ', _buildTransferRestrictionsJson(share.transferRestrictions),
                    ', "splitHistory": ', _buildSplitHistoryJson(share.splitHistory),
                    ', '
                ),

                // derived fields
                _buildDerivedJson(share),
                '}'
            )
        );
    }

    function _buildSeriesJson(SeriesTerms memory terms) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"terms": {',
                string(abi.encodePacked(
                    '"seriesName": "', JsonLib.jsonEscape(terms.seriesName),
                    '", "authorizedShares": "', from18DecimalsToString(terms.authorizedShares),
                    '", "parValue": "', from18DecimalsToString(terms.parValue),
                    '", "originalIssuePrice": "', from18DecimalsToString(terms.originalIssuePrice),
                    '", "liquidationPreferenceMultiple": "', from18DecimalsToString(terms.liquidationPreferenceMultiple),
                    '", "liquidationPreferenceType": "', _liquidationPreferenceTypeToString(terms.liquidationPreferenceType),
                    '", "dividendType": "', _dividendTypeToString(terms.dividendType),
                    '", "dividendRate": "', from18DecimalsToString(terms.dividendRate),
                    '", "isConvertible": "', JsonLib.boolToString(terms.isConvertible),
                    '", "conversionPrice": "', from18DecimalsToString(terms.conversionPrice),
                    '", "antiDilutionType": "', _antiDilutionTypeToString(terms.antiDilutionType),
                    '", "votesPerShare": "', from18DecimalsToString(terms.votesPerShare),
                    '", "designatedBoardSeats": "', Strings.toString(uint256(terms.designatedBoardSeats)),
                    '", "isRedeemable": "', JsonLib.boolToString(terms.isRedeemable),
                    '", "redemptionType": "', _redemptionTypeToString(terms.redemptionType),
                    '", "redemptionPrice": "', from18DecimalsToString(terms.redemptionPrice),
                    '", '
                )),
                string(abi.encodePacked(
                    '"effectiveDate": "', Strings.toString(terms.effectiveDate),
                    '", "sourceAuthorityURI": "', JsonLib.jsonEscape(terms.sourceAuthorityURI),
                    '", "participationCap": "', from18DecimalsToString(terms.participationCap),
                    '", "seniorityRank": "', Strings.toString(terms.seniorityRank),
                    '", "dividendAccrualStartDate": "', Strings.toString(terms.dividendAccrualStartDate),
                    '", "dividendCompounding": "', JsonLib.boolToString(terms.dividendCompounding),
                    '", "dividendIncreasesLiquidationAmount": "', JsonLib.boolToString(terms.dividendIncreasesLiquidationAmount),
                    '", "targetConversionSeriesId": "', JsonLib.jsonEscape(terms.targetConversionSeriesId),
                    '", "allowsFractionalConversion": "', JsonLib.boolToString(terms.allowsFractionalConversion),
                    '", "hasMandatoryConversion": "', JsonLib.boolToString(terms.hasMandatoryConversion),
                    '", "hasClassVotingRights": "', JsonLib.boolToString(terms.hasClassVotingRights),
                    '", "hasSeriesVotingRights": "', JsonLib.boolToString(terms.hasSeriesVotingRights),
                    '", '
                )),
                string(abi.encodePacked(
                    '"redemptionSchedule": "', JsonLib.jsonEscape(terms.redemptionSchedule),
                    '", "redemptionTriggerDescription": "', JsonLib.jsonEscape(terms.redemptionTriggerDescription),
                    '", "hasPayToPlay": "', JsonLib.boolToString(terms.hasPayToPlay),
                    '", "payToPlayTermsURI": "', JsonLib.jsonEscape(terms.payToPlayTermsURI),
                    '", "hasRegistrationRights": "', JsonLib.boolToString(terms.hasRegistrationRights),
                    '", "registrationRightsURI": "', JsonLib.jsonEscape(terms.registrationRightsURI),
                    '", "hasProRataRights": "', JsonLib.boolToString(terms.hasProRataRights),
                    '", "proRataRightsURI": "', JsonLib.jsonEscape(terms.proRataRightsURI),
                    '", "hasInformationRights": "', JsonLib.boolToString(terms.hasInformationRights),
                    '", "informationRightsURI": "', JsonLib.jsonEscape(terms.informationRightsURI),
                    '", "hasDragAlongRights": "', JsonLib.boolToString(terms.hasDragAlongRights),
                    '", "dragAlongTermsURI": "', JsonLib.jsonEscape(terms.dragAlongTermsURI),
                    '"'
                )),
                '}, '
            )
        );
    }

    function _buildCertificateJson(CertificateData memory cert) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"certificateData": {',
                '"isPartlyPaid": "', JsonLib.boolToString(cert.isPartlyPaid),
                '", "amountPaid": "', from18DecimalsToString(cert.amountPaid),
                '", "totalConsideration": "', from18DecimalsToString(cert.totalConsideration),
                '", "sourceAuthorityURI": "', JsonLib.jsonEscape(cert.sourceAuthorityURI),
                '", "representationType": "', _representationTypeToString(cert.representationType),
                '", "holdingPeriodTackingApplied": "', JsonLib.boolToString(cert.holdingPeriodTackingApplied),
                '"}, '
            )
        );
    }

    function _buildDerivedJson(ShareCertData memory share) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"paymentPercentage": "', Strings.toString(_getPaymentPercentage(share.certificateData)),
                '", "conversionRatio": "', from18DecimalsToString(_getConversionRatio(share.terms)),
                '"'
            )
        );
    }

    function _liquidationPreferenceTypeToString(
        LiquidationPreferenceType liquidationPreferenceType
    ) internal pure returns (string memory) {
        if (liquidationPreferenceType == LiquidationPreferenceType.NonParticipating) return "NonParticipating";
        if (liquidationPreferenceType == LiquidationPreferenceType.Participating) return "Participating";
        if (liquidationPreferenceType == LiquidationPreferenceType.CappedParticipating) return "CappedParticipating";
        return "Unknown";
    }

    function _antiDilutionTypeToString(AntiDilutionType antiDilutionType) internal pure returns (string memory) {
        if (antiDilutionType == AntiDilutionType.None) return "None";
        if (antiDilutionType == AntiDilutionType.BroadBasedWeightedAverage) {
            return "BroadBasedWeightedAverage";
        }
        if (antiDilutionType == AntiDilutionType.NarrowBasedWeightedAverage) {
            return "NarrowBasedWeightedAverage";
        }
        if (antiDilutionType == AntiDilutionType.FullRatchet) return "FullRatchet";
        return "Unknown";
    }

    function _dividendTypeToString(DividendType dividendType) internal pure returns (string memory) {
        if (dividendType == DividendType.None) return "None";
        if (dividendType == DividendType.NonCumulative) return "NonCumulative";
        if (dividendType == DividendType.Cumulative) return "Cumulative";
        return "Unknown";
    }

    function _redemptionTypeToString(RedemptionType redemptionType) internal pure returns (string memory) {
        if (redemptionType == RedemptionType.None) return "None";
        if (redemptionType == RedemptionType.HolderOptional) return "HolderOptional";
        if (redemptionType == RedemptionType.CompanyOptional) return "CompanyOptional";
        if (redemptionType == RedemptionType.Mandatory) return "Mandatory";
        if (redemptionType == RedemptionType.EventTriggered) return "EventTriggered";
        return "Unknown";
    }

    function _representationTypeToString(
        ShareRepresentationType representationType
    ) internal pure returns (string memory) {
        if (representationType == ShareRepresentationType.Certificated) return "Certificated";
        if (representationType == ShareRepresentationType.Uncertificated) return "Uncertificated";
        if (representationType == ShareRepresentationType.Tokenized) return "Tokenized";
        return "Unknown";
    }

    function _mandatoryConversionTriggerTypeToString(
        MandatoryConversionTriggerType triggerType
    ) internal pure returns (string memory) {
        if (triggerType == MandatoryConversionTriggerType.QualifiedIPO) return "QualifiedIPO";
        if (triggerType == MandatoryConversionTriggerType.ClassVote) return "ClassVote";
        if (triggerType == MandatoryConversionTriggerType.DeemedLiquidation) return "DeemedLiquidation";
        if (triggerType == MandatoryConversionTriggerType.Custom) return "Custom";
        return "Unknown";
    }

    function _votingScopeToString(VotingScope scope) internal pure returns (string memory) {
        if (scope == VotingScope.ClassWide) return "ClassWide";
        if (scope == VotingScope.SeriesSpecific) return "SeriesSpecific";
        return "Unknown";
    }

    function _transferRestrictionTypeToString(
        TransferRestrictionType restrictionType
    ) internal pure returns (string memory) {
        if (restrictionType == TransferRestrictionType.None) return "None";
        if (restrictionType == TransferRestrictionType.BoardConsentRequired) return "BoardConsentRequired";
        if (restrictionType == TransferRestrictionType.ROFRAndCoSale) return "ROFRAndCoSale";
        if (restrictionType == TransferRestrictionType.LockUp) return "LockUp";
        if (restrictionType == TransferRestrictionType.SecuritiesActRestriction) return "SecuritiesActRestriction";
        if (restrictionType == TransferRestrictionType.CustomRestriction) return "CustomRestriction";
        return "Unknown";
    }

    function _buildMandatoryConversionTriggerJson(
        MandatoryConversionTrigger memory trigger
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"triggerType": "', _mandatoryConversionTriggerTypeToString(trigger.triggerType),
                '", "primaryThreshold": "', from18DecimalsToString(trigger.primaryThreshold),
                '", "secondaryThreshold": "', from18DecimalsToString(trigger.secondaryThreshold),
                '", "additionalConditions": "', JsonLib.jsonEscape(trigger.additionalConditions),
                '", "description": "', JsonLib.jsonEscape(trigger.description),
                '"}'
            )
        );
    }

    function _buildMandatoryConversionTriggersJson(
        MandatoryConversionTrigger[] memory triggers
    ) internal pure returns (string memory) {
        if (triggers.length == 0) return "[]";
        string memory result = "[";
        for (uint256 i = 0; i < triggers.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ","));
            result = string(abi.encodePacked(result, _buildMandatoryConversionTriggerJson(triggers[i])));
        }
        return string(abi.encodePacked(result, "]"));
    }

    function _buildSpecialVotingRightJson(
        SpecialVotingRight memory right
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"matterType": "', JsonLib.jsonEscape(right.matterType),
                '", "votesPerShare": "', from18DecimalsToString(right.votesPerShare),
                '", "threshold": "', Strings.toString(right.threshold),
                '", "isVetoRight": "', JsonLib.boolToString(right.isVetoRight),
                '", "scope": "', _votingScopeToString(right.scope),
                '", "description": "', JsonLib.jsonEscape(right.description),
                '"}'
            )
        );
    }

    function _buildSpecialVotingRightsJson(
        SpecialVotingRight[] memory rights
    ) internal pure returns (string memory) {
        if (rights.length == 0) return "[]";
        string memory result = "[";
        for (uint256 i = 0; i < rights.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ","));
            result = string(abi.encodePacked(result, _buildSpecialVotingRightJson(rights[i])));
        }
        return string(abi.encodePacked(result, "]"));
    }

    function _buildTransferRestrictionExceptionJson(
        TransferRestrictionException memory exception
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"exceptionType": "', JsonLib.jsonEscape(exception.exceptionType),
                '", "exceptionText": "', JsonLib.jsonEscape(exception.exceptionText),
                '", "requiresEvidence": "', JsonLib.boolToString(exception.requiresEvidence),
                '"}'
            )
        );
    }

    function _buildTransferRestrictionExceptionsJson(
        TransferRestrictionException[] memory exceptions
    ) internal pure returns (string memory) {
        if (exceptions.length == 0) return "[]";
        string memory result = "[";
        for (uint256 i = 0; i < exceptions.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ","));
            result = string(abi.encodePacked(result, _buildTransferRestrictionExceptionJson(exceptions[i])));
        }
        return string(abi.encodePacked(result, "]"));
    }

    function _buildTransferRestrictionJson(
        TransferRestriction memory restriction
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"restrictionType": "', _transferRestrictionTypeToString(restriction.restrictionType),
                '", "restrictionText": "', JsonLib.jsonEscape(restriction.restrictionText),
                '", "sourceAgreement": "', JsonLib.jsonEscape(restriction.sourceAgreement),
                '", "isRemovable": "', JsonLib.boolToString(restriction.isRemovable),
                '", "exceptions": ', _buildTransferRestrictionExceptionsJson(restriction.exceptions),
                '}'
            )
        );
    }

    function _buildTransferRestrictionsJson(
        TransferRestriction[] memory restrictions
    ) internal pure returns (string memory) {
        if (restrictions.length == 0) return "[]";
        string memory result = "[";
        for (uint256 i = 0; i < restrictions.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ","));
            result = string(abi.encodePacked(result, _buildTransferRestrictionJson(restrictions[i])));
        }
        return string(abi.encodePacked(result, "]"));
    }

    function _buildSplitRecordJson(SplitRecord memory record) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '{"numerator": "', Strings.toString(record.numerator),
                '", "denominator": "', Strings.toString(record.denominator),
                '", "timestamp": "', Strings.toString(record.timestamp),
                '", "sourceAuthorityURI": "', JsonLib.jsonEscape(record.sourceAuthorityURI),
                '"}'
            )
        );
    }

    function _buildSplitHistoryJson(SplitRecord[] memory history) internal pure returns (string memory) {
        if (history.length == 0) return "[]";
        string memory result = "[";
        for (uint256 i = 0; i < history.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ","));
            result = string(abi.encodePacked(result, _buildSplitRecordJson(history[i])));
        }
        return string(abi.encodePacked(result, "]"));
    }

    function _getConversionRatio(SeriesTerms memory terms) internal pure returns (uint256 ratio) {
        if (!terms.isConvertible || terms.conversionPrice == 0) return 0;
        ratio = (terms.originalIssuePrice * PRICE_PRECISION) / terms.conversionPrice;
    }

    /// @notice Returns the paid fraction of the cert scaled by `PERCENTAGE_PRECISION` (10**4).
    /// @dev Early returns `PERCENTAGE_PRECISION` (treated as fully paid) when the cert is
    ///      not partly paid or `totalConsideration` is zero; otherwise returns the
    ///      `amountPaid`/`totalConsideration` ratio scaled by `PERCENTAGE_PRECISION`.
    function _getPaymentPercentage(CertificateData memory cert) internal pure returns (uint256 percentage) {
        if (!cert.isPartlyPaid || cert.totalConsideration == 0) return PERCENTAGE_PRECISION;
        percentage = (cert.amountPaid * PERCENTAGE_PRECISION) / cert.totalConsideration;
    }

    /// @notice Converts an 18-decimal value to a string with 2 decimal places.
    function from18DecimalsToString(uint256 value) public pure returns (string memory) {
        uint256 valueInCents = value / 1e16;
        uint256 wholePart = valueInCents / 100;
        uint256 centsPart = valueInCents % 100;

        string memory centsStr = centsPart < 10
            ? string(abi.encodePacked("0", Strings.toString(centsPart)))
            : Strings.toString(centsPart);

        return string(abi.encodePacked(Strings.toString(wholePart), ".", centsStr));
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
