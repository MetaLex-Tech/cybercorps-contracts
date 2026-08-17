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

import {SecurityClassInfo} from "../../CyberCorpConstants.sol";
import {IIssuanceManager} from "../../interfaces/IIssuanceManager.sol";
import {ILedgerEntryToken} from "../../interfaces/ILedgerEntryToken.sol";
import {
    CertificateData,
    MandatoryConversionTrigger,
    SHARE_LAYER_TAG,
    SeriesTerms,
    ShareCertData,
    ShareLayer,
    SpecialVotingRight,
    SplitRecord,
    TransferRestriction,
    hasShareLayerTag
} from "./ShareExtension.sol";

/// @title  ShareLayerLib - splits and merges the three layers of a share payload
/// @author MetaLeX Labs, Inc.
/// @notice A whole `ShareCertData` used to be stored on every certificate. Most of it is the same for
/// every certificate of a series, so a copy per certificate is waste. It is expensive waste at a
/// secondary trade: settlement copies the seller's payload into a fresh Ledger Entry Token for the
/// buyer, so the payload size sets the cost of settlement.
///
/// A layered issuance stores each section once, at the scope that owns it:
/// | scope  | where it lives                                | who shares it        |
/// |--------|-----------------------------------------------|----------------------|
/// | class  | `SecurityClassInfo.classData`, IssuanceManager | every series of a class |
/// | series | `seriesData`, the printer                     | every cert of a series  |
/// | cert   | `CertificateDetails.extensionData`            | the one cert            |
///
/// `resolve` merges the three back into the whole `ShareCertData` a reader wants. The more granular
/// scope wins, so a single certificate can override any section its series or class sets.
///
/// This is a linked library, so it is deployed once and shared. Read a cert through `resolveCert`.
library ShareLayerLib {
    function encode(ShareLayer memory layer) public pure returns (bytes memory) {
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function decode(bytes memory data) public pure returns (ShareLayer memory layer) {
        (, layer) = abi.decode(data, (bytes32, ShareLayer));
    }

    /// @notice Splits a whole `ShareCertData` into a series payload and a cert payload.
    /// @dev This is the best-guess scope split. The five series-wide sections go to the series layer.
    ///      Only `certificateData` stays on the cert. Set a section on the returned cert layer when one
    ///      certificate must differ from its series.
    function split(ShareCertData memory share)
        public
        pure
        returns (bytes memory seriesPayload, bytes memory certPayload)
    {
        ShareLayer memory series;
        series.terms = abi.encode(share.terms);
        series.conversionTriggers = abi.encode(share.mandatoryConversionTriggers);
        series.votingRights = abi.encode(share.specialVotingRights);
        series.transferRestrictions = abi.encode(share.transferRestrictions);
        series.splitHistory = abi.encode(share.splitHistory);

        ShareLayer memory cert;
        cert.certificateData = abi.encode(share.certificateData);

        return (abi.encode(SHARE_LAYER_TAG, series), abi.encode(SHARE_LAYER_TAG, cert));
    }

    /// @notice Merges the class, series and cert payloads into the whole `ShareCertData` a reader wants.
    /// @dev A legacy cert payload is a whole `ShareCertData`. It is returned as decoded and the layers
    ///      above are ignored, so a cert minted before layering reads back exactly as it did before.
    /// @param classData `SecurityClassInfo.classData` of the printer's class, or empty
    /// @param seriesData the printer's `seriesData`, or empty
    /// @param certData the cert's `CertificateDetails.extensionData`
    function resolve(bytes memory classData, bytes memory seriesData, bytes memory certData)
        public
        pure
        returns (ShareCertData memory share)
    {
        if (certData.length == 0) return share;
        if (!hasShareLayerTag(certData)) return abi.decode(certData, (ShareCertData));

        ShareLayer memory cert = decode(certData);
        ShareLayer memory series = seriesLayerOf(seriesData);
        ShareLayer memory class_ = classLayerOf(classData);

        bytes memory section = _mostGranular(cert.certificateData, series.certificateData, class_.certificateData);
        if (section.length != 0) share.certificateData = abi.decode(section, (CertificateData));

        section = _mostGranular(cert.terms, series.terms, class_.terms);
        if (section.length != 0) share.terms = abi.decode(section, (SeriesTerms));

        section = _mostGranular(cert.conversionTriggers, series.conversionTriggers, class_.conversionTriggers);
        if (section.length != 0) {
            share.mandatoryConversionTriggers = abi.decode(section, (MandatoryConversionTrigger[]));
        }

        section = _mostGranular(cert.votingRights, series.votingRights, class_.votingRights);
        if (section.length != 0) share.specialVotingRights = abi.decode(section, (SpecialVotingRight[]));

        section = _mostGranular(cert.transferRestrictions, series.transferRestrictions, class_.transferRestrictions);
        if (section.length != 0) share.transferRestrictions = abi.decode(section, (TransferRestriction[]));

        section = _mostGranular(cert.splitHistory, series.splitHistory, class_.splitHistory);
        if (section.length != 0) share.splitHistory = abi.decode(section, (SplitRecord[]));
    }

    /// @notice Reads the three layers of a cert straight off the chain and merges them.
    /// @dev Every read is guarded, so a printer or an IssuanceManager that predates a layer still
    ///      resolves. A missing layer contributes nothing.
    function resolveCert(address printer, uint256 tokenId) public view returns (ShareCertData memory) {
        bytes memory certData = ILedgerEntryToken(printer).getActiveCertificateDetails(tokenId).extensionData;

        bytes memory seriesData;
        try ILedgerEntryToken(printer).getSeriesInfo() returns (address, bytes memory data) {
            seriesData = data;
        } catch {}

        return resolve(classDataOf(printer), seriesData, certData);
    }

    /// @notice The class payload of a printer's security class, or empty when it has none.
    function classDataOf(address printer) public view returns (bytes memory classData) {
        try ILedgerEntryToken(printer).issuanceManager() returns (address im) {
            try IIssuanceManager(im).getPrinterClassId(printer) returns (uint256 classId) {
                if (classId == 0) return classData;
                try IIssuanceManager(im).getSecurityClass(classId) returns (SecurityClassInfo memory info) {
                    classData = info.classData;
                } catch {}
            } catch {}
        } catch {}
    }

    /// @notice Reads a series payload as a layer.
    /// @dev A legacy series payload is a bare `SeriesTerms`, which is the terms section on its own.
    function seriesLayerOf(bytes memory data) public pure returns (ShareLayer memory layer) {
        if (data.length == 0) return layer;
        if (hasShareLayerTag(data)) return decode(data);
        layer.terms = data;
    }

    /// @notice Reads a class payload as a layer.
    /// @dev A class payload has no legacy share format, so an untagged payload belongs to another
    ///      decoder and contributes nothing.
    function classLayerOf(bytes memory data) public pure returns (ShareLayer memory layer) {
        if (hasShareLayerTag(data)) layer = decode(data);
    }

    function _mostGranular(bytes memory cert, bytes memory series, bytes memory class_)
        private
        pure
        returns (bytes memory)
    {
        if (cert.length != 0) return cert;
        if (series.length != 0) return series;
        return class_;
    }
}
