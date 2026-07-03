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

enum OfferStatus { LIVE, CANCELLED, PARTIALLY_ACCEPTED, FULLY_ACCEPTED, FINALIZED }

enum SecondaryEscrowStatus { ACCEPTED, FINALIZED, VOIDED }

enum ExemptionPathway { RULE_144, SECTION_4A7, SECTION_4A1HALF, RULE_144A, REGULATION_S }

enum HostingMode { DIRECT, ADMINISTERED }

struct Offer {
    address spvAddress;             // cyberCORP address this offer belongs to
    address offeror;
    OfferSide side;
    address certPrinter;            // both sides: required; identifies the security class/series
    uint256 tokenId;                // sell offer-only: seller's Ledger Entry Token id; zero for buy offers
    uint256 units;                  // total units offered: immutable once offer is created
    address paymentToken;
    uint256 consideration;          // total payment for all offered units
    ExemptionPathway exemptionPathway;
    uint256 validUntil;
    bytes counterpartyRestrictions; // spec §8.1 Counterparty restrictions
    bytes additionalTerms;          // spec §8.1 Supplemental fields
    address integrator;
    OfferStatus status;
    uint256 unitsAccepted;          // units committed to active and finalized settlements; decrements on void only
    uint256 paymentAccepted;        // consideration committed to active and finalized settlements; decrements on void only
    uint256 unitsFinalized;         // units consumed by finalized settlements; monotonic (finalized lots never void), but may lag behind `unitsAccepted`
    bytes32 offerId;                // DealManager-generated offer key; NOT a CyberAgreementRegistry record
    bytes32 templateId;             // agreement template id; stored for use at acceptOffer
    uint256 salt;                   // offeror-supplied salt; used to derive unique settlementSalt per acceptance
    string[] globalValues;          // agreement global values; stored for use at acceptOffer
    string[] offerorPartyValues;    // offeror's party values; stored for use at acceptOffer
    bytes offerorAgreementSig;      // offeror's EIP-712 sig over offerAgreementId+terms; verified at postOffer, passed to signContractWithEscrow at acceptOffer
    bytes openEndorsementSig;       // sell offer-only: seller's pre-signed open endorsement (spec §7.3.1); in contrast, buy offer's open endorsement is acquired at acceptance and stored in SecondaryEscrow
    string buyerName;               // buy offer-only: buyer's registered name for OwnerDetails; empty for sell offers
    HostingMode buyerHostingMode;   // buy offer-only: Direct or Administered; defaults to Direct for sell offers
    address adminMultisig;          // buy offer-only: delivery address for Administered hosting; zero for sell offers
    bytes32[] settlementAgreementIds; // appended at each acceptOffer; length == 0 at postOffer (no buyer known yet)
    address[] thresholdConditions;    // resolved from DealManager config at postOffer; re-evaluated at acceptOffer and at finalize
    address[] closingConditions;      // snapshotted from DealManager config at postOffer; evaluated at finalize (gates asset transfer)
}

// Per-settlement escrow for secondary trades, keyed by settlementAgreementId.
struct SecondaryEscrow {
    // custody + lifecycle
    address counterparty;           // acceptor (msg.sender of acceptOffer); buyer/seller derived from offer.side
    address paymentToken;           // ERC20 payment token
    uint256 paymentAmount;          // consideration for this settlement lot
    uint256 units;                  // units in this settlement lot
    uint256 expiry;                 // settlement deadline
    SecondaryEscrowStatus status;   // ACCEPTED | FINALIZED | VOIDED
    // secondary-specific routing
    address feeDestination;         // integrator address for fee split; zero = all fees to MetaLeX
    bytes32 offerId;                // back-link to Offer
    uint256 tokenId;                // seller's Ledger Entry Token id; reservation target for decreaseUnitsReserved on void
    string buyerName;               // redundant for buy offer, it would be the same as its counterpart in `Offer`, but we still keep a record here for simplicity
    HostingMode buyerHostingMode;   // redundant for buy offer, it would be the same as its counterpart in `Offer`, but we still keep a record here for simplicity
    address adminMultisig;          // redundant for buy offer, it would be the same as its counterpart in `Offer`, but we still keep a record here for simplicity
    bytes openEndorsementSig;       // redundant for sell offer, it would be the same as its counterpart in `Offer`, but we still keep a record here for simplicity
}

struct PostOfferParams {
    OfferSide side;
    address certPrinter;            // sell offers: seller's cert printer; buy offers: required security class/series filter
    uint256 tokenId;                // sell offer-only: seller's Ledger Entry Token id; zero for buy offers
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
    string buyerName;               // buy offer-only: buyer's registered name for OwnerDetails; empty for sell offers
    HostingMode buyerHostingMode;   // buy offer-only: Direct or Administered; defaults to Direct for sell offers
    address adminMultisig;          // buy offer-only: delivery address for Administered hosting; zero for sell offers
}

struct AcceptOfferParams {
    bytes32 offerId;
    uint256 units;
    string buyerName;               // sell offer-only: ignored for buy offer acceptances (read from Offer instead)
    HostingMode buyerHostingMode;   // sell offer-only: Direct or Administered; ignored for buy offer acceptances
    address adminMultisig;          // sell offer-only: delivery address for Administered hosting; ignored for buy offer acceptances
    uint256 sellerTokenId;          // buy offer-only: seller's token id for buy-offer acceptances; use offer.tokenId for sell offers
    string[] acceptorPartyValues;
    bytes acceptorAgreementSig;
    bytes openEndorsementSig;       // buy offer-only: for buy-offer acceptances
}

