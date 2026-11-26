// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {LedgerEntryTokenStorage} from "./LedgerEntryTokenStorage.sol";
import {ILedgerEntryToken} from "../interfaces/ILedgerEntryToken.sol";
import {ILexChexBadge} from "../interfaces/ILexChexBadge.sol";
import {IIssuanceManager} from "../interfaces/IIssuanceManager.sol";
import {BorgAuth} from "../libs/auth.sol";
import {AccreditationPolicy} from "../libs/policies/AccreditationPolicy.sol";

/// @title  LedgerEntryTokenHolderLimits - section 12(g) counts of a LET contract (printer)
/// @author MetaLeX Labs, Inc.
/// @notice Holders who are not accredited, and holders of plan securities only (Rule 12g5-1(a)(8)), counted
/// beside the look-through tally of LedgerEntryTokenStorage. Linked library: it runs by delegatecall in the
/// printer's storage, reached two ways:
///  - from LedgerEntryTokenStorage, which calls `syncLot` / `syncHolder` where the tally changes;
///  - from anyone, through the printer's one forwarding function `holderLimits(bytes)`.
/// @dev Because the forwarder exposes every external function here to any caller, each one is exactly one
/// of: a view; a setter that checks the caller itself (the issuance manager or an admin of its AUTH, the
/// rule of `requireManagerOrAdmin`); or a sync that recomputes from the printer's own records and can only
/// move the totals to their correct value. No external function takes a storage pointer, a weight, a flag
/// or an owner from the caller.
///
/// The rule every function serves: each total equals the sum of the matching weight in `holderLimitAcct`.
/// A holder's record stores what it adds to each total, so a sync removes exactly that and adds the new
/// contribution. A record from before this library is all zero: it adds nothing, so the holder counts as
/// not accredited and not plan-only, which is the safe direction, until a sync.
library LedgerEntryTokenHolderLimits {
    // ── Any-caller syncs ────────────────────────────────────────────────────────────────────────────

    /// @notice Recompute one holder's booking and contributions from the printer's records and the badge.
    /// No live lot: no booking and no contribution. Company mark: not accredited. Else a valid credential with
    /// `K_ACCREDITED` books the holder and stores its id; else a booked holder whose stored credential was
    /// voided is unbooked; else the booking stays as it is (a lapse does not remove it).
    function syncHolder(address owner) external {
        _syncHolder(LedgerEntryTokenStorage.cyberCertStorage(), owner);
    }

    /// @notice Reconcile one lot's plan label and plan count, then sync the holders it affects. The label is
    /// in force only while the legal owner it was set for is the legal owner; a different legal owner deletes
    /// it, so a sale and a later buy-back do not revive it. A lot counts as a plan lot of its legal owner iff
    /// the label is in force and the lot is live in the tally. Changes nothing when nothing changed.
    function syncLot(uint256 tokenId) external {
        _syncLot(LedgerEntryTokenStorage.cyberCertStorage(), tokenId);
    }

    // ── Admin setters (issuance manager, or an admin of its AUTH) ─────────────────────────────────────

    /// @notice Set or clear the plan-security label of a lot for its current legal owner.
    function setPlanSecurity(uint256 tokenId, bool value) external {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        _requireManagerOrAdmin(s);
        address owner = s.owners[tokenId].ownerAddress;
        if (owner == address(0)) revert ILedgerEntryToken.TokenDoesNotExist();
        LedgerEntryTokenStorage.PlanLot storage lot = s.planLot[tokenId];
        bool inForce = lot.labelOwner == owner;
        lot.labelOwner = value ? owner : address(0);
        if (inForce != value) emit ILedgerEntryToken.PlanSecuritySet(tokenId, value);
        _syncLot(s, tokenId);
    }

    /// @notice Mark `account` as not accredited for this printer, or remove the mark. The holder is synced at
    /// once: the mark removes a booking; removing it books the holder again if the badge has a valid credential.
    function setNotAccreditedMark(address account, bool marked) external {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        _requireManagerOrAdmin(s);
        s.notAccreditedMark[account] = marked;
        emit ILedgerEntryToken.NotAccreditedMarkSet(account, marked);
        _syncHolder(s, account);
    }

    // ── Views ───────────────────────────────────────────────────────────────────────────────────────

    /// @notice `lookThroughHolderCount` less the holders booked accredited.
    function nonAccreditedLookThroughHolderCount() external view returns (uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return _sub(s.lookThroughHolderCount, s.accreditedLookThroughHolderCount);
    }

    /// @notice `lookThroughHolderCount` less the plan-only holders.
    function lookThroughHolderCountExcludingPlan() external view returns (uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return _sub(s.lookThroughHolderCount, s.planOnlyLookThroughHolderCount);
    }

    /// @notice Holders who are not accredited, less the plan-only holders who are not accredited.
    function nonAccreditedLookThroughHolderCountExcludingPlan() external view returns (uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return _sub(
            _sub(s.lookThroughHolderCount, s.accreditedLookThroughHolderCount),
            _sub(s.planOnlyLookThroughHolderCount, s.planOnlyAccreditedLookThroughHolderCount)
        );
    }

    /// @notice The three totals as stored.
    function holderLimitTotals() external view returns (uint256 accredited, uint256 planOnly, uint256 planOnlyAccredited) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return (
            s.accreditedLookThroughHolderCount,
            s.planOnlyLookThroughHolderCount,
            s.planOnlyAccreditedLookThroughHolderCount
        );
    }

    /// @notice Whether `account` is accredited for this printer now: a valid badge credential with
    /// `K_ACCREDITED` and no company mark. HolderCapCondition reads the buyer here.
    function isAccredited(address account) external view returns (bool) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (s.notAccreditedMark[account]) return false;
        return AccreditationPolicy.isAccredited(ILexChexBadge(s.lookThroughBadge), account);
    }

    /// @notice True when `owner` has a live lot and the plan label is in force on every live lot of `owner`.
    function isPlanOnlyHolder(address owner) external view returns (bool) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return _isPlanOnly(s.holderAcct[owner].liveLots, s.holderLimitAcct[owner].planLots);
    }

    /// @notice The look-through weight that a plan-only holder is left out of the counts with; 0 for an
    /// address that is not a plan-only holder. A holder keeps this weight when its registry gives no
    /// beneficial-owner count (a void or a lapse), so a holder that stops being plan-only enters the counts
    /// with it. A plan-only holder always has a weight of 1 or more.
    function planOnlyHolderWeight(address owner) external view returns (uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        LedgerEntryTokenStorage.HolderAcct storage a = s.holderAcct[owner];
        return _isPlanOnly(a.liveLots, s.holderLimitAcct[owner].planLots) ? a.weight : 0;
    }

    /// @notice The plan-security label of a lot: set, and set for the current legal owner.
    function isPlanSecurity(uint256 tokenId) external view returns (bool) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        address labelOwner = s.planLot[tokenId].labelOwner;
        return labelOwner != address(0) && labelOwner == s.owners[tokenId].ownerAddress;
    }

    /// @notice Whether the company marked `account` as not accredited for this printer.
    function notAccreditedMark(address account) external view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().notAccreditedMark[account];
    }

    /// @notice A holder's record: the booking, the counted plan lots, the credential the booking relies on.
    function holderLimitAccount(address owner)
        external
        view
        returns (bool accredited, uint32 planLots, uint256 credentialId)
    {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        LedgerEntryTokenStorage.HolderLimitAcct storage r = s.holderLimitAcct[owner];
        return (r.accredited, r.planLots, s.accreditedCredentialId[owner]);
    }

    // ── Internals ───────────────────────────────────────────────────────────────────────────────────

    function _syncLot(LedgerEntryTokenStorage.CyberCertStorage storage s, uint256 tokenId) private {
        address owner = s.owners[tokenId].ownerAddress;
        LedgerEntryTokenStorage.PlanLot storage lot = s.planLot[tokenId];
        address labelOwner = lot.labelOwner;
        if (labelOwner != address(0) && labelOwner != owner) {
            // Legal title moved: the exclusion was for the person who received the lot
            lot.labelOwner = address(0);
            labelOwner = address(0);
            emit ILedgerEntryToken.PlanSecuritySet(tokenId, false);
        }
        address target = (labelOwner != address(0) && s.liveCounted[tokenId]) ? owner : address(0);
        address previous = lot.countedUnder;
        if (previous != target) {
            if (previous != address(0)) {
                LedgerEntryTokenStorage.HolderLimitAcct storage p = s.holderLimitAcct[previous];
                if (p.planLots > 0) p.planLots -= 1;
            }
            if (target != address(0)) s.holderLimitAcct[target].planLots += 1;
            lot.countedUnder = target;
            if (previous != address(0) && previous != owner) _syncHolder(s, previous);
        }
        if (owner != address(0)) _syncHolder(s, owner);
    }

    function _syncHolder(LedgerEntryTokenStorage.CyberCertStorage storage s, address owner) private {
        LedgerEntryTokenStorage.HolderLimitAcct storage r = s.holderLimitAcct[owner];
        // Remove what this holder adds now
        s.accreditedLookThroughHolderCount -= r.accreditedWeight;
        s.planOnlyLookThroughHolderCount -= r.planOnlyWeight;
        s.planOnlyAccreditedLookThroughHolderCount -= r.planOnlyAccreditedWeight;

        LedgerEntryTokenStorage.HolderAcct storage a = s.holderAcct[owner];
        uint32 liveLots = a.liveLots;
        bool booked;
        uint32 weight;
        if (liveLots > 0) {
            booked = _decideBooking(s, owner, r.accredited);
            weight = a.weight;
        } else {
            delete s.accreditedCredentialId[owner]; // the booking ends with the holder; the mark stays
        }
        bool planOnly = _isPlanOnly(liveLots, r.planLots);
        uint32 accreditedWeight = booked ? weight : 0;
        uint32 planOnlyWeight = planOnly ? weight : 0;
        uint32 planOnlyAccreditedWeight = (booked && planOnly) ? weight : 0;

        r.accredited = booked;
        r.accreditedWeight = accreditedWeight;
        r.planOnlyWeight = planOnlyWeight;
        r.planOnlyAccreditedWeight = planOnlyAccreditedWeight;
        s.accreditedLookThroughHolderCount += accreditedWeight;
        s.planOnlyLookThroughHolderCount += planOnlyWeight;
        s.planOnlyAccreditedLookThroughHolderCount += planOnlyAccreditedWeight;
    }

    /// @dev The booking of a live holder. Sticky like the look-through weight: only a void of the credential
    /// it relies on (with no other valid one), or the company mark, removes it.
    function _decideBooking(LedgerEntryTokenStorage.CyberCertStorage storage s, address owner, bool booked)
        private
        returns (bool)
    {
        if (s.notAccreditedMark[owner]) {
            delete s.accreditedCredentialId[owner];
            return false;
        }
        ILexChexBadge badge = ILexChexBadge(s.lookThroughBadge);
        (bool found, uint256 credentialId) = AccreditationPolicy.accreditedCredential(badge, owner);
        if (found) {
            s.accreditedCredentialId[owner] = credentialId;
            return true;
        }
        if (!booked) return false;
        // Booked and no valid credential now: a lapse keeps it, a void ends it. With no registry, or one that
        // cannot answer, the void cannot be read, so the booking ends (the safe direction).
        if (AccreditationPolicy.isVoided(badge, s.accreditedCredentialId[owner])) {
            delete s.accreditedCredentialId[owner];
            return false;
        }
        return true;
    }

    function _isPlanOnly(uint32 liveLots, uint32 planLots) private pure returns (bool) {
        return liveLots > 0 && planLots == liveLots;
    }

    /// @dev A count read never reverts: each subtrahend is a subset of the minuend while the totals are kept,
    /// and a defect would read high (the safe direction) rather than stop the holder cap condition.
    function _sub(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function _requireManagerOrAdmin(LedgerEntryTokenStorage.CyberCertStorage storage s) private view {
        address manager = s.issuanceManager;
        if (msg.sender == manager) return;
        BorgAuth auth = BorgAuth(IIssuanceManager(manager).AUTH());
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
    }
}
