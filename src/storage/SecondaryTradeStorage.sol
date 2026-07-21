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

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712Lib} from "../libs/EIP712Lib.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/IIssuanceManager.sol";
import {ICyberCertPrinter} from "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/IDealManagerFactory.sol";
import "../interfaces/IDealManager.sol";
import "openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import "./DealManagerStorage.sol";
import "./DealManagerFactoryStorage.sol";
import {LexScrowStorage} from "./LexScrowStorage.sol";
import {ISecondaryTradingCondition} from "../libs/conditions/BaseSecondaryTradingCondition.sol";
import {ISecondaryTradeStorage, OfferSide, OfferStatus, SecondaryEscrowStatus, ExemptionPathway, HostingMode, Offer, SecondaryEscrow, PostOfferParams, AcceptOfferParams} from "../interfaces/ISecondaryTradeStorage.sol";

/// @title SecondaryTradeStorage
/// @notice Diamond storage + secondary-trade business logic for DealManager.
/// @dev The logic functions are `public`/`external` so the library is deployed separately and linked;
/// DealManager calls them via DELEGATECALL (msg.sender / storage context preserved), keeping that logic out
/// of DealManager's bytecode (EIP-170). This path's events/errors live in ISecondaryTradeStorage and are
/// referenced as ISecondaryTradeStorage.X
library SecondaryTradeStorage {
    using SafeERC20 for IERC20;

    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.secondary.trade.storage.v1");

    /// @dev Fallback settlement window used when settlementWindow is unset (0), so an accepted lot always
    /// gets a finalize window measured from acceptance rather than inheriting the (possibly imminent) offer
    /// expiry. Must exceed any configured TimeSettlementPeriodCondition minimum delay for the lot to be
    /// finalizeable; owners with a longer minimum (e.g. QMS-mode) set a larger window via setSettlementWindow.
    uint256 constant DEFAULT_SETTLEMENT_WINDOW = 7 days;

    // ── EIP-712 relayer-authorization constants (see the relayer overloads of post/cancel/acceptOffer) ──
    // The signed message binds the full structured params (so a wallet renders each named field), the
    // principal `forAddr`, and an unordered `nonce` that makes each authorization single-use independent
    // of any downstream state. Domain/digest construction and recovery are delegated to
    // EIP712Lib.verifySignature (see _verifyForAuth); only the trade-specific typehashes live here.
    string constant EIP712_NAME = "DealManager";
    string constant EIP712_VERSION = "1";
    // Nested-struct EIP-712: the AUTH typehash's encodeType appends the referenced params type (adjacent
    // string literals concatenate at compile time); the PARAMS typehash (the struct's own type) hashStructs
    // the params member. The duplicated params-type literals below must stay identical.
    bytes32 constant POST_OFFER_PARAMS_TYPEHASH = keccak256(
        "PostOfferParams(uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,address integrator,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues,bytes offerorAgreementSig,bytes openEndorsementSig,string buyerName,uint8 buyerHostingMode,address adminMultisig)"
    );
    bytes32 constant ACCEPT_OFFER_PARAMS_TYPEHASH = keccak256(
        "AcceptOfferParams(bytes32 offerId,uint256 units,uint8 exemptionPathway,string buyerName,uint8 buyerHostingMode,address adminMultisig,uint256 sellerTokenId,string[] acceptorPartyValues,bytes acceptorAgreementSig,bytes openEndorsementSig)"
    );
    bytes32 constant POST_OFFER_AUTH_TYPEHASH = keccak256(
        "PostOfferAuth(PostOfferParams params,address forAddr,uint256 nonce)"
        "PostOfferParams(uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,address integrator,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues,bytes offerorAgreementSig,bytes openEndorsementSig,string buyerName,uint8 buyerHostingMode,address adminMultisig)"
    );
    bytes32 constant ACCEPT_OFFER_AUTH_TYPEHASH = keccak256(
        "AcceptOfferAuth(AcceptOfferParams params,address forAddr,uint256 nonce)"
        "AcceptOfferParams(bytes32 offerId,uint256 units,uint8 exemptionPathway,string buyerName,uint8 buyerHostingMode,address adminMultisig,uint256 sellerTokenId,string[] acceptorPartyValues,bytes acceptorAgreementSig,bytes openEndorsementSig)"
    );
    bytes32 constant CANCEL_OFFER_AUTH_TYPEHASH =
        keccak256("CancelOfferAuth(bytes32 offerId,address forAddr,uint256 nonce)");
    bytes32 constant VOID_SECONDARY_AUTH_TYPEHASH =
        keccak256("VoidSecondaryTradeAuth(bytes32 agreementId,address signer,bytes32 signatureHash,uint256 nonce)");

    // This library's events/errors are declared once in ISecondaryTradeStorage and referenced as
    // ISecondaryTradeStorage.X below.

    struct SecondaryTradeData {
        mapping(bytes32 => Offer) offers;              // keyed by offerAgreementId
        mapping(bytes32 => SecondaryEscrow) escrows;   // keyed by settlementAgreementId
        uint256 minTradeUnits;
        uint256 minTradeConsideration;                 // 0 = disabled
        address defaultIntegrator;
        // Condition config (owner-managed, per-DealManager). Threshold conditions gate post/accept and are
        // re-checked at finalize; closing conditions gate finalize. The SPV layer and closing set are
        // snapshotted onto each Offer at postOffer so an offer is governed by the rules in effect when it was
        // posted; the pathway layer is snapshotted onto each SecondaryEscrow at acceptOffer, once the
        // settlement's pathway is elected. Traders never supply condition addresses.
        address[] spvThresholdConditions;                        // Layer 2 — fund-specific (§6); added at SPV onboarding; applies to every offer
        mapping(ExemptionPathway => address[]) pathwayThresholdConditions; // Layer 1 — exemption-specific (§5); selected by the settlement's elected pathway
        address[] closingConditions;                             // default closing set
        // Consumed relayer-authorization nonces: usedAuthNonce[forAddr][nonce], order-independent single-use.
        mapping(address => mapping(uint256 => bool)) usedAuthNonce;
        // Per-DealManager settlement window: how long after acceptance a lot has to finalize before it can be
        // voided as expired. Decouples settlement expiry from offer expiry (0 = DEFAULT_SETTLEMENT_WINDOW).
        uint256 settlementWindow;
        // Which exemption pathways this SPV supports. Default false, so an SPV that never configured a
        // pathway cannot have trades settled under it: an empty pathwayThresholdConditions entry would
        // otherwise read as "no Layer 1 checks required" rather than "not supported here". Also doubles as a
        // per-pathway off-switch. Read live (not snapshotted): disabling stops new offers and acceptances,
        // while lots already accepted resolve under the rules they were accepted under.
        mapping(ExemptionPathway => bool) pathwayEnabled;
    }

    /// @notice Effective settlement window, applying the default when unset (so legacy DealManager does not need migration)
    function getSettlementWindow() internal view returns (uint256) {
        uint256 window = secondaryTradeStorage().settlementWindow;
        return window == 0 ? DEFAULT_SETTLEMENT_WINDOW : window;
    }

    function secondaryTradeStorage() internal pure returns (SecondaryTradeData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function hasSecondaryEscrow(bytes32 agreementId) internal view returns (bool) {
        return secondaryTradeStorage().escrows[agreementId].counterparty != address(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — offer lifecycle (linked logic; called via delegatecall)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Relayer variant of postOffer: a relayer submits on behalf of `forAddr`, who authorizes the
    /// call with an EIP-712 signature over `params` + `forAddr` + `nonce`. Offer identity, custody and
    /// reservations are all attributed to `forAddr`.
    function postOffer(PostOfferParams calldata params, address forAddr, uint256 nonce, bytes memory sig) external returns (bytes32 offerId) {
        bytes32 structHash = keccak256(abi.encode(POST_OFFER_AUTH_TYPEHASH, _hashPostOfferParams(params), forAddr, nonce));
        _verifyForAuth(structHash, forAddr, nonce, sig);
        return _postOffer(params, forAddr);
    }

    function postOffer(PostOfferParams calldata params) external returns (bytes32 offerId) {
        return _postOffer(params, msg.sender);
    }

    function _postOffer(PostOfferParams calldata params, address offeror) internal returns (bytes32 offerId) {
        SecondaryTradeData storage ds = secondaryTradeStorage();

        // validate parameters
        if (params.certPrinter == address(0)) revert ISecondaryTradeStorage.MissingCertPrinter();
        if (!DealManagerStorage.getIssuanceManager().isPrinter(params.certPrinter))
            revert ISecondaryTradeStorage.UnknownCertPrinter();

        // Validate integrator
        address integrator = params.integrator != address(0)
            ? params.integrator
            : ds.defaultIntegrator;
        if (integrator != address(0)) {
            if (!IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).isIntegratorWhitelisted(integrator))
                revert ISecondaryTradeStorage.IntegratorNotWhitelisted();
        }

        // Reject zero-unit offers outright: the min-threshold check below only catches this when a
        // floor is configured, so a disabled-threshold offer would otherwise mint an empty, un-acceptable offer.
        if (params.units == 0) revert ISecondaryTradeStorage.BelowMinTradeThreshold();

        // The exemption is the buyer's to claim, so only a buy offer's offeror can pin it at posting. A sell
        // offeror may still pin one to restrict who can accept, or leave it NONE and let each buyer elect.
        if (params.side == OfferSide.BUY && params.exemptionPathway == ExemptionPathway.NONE)
            revert ISecondaryTradeStorage.ExemptionPathwayRequired();
        if (params.exemptionPathway != ExemptionPathway.NONE) _requirePathwayEnabled(params.exemptionPathway);

        // Validate min threshold against the whole offer
        _checkMinTradeThreshold(params.units, params.consideration);

        // Generate offer ID deterministically — DealManager-internal key, not a registry record
        offerId = keccak256(abi.encode(offeror, params.templateId, params.salt));
        if (ds.offers[offerId].offeror != address(0)) revert ISecondaryTradeStorage.OfferAlreadyExists();

        // Resolve conditions from this DealManager's config (never from the caller): the fund-specific (§6)
        // threshold layer and the default closing set are snapshotted onto the offer so it is governed by the
        // rules in effect at posting; the kill switch still bites later since KillSwitchCondition reads live
        // state internally. The exemption-specific (§5) layer is NOT snapshotted here — it hangs off the
        // elected pathway, which for an unpinned offer is only known once a buyer accepts, so each settlement
        // resolves and snapshots its own (see _acceptOffer).
        address[] memory resolvedThreshold = ds.spvThresholdConditions;
        address[] memory resolvedClosing = ds.closingConditions;

        // Store offer record before evaluating conditions so seller-side conditions that call
        // getOffer(offerId) see the populated record; a condition revert rolls this write back.
        ds.offers[offerId] = Offer({
            spvAddress: LexScrowStorage.getCorp(),
            offeror: offeror,
            side: params.side,
            certPrinter: params.certPrinter,
            tokenId: params.tokenId,
            units: params.units,
            paymentToken: params.paymentToken,
            consideration: params.consideration,
            exemptionPathway: params.exemptionPathway,
            validUntil: params.validUntil,
            counterpartyRestrictions: params.counterpartyRestrictions,
            additionalTerms: params.additionalTerms,
            integrator: integrator,
            status: OfferStatus.LIVE,
            unitsAccepted: 0,
            paymentAccepted: 0,
            unitsFinalized: 0,
            offerId: offerId,
            templateId: params.templateId,
            salt: params.salt,
            globalValues: params.globalValues,
            offerorPartyValues: params.offerorPartyValues,
            offerorAgreementSig: params.offerorAgreementSig,
            openEndorsementSig: params.openEndorsementSig,
            buyerName: params.side == OfferSide.BUY ? params.buyerName : "",
            buyerHostingMode: params.side == OfferSide.BUY ? params.buyerHostingMode : HostingMode.DIRECT,
            adminMultisig: params.side == OfferSide.BUY ? params.adminMultisig : address(0),
            settlementAgreementIds: new bytes32[](0),
            // Persisted so they can be re-evaluated at acceptOffer (spec §conditions: threshold
            // conditions gate both posting and acceptance).
            thresholdConditions: resolvedThreshold,     // SPV layer only; see the pathway layer on SecondaryEscrow
            // Persisted so they can be evaluated at finalize (spec §conditions: closing conditions
            // gate asset transfer).
            closingConditions: resolvedClosing
        });

        // Evaluate threshold conditions (offer is now readable via getOffer). At posting there are no
        // settlements yet (agreementId == 0), so buyer-facing conditions short-circuit; seller/offer-wide
        // conditions enforce. An unpinned offer has no pathway layer to run yet, so its seller-facing
        // exemption conditions (e.g. holding period) are first enforced at acceptance.
        _checkThresholdConditions(offerId, bytes32(0));

        if (params.side == OfferSide.SELL) {
            if (ICyberCertPrinter(params.certPrinter).legalOwnerOf(params.tokenId) != offeror)
                revert ISecondaryTradeStorage.NotCertOwner();
            // Reserve units on the seller's cert (the printer authorizes this DealManager as an admin)
            ICyberCertPrinter(params.certPrinter).increaseUnitsReserved(params.tokenId, params.units);
        } else {
            // BUY: pull consideration directly into contract custody
            IERC20(params.paymentToken).safeTransferFrom(offeror, address(this), params.consideration);
        }

        // Emit the full offer record (read back from storage so buy-side fields carry their normalized values)
        // so an off-chain indexer can rebuild the offer status from this single log.
        Offer storage posted = ds.offers[offerId];
        emit ISecondaryTradeStorage.OfferPosted(
            offerId, offeror, params.certPrinter, posted.spvAddress, params.side,
            params.tokenId, params.units, params.paymentToken, params.consideration,
            params.exemptionPathway, params.validUntil, integrator,
            posted.templateId, posted.buyerName, posted.buyerHostingMode, posted.adminMultisig,
            posted.counterpartyRestrictions, posted.thresholdConditions, posted.closingConditions
        );
    }

    /// @notice Relayer variant of cancelOffer: a relayer cancels on behalf of `forAddr`, who authorizes the
    /// call with an EIP-712 signature over `offerId` + `forAddr` + `nonce`.
    function cancelOffer(bytes32 offerId, address forAddr, uint256 nonce, bytes memory sig) external {
        bytes32 structHash = keccak256(abi.encode(CANCEL_OFFER_AUTH_TYPEHASH, offerId, forAddr, nonce));
        _verifyForAuth(structHash, forAddr, nonce, sig);
        _cancelOffer(offerId, forAddr);
    }

    /// @notice Cancels a non-terminal offer and returns its uncommitted assets to the offeror
    /// @dev Only the free pool (uncommitted units / consideration) is refunded/released. Settlements already
    /// accepted stay ACCEPTED and resolve on their own — finalized normally, or voided via the two-party
    /// voidSecondaryTradeAgreement / expiry path; their assets stay in DealManager custody until then.
    /// @param offerId Offer to cancel
    function cancelOffer(bytes32 offerId) public {
        _cancelOffer(offerId, msg.sender);
    }

    function _cancelOffer(bytes32 offerId, address canceller) internal {
        Offer storage offer = secondaryTradeStorage().offers[offerId];
        if (offer.offeror != canceller) revert ISecondaryTradeStorage.NotOfferor();
        if (_isOfferTerminal(offer.status)) revert ISecondaryTradeStorage.OfferNotAvailable();

        offer.status = OfferStatus.CANCELLED;

        // Return only the free pool; committed lots stay reserved / in custody and are consumed at
        // finalize or released/refunded when their settlement is voided.
        if (offer.side == OfferSide.SELL) {
            // Release only the uncommitted units; in-flight settlement lots are consumed at finalize or released at void
            uint256 freeUnits = offer.units - offer.unitsAccepted;
            if (freeUnits > 0) {
                ICyberCertPrinter(offer.certPrinter).decreaseUnitsReserved(offer.tokenId, freeUnits);
            }
        } else {
            // BUY: refund only the uncommitted portion; paymentAccepted tracks what's committed to
            // active and finalized settlements (mirrors unitsAccepted: decrements on void only)
            uint256 freePayment = offer.consideration - offer.paymentAccepted;
            if (freePayment > 0) {
                IERC20(offer.paymentToken).safeTransfer(offer.offeror, freePayment);
            }
        }

        emit ISecondaryTradeStorage.OfferCancelled(offerId, canceller);
    }

    /// @notice Relayer variant of acceptOffer: a relayer accepts on behalf of `forAddr`, who authorizes the
    /// call with an EIP-712 signature over `params` + `forAddr` + `nonce`. The acceptor identity, custody
    /// and reservations are all attributed to `forAddr` (whose params.acceptorAgreementSig the registry
    /// still verifies).
    function acceptOffer(AcceptOfferParams calldata params, address forAddr, uint256 nonce, bytes memory sig) external returns (bytes32 settlementAgreementId) {
        bytes32 structHash = keccak256(abi.encode(ACCEPT_OFFER_AUTH_TYPEHASH, _hashAcceptOfferParams(params), forAddr, nonce));
        _verifyForAuth(structHash, forAddr, nonce, sig);
        return _acceptOffer(params, forAddr);
    }

    function acceptOffer(AcceptOfferParams calldata params) public returns (bytes32 settlementAgreementId) {
        return _acceptOffer(params, msg.sender);
    }

    function _acceptOffer(AcceptOfferParams calldata params, address acceptor) internal returns (bytes32 settlementAgreementId) {
        Offer storage offer = secondaryTradeStorage().offers[params.offerId];

        if (offer.status != OfferStatus.LIVE && offer.status != OfferStatus.PARTIALLY_ACCEPTED) revert ISecondaryTradeStorage.OfferNotAvailable();
        if (block.timestamp > offer.validUntil) revert ISecondaryTradeStorage.OfferExpired();

        // Elect this settlement's exemption pathway. The exemption is claimed by the buyer, so on a buy offer
        // the offeror already made the choice at posting and it stands; on a sell offer the accepting buyer
        // elects here, subject to any pathway the seller pinned. Each lot elects independently, so one offer
        // can settle to different buyers under different pathways.
        ExemptionPathway electedPathway;
        if (offer.side == OfferSide.BUY) {
            electedPathway = offer.exemptionPathway;
        } else {
            electedPathway = params.exemptionPathway;
            if (electedPathway == ExemptionPathway.NONE) revert ISecondaryTradeStorage.ExemptionPathwayRequired();
            if (offer.exemptionPathway != ExemptionPathway.NONE && offer.exemptionPathway != electedPathway)
                revert ISecondaryTradeStorage.ExemptionPathwayMismatch(offer.exemptionPathway, electedPathway);
        }
        // Re-checked here for both sides: a pathway enabled at posting may have been withdrawn since.
        _requirePathwayEnabled(electedPathway);

        // Reject zero-unit fills outright: the min-threshold check below only catches this when a
        // floor is configured, so a disabled-threshold offer would otherwise mint an empty settlement.
        if (params.units == 0) revert ISecondaryTradeStorage.BelowMinTradeThreshold();
        uint256 remainingUnits = offer.units - offer.unitsAccepted;
        if (params.units > remainingUnits) revert ISecondaryTradeStorage.UnitsExceedOffer();

        // Pro-rata consideration for this (possibly partial) fill. The final lot that exhausts the
        // remaining units takes the leftover consideration (offer.consideration - offer.paymentAccepted)
        // rather than another floored pro-rata amount; otherwise flooring across partial fills strands
        // the rounding remainder — unpaid to the seller, or stuck in custody for a buy offer.
        uint256 partialConsideration = params.units == remainingUnits
            ? offer.consideration - offer.paymentAccepted
            : offer.consideration * params.units / offer.units;

        // Re-apply the admin-set minimum-ticket floors that postOffer enforced on the whole offer, now
        // against this lot — otherwise a tiny partial fill can settle below the floor. For a non-exhausting
        // fill we also require the remainder left on the offer to clear the floor, so a sub-floor tail can
        // never be created; that makes the eventual exhausting fill provably above the floor (by induction
        // from postOffer's full-offer check) and needs no exemption.
        if (params.units < remainingUnits) {
            _checkMinTradeThreshold(params.units, partialConsideration);
            uint256 remainderUnits = remainingUnits - params.units;
            uint256 remainderConsideration = (offer.consideration - offer.paymentAccepted) - partialConsideration;
            _checkMinTradeThreshold(remainderUnits, remainderConsideration);
        }

        // Settlement window runs from acceptance, not the offer's validUntil: a lot accepted moments before
        // the offer expires still gets the full window to finalize (and clear any settlement-period minimum
        // delay), instead of a truncated or already-expired one.
        uint256 settlementExpiry = block.timestamp + getSettlementWindow();

        // Create fully-signed settlement agreement via registry.
        // settlementAgreementIds.length is a push-only monotonic nonce: unique per acceptance even if prior
        // settlements are later voided (which decrements unitsAccepted but never shrinks the array).
        address registry = LexScrowStorage.getDealRegistry();
        bytes32 settlementSalt = keccak256(abi.encodePacked(offer.salt, offer.settlementAgreementIds.length));
        address[] memory settlementParties = new address[](2);
        settlementParties[0] = offer.offeror;
        settlementParties[1] = acceptor;
        string[][] memory settlementPartyValues = new string[][](2);
        settlementPartyValues[0] = offer.offerorPartyValues;
        settlementPartyValues[1] = params.acceptorPartyValues;
        settlementAgreementId = ICyberAgreementRegistry(registry).createContract(
            offer.templateId,
            uint256(settlementSalt),
            offer.globalValues,
            settlementParties,
            settlementPartyValues,
            bytes32(0),
            address(this),
            settlementExpiry
        );
        // Offeror: DealManager (finalizer) attests commitment via signContractWithEscrow.
        // The registry does not verify escrowSigner's EIP-712 sig here; the offeror's
        // commitment is evidenced by their postOffer() tx and stored offerorAgreementSig.
        ICyberAgreementRegistry(registry).signContractWithEscrow(
            offer.offeror, settlementAgreementId, offer.offerorPartyValues,
            offer.offerorAgreementSig, false, ""
        );
        // Acceptor: proper EIP-712 sig verified by the registry.
        ICyberAgreementRegistry(registry).signContractFor(
            acceptor, settlementAgreementId, params.acceptorPartyValues,
            params.acceptorAgreementSig, false, ""
        );

        // Resolve cert printer, tokenId, buyer, and endorsement sig per offer side. The seller's open-endorsement
        // signature is only captured here (parked on the SecondaryEscrow below); it is not written to the token
        // until finalization, where secondaryTransfer materializes the real endorsement with the known buyer.
        address certPrinter;
        uint256 tokenId;
        address buyer;
        bytes memory endorsementSig;

        if (offer.side == OfferSide.SELL) {
            certPrinter = offer.certPrinter;
            tokenId = offer.tokenId;
            buyer = acceptor;
            endorsementSig = offer.openEndorsementSig;
            // Re-check the seller still owns the cert
            if (ICyberCertPrinter(certPrinter).legalOwnerOf(tokenId) != offer.offeror)
                revert ISecondaryTradeStorage.SecondaryTradeSellerOwnershipChanged();
        } else {
            certPrinter = offer.certPrinter;
            tokenId = params.sellerTokenId;
            buyer = offer.offeror;
            endorsementSig = params.openEndorsementSig;
            if (ICyberCertPrinter(certPrinter).legalOwnerOf(tokenId) != acceptor)
                revert ISecondaryTradeStorage.NotCertOwner();
            // Reserve units on the seller's cert at acceptance (buy-offer flow, routed through IssuanceManager)
            ICyberCertPrinter(certPrinter).increaseUnitsReserved(tokenId, params.units);
        }

        // Resolve the buyer info per side: buy offers carry it on the offer (the offeror is the buyer),
        // sells take it from the acceptance.
        string memory buyerName;
        HostingMode buyerHostingMode;
        address adminMultisig;
        if (offer.side == OfferSide.BUY) {
            buyerName = offer.buyerName;
            buyerHostingMode = offer.buyerHostingMode;
            adminMultisig = offer.adminMultisig;
        } else {
            buyerName = params.buyerName;
            buyerHostingMode = params.buyerHostingMode;
            adminMultisig = params.adminMultisig;
        }

        // Fund the settlement escrow.
        // BUY: funds are already in contract from postOffer(); no token movement needed.
        // SELL: pull the buyer's payment directly into contract.
        if (offer.side == OfferSide.SELL) {
            IERC20(offer.paymentToken).safeTransferFrom(buyer, address(this), partialConsideration);
        }
        address[] memory pathwayConds = _resolvePathwayConditions(secondaryTradeStorage(), electedPathway);
        secondaryTradeStorage().escrows[settlementAgreementId] = SecondaryEscrow({
            counterparty: acceptor,
            paymentToken: offer.paymentToken,
            paymentAmount: partialConsideration,
            units: params.units,
            expiry: settlementExpiry,
            status: SecondaryEscrowStatus.ACCEPTED,
            feeDestination: offer.integrator,
            offerId: params.offerId,
            tokenId: tokenId,
            buyerName: buyerName,
            buyerHostingMode: buyerHostingMode,
            adminMultisig: adminMultisig,
            openEndorsementSig: endorsementSig,
            exemptionPathway: electedPathway,
            pathwayThresholdConditions: pathwayConds
        });

        // Record settlement for buyer-facing threshold condition lookup
        offer.settlementAgreementIds.push(settlementAgreementId);

        // Re-evaluate threshold conditions now that a settlement exists: buyer-facing conditions
        // (KYC/AML, accreditation, holder caps, etc.) that short-circuited at posting resolve the
        // acceptor via the settlementAgreementId passed here and enforce. A failure reverts the whole
        // acceptance, undoing the settlement, escrow funding, and reservations above.
        _checkThresholdConditions(params.offerId, settlementAgreementId);

        // Update offer accounting and fill state
        offer.unitsAccepted += params.units;
        offer.paymentAccepted += partialConsideration;
        if (offer.unitsAccepted >= offer.units) {
            offer.status = OfferStatus.FULLY_ACCEPTED;
        } else {
            offer.status = OfferStatus.PARTIALLY_ACCEPTED;
        }

        // Acceptance funds the escrow atomically, so this event carries the settlement's payment too.
        emit ISecondaryTradeStorage.OfferAccepted(
            params.offerId, settlementAgreementId, acceptor, params.units, offer.paymentToken, partialConsideration,
            tokenId, settlementExpiry,
            buyerName, buyerHostingMode, adminMultisig, endorsementSig,
            electedPathway, pathwayConds
        );
    }

    /// @dev abi-encodes the ownership-change params for IssuanceManager.secondaryTransfer. Built from
    /// per-settlement state (the offer plus the SecondaryEscrow), so acceptOffer and finalize stay in lockstep.
    function _encodeDealMetadata(
        address certPrinter,
        uint256 tokenId,
        uint256 units,
        address buyer,
        string memory buyerName,
        HostingMode buyerHostingMode,
        address adminMultisig,
        ExemptionPathway exemptionPathway,
        bytes32 settlementAgreementId,
        bytes memory openEndorsementSig
    ) internal pure returns (bytes memory) {
        return abi.encode(
            certPrinter, tokenId, units, buyer, buyerName,
            buyerHostingMode, adminMultisig, exemptionPathway, settlementAgreementId, openEndorsementSig
        );
    }

    /// @notice Finalizes an accepted secondary-trade settlement (pays the seller, executes the ownership change)
    /// @dev Secondary counterpart of DealManager.finalizeDeal. Self-contained: the local escrow status is the
    /// source of truth, so _requireUnconcludedSecondaryEscrow rejects already-finalized/voided settlements; the
    /// settlement is created fully-signed at acceptOffer, so no all-parties-signed check is needed here.
    function finalizeSecondaryTradeAgreement(bytes32 agreementId) external {
        SecondaryEscrow storage secEscrow = secondaryTradeStorage().escrows[agreementId];
        Offer storage offer = secondaryTradeStorage().offers[secEscrow.offerId];

        // Validate the local escrow (source of truth) and fail with local errors BEFORE the external
        // registry call, so an already-finalized/voided settlement never reaches finalizeContract.
        _requireUnconcludedSecondaryEscrow(secEscrow);
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).finalizeContract(agreementId);

        // Defensive backstop: finalizeContract already reverts ContractExpired on the same deadline, so this
        // local guard is effectively unreachable, but kept in case the registry and escrow expiry ever diverge.
        if (block.timestamp > secEscrow.expiry) revert ISecondaryTradeStorage.SecondaryTradeAgreementExpired();
        // Re-check threshold (eligibility) conditions at finalization: a buyer who was eligible at
        // acceptance may have lost eligibility before settlement (credential revoked, holder cap
        // breached, blocked-state move, kill of an approval). Both ids are known, so buyer-facing
        // conditions read this lot's acceptor directly.
        _checkThresholdConditions(secEscrow.offerId, agreementId);

        address[] storage conditions = offer.closingConditions;
        for (uint256 i = 0; i < conditions.length; i++) {
            // note: always double check if `Offer` is properly updated because `checkCondition()` depends on it
            if (!ISecondaryTradingCondition(conditions[i]).checkCondition(IDealManager(address(this)), msg.sig, secEscrow.offerId, agreementId))
                revert ISecondaryTradeStorage.SecondaryConditionsNotMet(conditions[i]);
        }

        // Effect: mark finalized before external calls
        secEscrow.status = SecondaryEscrowStatus.FINALIZED;
        offer.unitsFinalized += secEscrow.units;
        // All offered units settled: the offer reaches its FINALIZED terminal state. CANCELLED
        // stays sticky — both are terminal, and cancellation is the offeror's recorded intent.
        if (offer.status != OfferStatus.CANCELLED && offer.unitsFinalized == offer.units) {
            offer.status = OfferStatus.FINALIZED;
        }
        (address seller, address buyer) = _settlementParties(offer, secEscrow);
        // Require seller ownership to remain unchanged; if it was a legitimately-moved
        // position it'd still revert here and it could be resolved via the void/expiry path instead of mispaying.
        if (ICyberCertPrinter(offer.certPrinter).legalOwnerOf(secEscrow.tokenId) != seller)
            revert ISecondaryTradeStorage.SecondaryTradeSellerOwnershipChanged();
        // Fee math (mirrors DealManager.computeFee / getPlatformPayable) computed directly from the factory
        address upgradeFactory = DealManagerStorage.getUpgradeFactory();
        uint256 fee = secEscrow.paymentAmount * IDealManagerFactory(upgradeFactory).getDefaultFeeRatio() / DealManagerFactoryStorage.BASIS_POINTS;
        uint256 toSeller = secEscrow.paymentAmount - fee;

        if (toSeller > 0) {
            IERC20(secEscrow.paymentToken).safeTransfer(seller, toSeller);
        }

        if (fee > 0) {
            // Re-validate the integrator against the whitelist at settlement: per spec §12B.4 a
            // de-whitelisted integrator falls through to the unsplit MetaLeX-only flow (never reverts).
            address feeDestination = secEscrow.feeDestination;
            uint256 integratorFee;
            if (feeDestination != address(0) && IDealManagerFactory(upgradeFactory).isIntegratorWhitelisted(feeDestination)) {
                // Per spec §12B.4: this integrator's own share of the fee, keyed by feeDestination.
                uint256 integratorRatio = IDealManagerFactory(upgradeFactory).getIntegratorFeeShare(feeDestination);
                integratorFee = fee * integratorRatio / DealManagerFactoryStorage.BASIS_POINTS;
            } else {
                feeDestination = address(0); // fell through to platform-only; report no credited integrator
            }
            uint256 platformFee = fee - integratorFee;
            if (integratorFee > 0) IERC20(secEscrow.paymentToken).safeTransfer(feeDestination, integratorFee);
            if (platformFee > 0) IERC20(secEscrow.paymentToken).safeTransfer(IDealManagerFactory(upgradeFactory).getPlatformPayable(), platformFee);
            // Emit the realized split (feeDestination zero = platform-only) so an indexer needn't recompute it.
            emit ISecondaryTradeStorage.SecondaryFeeDistributed(agreementId, secEscrow.paymentToken, feeDestination, fee, integratorFee, platformFee);
        }

        // Ready to transfer units, release this lot's reservation first
        ICyberCertPrinter(offer.certPrinter).decreaseUnitsReserved(secEscrow.tokenId, secEscrow.units);

        // Execute ownership change: void/decrement seller cert + mint buyer cert.
        DealManagerStorage.getIssuanceManager().secondaryTransfer(
            _encodeDealMetadata(
                offer.certPrinter, secEscrow.tokenId, secEscrow.units, buyer,
                secEscrow.buyerName, secEscrow.buyerHostingMode, secEscrow.adminMultisig,
                secEscrow.exemptionPathway, agreementId, secEscrow.openEndorsementSig
            )
        );

        emit ISecondaryTradeStorage.SecondaryTradeAgreementFinalized(agreementId, seller, buyer, secEscrow.units, secEscrow.paymentAmount);
    }

    /// @notice Voids an expired secondary-trade settlement and refunds/releases its escrowed assets
    /// @dev Secondary counterpart of DealManager.voidExpiredDeal.
    function voidExpiredSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes memory signature) external {
        SecondaryEscrow storage secEscrow = secondaryTradeStorage().escrows[agreementId];
        _requireUnconcludedSecondaryEscrow(secEscrow);
        if (block.timestamp <= secEscrow.expiry) revert ISecondaryTradeStorage.SecondaryTradeAgreementNotExpired();
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        _voidSecondaryTradeAgreement(agreementId);
    }

    /// @notice Records a party's request to void an ACCEPTED secondary settlement before it is finalized or expires
    /// @dev Finalizer-vouched request channel: the registry voids the agreement only once BOTH parties have
    /// requested (or it is past expiry). The local escrow is settled only when that actually happens, keeping
    /// DealManager and the registry in sync; a lone request just records intent and the counterparty can still finalize.
    /// @param agreementId Settlement agreement to void
    /// @param signer Caller's address (must equal msg.sender)
    /// @param signature Caller's EIP-712 void signature, forwarded to the agreement registry
    function voidSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes memory signature) external {
        if (msg.sender != signer) revert ISecondaryTradeStorage.NotSigner();
        _requestVoidSecondaryTradeAgreement(agreementId, signer, signature, msg.sender);
    }

    /// @notice Relayer variant: a relayer submits `signer`'s void request on their behalf. `signer` authorizes
    /// with an EIP-712 signature over `agreementId` + `signer` + keccak256(void signature) + `nonce`; the void
    /// `signature` itself is still verified against `signer` downstream by the registry.
    function voidSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes memory signature, uint256 nonce, bytes memory authSig) external {
        bytes32 structHash = keccak256(abi.encode(VOID_SECONDARY_AUTH_TYPEHASH, agreementId, signer, keccak256(signature), nonce));
        _verifyForAuth(structHash, signer, nonce, authSig);
        _requestVoidSecondaryTradeAgreement(agreementId, signer, signature, signer);
    }

    function _requestVoidSecondaryTradeAgreement(bytes32 agreementId, address signer, bytes memory signature, address party) internal {
        SecondaryEscrow storage secEscrow = secondaryTradeStorage().escrows[agreementId];
        _requireUnconcludedSecondaryEscrow(secEscrow);
        Offer storage offer = secondaryTradeStorage().offers[secEscrow.offerId];
        if (party != secEscrow.counterparty && party != offer.offeror) revert ISecondaryTradeStorage.NotPartyToAgreement();
        address registry = LexScrowStorage.getDealRegistry();
        ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
        // A lone request only records intent; the registry voids once both parties have requested
        // (or past expiry). Settle the escrow locally only when that actually happens.
        if (ICyberAgreementRegistry(registry).isVoided(agreementId)) {
            _voidSecondaryTradeAgreement(agreementId);
        }
    }

    /// @notice Syncs a secondary settlement that was voided directly in the agreement registry
    /// @dev Callable by anyone; guards against double-void via the terminal-state checks
    /// @param agreementId Settlement agreement that was already voided in the registry
    function syncVoidedSecondaryTradeAgreement(bytes32 agreementId) external {
        SecondaryEscrow storage secEscrow = secondaryTradeStorage().escrows[agreementId];
        _requireUnconcludedSecondaryEscrow(secEscrow);
        if (!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert ISecondaryTradeStorage.SecondaryTradeAgreementNotVoided();
        _voidSecondaryTradeAgreement(agreementId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — internals
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Reverts if `units` or `consideration` falls below the admin-set minimum-ticket floors
    /// (either floor disabled when 0). Shared by postOffer (whole offer) and acceptOffer (per lot)
    /// so both gates stay in lockstep.
    function _checkMinTradeThreshold(uint256 units, uint256 consideration) internal view {
        SecondaryTradeData storage ds = secondaryTradeStorage();
        if (ds.minTradeUnits > 0 && units < ds.minTradeUnits) revert ISecondaryTradeStorage.BelowMinTradeThreshold();
        if (ds.minTradeConsideration > 0 && consideration < ds.minTradeConsideration) revert ISecondaryTradeStorage.BelowMinTradeThreshold();
    }

    /// @dev Walks the offer's stored threshold conditions, reverting on the first failure. Conditions
    /// receive the uniform secondary-trade payload `abi.encode(offerId, agreementId)`; `agreementId` is
    /// `bytes32(0)` at posting (no settlement yet) and the settlement id at acceptance and at finalization,
    /// so a buyer-facing condition reads its acceptor directly instead of reaching into settlementAgreementIds.
    /// Re-run at finalization so eligibility lost between acceptance and settlement blocks the asset transfer.
    /// The selector handed to conditions is `msg.sig` — the gated entrypoint's own selector, so the relayer
    /// overloads present their own selector (not the direct-call one); see ISecondaryTradingCondition.
    /// @dev Runs both threshold layers: the offer's SPV layer (§6) plus the exemption layer (§5). Before a
    /// settlement exists the latter is only knowable for an offer that pinned a pathway; from acceptance on it
    /// comes from the settlement's own snapshot, so each lot is judged against the pathway its buyer elected.
    function _checkThresholdConditions(bytes32 offerId, bytes32 agreementId) internal view {
        SecondaryTradeData storage ds = secondaryTradeStorage();
        _runConditions(ds.offers[offerId].thresholdConditions, offerId, agreementId);
        if (agreementId == bytes32(0)) {
            ExemptionPathway pinned = ds.offers[offerId].exemptionPathway;
            if (pinned != ExemptionPathway.NONE) _runConditions(ds.pathwayThresholdConditions[pinned], offerId, agreementId);
        } else {
            _runConditions(ds.escrows[agreementId].pathwayThresholdConditions, offerId, agreementId);
        }
    }

    function _runConditions(address[] storage conditions, bytes32 offerId, bytes32 agreementId) internal view {
        for (uint256 i = 0; i < conditions.length; i++) {
            // note: always double check if `Offer` is properly updated because `checkCondition()` depends on it
            if (!ISecondaryTradingCondition(conditions[i]).checkCondition(IDealManager(address(this)), msg.sig, offerId, agreementId))
                revert ISecondaryTradeStorage.SecondaryConditionsNotMet(conditions[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Relayer-authorization internals (EIP-712 + unordered nonce)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev EIP-712 hashStruct of PostOfferParams (dynamic members pre-hashed, enums as uint8).
    function _hashPostOfferParams(PostOfferParams calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            POST_OFFER_PARAMS_TYPEHASH,
            uint8(p.side),
            p.certPrinter,
            p.tokenId,
            p.units,
            p.paymentToken,
            p.consideration,
            uint8(p.exemptionPathway),
            p.validUntil,
            keccak256(p.counterpartyRestrictions),
            keccak256(p.additionalTerms),
            p.integrator,
            p.templateId,
            p.salt,
            _hashStringArray(p.globalValues),
            _hashStringArray(p.offerorPartyValues),
            keccak256(p.offerorAgreementSig),
            keccak256(p.openEndorsementSig),
            keccak256(bytes(p.buyerName)),
            uint8(p.buyerHostingMode),
            p.adminMultisig
        ));
    }

    /// @dev EIP-712 hashStruct of AcceptOfferParams (dynamic members pre-hashed, enums as uint8).
    function _hashAcceptOfferParams(AcceptOfferParams calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ACCEPT_OFFER_PARAMS_TYPEHASH,
            p.offerId,
            p.units,
            uint8(p.exemptionPathway),
            keccak256(bytes(p.buyerName)),
            uint8(p.buyerHostingMode),
            p.adminMultisig,
            p.sellerTokenId,
            _hashStringArray(p.acceptorPartyValues),
            keccak256(p.acceptorAgreementSig),
            keccak256(p.openEndorsementSig)
        ));
    }

    /// @dev EIP-712 array encoding: keccak256 over the concatenated per-element hashes.
    function _hashStringArray(string[] calldata arr) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            hashes[i] = keccak256(bytes(arr[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @dev Consumes an unordered nonce: reverts if already used, else marks it used. Order-independent,
    /// single-use per (forAddr, nonce).
    function _useUnorderedNonce(address from, uint256 nonce) internal {
        SecondaryTradeData storage ds = secondaryTradeStorage();
        if (ds.usedAuthNonce[from][nonce]) revert ISecondaryTradeStorage.SecondaryAuthReplayed();
        ds.usedAuthNonce[from][nonce] = true;
    }

    /// @dev Verifies a relayer overload's EIP-712 authorization: `sig` must recover to `forAddr` over the
    /// domain-separated `structHash`, then the nonce is consumed. Consumption only sticks if the whole call
    /// succeeds (a later revert rolls the write back), so failed calls do not burn the authorization.
    /// The domain is bound to this DealManager: under delegatecall `address(this)` is the DealManager proxy,
    /// the correct verifyingContract.
    function _verifyForAuth(bytes32 structHash, address forAddr, uint256 nonce, bytes memory sig) internal {
        if (!EIP712Lib.verifySignature(EIP712_NAME, EIP712_VERSION, address(this), forAddr, structHash, sig))
            revert ISecondaryTradeStorage.InvalidSecondaryAuthSignature();
        _useUnorderedNonce(forAddr, nonce);
    }

    /// @dev The exemption-specific (§5) threshold layer registered for `pathway` per v3.53 §7.2, snapshotted
    /// onto a settlement at acceptance. Insertion order is preserved so failures surface deterministically.
    /// Traders choose the pathway, never the condition addresses.
    function _resolvePathwayConditions(SecondaryTradeData storage ds, ExemptionPathway pathway)
        internal view returns (address[] memory resolved)
    {
        return ds.pathwayThresholdConditions[pathway];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Condition config management (linked logic; called via delegatecall by DealManager owner setters)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Replaces the fund-specific (§6) threshold layer wholesale.
    function setSpvThresholdConditions(address[] calldata conditions) external {
        _validateConditions(conditions);
        secondaryTradeStorage().spvThresholdConditions = conditions;
    }

    /// @notice Replaces the exemption-specific (§5) threshold layer for `pathway` and declares whether this
    /// SPV supports the pathway at all. The two travel together: an unsupported pathway must not be
    /// electable, and an empty condition list would otherwise read as "no Layer 1 checks required". NONE is
    /// not a pathway — it only ever means "unpinned" on an offer.
    function setPathwayThresholdConditions(ExemptionPathway pathway, address[] calldata conditions, bool enabled)
        external
    {
        if (pathway == ExemptionPathway.NONE) revert ISecondaryTradeStorage.ExemptionPathwayRequired();
        _validateConditions(conditions);
        SecondaryTradeData storage ds = secondaryTradeStorage();
        ds.pathwayThresholdConditions[pathway] = conditions;
        ds.pathwayEnabled[pathway] = enabled;
    }

    /// @notice Replaces the closing set wholesale.
    function setClosingConditions(address[] calldata conditions) external {
        _validateConditions(conditions);
        secondaryTradeStorage().closingConditions = conditions;
    }

    /// @dev Fail-closed gate on every pathway a trade can be committed to: pinned at posting, elected at
    /// acceptance. Enforced at both, so an offer can never be posted against a pathway that would only
    /// reject its buyers later, after the seller's units are already reserved.
    function _requirePathwayEnabled(ExemptionPathway pathway) internal view {
        if (!secondaryTradeStorage().pathwayEnabled[pathway])
            revert ISecondaryTradeStorage.ExemptionPathwayNotEnabled(pathway);
    }

    /// @dev Validates an owner-supplied condition list before it replaces a stored one, rejecting the zero
    /// address and duplicates so the list behaves as a set. Lists are small (admin-curated), so the linear
    /// dedupe scan is cheap.
    function _validateConditions(address[] calldata conditions) internal view {
        for (uint256 i = 0; i < conditions.length; i++) {
            address condition = conditions[i];
            if (condition == address(0)) revert ISecondaryTradeStorage.InvalidSecondaryCondition();
            // Only strongly-typed secondary-trading conditions may be wired in: reject anything that doesn't
            // advertise ISecondaryTradingCondition via ERC-165 at config time, so a mismatched checkCondition
            // signature can never reach post/accept/finalize. ERC165Checker returns false (no revert) for
            // non-ERC165 targets.
            if (!ERC165Checker.supportsInterface(condition, type(ISecondaryTradingCondition).interfaceId))
                revert ISecondaryTradeStorage.SecondaryConditionInterfaceUnsupported(condition);
            for (uint256 j = 0; j < i; j++) {
                if (conditions[j] == condition) revert ISecondaryTradeStorage.SecondaryConditionAlreadyExists();
            }
        }
    }

    /// @dev Terminal offer states: immutable, not cancellable, and never restored by a void
    function _isOfferTerminal(OfferStatus status) internal pure returns (bool) {
        return status == OfferStatus.CANCELLED || status == OfferStatus.FINALIZED;
    }

    /// @dev Derives the settlement's seller and buyer from the offer side: the offeror is the
    /// seller on SELL offers and the buyer on BUY offers; the counterparty (acceptor) is the other.
    function _settlementParties(Offer storage offer, SecondaryEscrow storage secEscrow)
        internal view returns (address seller, address buyer)
    {
        return offer.side == OfferSide.SELL
            ? (offer.offeror, secEscrow.counterparty)
            : (secEscrow.counterparty, offer.offeror);
    }

    /// @dev Reverts unless the settlement escrow exists and is not yet concluded (status still ACCEPTED,
    /// i.e. neither FINALIZED nor VOIDED). Note "unconcluded" is not "unexpired": an escrow past its
    /// `expiry` is still ACCEPTED and passes here — expiry alone is not a terminal state, the lot just
    /// awaits finalize or a void. The existence check must come first: SecondaryEscrowStatus.ACCEPTED == 0,
    /// so an absent escrow would otherwise read as ACCEPTED and pass. This positively validates the secondary
    /// id space (mirrors the primary side's LexScrowStorage.hasPrimaryEscrow guard). Terminal states get
    /// explicit errors so callers never act on an already-settled escrow.
    function _requireUnconcludedSecondaryEscrow(SecondaryEscrow storage secEscrow) internal view {
        if (secEscrow.counterparty == address(0)) revert ISecondaryTradeStorage.SecondaryEscrowNotFound();
        if (secEscrow.status == SecondaryEscrowStatus.FINALIZED) revert ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyFinalized();
        if (secEscrow.status == SecondaryEscrowStatus.VOIDED) revert ISecondaryTradeStorage.SecondaryTradeAgreementAlreadyVoided();
    }

    function _voidSecondaryTradeAgreement(bytes32 agreementId) internal {
        SecondaryEscrow storage secEscrow = secondaryTradeStorage().escrows[agreementId];
        Offer storage offer = secondaryTradeStorage().offers[secEscrow.offerId];

        // Update accounting counters
        offer.unitsAccepted -= secEscrow.units;
        offer.paymentAccepted -= secEscrow.paymentAmount;

        // Release this lot's unit reservation.
        // BUY: reserved at acceptance for this settlement only — always release.
        // SELL: reserved at postOffer for the whole offer — release only when the offer is CANCELLED
        // (the lot can never be re-accepted); otherwise the lot returns to the offer's free pool
        // and stays reserved.
        if (offer.side == OfferSide.BUY || offer.status == OfferStatus.CANCELLED) {
            ICyberCertPrinter(offer.certPrinter).decreaseUnitsReserved(secEscrow.tokenId, secEscrow.units);
        }

        // Restore offer status (keep terminal offers closed)
        if (!_isOfferTerminal(offer.status)) {
            offer.status = offer.unitsAccepted == 0 ? OfferStatus.LIVE : OfferStatus.PARTIALLY_ACCEPTED;
        }

        bool wasAccepted = secEscrow.status == SecondaryEscrowStatus.ACCEPTED;
        secEscrow.status = SecondaryEscrowStatus.VOIDED;
        emit ISecondaryTradeStorage.SecondaryTradeAgreementVoided(agreementId);
        if (wasAccepted) {
            // Refund mirrors the reservation logic above, with sides swapped.
            // SELL: payment was pulled per-settlement at acceptOffer — always refund the buyer.
            // BUY: payment came from the offer's pool at postOffer — refund only when the offer is
            // CANCELLED (the lot can never be re-accepted); otherwise the payment returns to the
            // offer's free pool and stays in custody.
            if (offer.side == OfferSide.SELL || offer.status == OfferStatus.CANCELLED) {
                (, address buyer) = _settlementParties(offer, secEscrow);
                IERC20(secEscrow.paymentToken).safeTransfer(buyer, secEscrow.paymentAmount);
            }
        }
    }
}
