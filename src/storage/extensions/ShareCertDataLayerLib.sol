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

import {IIssuanceManager} from "../../interfaces/IIssuanceManager.sol";
import {ILedgerEntryToken} from "../../interfaces/ILedgerEntryToken.sol";
import {
    CertificateData,
    MandatoryConversionTrigger,
    SeriesTerms,
    ShareCertData,
    SpecialVotingRight,
    SplitRecord,
    TransferRestriction
} from "./ShareExtension.sol";
import {ShareCertDataLayer} from "./ShareExtensionV3.sol";

/// @title  ShareCertDataLayerLib - merges the class, series and cert layers of a share payload
/// @author MetaLeX Labs, Inc.
/// @notice A `ShareCertDataLayer` is stored at three scopes. This library reads all three and returns
/// the resolved `ShareCertData`.
///
/// It is a linked library, so it is deployed one time and shared. The large `ShareCertData` coder stays
/// here, and not in `ShareExtensionV3`, which has little EIP-170 margin.
library ShareCertDataLayerLib {
    /// @notice The resolved payload, abi-encoded as a whole `ShareCertData`.
    /// @dev `ShareExtensionV3` renders through this, so it never carries the `ShareCertData` coder. The
    ///      result is a legacy-shaped payload, which the inherited renderer knows how to draw.
    function resolveEncoded(address printer, uint256 tokenId) public view returns (bytes memory) {
        return abi.encode(resolveCert(printer, tokenId));
    }

    /// @notice Packs a whole `ShareCertData` into one cert layer that sets every section.
    /// @dev The layer sets every section and no overwrite flag, so it assumes an empty series and an
    ///      empty class. Resolved that way, the payload reads back as the struct that went in.
    function encodeAsLayer(ShareCertData memory share) public pure returns (bytes memory) {
        ShareCertDataLayer memory layer;
        layer.certificateData = new CertificateData[](1);
        layer.certificateData[0] = share.certificateData;
        layer.terms = new SeriesTerms[](1);
        layer.terms[0] = share.terms;
        layer.conversionTriggers = new MandatoryConversionTrigger[][](1);
        layer.conversionTriggers[0] = share.mandatoryConversionTriggers;
        layer.votingRights = new SpecialVotingRight[][](1);
        layer.votingRights[0] = share.specialVotingRights;
        layer.transferRestrictions = new TransferRestriction[][](1);
        layer.transferRestrictions[0] = share.transferRestrictions;
        layer.splitHistory = new SplitRecord[][](1);
        layer.splitHistory[0] = share.splitHistory;
        return abi.encode(layer);
    }

    /// @notice The merge of three given payloads, abi-encoded as a whole `ShareCertData`.
    /// @dev Same purpose as the two-argument form. `ShareExtensionV3.getExtensionURI` uses it to render
    ///      one cert payload with no series and no class.
    function resolveEncoded(bytes memory classData, bytes memory seriesData, bytes memory certData)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(resolve(classData, seriesData, certData));
    }

    /// @notice Reads the layers of a cert off the chain and merges them.
    /// @dev The series read is guarded, so a printer that predates that scope still resolves and its
    ///      missing payload contributes nothing.
    function resolveCert(address printer, uint256 tokenId) public view returns (ShareCertData memory) {
        bytes memory certData = ILedgerEntryToken(printer).getActiveCertificateDetails(tokenId).extensionData;

        bytes memory seriesData;
        try ILedgerEntryToken(printer).getSeriesInfo() returns (address, bytes memory data) {
            seriesData = data;
        } catch {}

        return resolve(classDataOf(printer), seriesData, certData);
    }

    /// @notice Merges the class, series and cert payloads into a whole `ShareCertData`. A scope with no
    ///         payload gives a blank layer and sets nothing.
    /// @dev The merge rules are on `ShareCertDataLayer`, which is the one place they are written down.
    ///      This function is `pure`. `resolveCert` does the chain reads and then calls it.
    /// @param classData `SecurityClassInfo.classData` of the printer's class, or empty
    /// @param seriesData the printer's `seriesData`, or empty
    /// @param certData the cert's `CertificateDetails.extensionData`
    function resolve(bytes memory classData, bytes memory seriesData, bytes memory certData)
        public
        pure
        returns (ShareCertData memory share)
    {
        // An empty cert payload sets nothing, so every section comes from the series and the class.
        ShareCertDataLayer memory cert = decodeLayer(certData);
        ShareCertDataLayer memory series = decodeLayer(seriesData);
        ShareCertDataLayer memory class_ = decodeLayer(classData);

        if (cert.certificateData.length != 0) share.certificateData = cert.certificateData[0];
        else if (series.certificateData.length != 0) share.certificateData = series.certificateData[0];
        else if (class_.certificateData.length != 0) share.certificateData = class_.certificateData[0];

        if (cert.terms.length != 0) share.terms = cert.terms[0];
        else if (series.terms.length != 0) share.terms = series.terms[0];
        else if (class_.terms.length != 0) share.terms = class_.terms[0];

        share.mandatoryConversionTriggers = _mergeConversionTriggers(class_, series, cert);
        share.specialVotingRights = _mergeVotingRights(class_, series, cert);
        share.transferRestrictions = _mergeTransferRestrictions(class_, series, cert);
        share.splitHistory = _mergeSplitHistory(class_, series, cert);
    }

    /// @notice The layers that give entries to a list section, from the least granular to the most.
    /// @dev A layer that sets the section and sets its overwrite flag drops every layer above it. A
    ///      layer that does not set the section gives nothing, and its flag does nothing.
    function _deriveContributors(bool classSet, bool seriesSet, bool seriesOverwrite, bool certSet, bool certOverwrite)
        private
        pure
        returns (bool useClass, bool useSeries, bool useCert)
    {
        useCert = certSet;
        if (certSet && certOverwrite) return (false, false, true);
        useSeries = seriesSet;
        if (seriesSet && seriesOverwrite) return (false, true, useCert);
        useClass = classSet;
    }

    function _mergeConversionTriggers(
        ShareCertDataLayer memory class_,
        ShareCertDataLayer memory series,
        ShareCertDataLayer memory cert
    ) private pure returns (MandatoryConversionTrigger[] memory merged) {
        (bool useClass, bool useSeries, bool useCert) = _deriveContributors(
            class_.conversionTriggers.length != 0,
            series.conversionTriggers.length != 0,
            series.overwriteConversionTriggers,
            cert.conversionTriggers.length != 0,
            cert.overwriteConversionTriggers
        );

        MandatoryConversionTrigger[] memory none = new MandatoryConversionTrigger[](0);
        MandatoryConversionTrigger[] memory fromClass = useClass ? class_.conversionTriggers[0] : none;
        MandatoryConversionTrigger[] memory fromSeries = useSeries ? series.conversionTriggers[0] : none;
        MandatoryConversionTrigger[] memory fromCert = useCert ? cert.conversionTriggers[0] : none;

        merged = new MandatoryConversionTrigger[](fromClass.length + fromSeries.length + fromCert.length);
        uint256 next;
        for (uint256 i = 0; i < fromClass.length; i++) {
            merged[next++] = fromClass[i];
        }
        for (uint256 i = 0; i < fromSeries.length; i++) {
            merged[next++] = fromSeries[i];
        }
        for (uint256 i = 0; i < fromCert.length; i++) {
            merged[next++] = fromCert[i];
        }
    }

    function _mergeVotingRights(
        ShareCertDataLayer memory class_,
        ShareCertDataLayer memory series,
        ShareCertDataLayer memory cert
    ) private pure returns (SpecialVotingRight[] memory merged) {
        (bool useClass, bool useSeries, bool useCert) = _deriveContributors(
            class_.votingRights.length != 0,
            series.votingRights.length != 0,
            series.overwriteVotingRights,
            cert.votingRights.length != 0,
            cert.overwriteVotingRights
        );

        SpecialVotingRight[] memory none = new SpecialVotingRight[](0);
        SpecialVotingRight[] memory fromClass = useClass ? class_.votingRights[0] : none;
        SpecialVotingRight[] memory fromSeries = useSeries ? series.votingRights[0] : none;
        SpecialVotingRight[] memory fromCert = useCert ? cert.votingRights[0] : none;

        merged = new SpecialVotingRight[](fromClass.length + fromSeries.length + fromCert.length);
        uint256 next;
        for (uint256 i = 0; i < fromClass.length; i++) {
            merged[next++] = fromClass[i];
        }
        for (uint256 i = 0; i < fromSeries.length; i++) {
            merged[next++] = fromSeries[i];
        }
        for (uint256 i = 0; i < fromCert.length; i++) {
            merged[next++] = fromCert[i];
        }
    }

    function _mergeTransferRestrictions(
        ShareCertDataLayer memory class_,
        ShareCertDataLayer memory series,
        ShareCertDataLayer memory cert
    ) private pure returns (TransferRestriction[] memory merged) {
        (bool useClass, bool useSeries, bool useCert) = _deriveContributors(
            class_.transferRestrictions.length != 0,
            series.transferRestrictions.length != 0,
            series.overwriteTransferRestrictions,
            cert.transferRestrictions.length != 0,
            cert.overwriteTransferRestrictions
        );

        TransferRestriction[] memory none = new TransferRestriction[](0);
        TransferRestriction[] memory fromClass = useClass ? class_.transferRestrictions[0] : none;
        TransferRestriction[] memory fromSeries = useSeries ? series.transferRestrictions[0] : none;
        TransferRestriction[] memory fromCert = useCert ? cert.transferRestrictions[0] : none;

        merged = new TransferRestriction[](fromClass.length + fromSeries.length + fromCert.length);
        uint256 next;
        for (uint256 i = 0; i < fromClass.length; i++) {
            merged[next++] = fromClass[i];
        }
        for (uint256 i = 0; i < fromSeries.length; i++) {
            merged[next++] = fromSeries[i];
        }
        for (uint256 i = 0; i < fromCert.length; i++) {
            merged[next++] = fromCert[i];
        }
    }

    function _mergeSplitHistory(
        ShareCertDataLayer memory class_,
        ShareCertDataLayer memory series,
        ShareCertDataLayer memory cert
    ) private pure returns (SplitRecord[] memory merged) {
        (bool useClass, bool useSeries, bool useCert) = _deriveContributors(
            class_.splitHistory.length != 0,
            series.splitHistory.length != 0,
            series.overwriteSplitHistory,
            cert.splitHistory.length != 0,
            cert.overwriteSplitHistory
        );

        SplitRecord[] memory none = new SplitRecord[](0);
        SplitRecord[] memory fromClass = useClass ? class_.splitHistory[0] : none;
        SplitRecord[] memory fromSeries = useSeries ? series.splitHistory[0] : none;
        SplitRecord[] memory fromCert = useCert ? cert.splitHistory[0] : none;

        merged = new SplitRecord[](fromClass.length + fromSeries.length + fromCert.length);
        uint256 next;
        for (uint256 i = 0; i < fromClass.length; i++) {
            merged[next++] = fromClass[i];
        }
        for (uint256 i = 0; i < fromSeries.length; i++) {
            merged[next++] = fromSeries[i];
        }
        for (uint256 i = 0; i < fromCert.length; i++) {
            merged[next++] = fromCert[i];
        }
    }

    /// @notice Reads a scoped payload as a layer. An empty payload gives a blank layer, which sets
    ///         nothing.
    /// @dev One decoder serves all three scopes. They hold the same struct in the same format.
    function decodeLayer(bytes memory data) internal pure returns (ShareCertDataLayer memory layer) {
        if (data.length != 0) layer = abi.decode(data, (ShareCertDataLayer));
    }

    /// @notice The class payload of a printer's security class, or empty when it has none.
    function classDataOf(address printer) internal view returns (bytes memory classData) {
        IIssuanceManager im = IIssuanceManager(ILedgerEntryToken(printer).issuanceManager());
        uint256 classId = im.getPrinterClassId(printer);
        return im.getSecurityClass(classId).classData;
    }
}
