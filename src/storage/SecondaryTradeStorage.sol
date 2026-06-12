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

enum OfferSide { SELL, BUY }

enum OfferStatus { LIVE, CANCELLED, EXPIRED, PARTIALLY_ACCEPTED, FULLY_ACCEPTED }

enum ExemptionPathway { RULE_144, SECTION_4A7, SECTION_4A1HALF, RULE_144A, REGULATION_S }

enum SecondaryEscrowStatus { PAID, FINALIZED, VOIDED }

struct Offer {
    address spvAddress;             // cyberCORP address this offer belongs to
    address offeror;
    OfferSide side;
    address certPrinter;            // both sides: required; identifies the security class/series
    uint256 tokenId;                // sell offer-only: seller's Ledger Entry Token id; zero for bids
    uint256 units;                  // total units offered
    address paymentToken;
    uint256 consideration;          // total payment for all offered units
    ExemptionPathway exemptionPathway;
    uint256 validUntil;
    // TODO add real test cases for it
    bytes counterpartyRestrictions; // spec §8.1 Counterparty restrictions
    bytes additionalTerms;          // spec §8.1 Supplemental fields
    // TODO add real test cases for it
    address integrator;
    OfferStatus status;
    uint256 unitsAccepted;           // units currently committed to active PAID settlements; decrements on void
    uint256 paymentAccepted;         // consideration currently committed to active settlements; decrements on finalize and void
    bytes32 offerId;                 // DealManager-generated offer key; NOT a CyberAgreementRegistry record
    bytes32 templateId;             // agreement template id; stored for use at acceptOffer
    uint256 salt;                   // offeror-supplied salt; used to derive unique settlementSalt per acceptance
    string[] globalValues;          // agreement global values; stored for use at acceptOffer
    string[] offerorPartyValues;    // offeror's party values; stored for use at acceptOffer
    bytes offerorAgreementSig;      // offeror's EIP-712 sig over offerAgreementId+terms; verified at postOffer, passed to signContractWithEscrow at acceptOffer
    // TODO add real test cases for it
    bytes openEndorsementSig;       // sell offer-only: seller's pre-signed open endorsement (spec §7.3.1); zero for bids
    // TODO review: exact ID schema not yet determined
    bytes32 unitReservationId;      // sell offer-only: reservation id from CertPrinter; zero for bids
    string buyerName;               // buy offer-only: buyer's registered name for OwnerDetails; empty for sell offers
    uint8 buyerHostingMode;         // buy offer-only: 0 = Direct, 1 = Administered; zero for sell offers
    address adminMultisig;          // buy offer-only: delivery address for Administered hosting; zero for sell offers
    bytes32[] settlementAgreementIds; // appended at each acceptOffer; length == 0 at postOffer (no buyer known yet)
}

// Self-contained settlement escrow for secondary trades, keyed by settlementAgreementId.
// Owns custody (payment in/out) and lifecycle (status, expiry) directly — no LexScrowStorage.Escrow companion.
struct SecondaryEscrow {
    // custody + lifecycle
    address buyer;                  // acceptor / counterparty
    address paymentToken;           // ERC20 payment token
    uint256 paymentAmount;          // consideration for this settlement lot
    uint256 units;                  // units in this settlement lot
    uint256 expiry;                 // settlement deadline
    SecondaryEscrowStatus status;   // PAID | FINALIZED | VOIDED
    // secondary-specific routing
    address sellerAddress;          // payment destination at finalizeDeal
    address feeDestination;         // integrator address for fee split; zero = all fees to MetaLeX
    bytes32 offerId;                // back-link to Offer
    bytes32 unitReservationId;      // sell offer-only: reservation id to release on void; zero for bids
    bytes dealMetadata;             // abi-encoded ownership-change params for IssuanceManager.secondaryTransfer
}

