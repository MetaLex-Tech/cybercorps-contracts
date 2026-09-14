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

import "./ShareExtensionV3.sol";
import {ShareCertDataLayerLib} from "./ShareCertDataLayerLib.sol";

contract ShareExtensionLogic {
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;

    function decodeExtensionData(bytes memory data) external pure returns (ShareCertDataLayer memory) {
        return ShareCertDataLayerLib.decodeLayer(data);
    }

    function encodeExtensionData(ShareCertDataLayer memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function validateShareData(bytes memory data) external pure returns (bool valid, string memory error) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        if (layer.terms.length != 0) {
            (valid, error) = _validateSeriesTermsInternal(layer.terms[0]);
            if (!valid) return (valid, error);
        }
        if (layer.certificateData.length != 0) {
            return _validateCertificateDataInternal(layer.certificateData[0]);
        }
        return (true, "");
    }

    function validateSeriesTerms(SeriesTerms memory terms) external pure returns (bool valid, string memory error) {
        return _validateSeriesTermsInternal(terms);
    }

    function validateCertificateData(
        CertificateData memory certificateData
    ) external pure returns (bool valid, string memory error) {
        return _validateCertificateDataInternal(certificateData);
    }

    function updateSeriesTerms(bytes memory data, SeriesTerms memory terms) external pure returns (bytes memory) {
        (bool valid, string memory error) = _validateSeriesTermsInternal(terms);
        require(valid, error);

        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        layer.terms = new SeriesTerms[](1);
        layer.terms[0] = terms;
        return abi.encode(layer);
    }

    function updateCertificateData(
        bytes memory data,
        CertificateData memory certificateData
    ) external pure returns (bytes memory) {
        (bool valid, string memory error) = _validateCertificateDataInternal(certificateData);
        require(valid, error);

        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        layer.certificateData = new CertificateData[](1);
        layer.certificateData[0] = certificateData;
        return abi.encode(layer);
    }

    function updateConversionPrice(bytes memory data, uint256 newPrice) external pure returns (bytes memory) {
        require(newPrice > 0, "ShareExtensionLogic: conversionPrice must be > 0");

        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.terms.length, "terms");
        require(layer.terms[0].isConvertible, "ShareExtensionLogic: series is not convertible");
        layer.terms[0].conversionPrice = newPrice;
        return abi.encode(layer);
    }

    function updateAuthorizedShares(bytes memory data, uint256 newAmount) external pure returns (bytes memory) {
        require(newAmount > 0, "ShareExtensionLogic: authorizedShares must be > 0");

        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.terms.length, "terms");
        layer.terms[0].authorizedShares = newAmount;
        return abi.encode(layer);
    }

    function updateSeriesName(bytes memory data, string memory newName) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.terms.length, "terms");
        layer.terms[0].seriesName = newName;
        return abi.encode(layer);
    }

    function addConversionTrigger(
        bytes memory data,
        MandatoryConversionTrigger memory conversionTrigger
    ) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.conversionTriggers.length, "conversionTriggers");
        layer.conversionTriggers[0] = _appendConversionTrigger(layer.conversionTriggers[0], conversionTrigger);
        return abi.encode(layer);
    }

    function removeConversionTrigger(bytes memory data, uint256 index) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.conversionTriggers.length, "conversionTriggers");
        layer.conversionTriggers[0] = _removeConversionTrigger(layer.conversionTriggers[0], index);
        return abi.encode(layer);
    }

    function addSpecialVotingRight(
        bytes memory data,
        SpecialVotingRight memory votingRight
    ) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.votingRights.length, "votingRights");
        layer.votingRights[0] = _appendSpecialVotingRight(layer.votingRights[0], votingRight);
        return abi.encode(layer);
    }

    function removeSpecialVotingRight(bytes memory data, uint256 index) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.votingRights.length, "votingRights");
        layer.votingRights[0] = _removeSpecialVotingRight(layer.votingRights[0], index);
        return abi.encode(layer);
    }

    function addTransferRestriction(
        bytes memory data,
        TransferRestriction memory restriction
    ) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.transferRestrictions.length, "transferRestrictions");
        layer.transferRestrictions[0] = _appendTransferRestriction(layer.transferRestrictions[0], restriction);
        return abi.encode(layer);
    }

    function removeTransferRestriction(bytes memory data, uint256 index) external pure returns (bytes memory) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.transferRestrictions.length, "transferRestrictions");
        layer.transferRestrictions[0] = _removeTransferRestriction(layer.transferRestrictions[0], index);
        return abi.encode(layer);
    }

    function recordStockSplit(
        bytes memory data,
        uint256 splitNumerator,
        uint256 splitDenominator,
        string memory sourceAuthorityURI,
        uint256 timestamp
    ) external pure returns (bytes memory) {
        require(splitNumerator > 0 && splitDenominator > 0, "ShareExtensionLogic: split ratio must be non-zero");
        require(splitNumerator != splitDenominator, "ShareExtensionLogic: split ratio must differ from 1:1");

        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        _requireSet(layer.terms.length, "terms");
        _requireSet(layer.conversionTriggers.length, "conversionTriggers");
        _requireSet(layer.splitHistory.length, "splitHistory");

        SeriesTerms memory terms = layer.terms[0];
        terms.originalIssuePrice = (terms.originalIssuePrice * splitDenominator) / splitNumerator;
        terms.parValue = (terms.parValue * splitDenominator) / splitNumerator;
        if (terms.conversionPrice > 0) {
            terms.conversionPrice = (terms.conversionPrice * splitDenominator) / splitNumerator;
        }
        if (terms.redemptionPrice > 0) {
            terms.redemptionPrice = (terms.redemptionPrice * splitDenominator) / splitNumerator;
        }
        terms.authorizedShares = (terms.authorizedShares * splitNumerator) / splitDenominator;

        MandatoryConversionTrigger[] memory triggers = layer.conversionTriggers[0];
        for (uint256 i = 0; i < triggers.length; i++) {
            if (
                triggers[i].triggerType == MandatoryConversionTriggerType.QualifiedIPO
                    && triggers[i].primaryThreshold > 0
            ) {
                triggers[i].primaryThreshold = (triggers[i].primaryThreshold * splitDenominator) / splitNumerator;
            }
        }

        layer.splitHistory[0] = _appendSplitRecord(
            layer.splitHistory[0],
            SplitRecord({
                numerator: splitNumerator,
                denominator: splitDenominator,
                timestamp: timestamp,
                sourceAuthorityURI: sourceAuthorityURI
            })
        );

        return abi.encode(layer);
    }

    function getConversionRatio(bytes memory data) external pure returns (uint256 ratio) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        if (layer.terms.length == 0) return 0;
        SeriesTerms memory terms = layer.terms[0];
        if (!terms.isConvertible || terms.conversionPrice == 0) return 0;
        ratio = (terms.originalIssuePrice * PRICE_PRECISION) / terms.conversionPrice;
    }

    function getPaymentPercentage(bytes memory data) external pure returns (uint256 percentage) {
        ShareCertDataLayer memory layer = ShareCertDataLayerLib.decodeLayer(data);
        if (layer.certificateData.length == 0) return PERCENTAGE_PRECISION;
        CertificateData memory cert = layer.certificateData[0];
        if (!cert.isPartlyPaid || cert.totalConsideration == 0) return PERCENTAGE_PRECISION;
        percentage = (cert.amountPaid * PERCENTAGE_PRECISION) / cert.totalConsideration;
    }

    // TODO before uncomment, update codes to meet the current ShareCertDataLayer spec
    // function computeAccruedDividends(bytes memory data, uint256 asOfTimestamp) external pure returns (uint256 accrued) {
    //     ShareCertData memory share = abi.decode(data, (ShareCertData));
    //     SeriesTerms memory terms = share.terms;
    //     CertificateData memory cert = share.certificateData;

    //     if (terms.dividendType != DividendType.Cumulative) return 0;
    //     if (asOfTimestamp <= terms.dividendAccrualStartDate) return 0;

    //     uint256 elapsed = asOfTimestamp - terms.dividendAccrualStartDate;
    //     uint256 principal = terms.originalIssuePrice * cert.numberOfShares;

    //     if (!terms.dividendCompounding) {
    //         accrued = (terms.dividendRate * principal * elapsed) / (365 days * PRICE_PRECISION);
    //         return accrued;
    //     }

    //     uint256 fullYears = elapsed / 365 days;
    //     uint256 remainder = elapsed % 365 days;
    //     uint256 compounded = principal;

    //     for (uint256 i = 0; i < fullYears; i++) {
    //         compounded = (compounded * (PRICE_PRECISION + terms.dividendRate)) / PRICE_PRECISION;
    //     }

    //     if (remainder > 0) {
    //         compounded += (compounded * terms.dividendRate * remainder) / (365 days * PRICE_PRECISION);
    //     }

    //     accrued = compounded - principal;
    // }

    function _requireSet(uint256 length, string memory name) private pure {
        if (length != 0) return;
        require(false, string.concat("ShareExtensionLogic: layer has no ", name, " section"));
    }

    function _validateSeriesTermsInternal(SeriesTerms memory terms) internal pure returns (bool, string memory) {
        if (terms.authorizedShares == 0) return (false, "ShareExtensionLogic: authorizedShares must be > 0");
        if (terms.parValue == 0) return (false, "ShareExtensionLogic: parValue must be > 0");

        if (!terms.isConvertible) {
            if (terms.conversionPrice != 0) {
                return (false, "ShareExtensionLogic: conversionPrice must be 0 when not convertible");
            }
            if (bytes(terms.targetConversionSeriesId).length != 0) {
                return (false, "ShareExtensionLogic: targetConversionSeriesId must be zero when not convertible");
            }
            if (terms.hasMandatoryConversion) {
                return (false, "ShareExtensionLogic: hasMandatoryConversion must be false when not convertible");
            }
        }

        if (terms.isConvertible) {
            if (terms.conversionPrice == 0) {
                return (false, "ShareExtensionLogic: conversionPrice must be > 0 when convertible");
            }
            if (bytes(terms.targetConversionSeriesId).length == 0) {
                return (false, "ShareExtensionLogic: targetConversionSeriesId must be non-zero when convertible");
            }
        }

        if (terms.dividendType == DividendType.None && terms.dividendRate != 0) {
            return (false, "ShareExtensionLogic: dividendRate must be 0 when dividendType is None");
        }

        if (terms.dividendType == DividendType.Cumulative && terms.dividendAccrualStartDate == 0) {
            return (false, "ShareExtensionLogic: dividendAccrualStartDate should be non-zero for Cumulative");
        }

        if (terms.liquidationPreferenceType != LiquidationPreferenceType.CappedParticipating) {
            if (terms.participationCap != 0) {
                return (false, "ShareExtensionLogic: participationCap must be 0 when not capped");
            }
        } else if (terms.participationCap == 0) {
            return (false, "ShareExtensionLogic: participationCap must be > 0 when capped");
        }

        if (!terms.isRedeemable) {
            if (terms.redemptionPrice != 0) {
                return (false, "ShareExtensionLogic: redemptionPrice must be 0 when not redeemable");
            }
            if (terms.redemptionType != RedemptionType.None) {
                return (false, "ShareExtensionLogic: redemptionType must be None when not redeemable");
            }
        }

        return (true, "");
    }

    function _validateCertificateDataInternal(
        CertificateData memory certificateData
    ) internal pure returns (bool, string memory) {
        if (certificateData.isPartlyPaid) {
            if (certificateData.totalConsideration == 0) {
                return (false, "ShareExtensionLogic: totalConsideration must be > 0 when partly paid");
            }
            if (certificateData.amountPaid >= certificateData.totalConsideration) {
                return (false, "ShareExtensionLogic: amountPaid must be < totalConsideration when partly paid");
            }
        } else {
            if (certificateData.amountPaid != 0) {
                return (false, "ShareExtensionLogic: amountPaid must be 0 when not partly paid");
            }
            if (certificateData.totalConsideration != 0) {
                return (false, "ShareExtensionLogic: totalConsideration must be 0 when not partly paid");
            }
        }

        return (true, "");
    }

    function _appendConversionTrigger(
        MandatoryConversionTrigger[] memory items,
        MandatoryConversionTrigger memory item
    ) internal pure returns (MandatoryConversionTrigger[] memory updated) {
        updated = new MandatoryConversionTrigger[](items.length + 1);
        for (uint256 i = 0; i < items.length; i++) {
            updated[i] = items[i];
        }
        updated[items.length] = item;
    }

    function _removeConversionTrigger(
        MandatoryConversionTrigger[] memory items,
        uint256 index
    ) internal pure returns (MandatoryConversionTrigger[] memory updated) {
        require(index < items.length, "ShareExtensionLogic: trigger index out of bounds");
        updated = new MandatoryConversionTrigger[](items.length - 1);
        for (uint256 i = 0; i < index; i++) {
            updated[i] = items[i];
        }
        for (uint256 i = index + 1; i < items.length; i++) {
            updated[i - 1] = items[i];
        }
    }

    function _appendSpecialVotingRight(
        SpecialVotingRight[] memory items,
        SpecialVotingRight memory item
    ) internal pure returns (SpecialVotingRight[] memory updated) {
        updated = new SpecialVotingRight[](items.length + 1);
        for (uint256 i = 0; i < items.length; i++) {
            updated[i] = items[i];
        }
        updated[items.length] = item;
    }

    function _removeSpecialVotingRight(
        SpecialVotingRight[] memory items,
        uint256 index
    ) internal pure returns (SpecialVotingRight[] memory updated) {
        require(index < items.length, "ShareExtensionLogic: voting right index out of bounds");
        updated = new SpecialVotingRight[](items.length - 1);
        for (uint256 i = 0; i < index; i++) {
            updated[i] = items[i];
        }
        for (uint256 i = index + 1; i < items.length; i++) {
            updated[i - 1] = items[i];
        }
    }

    function _appendTransferRestriction(
        TransferRestriction[] memory items,
        TransferRestriction memory item
    ) internal pure returns (TransferRestriction[] memory updated) {
        updated = new TransferRestriction[](items.length + 1);
        for (uint256 i = 0; i < items.length; i++) {
            updated[i] = items[i];
        }
        updated[items.length] = item;
    }

    function _removeTransferRestriction(
        TransferRestriction[] memory items,
        uint256 index
    ) internal pure returns (TransferRestriction[] memory updated) {
        require(index < items.length, "ShareExtensionLogic: restriction index out of bounds");
        updated = new TransferRestriction[](items.length - 1);
        for (uint256 i = 0; i < index; i++) {
            updated[i] = items[i];
        }
        for (uint256 i = index + 1; i < items.length; i++) {
            updated[i - 1] = items[i];
        }
    }

    function _appendSplitRecord(
        SplitRecord[] memory items,
        SplitRecord memory item
    ) internal pure returns (SplitRecord[] memory updated) {
        updated = new SplitRecord[](items.length + 1);
        for (uint256 i = 0; i < items.length; i++) {
            updated[i] = items[i];
        }
        updated[items.length] = item;
    }
}
