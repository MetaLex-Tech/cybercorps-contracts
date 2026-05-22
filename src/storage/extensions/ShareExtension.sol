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
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../libs/auth.sol";
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
    bytes32 matterType;
    uint256 votesPerShare;
    uint256 threshold;
    bool isVetoRight;
    VotingScope scope;
    string description;
}

struct TransferRestrictionException {
    bytes32 exceptionType;
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
    bytes32 shareClassKey;
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
    bytes32 targetConversionSeriesId;
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
    bool hasInformationRights;
    bool hasDragAlongRights;
    string dragAlongTermsURI;
}

struct CertificateData {
    uint256 certificateNumber;
    uint256 numberOfShares;
    uint256 issueDate;
    bool isPartlyPaid;
    uint256 amountPaid;
    uint256 totalConsideration;
    string sourceAuthorityURI;
    ShareRepresentationType representationType;
    uint256 holdingPeriodStartDate;
    bool holdingPeriodTackingApplied;
}

struct ShareExtensionDataSplitProposal {
    string[] moveToPrinterExtensionData;
    string[] keepInCertificateExtensionData;
    string[] removeBecauseCoveredByRoundManager;
}

struct SharePrinterExtensionData {
    SeriesTerms terms;
    MandatoryConversionTrigger[] mandatoryConversionTriggers;
    SpecialVotingRight[] specialVotingRights;
    TransferRestriction[] transferRestrictions;
    SplitRecord[] splitHistory;
    ShareExtensionDataSplitProposal dataSplitProposal;
}

struct ShareCertificateData {
    uint256 certificateNumber;
    uint256 issueDate;
    bool isPartlyPaid;
    uint256 amountPaid;
    string sourceAuthorityURI;
    ShareRepresentationType representationType;
    uint256 holdingPeriodStartDate;
    bool holdingPeriodTackingApplied;
}