struct PostOfferParams {
    OfferSide side;
    address certPrinter;            // sell offers: seller's cert printer; bids: required security class/series filter
    uint256 tokenId;                // sell offer-only: seller's Ledger Entry Token id; zero for bids
    uint256 units;
    address paymentToken;
    uint256 consideration;
    ExemptionPathway exemptionPathway;
    uint256 validUntil;
    bytes counterpartyRestrictions;
    bytes additionalTerms;
    address integrator;             // zero = use DealManager defaultIntegrator
    bytes32 templateId;
    uint256 salt;
    string[] globalValues;
    string[] offerorPartyValues;
    bytes offerorAgreementSig;
    bytes openEndorsementSig;       // sell offer-only
    address[] thresholdConditions;
    string buyerName;               // buy offer-only: buyer's registered name for OwnerDetails; empty for sell offers
    uint8 buyerHostingMode;         // buy offer-only: 0 = Direct, 1 = Administered; zero for sell offers
    // TODO should it be validated? What if the user provided the wrong address?
    address adminMultisig;          // buy offer-only: delivery address for Administered hosting; zero for sell offers
}

struct AcceptOfferParams {
    bytes32 offerId;
    uint256 units;
    address buyer;                  // registered owner; for buy offers typically offer.offeror
    string buyerName;               // sell offer-only: ignored for buy offer acceptances (read from Offer instead)
    uint8 buyerHostingMode;         // sell offer-only: 0 = Direct, 1 = Administered; ignored for buy offer acceptances
    // TODO should it be validated? What if the user provided the wrong address?
    address adminMultisig;          // sell offer-only: delivery address for Administered hosting; ignored for buy offer acceptances
    uint256 sellerTokenId;          // buy offer-only: seller's token id for bid acceptances; use offer.tokenId for sell offers
    string[] acceptorPartyValues;
    bytes acceptorAgreementSig;
    bytes openEndorsementSig;       // buy offer-only: for bid acceptances
}

library SecondaryTradeStorage {
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.secondary.trade.storage.v1");

    struct SecondaryTradeData {
        mapping(bytes32 => Offer) offers;              // keyed by offerAgreementId
        mapping(bytes32 => SecondaryEscrow) escrows;   // keyed by settlementAgreementId
        uint256 minTradeUnits;
        uint256 minTradeConsideration;                 // 0 = disabled
        address defaultIntegrator;
    }

    function secondaryTradeStorage() internal pure returns (SecondaryTradeData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function hasSecondaryEscrow(bytes32 agreementId) internal view returns (bool) {
        return secondaryTradeStorage().escrows[agreementId].sellerAddress != address(0);
    }

    function getOffer(bytes32 offerId) internal view returns (Offer storage) {
        return secondaryTradeStorage().offers[offerId];
    }

    function setOffer(bytes32 offerId, Offer memory offer) internal {
        secondaryTradeStorage().offers[offerId] = offer;
    }

    function getSecondaryEscrow(bytes32 agreementId) internal view returns (SecondaryEscrow storage) {
        return secondaryTradeStorage().escrows[agreementId];
    }

    function setSecondaryEscrow(bytes32 agreementId, SecondaryEscrow memory escrow) internal {
        secondaryTradeStorage().escrows[agreementId] = escrow;
    }

    function getMinTradeUnits() internal view returns (uint256) {
        return secondaryTradeStorage().minTradeUnits;
    }

    function getMinTradeConsideration() internal view returns (uint256) {
        return secondaryTradeStorage().minTradeConsideration;
    }

    function setMinTradeThreshold(uint256 units, uint256 consideration) internal {
        SecondaryTradeData storage ds = secondaryTradeStorage();
        ds.minTradeUnits = units;
        ds.minTradeConsideration = consideration;
    }

    function getDefaultIntegrator() internal view returns (address) {
        return secondaryTradeStorage().defaultIntegrator;
    }

    function setDefaultIntegrator(address integrator) internal {
        secondaryTradeStorage().defaultIntegrator = integrator;
    }
}
