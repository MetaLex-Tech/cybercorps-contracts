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

struct Offer {
    address spvAddress;             // cyberCORP address this offer belongs to
    address offeror;
    OfferSide side;
    address certPrinter;            // sell offers: seller's cert printer; bids: zero (known at acceptance)
    uint256 tokenId;                // sell offers: seller's Ledger Entry Token id; bids: zero
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
    uint256 unitsAccepted;
    bytes32 offerAgreementId;       // open-to-matching agreement in CyberAgreementRegistry
    // TODO add real tests cases for it
    bytes openEndorsementSig;       // spec §7.3.1 sell offers: seller's pre-signed open endorsement; bids: zero
    // TODO review: exact ID schema not yet determined
    bytes32 unitReservationId;      // sell offers: reservation id from CertPrinter; bids: zero
    // TODO review: exact ID schema not yet determined
    bytes32 bidCommitmentEscrowId;  // bids: holding escrow id in LexScrowStorage; sell offers: zero
}

// Companion to the LexScrowStorage settlement escrow, keyed by the same settlementAgreementId.
// LexScrowStorage.Escrow holds the base escrow (corpAssets=[], buyerAssets=[payment], status).
// SecondaryEscrow holds the secondary-specific routing and ownership-change data.
struct SecondaryEscrow {
    address sellerAddress;          // payment destination at finalizeDeal
    address feeDestination;         // integrator address for fee split; zero = all fees to MetaLeX
    bytes32 offerId;                // back-link to Offer (offerAgreementId)
    address sellerCertPrinter;      // cert printer for unit reservation release on void
    bytes32 unitReservationId;      // reservation id to release on void
    bytes dealMetadata;             // abi-encoded ownership-change params for IssuanceManager.secondaryTransfer
}

struct PostOfferParams {
    OfferSide side;
    address certPrinter;            // sell offers: seller's cert printer; bids: zero
    uint256 tokenId;                // sell offers: seller's Ledger Entry Token id; bids: zero
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
    bytes openEndorsementSig;       // sell offers only
    // TODO test multiple mock conditions
    address[] thresholdConditions;
}

struct AcceptOfferParams {
    bytes32 offerAgreementId;
    uint256 units;
    address buyer;                  // registered owner; for BIDs typically offer.offeror
    string buyerName;
    bool fullSale;
    uint8 buyerHostingMode;         // 0 = Direct, 1 = Administered
    address adminMultisig;          // delivery address for Administered hosting
    address sellerCertPrinter;      // bid acceptances only; sell offers: use offer.certPrinter
    uint256 sellerTokenId;          // bid acceptances only; sell offers: use offer.tokenId
    string[] acceptorPartyValues;
    bytes acceptorAgreementSig;
    bytes openEndorsementSig;       // bid acceptances only
    address[] closingConditions;
    address[] thresholdConditions;
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

    function getOffer(bytes32 offerAgreementId) internal view returns (Offer storage) {
        return secondaryTradeStorage().offers[offerAgreementId];
    }

    function setOffer(bytes32 offerAgreementId, Offer memory offer) internal {
        secondaryTradeStorage().offers[offerAgreementId] = offer;
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