/// @title ISecondaryTradeStorage
/// @notice Events/errors owned by the SecondaryTradeStorage library — the single source of truth.
/// @dev SecondaryTradeStorage emits/reverts these via the qualified ISecondaryTradeStorage.X form, and
/// any manager that links the library (e.g. DealManager) inherits this interface so the selectors/topics
/// appear in its ABI for off-chain decoding.
interface ISecondaryTradeStorage {
    // Events below carry every field an off-chain indexer needs to reconstruct secondary-trade status
    // (open offers + settlements) from logs alone: an Offer is fully described by OfferPosted, each settlement
    // by OfferAccepted (which also reports its funding), and lifecycle transitions by the remaining events.
    /// @dev offerId/offeror/certPrinter indexed so a UI can filter offers by security and by user.
    event OfferPosted(
        bytes32 indexed offerId,
        address indexed offeror,
        address indexed certPrinter,
        address spvAddress,
        OfferSide side,
        uint256 tokenId,
        uint256 units,
        address paymentToken,
        uint256 consideration,
        ExemptionPathway exemptionPathway,
        uint256 validUntil,
        address integrator,
        bytes32 templateId,
        string buyerName,
        HostingMode buyerHostingMode,
        address adminMultisig,
        bytes counterpartyRestrictions,
        address[] thresholdConditions,
        address[] closingConditions
    );
    event OfferCancelled(bytes32 indexed offerId, address indexed offeror);
    event OfferAccepted(
        bytes32 indexed offerId,
        bytes32 indexed settlementAgreementId,
        address indexed acceptor,
        uint256 units,
        address paymentToken,
        uint256 paymentAmount,
        uint256 tokenId,
        uint256 agreementExpiry,
        // per-settlement materialization fields, mirroring SecondaryEscrow (sourced from the offer or the
        // acceptance per side); feeDestination is omitted as it equals the offer's integrator (see OfferPosted).
        string buyerName,
        HostingMode buyerHostingMode,
        address adminMultisig,
        bytes openEndorsementSig
    );
    event SecondaryTradeAgreementFinalized(bytes32 indexed agreementId, address seller, address buyer, uint256 units, uint256 consideration);
    event SecondaryTradeAgreementVoided(bytes32 indexed agreementId);
    /// @dev Reports the realized fee split: feeDestination is the credited integrator (zero when the fee
    /// routed entirely to the platform). The split is read from live factory state at settlement, so it is
    /// captured here rather than left for the indexer to recompute.
    /// @param fee Total fee taken from the trade consideration (paymentAmount * defaultFeeRatio).
    /// Always equals integratorFee + platformFee; the two split fields are its breakdown, not additions to it.
    /// @param integratorFee Portion of `fee` credited to feeDestination, fee * integratorFeeShare(feeDestination)
    /// (0 if no whitelisted integrator).
    /// @param platformFee Remainder of `fee` routed to the platform (fee - integratorFee).
    event SecondaryFeeDistributed(
        bytes32 indexed agreementId,
        address indexed feeToken,
        address indexed feeDestination,
        uint256 fee,
        uint256 integratorFee,
        uint256 platformFee
    );

    error OfferNotAvailable();
    error OfferExpired();
    /// @notice A trade's units or consideration is below the admin-set minimum-ticket threshold;
    /// enforced on the whole offer at postOffer and on each lot at acceptOffer
    error BelowMinTradeThreshold();
    error IntegratorNotWhitelisted();
    error UnitsExceedOffer();
    error NotOfferor();
    error NotCertOwner();
    error MissingCertPrinter();
    error UnknownCertPrinter();
    error NotPartyToAgreement();
    error OfferAlreadyExists();
    /// @notice Caller is not the signer they claim to be (signer must equal msg.sender)
    error NotSigner();
    /// @notice A relayer overload's EIP-712 authorization did not recover to `forAddr`
    error InvalidSecondaryAuthSignature();
    /// @notice A relayer overload's unordered authorization nonce was already consumed (replay)
    error SecondaryAuthReplayed();
    error SecondaryEscrowNotFound();
    error SecondaryTradeAgreementAlreadyFinalized();
    error SecondaryTradeAgreementAlreadyVoided();
    error SecondaryTradeAgreementExpired();
    error SecondaryTradeAgreementNotExpired();
    error SecondaryTradeAgreementNotVoided();
    /// @notice At finalize, the cert's current legal owner no longer matches the settlement's seller of record
    /// (ownership moved after listing/acceptance), so the payee and the party whose units are consumed diverge
    error SecondaryTradeSellerOwnershipChanged();
    error SecondaryConditionsNotMet(address condition);
    /// @notice Condition address supplied to a config setter is the zero address
    error InvalidSecondaryCondition();
    /// @notice Condition does not advertise ISecondaryTradingCondition via ERC-165 supportsInterface
    error SecondaryConditionInterfaceUnsupported(address condition);
    /// @notice Condition is already present in the target list (sets are deduplicated)
    error SecondaryConditionAlreadyExists();
    /// @notice removeConditionAt index is past the end of the target list
    error SecondaryConditionIndexOutOfBounds();
}
