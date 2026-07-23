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

import "../CyberCorpConstants.sol";
import {
    CertificateDetails,
    Endorsement,
    ICyberCertPrinter,
    OwnerDetails,
    RestrictiveLegend,
    RestrictionType
} from "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/IIssuanceManager.sol";
import {BorgAuth} from "../libs/auth.sol";
import {ILexChexBadge} from "../interfaces/ILexChexBadge.sol";
import "../interfaces/IUriBuilder.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import "./extensions/ICertificateExtension.sol";
import {FUND_INTEREST_EXTENSION_TYPE} from "./extensions/FundInterestExtension.sol";

library CyberCertPrinterStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.cert.printer.storage.v1");

    // Errors and events are shared: declared once on ICyberCertPrinter and referenced as ICyberCertPrinter.X
    // (below), so library reverts/logs carry the same selectors/topics as the printer's under delegatecall.

    /// @dev Per-legal-owner account for the §3(c)(1)(A) look-through holder tally. Packs into one slot.
    /// `weight`/`isUS` are critical snapshots of LeXcheXBadge so we could do incremental updates on resyncs
    struct HolderAcct {
        uint32 liveLots; // live (non-void) lots held of record; holder is live iff > 0
        uint32 weight;   // look-through weight currently accumulated into the totals (max(boCount,1))
        bool isUS;       // whether this holder's weight is currently accumulated into the US subtotal
    }

    // Main storage layout struct
    struct CyberCertStorage {
        // Token data
        mapping(uint256 => CertificateDetails) certificateDetails;
        mapping(uint256 => Endorsement[]) endorsements;
        // use `_setLegalOwner()` to set. DO NOT set `owners[tokenId]` directly or otherwise its indexes would break
        mapping(uint256 => OwnerDetails) owners;
        mapping(uint256 => SecurityStatus) securityStatus;
        mapping(uint256 => string[]) certLegend;
        // Restriction hooks
        mapping(uint256 => ITransferRestrictionHook) restrictionHooksById;
        ITransferRestrictionHook globalRestrictionHook;
        address extension;
        // Contract configuration - making these public
        address issuanceManager;
        SecurityClass securityType;
        SecuritySeries securitySeries;
        string certificateUri;
        string[] defaultLegend;
        bool transferable;
        bool endorsementRequired;
        // New variables must be appended below to preserve storage layout for upgrades
        mapping(uint256 => bool) tokenTransferable;
        mapping(uint256 => bytes[]) issuerSignatures;
        // Units locked in a pending deal/loan; always <= certificateDetails[tokenId].unitsRepresented
        mapping(uint256 => uint256) unitsReserved;
        mapping(uint256 => RestrictiveLegend[]) certLegendsV2;
        RestrictiveLegend[] defaultLegendsV2;
        mapping(address => uint256) holderTokenCount;
        uint256 uniqueHolderCount;

        // ERC721Enumerable-like implementation for legal owners
        // Note it includes voided-but-not-burnt certs. Technically one could transfer a voided cert to another,
        // and its legal owner change would still be tracked
        mapping(address => mapping(uint256 => uint256)) legalOwnedTokens; // owner => index => tokenId
        mapping(uint256 => uint256) legalOwnedTokensIndex; // tokenId => index within its owner's list
        mapping(address => uint256) legalOwnerTokenCount; // owner => number of certs held of record
        mapping(uint256 => bool) legalOwnedTokenTracked; // token is present in its legal owner's enumeration

        // Per-lot timestamps (spec §12B.3). issueTimestamp is set once at mint; acquisitionTimestamp is
        // (re)stamped on each legal-owner change and drives the Rule 144 / Reg S holding-period conditions.
        mapping(uint256 => uint64) issueTimestamp;
        mapping(uint256 => uint64) acquisitionTimestamp;

        // §3(c)(1)(A) look-through holder tally (read O(1) by HolderCapCondition). Maintained incrementally
        // at every legal-owner change / void / unvoid / burn. Parallel to the enumeration above; the
        // enumeration's `legalOwnerTokenCount` (which includes voided lots) is left untouched for other
        // consumers. See _countLot / _uncountLot / _resyncHolder.
        mapping(address => HolderAcct) holderAcct;
        mapping(uint256 => bool) liveCounted;  // token currently contributes to its owner's liveLots
        uint256 lookThroughHolderCount;        // Σ holderAcct.weight over all live holders
        uint256 usLookThroughHolderCount;      // Σ holderAcct.weight over US-resident live holders (subset)
        address lookThroughBadge;              // ILexChexBadge sampled for look-through weight + US residency

        // Series-scope extension data: the printer itself is the series scope, so this is a singleton
        // (vs the per-token `certificateDetails[].extensionData`). Both payloads are decoded/rendered by
        // the printer's single `extension` contract (ICertificateExtensionV3 handles cert- and series-scope
        // sections). The class-level counterpart lives on the IssuanceManager (SecurityClassInfo registry
        // + printerClassIds).
        bytes seriesData;
    }

    // Returns the storage layout
    function cyberCertStorage() internal pure returns (CyberCertStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    // URI storage functionality
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = cyberCertStorage();
        RestrictiveLegend[] memory certLegend = getEffectiveRestrictiveLegends(tokenId);
        ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());
        CertificateDetails memory effectiveDetails = getCertificateDetails(
            tokenId
        );

        // Get registry and agreementId from first endorsement if it exists
        address registry = address(0);
        bytes32 agreementId = bytes32(0);
        if (s.endorsements[tokenId].length > 0) {
            Endorsement memory firstEndorsement = s.endorsements[tokenId][0];
            registry = firstEndorsement.registry;
            agreementId = firstEndorsement.agreementId;
        }

        return IUriBuilder(IIssuanceManager(s.issuanceManager).uriBuilder()).buildCertificateUri(
            corp.cyberCORPName(),
            corp.cyberCORPType(),
            corp.cyberCORPJurisdiction(),
            corp.cyberCORPContactDetails(),
            s.securityType,
            s.securitySeries,
            s.certificateUri,
            certLegend,
            effectiveDetails,
            s.endorsements[tokenId],
            s.owners[tokenId],
            registry,
            agreementId,
            tokenId,
            address(this),
            address(s.extension)
        );
    }

    /// @dev Transfer-time restriction and endorsement logic, extracted from
    /// LedgerEntryToken._update to reduce the printer's bytecode size.
    /// External so it runs via delegatecall against this deployed library.
    /// Only called for true transfers (from != 0 && to != 0).
    function processTransfer(address from, address to, uint256 tokenId) external {
        CyberCertStorage storage s = cyberCertStorage();

        // Check built-in transferability flag and per-token override
        if (!s.transferable && !s.tokenTransferable[tokenId]) {
            ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());
            if (from != corp.dealManager() && from != corp.roundManager()) revert ICyberCertPrinter.TokenNotTransferable();
        }

        // Check global hook if it exists
        if (address(s.globalRestrictionHook) != address(0)) {
            (bool allowed, string memory reason) = s.globalRestrictionHook.checkTransferRestriction(
                from, to, tokenId, ""
            );
            if (!allowed) revert ICyberCertPrinter.TransferRestricted(reason);
        }

        ITransferRestrictionHook typeHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
            
        if (address(typeHook) != address(0)) {
            (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                from, to, tokenId, ""
            );
            if (!allowed) revert ICyberCertPrinter.TransferRestricted(reason);
        }

        address ownerAddress = s.owners[tokenId].ownerAddress;
        uint256 endorsementCount = s.endorsements[tokenId].length;
        //check endorsement and update owners
        if (from == ownerAddress) {
            if (!s.endorsementRequired) {
                emit ICyberCertPrinter.CertificateAssigned(tokenId, to, "", IIssuanceManager(s.issuanceManager).companyName());
                _setLegalOwner(s, tokenId, to, "");
            }
            else if (endorsementCount > 0) {
                Endorsement memory endorsement = s.endorsements[tokenId][endorsementCount - 1];
                if (endorsement.endorsee == to) {
                    // Endorsement exists; ownership will be updated
                    emit ICyberCertPrinter.CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(s.issuanceManager).companyName());
                    _setLegalOwner(s, tokenId, endorsement.endorsee, endorsement.endorseeName);
                }
            }
        // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
        }
        // Token is not being transferred from the current owner (e.g. held by a custodian). Delivery to the party
        // named in the latest endorsement promotes legal title (DvP settlement); a move back to the legal owner or
        // on to any other party is a possession-only custody move that leaves legal ownership untouched.
        else if (endorsementCount > 0 && s.endorsements[tokenId][endorsementCount - 1].endorsee == to) {
            Endorsement memory endorsement = s.endorsements[tokenId][endorsementCount - 1];
            emit ICyberCertPrinter.CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(s.issuanceManager).companyName());
            _setLegalOwner(s, tokenId, endorsement.endorsee, endorsement.endorseeName);
        }
    }

    /// @dev Post-mint bookkeeping for LedgerEntryToken.safeMint (the _safeMint itself stays in the printer).
    function recordMint(uint256 tokenId, address to, CertificateDetails memory details) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certLegend[tokenId] = s.defaultLegend;
        copyDefaultRestrictiveLegendsToCert(s, tokenId);
        s.certificateDetails[tokenId] = details;
        _setLegalOwner(s, tokenId, to, "");
        emit ICyberCertPrinter.CyberCertPrinter_CertificateCreated(tokenId);
    }

    /// @dev Post-mint bookkeeping for LedgerEntryToken.safeMintAndAssign.
    function recordMintAndAssign(
        uint256 tokenId,
        address to,
        CertificateDetails memory details,
        string memory investorName
    ) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certLegend[tokenId] = s.defaultLegend;
        copyDefaultRestrictiveLegendsToCert(s, tokenId);
        s.certificateDetails[tokenId] = details;
        _setLegalOwner(s, tokenId, to, investorName);
        emit ICyberCertPrinter.CertificateAssigned(tokenId, to, investorName, IIssuanceManager(s.issuanceManager).companyName());
        emit ICyberCertPrinter.CyberCertPrinter_CertificateCreated(tokenId);
    }

    /// @dev Bookkeeping for LedgerEntryToken.assignCert (the ownerOf check stays in the printer).
    function recordAssign(uint256 tokenId, address to, CertificateDetails memory details) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certificateDetails[tokenId] = details;
        _setLegalOwner(s, tokenId, to, "");
        emit ICyberCertPrinter.CertificateAssigned(tokenId, to, "", IIssuanceManager(s.issuanceManager).companyName());
    }

    /// @dev Endorsement push + event for LedgerEntryToken.addEndorsement (the auth check stays in the printer).
    function recordEndorsement(uint256 tokenId, Endorsement memory newEndorsement) external {
        _recordEndorsement(tokenId, newEndorsement);
    }

    /// @dev Builds a secondary-market endorsement (endorsee/name left blank; registry cleared) and records it.
    /// Mirrors the tuple the IssuanceManager used to assemble before proxying to addEndorsement.
    function endorseCertificate(
        uint256 tokenId,
        address endorser,
        bytes memory signature,
        bytes32 agreementId
    ) external {
        _recordEndorsement(
            tokenId,
            Endorsement({
                endorser: endorser,
                timestamp: block.timestamp,
                signatureHash: signature,
                registry: address(0),
                agreementId: agreementId,
                endorsee: address(0),
                endorseeName: ""
            })
        );
    }

    function _recordEndorsement(uint256 tokenId, Endorsement memory newEndorsement) private {
        CyberCertStorage storage s = cyberCertStorage();
        s.endorsements[tokenId].push(newEndorsement);
        emit ICyberCertPrinter.CertificateEndorsed(
            tokenId,
            newEndorsement.endorser,
            newEndorsement.endorsee,
            newEndorsement.endorseeName,
            newEndorsement.registry,
            newEndorsement.agreementId,
            s.endorsements[tokenId].length - 1,
            block.timestamp
        );
    }

    /// @dev Single chokepoint for every owners[] write: reassign tokenId's legal owner to `newOwner`
    /// (holder-of-record name `name`) while keeping the per-legal-owner enumeration in sync.
    function _setLegalOwner(CyberCertStorage storage s, uint256 tokenId, address newOwner, string memory name) private {
        OwnerDetails storage record = s.owners[tokenId];
        address current = record.ownerAddress;

        // Same owner of record: not an acquisition, so leave the clock and the enumeration move alone. Still
        // lazily backfill a legacy token's enumeration entry, and emit if the holder-of-record name changed.
        if (current == newOwner) {
            if (newOwner != address(0)) {
                _addToLegalOwnerEnumeration(s, newOwner, tokenId);
                if (keccak256(bytes(record.name)) != keccak256(bytes(name))) {
                    emit ICyberCertPrinter.LegalOwnerChanged(tokenId, current, newOwner, name, s.acquisitionTimestamp[tokenId]);
                }
            }
            record.name = name;
            return;
        }

        // Genuine change of legal owner, emitted either way. A move to a real holder is an acquisition: (re)stamp
        // the clock and, on the first assignment (current == 0), the immutable issue timestamp. A move to
        // address(0) clears the record and its clock (keeping acquisitionTimestamp != 0 iff there is an owner).
        uint64 ts;
        if (newOwner != address(0)) {
            ts = uint64(block.timestamp);
            s.acquisitionTimestamp[tokenId] = ts;
            if (current == address(0)) s.issueTimestamp[tokenId] = ts;
        } else {
            s.acquisitionTimestamp[tokenId] = 0;
        }
        emit ICyberCertPrinter.LegalOwnerChanged(tokenId, current, newOwner, name, ts);

        // Look-through tally: this lot leaves `current` and joins `newOwner` (both no-ops when the address
        // is 0 or the token is void/untracked).
        _uncountLot(s, tokenId, current);

        // The remove is a no-op for an un-tracked token and the add is idempotent, so this keeps live state and
        // lazily backfills a legacy token (minted before the enumeration existed).
        if (current != address(0)) _removeFromLegalOwnerEnumeration(s, current, tokenId);
        if (newOwner != address(0)) _addToLegalOwnerEnumeration(s, newOwner, tokenId);
        record.ownerAddress = newOwner;
        record.name = name;

        _countLot(s, tokenId, newOwner);
    }

    /// @dev Idempotent: a token already in an owner's enumeration is left alone (so backfilling a tracked token
    /// is a no-op and we never double-count).
    function _addToLegalOwnerEnumeration(CyberCertStorage storage s, address owner, uint256 tokenId) private {
        if (s.legalOwnedTokenTracked[tokenId]) return;
        uint256 index = s.legalOwnerTokenCount[owner];
        s.legalOwnedTokens[owner][index] = tokenId;
        s.legalOwnedTokensIndex[tokenId] = index;
        s.legalOwnerTokenCount[owner] = index + 1;
        s.legalOwnedTokenTracked[tokenId] = true;
    }

    /// @dev Swap-and-pop removal, mirroring OZ ERC721Enumerable's _removeTokenFromOwnerEnumeration. No-op for an
    /// un-tracked token — this is what keeps a legacy printer's first owner-change/burn from underflowing
    /// `legalOwnerTokenCount` (which is 0 until the token is backfilled).
    function _removeFromLegalOwnerEnumeration(CyberCertStorage storage s, address owner, uint256 tokenId) private {
        if (!s.legalOwnedTokenTracked[tokenId]) return;
        uint256 lastIndex = s.legalOwnerTokenCount[owner] - 1;
        uint256 tokenIndex = s.legalOwnedTokensIndex[tokenId];
        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = s.legalOwnedTokens[owner][lastIndex];
            s.legalOwnedTokens[owner][tokenIndex] = lastTokenId;
            s.legalOwnedTokensIndex[lastTokenId] = tokenIndex;
        }
        delete s.legalOwnedTokensIndex[tokenId];
        delete s.legalOwnedTokens[owner][lastIndex];
        s.legalOwnerTokenCount[owner] = lastIndex;
        s.legalOwnedTokenTracked[tokenId] = false;
    }

    /// @dev Drop tokenId from its legal owner's enumeration on burn — no transfer hook fires for to==0,
    /// so the printer calls this explicitly.
    function recordBurnLegalOwner(uint256 tokenId) external {
        CyberCertStorage storage s = cyberCertStorage();
        address owner = s.owners[tokenId].ownerAddress;
        // Drop the lot from the look-through tally (no-op if already uncounted, e.g. the token was voided).
        _uncountLot(s, tokenId, owner);
        if (owner != address(0)) _removeFromLegalOwnerEnumeration(s, owner, tokenId);
        delete s.owners[tokenId];
    }

    /// @dev One-time/idempotent migration for printers deployed before the legal-owner enumeration existed:
    /// adds each live token in [startIndex, startIndex+count) to its legal owner's enumeration. Permissionless
    /// and safe to re-run — already-tracked tokens are skipped. Call in batches over [0, totalSupply()).
    function backfillLegalOwnerEnumeration(uint256 startIndex, uint256 count) external {
        CyberCertStorage storage s = cyberCertStorage();
        ICyberCertPrinter self = ICyberCertPrinter(address(this)); // delegatecalled: address(this) is the printer
        uint256 supply = self.totalSupply();
        uint256 end = startIndex + count;
        if (end > supply) end = supply;
        for (uint256 i = startIndex; i < end; i++) {
            uint256 tokenId = self.tokenByIndex(i); // enumerates live tokens only (burned are excluded)
            address owner = s.owners[tokenId].ownerAddress;
            if (owner != address(0)) _addToLegalOwnerEnumeration(s, owner, tokenId);
        }
    }

    // ── §3(c)(1)(A) look-through holder tally ────────────────────────────────────────────────────────

    /// @dev A lot counts toward its owner's holder weight iff it is not voided (freshly-minted lots are
    /// Unassigned, which is live). Burned tokens never reach here — they are uncounted at burn.
    function _isLive(CyberCertStorage storage s, uint256 tokenId) private view returns (bool) {
        return s.securityStatus[tokenId] != SecurityStatus.Void;
    }

    /// @dev Sample the look-through weight and US flag from the configured badge; if no badge is wired the
    /// tally degrades to address-level (weight 1, non-US).
    function _sample(CyberCertStorage storage s, address owner) private view returns (uint32 weight, bool isUS) {
        address badge = s.lookThroughBadge;
        if (badge == address(0)) return (1, false);
        uint32 bo = ILexChexBadge(badge).getBeneficialOwnerCount(owner);
        weight = bo > 0 ? bo : 1;
        isUS = ILexChexBadge(badge).isUSInvestor(owner);
    }

    /// @dev Re-read the badge for a live holder and reconcile the totals by the delta, so
    /// `total == Σ holderAcct.weight` stays exact across BO-count or jurisdiction changes. No-op otherwise.
    function _resyncHolder(CyberCertStorage storage s, address owner) private {
        HolderAcct storage a = s.holderAcct[owner];
        if (a.liveLots == 0) return;
        (uint32 newWeight, bool newIsUS) = _sample(s, owner);
        s.lookThroughHolderCount = s.lookThroughHolderCount - a.weight + newWeight;
        uint256 usCount = s.usLookThroughHolderCount;
        if (a.isUS) usCount -= a.weight;
        if (newIsUS) usCount += newWeight;
        s.usLookThroughHolderCount = usCount;
        a.weight = newWeight;
        a.isUS = newIsUS;
    }

    /// @dev Mark tokenId as a live lot for `owner`. On the owner's 0→1 transition, sample and add their
    /// weight to the totals; a further acquisition resyncs their (possibly re-credentialed) weight.
    /// Idempotent via `liveCounted`; no-op for the zero address or a voided token.
    function _countLot(CyberCertStorage storage s, uint256 tokenId, address owner) private {
        if (owner == address(0) || s.liveCounted[tokenId] || !_isLive(s, tokenId)) return;
        s.liveCounted[tokenId] = true;
        HolderAcct storage a = s.holderAcct[owner];
        if (a.liveLots == 0) {
            (uint32 weight, bool isUS) = _sample(s, owner);
            a.liveLots = 1;
            a.weight = weight;
            a.isUS = isUS;
            s.lookThroughHolderCount += weight;
            if (isUS) s.usLookThroughHolderCount += weight;
        } else {
            a.liveLots += 1;
            _resyncHolder(s, owner);
        }
    }

    /// @dev Un-mark tokenId as a live lot for `owner`. On the owner's 1→0 transition, subtract their stored
    /// weight and clear the account. Idempotent via `liveCounted`.
    function _uncountLot(CyberCertStorage storage s, uint256 tokenId, address owner) private {
        if (!s.liveCounted[tokenId]) return;
        s.liveCounted[tokenId] = false;
        HolderAcct storage a = s.holderAcct[owner];
        if (a.liveLots == 0) return; // defensive
        a.liveLots -= 1;
        if (a.liveLots == 0) {
            s.lookThroughHolderCount -= a.weight;
            if (a.isUS) s.usLookThroughHolderCount -= a.weight;
            delete s.holderAcct[owner];
        }
    }

    /// @dev Tally maintenance for voidCert — drop the lot's live contribution. Call after status is set Void.
    function recordVoidLegalOwner(uint256 tokenId) external {
        CyberCertStorage storage s = cyberCertStorage();
        _uncountLot(s, tokenId, s.owners[tokenId].ownerAddress);
    }

    /// @dev Tally maintenance for unvoidCert — restore the lot's live contribution. Call after status is
    /// set back to Assigned (so `_isLive` is true).
    function recordUnvoidLegalOwner(uint256 tokenId) external {
        CyberCertStorage storage s = cyberCertStorage();
        _countLot(s, tokenId, s.owners[tokenId].ownerAddress);
    }

    /// @dev Keeper/admin refresh after a re-credential: reconcile a live holder's contribution to the badge.
    function resyncHolder(address owner) external {
        _resyncHolder(cyberCertStorage(), owner);
    }

    function resyncHolders(address[] calldata owners) external {
        CyberCertStorage storage s = cyberCertStorage();
        for (uint256 i = 0; i < owners.length; i++) _resyncHolder(s, owners[i]);
    }

    /// @dev One-time/idempotent backfill for printers upgraded to add the look-through tally: count each
    /// live token in [startIndex, startIndex+count). Set the badge first. Permissionless, safe to re-run
    /// (already-counted tokens are skipped). Call in batches over [0, totalSupply()).
    function backfillLookThroughTally(uint256 startIndex, uint256 count) external {
        CyberCertStorage storage s = cyberCertStorage();
        ICyberCertPrinter self = ICyberCertPrinter(address(this)); // delegatecalled: address(this) is the printer
        uint256 supply = self.totalSupply();
        uint256 end = startIndex + count;
        if (end > supply) end = supply;
        for (uint256 i = startIndex; i < end; i++) {
            uint256 tokenId = self.tokenByIndex(i);
            _countLot(s, tokenId, s.owners[tokenId].ownerAddress);
        }
    }

    /// @dev In the past, we relied on IssuanceManager to be the proxy for all admin-gated cert functions,
    /// but it took too much unnecessary space. Now we do admin-gate locally. It still utilizes
    /// IssuanceManager's AUTH, but the logic lives here instead.
    /// Offchain clients will need to interact with this contract directly instead of through IssuanceManager, but
    /// other than that, all behaviors stay the same as before.
    function requireManagerOrAdmin() external view {
        CyberCertStorage storage s = cyberCertStorage();
        if (msg.sender == s.issuanceManager) return;
        BorgAuth auth = BorgAuth(IIssuanceManager(s.issuanceManager).AUTH());
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
    }

    /// @dev Rewrites only the Rule 144(d)(3) tacking anchor in the cert's FundInterestData, then writes
    /// it back through the same reserved-units invariant.
    function updateTackedFromAcquisitionDate(uint256 tokenId, uint64 ts) external {
        CyberCertStorage storage s = cyberCertStorage();
        address ext = s.extension;
        if (
            ext == address(0) ||
            !ICertificateExtension(ext).supportsExtensionType(FUND_INTEREST_EXTENSION_TYPE)
        ) revert ICyberCertPrinter.ExtensionTypeNotSupported();
        CertificateDetails memory details = getActiveCertificateDetails(tokenId);
        details.extensionData = IFundInterestExtension(ext).withTackedFrom(details.extensionData, ts);
        if (details.unitsRepresented < s.unitsReserved[tokenId]) revert ICyberCertPrinter.ExceedsAvailableUnits();
        s.certificateDetails[tokenId] = details;
    }

    function setLookThroughBadge(address badge) internal {
        cyberCertStorage().lookThroughBadge = badge;
    }

    function getLookThroughBadge() internal view returns (address) {
        return cyberCertStorage().lookThroughBadge;
    }

    function getLookThroughHolderCount() internal view returns (uint256) {
        return cyberCertStorage().lookThroughHolderCount;
    }

    function getUsLookThroughHolderCount() internal view returns (uint256) {
        return cyberCertStorage().usLookThroughHolderCount;
    }

    function isLegalHolder(address owner) internal view returns (bool) {
        return cyberCertStorage().holderAcct[owner].liveLots > 0;
    }

    /// @dev Reserve units against a pending deal/loan. Reverts if the total reserved
    /// would exceed the certificate's units.
    function increaseUnitsReserved(uint256 tokenId, uint256 amount) external {
        CyberCertStorage storage s = cyberCertStorage();
        uint256 newReserved = s.unitsReserved[tokenId] + amount;
        if (newReserved > s.certificateDetails[tokenId].unitsRepresented) revert ICyberCertPrinter.ExceedsAvailableUnits();
        s.unitsReserved[tokenId] = newReserved;
        emit ICyberCertPrinter.UnitsReservedUpdated(tokenId, newReserved);
    }

    /// @dev Release previously reserved units. Reverts if releasing more than is reserved.
    function decreaseUnitsReserved(uint256 tokenId, uint256 amount) external {
        CyberCertStorage storage s = cyberCertStorage();
        uint256 reserved = s.unitsReserved[tokenId];
        if (amount > reserved) revert ICyberCertPrinter.ExceedsReservedUnits();
        uint256 newReserved;
        unchecked { newReserved = reserved - amount; }
        s.unitsReserved[tokenId] = newReserved;
        emit ICyberCertPrinter.UnitsReservedUpdated(tokenId, newReserved);
    }

    function getUnitsReserved(uint256 tokenId) internal view returns (uint256) {
        return cyberCertStorage().unitsReserved[tokenId];
    }

    function getIssueTimestamp(uint256 tokenId) internal view returns (uint64) {
        return cyberCertStorage().issueTimestamp[tokenId];
    }

    /// @dev Admin override of issueTimestamp for positions issued off-chain before being recorded on-chain.
    function setIssueTimestamp(uint256 tokenId, uint64 ts) external {
        cyberCertStorage().issueTimestamp[tokenId] = ts;
        emit ICyberCertPrinter.IssueTimestampSet(tokenId, ts);
    }

    function getAcquisitionTimestamp(uint256 tokenId) internal view returns (uint64) {
        return cyberCertStorage().acquisitionTimestamp[tokenId];
    }

    /// @dev Admin override of acquisitionTimestamp, e.g. to seed a seasoned position migrated on-chain.
    function setAcquisitionTimestamp(uint256 tokenId, uint64 ts) external {
        cyberCertStorage().acquisitionTimestamp[tokenId] = ts;
        emit ICyberCertPrinter.AcquisitionTimestampSet(tokenId, ts);
    }

    /// @dev Idempotent migration for tokens minted before acquisitionTimestamp became a base field: copies each
    /// live token's FundInterestExtension acquisitionDate into the base mapping over [startIndex, +count).
    /// Permissionless; already-set tokens skipped; no-op on non-FUND_INTEREST printers. Batch over the supply.
    function backfillAcquisitionTimestamp(uint256 startIndex, uint256 count) external {
        CyberCertStorage storage s = cyberCertStorage();
        address ext = s.extension;
        if (
            ext == address(0) ||
            !ICertificateExtension(ext).supportsExtensionType(FUND_INTEREST_EXTENSION_TYPE)
        ) return;
        ICyberCertPrinter self = ICyberCertPrinter(address(this)); // delegatecalled: address(this) is the printer
        uint256 supply = self.totalSupply();
        uint256 end = startIndex + count;
        if (end > supply) end = supply;
        for (uint256 i = startIndex; i < end; i++) {
            uint256 tokenId = self.tokenByIndex(i); // live tokens only (burned excluded)
            if (s.acquisitionTimestamp[tokenId] != 0) continue;
            bytes memory data = s.certificateDetails[tokenId].extensionData;
            if (data.length == 0) continue;
            uint64 acq = IFundInterestExtension(ext).acquisitionDate(data);
            if (acq != 0) s.acquisitionTimestamp[tokenId] = acq;
        }
    }

    function recordHolderChange(address from, address to) internal {
        CyberCertStorage storage s = cyberCertStorage();

        if (from == to) return;

        if (from != address(0)) {
            uint256 fromBalance = s.holderTokenCount[from] - 1;
            s.holderTokenCount[from] = fromBalance;
            if (fromBalance == 0) {
                s.uniqueHolderCount--;
            }
        }

        if (to != address(0)) {
            uint256 toBalance = s.holderTokenCount[to];
            if (toBalance == 0) {
                s.uniqueHolderCount++;
            }
            s.holderTokenCount[to] = toBalance + 1;
        }
    }

    function getHolderCount() internal view returns (uint256) {
        return cyberCertStorage().uniqueHolderCount;
    }

    // Legend management; isDefault selects the defaultLegend array (tokenId ignored) vs a cert's legend
    function _legendArray(uint256 tokenId, bool isDefault) private view returns (string[] storage) {
        CyberCertStorage storage s = cyberCertStorage();
        if (isDefault) return s.defaultLegend;
        return s.certLegend[tokenId];
    }

    function addLegend(uint256 tokenId, bool isDefault, string memory newLegend) external {
        _legendArray(tokenId, isDefault).push(newLegend);
    }

    function removeLegendAt(uint256 tokenId, bool isDefault, uint256 index) external {
        string[] storage arr = _legendArray(tokenId, isDefault);
        uint256 len = arr.length;
        if (index >= len) revert ICyberCertPrinter.InvalidLegendIndex();

        // Move the last element to the index being removed (if it's not the last element)
        // and then pop the last element
        uint256 lastIndex = len - 1;
        if (index != lastIndex) {
            string memory lastLegend = arr[lastIndex];
            arr[index] = lastLegend;
        }
        arr.pop();
    }

    function _restrictiveLegendArray(uint256 tokenId, bool isDefault) private view returns (RestrictiveLegend[] storage) {
        CyberCertStorage storage s = cyberCertStorage();
        if (isDefault) return s.defaultLegendsV2;
        return s.certLegendsV2[tokenId];
    }

    function copyDefaultRestrictiveLegendsToCert(CyberCertStorage storage s, uint256 tokenId) private {
        delete s.certLegendsV2[tokenId];
        RestrictiveLegend[] storage certLegends = s.certLegendsV2[tokenId];
        for (uint256 i = 0; i < s.defaultLegendsV2.length; i++) {
            RestrictiveLegend memory legend = s.defaultLegendsV2[i];
            certLegends.push(legend);
        }
    }

    function addRestrictiveLegend(uint256 tokenId, bool isDefault, RestrictiveLegend memory newLegend) external {
        _restrictiveLegendArray(tokenId, isDefault).push(newLegend);
    }

    function removeRestrictiveLegendAt(uint256 tokenId, bool isDefault, uint256 index) external {
        RestrictiveLegend[] storage arr = _restrictiveLegendArray(tokenId, isDefault);
        uint256 len = arr.length;
        if (index >= len) revert ICyberCertPrinter.InvalidLegendIndex();

        uint256 lastIndex = len - 1;
        if (index != lastIndex) {
            arr[index] = arr[lastIndex];
        }
        arr.pop();
    }

    function getEffectiveRestrictiveLegends(uint256 tokenId) internal view returns (RestrictiveLegend[] memory legends) {
        CyberCertStorage storage s = cyberCertStorage();
        if (s.certLegendsV2[tokenId].length > 0) {
            RestrictiveLegend[] storage storedLegends = s.certLegendsV2[tokenId];
            legends = new RestrictiveLegend[](storedLegends.length);
            for (uint256 i = 0; i < storedLegends.length; i++) {
                legends[i] = storedLegends[i];
            }
        } else {
            string[] storage legacyLegends = s.certLegend[tokenId];
            legends = new RestrictiveLegend[](legacyLegends.length);
            for (uint256 i = 0; i < legacyLegends.length; i++) {
                legends[i] = RestrictiveLegend({
                    restrictionType: RestrictionType.Custom,
                    title: "",
                    text: legacyLegends[i],
                    jurisdiction: "",
                    referenceId: bytes32(0),
                    effectiveTimestamp: 0,
                    expirationTimestamp: 0,
                    active: true,
                    data: ""
                });
            }
        }
    }

    // Internal getters for complex types
    function getStoredCertificateDetails(uint256 tokenId) internal view returns (CertificateDetails storage) {
        return cyberCertStorage().certificateDetails[tokenId];
    }

    function getActiveCertificateDetails(
        uint256 tokenId
    ) internal view returns (CertificateDetails memory details) {
        details = cyberCertStorage().certificateDetails[tokenId];
    }

    function getCertificateDetails(
        uint256 tokenId
    ) internal view returns (CertificateDetails memory details) {
        CyberCertStorage storage s = cyberCertStorage();
        details = getActiveCertificateDetails(tokenId);

        (
            bool isScripified,
            uint256 scripifiedUnits,
            uint256 _maxUnitsRepresented
        ) = IIssuanceManager(s.issuanceManager).getCertScripifiedStatus(
                address(this),
                tokenId
            );

        if (isScripified) {
            details.unitsRepresented = details.unitsRepresented + scripifiedUnits;
        }
    }

    function getEndorsements(uint256 tokenId) internal view returns (Endorsement[] storage) {
        return cyberCertStorage().endorsements[tokenId];
    }

    function getOwnerDetails(uint256 tokenId) internal view returns (OwnerDetails storage) {
        return cyberCertStorage().owners[tokenId];
    }

    function getSecurityStatus(uint256 tokenId) internal view returns (SecurityStatus) {
        return cyberCertStorage().securityStatus[tokenId];
    }

    // Setters
    function setCertificateDetails(uint256 tokenId, CertificateDetails memory details) internal {
        cyberCertStorage().certificateDetails[tokenId] = details;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory endorsement) internal {
        cyberCertStorage().endorsements[tokenId].push(endorsement);
    }

    function setOwnerDetails(uint256 tokenId, OwnerDetails memory details) internal {
        _setLegalOwner(cyberCertStorage(), tokenId, details.ownerAddress, details.name);
    }

    function setSecurityStatus(uint256 tokenId, SecurityStatus status) internal {
        cyberCertStorage().securityStatus[tokenId] = status;
    }

    // Configuration setters
    function setIssuanceManager(address _issuanceManager) internal {
        cyberCertStorage().issuanceManager = _issuanceManager;
    }

    function setCertificateUri(string memory _certificateUri) internal {
        cyberCertStorage().certificateUri = _certificateUri;
    }

    function setTransferable(bool _transferable) internal {
        cyberCertStorage().transferable = _transferable;
    }

    function setTokenTransferable(uint256 tokenId, bool value) internal {
        cyberCertStorage().tokenTransferable[tokenId] = value;
    }

    function isTokenTransferable(uint256 tokenId) internal view returns (bool) {
        return cyberCertStorage().tokenTransferable[tokenId];
    }

    function setRestrictionHook(uint256 tokenId, ITransferRestrictionHook hook) internal {
        cyberCertStorage().restrictionHooksById[tokenId] = hook;
    }

    function setGlobalRestrictionHook(ITransferRestrictionHook hook) internal {
        cyberCertStorage().globalRestrictionHook = hook;
    }

    // Update the getter/setter for defaultLegend
    function getDefaultLegend() internal view returns (string[] memory) {
        return cyberCertStorage().defaultLegend;
    }

    function setDefaultLegend(string[] memory _defaultLegend) internal {
        cyberCertStorage().defaultLegend = _defaultLegend;
    }

    // Extension management
    function setExtension(uint256 tokenId, address extension) internal {
        cyberCertStorage().extension = extension;
    }

    function getExtension(uint256 tokenId) internal view returns (address) {
        return cyberCertStorage().extension;
    }

    function _getExtensionData(uint256 tokenId) internal view returns (bytes memory) {
        return cyberCertStorage().certificateDetails[tokenId].extensionData;
    }

} 