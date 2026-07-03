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
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/IIssuanceManager.sol";
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
    using ECDSA for bytes32;

    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.secondary.trade.storage.v1");

    // ── EIP-712 relayer-authorization constants (see the relayer overloads of post/cancel/acceptOffer) ──
    // The signed message binds the full structured params (so a wallet renders each named field), the
    // principal `forAddr`, and an unordered `nonce` that makes each authorization single-use independent
    // of any downstream state.
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Nested-struct EIP-712: the AUTH typehash's encodeType appends the referenced params type (adjacent
    // string literals concatenate at compile time); the PARAMS typehash (the struct's own type) hashStructs
    // the params member. The duplicated params-type literals below must stay identical.
    bytes32 constant POST_OFFER_PARAMS_TYPEHASH = keccak256(
        "PostOfferParams(uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,address integrator,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues,bytes offerorAgreementSig,bytes openEndorsementSig,string buyerName,uint8 buyerHostingMode,address adminMultisig)"
    );
    bytes32 constant ACCEPT_OFFER_PARAMS_TYPEHASH = keccak256(
        "AcceptOfferParams(bytes32 offerId,uint256 units,string buyerName,uint8 buyerHostingMode,address adminMultisig,uint256 sellerTokenId,string[] acceptorPartyValues,bytes acceptorAgreementSig,bytes openEndorsementSig)"
    );
    bytes32 constant POST_OFFER_AUTH_TYPEHASH = keccak256(
        "PostOfferAuth(PostOfferParams params,address forAddr,uint256 nonce)"
        "PostOfferParams(uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,address integrator,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues,bytes offerorAgreementSig,bytes openEndorsementSig,string buyerName,uint8 buyerHostingMode,address adminMultisig)"
    );
    bytes32 constant ACCEPT_OFFER_AUTH_TYPEHASH = keccak256(
        "AcceptOfferAuth(AcceptOfferParams params,address forAddr,uint256 nonce)"
        "AcceptOfferParams(bytes32 offerId,uint256 units,string buyerName,uint8 buyerHostingMode,address adminMultisig,uint256 sellerTokenId,string[] acceptorPartyValues,bytes acceptorAgreementSig,bytes openEndorsementSig)"
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
        // re-checked at finalize; closing conditions gate finalize. Resolved/snapshotted onto each Offer at postOffer so an offer
        // is governed by the rules in effect when it was posted. Offerors never supply condition addresses.
        address[] spvThresholdConditions;                        // Layer 2 — fund-specific (§6); added at SPV onboarding; applies to every offer
        mapping(ExemptionPathway => address[]) pathwayThresholdConditions; // Layer 1 — exemption-specific (§5); selected by offer.exemptionPathway
        address[] closingConditions;                             // default closing set
        // Consumed relayer-authorization nonces: usedAuthNonce[forAddr][nonce], order-independent single-use.
        mapping(address => mapping(uint256 => bool)) usedAuthNonce;
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

        // Validate min threshold against the whole offer
        _checkMinTradeThreshold(params.units, params.consideration);

        // Generate offer ID deterministically — DealManager-internal key, not a registry record
        offerId = keccak256(abi.encode(offeror, params.templateId, params.salt));
        if (ds.offers[offerId].offeror != address(0)) revert ISecondaryTradeStorage.OfferAlreadyExists();

        // Resolve conditions from this DealManager's config (never from the caller): threshold = fund-specific
        // (§6) ++ exemption-specific (§5), closing = the default set. Both are snapshotted onto the offer so it is governed by the rules in
        // effect at posting; the kill switch still bites later since GlobalKill reads live state internally.
        address[] memory resolvedThreshold = _resolveThresholdConditions(ds, params.exemptionPathway);
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
            thresholdConditions: resolvedThreshold,
            // Persisted so they can be evaluated at finalize (spec §conditions: closing conditions
            // gate asset transfer).
            closingConditions: resolvedClosing
        });

        // Evaluate threshold conditions (offer is now readable via getOffer). At posting there are no
        // settlements yet (agreementId == 0), so buyer-facing conditions short-circuit; seller/offer-wide
        // conditions enforce.
        _checkThresholdConditions(offerId, bytes32(0));

        if (params.side == OfferSide.SELL) {
            // Reserve units on the seller's cert (routed through IssuanceManager, the only caller the printer allows)
            DealManagerStorage.getIssuanceManager().increaseUnitsReserved(params.certPrinter, params.tokenId, params.units);
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
                DealManagerStorage.getIssuanceManager().decreaseUnitsReserved(offer.certPrinter, offer.tokenId, freeUnits);
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
            offer.validUntil
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
        } else {
            certPrinter = offer.certPrinter;
            tokenId = params.sellerTokenId;
            buyer = offer.offeror;
            endorsementSig = params.openEndorsementSig;
            // Reserve units on the seller's cert at acceptance (buy-offer flow, routed through IssuanceManager)
            DealManagerStorage.getIssuanceManager().increaseUnitsReserved(certPrinter, tokenId, params.units);
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
        secondaryTradeStorage().escrows[settlementAgreementId] = SecondaryEscrow({
            counterparty: acceptor,
            paymentToken: offer.paymentToken,
            paymentAmount: partialConsideration,
            units: params.units,
            expiry: offer.validUntil,
            status: SecondaryEscrowStatus.ACCEPTED,
            feeDestination: offer.integrator,
            offerId: params.offerId,
            tokenId: tokenId,
            buyerName: buyerName,
            buyerHostingMode: buyerHostingMode,
            adminMultisig: adminMultisig,
            openEndorsementSig: endorsementSig
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
            tokenId, offer.validUntil,
            buyerName, buyerHostingMode, adminMultisig, endorsementSig
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
        DealManagerStorage.getIssuanceManager().decreaseUnitsReserved(offer.certPrinter, secEscrow.tokenId, secEscrow.units);

        // Execute ownership change: void/decrement seller cert + mint buyer cert.
        DealManagerStorage.getIssuanceManager().secondaryTransfer(
            _encodeDealMetadata(
                offer.certPrinter, secEscrow.tokenId, secEscrow.units, buyer,
                secEscrow.buyerName, secEscrow.buyerHostingMode, secEscrow.adminMultisig,
                offer.exemptionPathway, agreementId, secEscrow.openEndorsementSig
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
    function _checkThresholdConditions(bytes32 offerId, bytes32 agreementId) internal view {
        address[] storage conditions = secondaryTradeStorage().offers[offerId].thresholdConditions;
        for (uint256 i = 0; i < conditions.length; i++) {
            // note: always double check if `Offer` is properly updated because `checkCondition()` depends on it
            if (!ISecondaryTradingCondition(conditions[i]).checkCondition(IDealManager(address(this)), msg.sig, offerId, agreementId))
                revert ISecondaryTradeStorage.SecondaryConditionsNotMet(conditions[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Relayer-authorization internals (EIP-712 + unordered nonce)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev EIP-712 domain separator, bound to this DealManager. Under delegatecall `address(this)` is the
    /// DealManager proxy, so it is the correct verifyingContract; computed per-call (not cached) since the
    /// linked library holds no immutables.
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("DealManager")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

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
    function _verifyForAuth(bytes32 structHash, address forAddr, uint256 nonce, bytes memory sig) internal {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        if (digest.recover(sig) != forAddr) revert ISecondaryTradeStorage.InvalidSecondaryAuthSignature();
        _useUnorderedNonce(forAddr, nonce);
    }

    /// @dev Builds an offer's threshold set from this DealManager's config per v3.53 §7.2: the fund-specific
    /// (§6, per-SPV) layer ++ the exemption-specific (§5) layer registered for the offer's exemption pathway.
    /// Insertion order is preserved so failures surface deterministically. Offerors choose the pathway, never
    /// the condition addresses.
    function _resolveThresholdConditions(SecondaryTradeData storage ds, ExemptionPathway pathway)
        internal view returns (address[] memory resolved)
    {
        address[] storage spv = ds.spvThresholdConditions;
        address[] storage pathwayConds = ds.pathwayThresholdConditions[pathway];

        resolved = new address[](spv.length + pathwayConds.length);
        uint256 k;
        for (uint256 i = 0; i < spv.length; i++) resolved[k++] = spv[i];
        for (uint256 i = 0; i < pathwayConds.length; i++) resolved[k++] = pathwayConds[i];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Condition config management (linked logic; called via delegatecall by DealManager owner setters)
    // ─────────────────────────────────────────────────────────────────────────

    function addSpvThresholdCondition(address condition) external {
        _addCondition(secondaryTradeStorage().spvThresholdConditions, condition);
    }

    function removeSpvThresholdConditionAt(uint256 index) external {
        _removeConditionAt(secondaryTradeStorage().spvThresholdConditions, index);
    }

    function addPathwayThresholdCondition(ExemptionPathway pathway, address condition) external {
        _addCondition(secondaryTradeStorage().pathwayThresholdConditions[pathway], condition);
    }

    function removePathwayThresholdConditionAt(ExemptionPathway pathway, uint256 index) external {
        _removeConditionAt(secondaryTradeStorage().pathwayThresholdConditions[pathway], index);
    }

    function addClosingCondition(address condition) external {
        _addCondition(secondaryTradeStorage().closingConditions, condition);
    }

    function removeClosingConditionAt(uint256 index) external {
        _removeConditionAt(secondaryTradeStorage().closingConditions, index);
    }

    /// @dev Appends to an owner-managed condition list, rejecting the zero address and duplicates so the
    /// list behaves as a set. Lists are small (admin-curated), so the linear dedupe scan is cheap.
    function _addCondition(address[] storage list, address condition) internal {
        if (condition == address(0)) revert ISecondaryTradeStorage.InvalidSecondaryCondition();
        // Only strongly-typed secondary-trading conditions may be wired in: reject anything that doesn't
        // advertise ISecondaryTradingCondition via ERC-165 at config time, so a mismatched checkCondition
        // signature can never reach post/accept/finalize. ERC165Checker returns false (no revert) for
        // non-ERC165 targets.
        if (!ERC165Checker.supportsInterface(condition, type(ISecondaryTradingCondition).interfaceId))
            revert ISecondaryTradeStorage.SecondaryConditionInterfaceUnsupported(condition);
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == condition) revert ISecondaryTradeStorage.SecondaryConditionAlreadyExists();
        }
        list.push(condition);
    }

    /// @dev Swap-pop removal — order within the list is not significant for membership, only for the
    /// deterministic evaluation order of an already-posted offer (which snapshots its own copy anyway).
    function _removeConditionAt(address[] storage list, uint256 index) internal {
        uint256 len = list.length;
        if (index >= len) revert ISecondaryTradeStorage.SecondaryConditionIndexOutOfBounds();
        list[index] = list[len - 1];
        list.pop();
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
            DealManagerStorage.getIssuanceManager().decreaseUnitsReserved(offer.certPrinter, secEscrow.tokenId, secEscrow.units);
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