contract ShareExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;
    string public constant SECURITIES_ACT_LEGEND =
        "THE SECURITIES REPRESENTED HEREBY HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, "
        'AS AMENDED (THE "ACT"), OR UNDER THE SECURITIES LAWS OF ANY STATE. THESE SECURITIES ARE '
        "SUBJECT TO RESTRICTIONS ON TRANSFERABILITY AND RESALE AND MAY NOT BE TRANSFERRED OR RESOLD "
        "EXCEPT AS PERMITTED UNDER THE ACT AND APPLICABLE STATE SECURITIES LAWS, PURSUANT TO "
        "REGISTRATION OR EXEMPTION THEREFROM.";

    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodePrinterExtensionData(
        bytes memory data
    ) external pure returns (SharePrinterExtensionData memory) {
        return abi.decode(data, (SharePrinterExtensionData));
    }

    function encodePrinterExtensionData(
        SharePrinterExtensionData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function decodeCertificateExtensionData(
        bytes memory data
    ) external pure returns (ShareCertificateData memory) {
        return abi.decode(data, (ShareCertificateData));
    }

    function encodeCertificateExtensionData(
        ShareCertificateData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(
        bytes32 extensionType
    ) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(
        bytes memory printerExtensionData,
        bytes memory certificateExtensionData
    ) external pure override returns (string memory) {
        return
            _buildExtensionURI(printerExtensionData, certificateExtensionData);
    }

    function _buildExtensionURI(
        bytes memory printerExtensionData,
        bytes memory certificateExtensionData
    ) internal pure returns (string memory) {
        if (printerExtensionData.length == 0) return "";

        SharePrinterExtensionData memory printerData = abi.decode(
            printerExtensionData,
            (SharePrinterExtensionData)
        );

        if (certificateExtensionData.length == 0) {
            return
                string(
                    abi.encodePacked(
                        ', "shareDetails": {',
                        _buildSeriesJson(printerData.terms),
                        _buildPrinterDerivedJson(printerData),
                        '"}'
                    )
                );
        }

        ShareCertificateData memory certificateData = abi.decode(
            certificateExtensionData,
            (ShareCertificateData)
        );
        CertificateData memory cert = _toCertificateData(certificateData);

        return
            string(
                abi.encodePacked(
                    ', "shareDetails": {',
                    _buildSeriesJson(printerData.terms),
                    _buildCertificateJson(certificateData),
                    _buildDerivedJson(printerData, cert),
                    '"}'
                )
            );
    }

    function _buildSeriesJson(
        SeriesTerms memory terms
    ) internal pure returns (string memory) {
        return
            string.concat(
                _buildSeriesJsonPartOne(terms),
                _buildSeriesJsonPartTwo(terms)
            );
    }

    function _buildSeriesJsonPartOne(
        SeriesTerms memory terms
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"shareClassKey": "',
                    _shareClassKeyToString(terms.shareClassKey),
                    '", "seriesName": "',
                    terms.seriesName,
                    '", "authorizedShares": "',
                    Strings.toString(terms.authorizedShares),
                    '", "parValue": "',
                    Strings.toString(terms.parValue),
                    '", "originalIssuePrice": "',
                    Strings.toString(terms.originalIssuePrice),
                    '", "liquidationPreferenceMultiple": "',
                    Strings.toString(terms.liquidationPreferenceMultiple),
                    '", "liquidationPreferenceType": "',
                    _liquidationPreferenceTypeToString(
                        terms.liquidationPreferenceType
                    ),
                    '", '
                )
            );
    }

    function _buildSeriesJsonPartTwo(
        SeriesTerms memory terms
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"dividendType": "',
                    _dividendTypeToString(terms.dividendType),
                    '", "dividendRate": "',
                    Strings.toString(terms.dividendRate),
                    '", "isConvertible": "',
                    _boolToString(terms.isConvertible),
                    '", "conversionPrice": "',
                    Strings.toString(terms.conversionPrice),
                    '", "antiDilutionType": "',
                    _antiDilutionTypeToString(terms.antiDilutionType),
                    '", "votesPerShare": "',
                    Strings.toString(terms.votesPerShare),
                    '", "designatedBoardSeats": "',
                    Strings.toString(uint256(terms.designatedBoardSeats)),
                    '", "isRedeemable": "',
                    _boolToString(terms.isRedeemable),
                    '", "redemptionType": "',
                    _redemptionTypeToString(terms.redemptionType),
                    '", "redemptionPrice": "',
                    Strings.toString(terms.redemptionPrice),
                    '", '
                )
            );
    }

    function _buildCertificateJson(
        CertificateData memory cert
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"numberOfShares": "',
                    Strings.toString(cert.numberOfShares),
                    '", "certificateNumber": "',
                    Strings.toString(cert.certificateNumber),
                    '", "issueDate": "',
                    Strings.toString(cert.issueDate),
                    '", "isPartlyPaid": "',
                    _boolToString(cert.isPartlyPaid),
                    '", "amountPaid": "',
                    Strings.toString(cert.amountPaid),
                    '", "totalConsideration": "',
                    Strings.toString(cert.totalConsideration),
                    '", "representationType": "',
                    _representationTypeToString(cert.representationType),
                    '", "holdingPeriodStartDate": "',
                    Strings.toString(cert.holdingPeriodStartDate),
                    '", "holdingPeriodTackingApplied": "',
                    _boolToString(cert.holdingPeriodTackingApplied),
                    '", '
                )
            );
    }

    function _buildCertificateJson(
        ShareCertificateData memory cert
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"certificateNumber": "',
                    Strings.toString(cert.certificateNumber),
                    '", "issueDate": "',
                    Strings.toString(cert.issueDate),
                    '", "isPartlyPaid": "',
                    _boolToString(cert.isPartlyPaid),
                    '", "amountPaid": "',
                    Strings.toString(cert.amountPaid),
                    '", "representationType": "',
                    _representationTypeToString(cert.representationType),
                    '", "holdingPeriodStartDate": "',
                    Strings.toString(cert.holdingPeriodStartDate),
                    '", "holdingPeriodTackingApplied": "',
                    _boolToString(cert.holdingPeriodTackingApplied),
                    '", '
                )
            );
    }

    function _buildDerivedJson(
        SharePrinterExtensionData memory printerData,
        CertificateData memory cert
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _buildPrinterDerivedJson(printerData),
                    ', "paymentPercentage": "',
                    Strings.toString(_getPaymentPercentage(cert)),
                    '"'
                )
            );
    }

    function _buildPrinterDerivedJson(
        SharePrinterExtensionData memory printerData
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"mandatoryConversionTriggerCount": "',
                    Strings.toString(
                        printerData.mandatoryConversionTriggers.length
                    ),
                    '", "specialVotingRightCount": "',
                    Strings.toString(printerData.specialVotingRights.length),
                    '", "transferRestrictionCount": "',
                    Strings.toString(printerData.transferRestrictions.length),
                    '", "splitHistoryCount": "',
                    Strings.toString(printerData.splitHistory.length),
                    '", "conversionRatio": "',
                    Strings.toString(_getConversionRatio(printerData.terms)),
                    '"'
                )
            );
    }

    function _toCertificateData(
        ShareCertificateData memory data
    ) internal pure returns (CertificateData memory certificateData) {
        certificateData = CertificateData({
            certificateNumber: data.certificateNumber,
            numberOfShares: 0,
            issueDate: data.issueDate,
            isPartlyPaid: data.isPartlyPaid,
            amountPaid: data.amountPaid,
            totalConsideration: 0,
            sourceAuthorityURI: data.sourceAuthorityURI,
            representationType: data.representationType,
            holdingPeriodStartDate: data.holdingPeriodStartDate,
            holdingPeriodTackingApplied: data.holdingPeriodTackingApplied
        });
    }

    function _emptyCertificateData()
        internal
        pure
        returns (CertificateData memory certificateData)
    {}

    function _bytesToHexString(
        bytes memory data
    ) internal pure returns (string memory) {
        bytes16 symbols = "0123456789abcdef";
        bytes memory buffer = new bytes(2 + data.length * 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            buffer[2 + i * 2] = symbols[uint8(data[i] >> 4)];
            buffer[3 + i * 2] = symbols[uint8(data[i] & 0x0f)];
        }
        return string(buffer);
    }

    function _shareClassKeyToString(
        bytes32 key
    ) internal pure returns (string memory) {
        if (key == keccak256("COMMON")) return "Common";
        if (key == keccak256("PREFERRED")) return "Preferred";
        return Strings.toHexString(uint256(key), 32);
    }

    function _liquidationPreferenceTypeToString(
        LiquidationPreferenceType liquidationPreferenceType
    ) internal pure returns (string memory) {
        if (
            liquidationPreferenceType ==
            LiquidationPreferenceType.NonParticipating
        ) return "NonParticipating";
        if (
            liquidationPreferenceType == LiquidationPreferenceType.Participating
        ) return "Participating";
        if (
            liquidationPreferenceType ==
            LiquidationPreferenceType.CappedParticipating
        ) return "CappedParticipating";
        return "Unknown";
    }

    function _antiDilutionTypeToString(
        AntiDilutionType antiDilutionType
    ) internal pure returns (string memory) {
        if (antiDilutionType == AntiDilutionType.None) return "None";
        if (antiDilutionType == AntiDilutionType.BroadBasedWeightedAverage) {
            return "BroadBasedWeightedAverage";
        }
        if (antiDilutionType == AntiDilutionType.NarrowBasedWeightedAverage) {
            return "NarrowBasedWeightedAverage";
        }
        if (antiDilutionType == AntiDilutionType.FullRatchet)
            return "FullRatchet";
        return "Unknown";
    }

    function _dividendTypeToString(
        DividendType dividendType
    ) internal pure returns (string memory) {
        if (dividendType == DividendType.None) return "None";
        if (dividendType == DividendType.NonCumulative) return "NonCumulative";
        if (dividendType == DividendType.Cumulative) return "Cumulative";
        return "Unknown";
    }

    function _redemptionTypeToString(
        RedemptionType redemptionType
    ) internal pure returns (string memory) {
        if (redemptionType == RedemptionType.None) return "None";
        if (redemptionType == RedemptionType.HolderOptional)
            return "HolderOptional";
        if (redemptionType == RedemptionType.CompanyOptional)
            return "CompanyOptional";
        if (redemptionType == RedemptionType.Mandatory) return "Mandatory";
        if (redemptionType == RedemptionType.EventTriggered)
            return "EventTriggered";
        return "Unknown";
    }

    function _representationTypeToString(
        ShareRepresentationType representationType
    ) internal pure returns (string memory) {
        if (representationType == ShareRepresentationType.Certificated)
            return "Certificated";
        if (representationType == ShareRepresentationType.Uncertificated)
            return "Uncertificated";
        if (representationType == ShareRepresentationType.Tokenized)
            return "Tokenized";
        return "Unknown";
    }

    function _boolToString(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    function _getConversionRatio(
        SeriesTerms memory terms
    ) internal pure returns (uint256 ratio) {
        if (!terms.isConvertible || terms.conversionPrice == 0) return 0;
        ratio =
            (terms.originalIssuePrice * PRICE_PRECISION) /
            terms.conversionPrice;
    }

    function _getPaymentPercentage(
        CertificateData memory cert
    ) internal pure returns (uint256 percentage) {
        if (!cert.isPartlyPaid || cert.totalConsideration == 0)
            return PERCENTAGE_PRECISION;
        percentage =
            (cert.amountPaid * PERCENTAGE_PRECISION) /
            cert.totalConsideration;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
