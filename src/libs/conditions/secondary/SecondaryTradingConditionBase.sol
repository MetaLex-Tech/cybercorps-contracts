// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../BaseSecondaryTradingCondition.sol";
import "../../auth.sol";
import {Offer, SecondaryEscrow, OfferSide} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @notice Minimal surface for reading the BorgAuth wired into a CyberCorp / DealManager
/// (both inherit BorgAuthACL, whose public AUTH getter this matches).
interface IBorgAuthProvider {
    function AUTH() external view returns (address);
}

/// @title  SecondaryTradingConditionBase - shared helpers for secondary-trading conditions
/// @author MetaLeX Labs, Inc.
/// @notice Extends BaseSecondaryTradingCondition with the two things nearly every threshold condition
/// needs: resolving the settlement's seller/buyer from the offer + escrow (per the conditions spec, the
/// buyer is unknown at postOffer — agreementId == bytes32(0) — so buyer-facing checks short-circuit),
/// and gating per-SPV configuration setters on the SPV's own BorgAuth.
abstract contract SecondaryTradingConditionBase is BaseSecondaryTradingCondition {
    /// @dev Derives the parties of the evaluation context.
    /// At posting (agreementId == 0) only the offeror's side is known: SELL → seller, BUY → buyer.
    /// At acceptance/finalization the escrow's counterparty fills the other side.
    /// `sellerTokenId` is the seller's Ledger Entry Token id when known (0 for a buy offer at posting).
    function _resolveParties(
        IDealManager dealManager,
        Offer memory offer,
        bytes32 agreementId
    ) internal view returns (address seller, address buyer, uint256 sellerTokenId) {
        if (agreementId == bytes32(0)) {
            if (offer.side == OfferSide.SELL) {
                seller = offer.offeror;
                sellerTokenId = offer.tokenId;
            } else {
                buyer = offer.offeror;
            }
        } else {
            SecondaryEscrow memory escrow = dealManager.getSecondaryEscrow(agreementId);
            if (offer.side == OfferSide.SELL) {
                seller = offer.offeror;
                buyer = escrow.counterparty;
            } else {
                seller = escrow.counterparty;
                buyer = offer.offeror;
            }
            sellerTokenId = escrow.tokenId;
        }
    }

    /// @dev Reverts unless msg.sender holds ADMIN_ROLE (or above) on the target's BorgAuth.
    /// Used to gate per-SPV configuration on the SPV's (or its DealManager's) own authority.
    function _requireAuthAdmin(address authProvider) internal view {
        BorgAuth auth = BorgAuth(IBorgAuthProvider(authProvider).AUTH());
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
    }

    /// @dev Reverts unless msg.sender holds OWNER_ROLE on the target's BorgAuth.
    function _requireAuthOwner(address authProvider) internal view {
        BorgAuth auth = BorgAuth(IBorgAuthProvider(authProvider).AUTH());
        auth.onlyRole(auth.OWNER_ROLE(), msg.sender);
    }
}
