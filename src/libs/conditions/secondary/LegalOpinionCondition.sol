// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  LegalOpinionCondition - §4(a)(1½) GP/issuer-counsel assurance gate
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition with per-SPV configuration (§6.3): each SPV chooses between the
/// lower-effort GP sign-off mechanism, the formal opinion-upload mechanism (hash/URI of an opinion
/// submitted via cyberSign), or accepting either (the default). Records are keyed per deal id — either
/// the offerId (pre-approving every settlement of the offer) or a specific settlementAgreementId — and
/// both record types are written under the SPV's own BorgAuth admin (the GP, or counsel delegated
/// ADMIN_ROLE). Silent at posting: the assurance is a per-deal artifact evaluated from acceptance onward.
contract LegalOpinionCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    enum OpinionMechanism {
        EITHER,         // default: GP sign-off or formal opinion satisfies
        GP_SIGNOFF,     // only a recorded GP sign-off satisfies
        FORMAL_OPINION  // only a recorded formal opinion satisfies
    }

    struct OpinionRecord {
        bytes32 opinionHash;    // hash of the opinion document
        string uri;             // cyberSign / offchain record locator
        address submitter;
        uint64 submittedAt;
    }

    error InvalidSpv();
    error InvalidDealManager();
    error InvalidDealId();
    error InvalidOpinionHash();

    event MechanismUpdated(address indexed spv, OpinionMechanism mechanism);
    event GPSignOffRecorded(address indexed dealManager, bytes32 indexed dealId, address indexed approver);
    event GPSignOffRevoked(address indexed dealManager, bytes32 indexed dealId, address indexed approver);
    event OpinionSubmitted(address indexed dealManager, bytes32 indexed dealId, bytes32 opinionHash, string uri, address indexed submitter);

    struct LegalOpinionStorage {
        mapping(address => OpinionMechanism) mechanisms;
        mapping(address => mapping(bytes32 => bool)) gpSignOffs;
        mapping(address => mapping(bytes32 => OpinionRecord)) opinions;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.legal-opinion.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 3 = 47)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Selects an SPV's assurance mechanism; only the SPV's own BorgAuth admin
    function setMechanism(address spv, OpinionMechanism mechanism) external {
        if (spv == address(0)) revert InvalidSpv();
        _requireAuthAdmin(spv);
        _legalOpinionStorage().mechanisms[spv] = mechanism;
        emit MechanismUpdated(spv, mechanism);
    }

    /// @notice Records the GP's compliance sign-off for a deal (offerId to pre-approve all its
    /// settlements, or a specific settlementAgreementId); only the DealManager's BorgAuth admin
    function recordGPSignOff(address dealManager, bytes32 dealId) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        if (dealId == bytes32(0)) revert InvalidDealId();
        _requireAuthAdmin(dealManager);
        _legalOpinionStorage().gpSignOffs[dealManager][dealId] = true;
        emit GPSignOffRecorded(dealManager, dealId, msg.sender);
    }

    /// @notice Withdraws a previously recorded sign-off (threshold conditions re-run at finalize, so a
    /// revocation between acceptance and settlement blocks the asset transfer)
    function revokeGPSignOff(address dealManager, bytes32 dealId) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        _requireAuthAdmin(dealManager);
        _legalOpinionStorage().gpSignOffs[dealManager][dealId] = false;
        emit GPSignOffRevoked(dealManager, dealId, msg.sender);
    }

    /// @notice Anchors a formal legal opinion (hash/URI of the cyberSign record) for a deal;
    /// only the DealManager's BorgAuth admin (GP or delegated counsel)
    function submitOpinion(address dealManager, bytes32 dealId, bytes32 opinionHash, string memory uri) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        if (dealId == bytes32(0)) revert InvalidDealId();
        if (opinionHash == bytes32(0)) revert InvalidOpinionHash();
        _requireAuthAdmin(dealManager);
        _legalOpinionStorage().opinions[dealManager][dealId] = OpinionRecord({
            opinionHash: opinionHash,
            uri: uri,
            submitter: msg.sender,
            submittedAt: uint64(block.timestamp)
        });
        emit OpinionSubmitted(dealManager, dealId, opinionHash, uri, msg.sender);
    }

    /// @notice Whether a satisfying assurance record exists for the deal under the SPV's mechanism
    function hasAssurance(address spv, address dealManager, bytes32 offerId, bytes32 agreementId) public view returns (bool) {
        LegalOpinionStorage storage $ = _legalOpinionStorage();
        OpinionMechanism mechanism = $.mechanisms[spv];
        if (mechanism != OpinionMechanism.FORMAL_OPINION) {
            if ($.gpSignOffs[dealManager][offerId]) return true;
            if (agreementId != bytes32(0) && $.gpSignOffs[dealManager][agreementId]) return true;
        }
        if (mechanism != OpinionMechanism.GP_SIGNOFF) {
            if ($.opinions[dealManager][offerId].opinionHash != bytes32(0)) return true;
            if (agreementId != bytes32(0) && $.opinions[dealManager][agreementId].opinionHash != bytes32(0)) return true;
        }
        return false;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        // Per-deal assurance: nothing to verify until a settlement exists
        if (agreementId == bytes32(0)) return true;

        Offer memory offer = dealManager.getOffer(offerId);
        return hasAssurance(offer.spvAddress, address(dealManager), offerId, agreementId);
    }

    /// @notice An SPV's chosen assurance mechanism
    function mechanisms(address spv) public view returns (OpinionMechanism) {
        return _legalOpinionStorage().mechanisms[spv];
    }

    /// @notice Whether a GP sign-off is on record for a deal
    function gpSignOffs(address dealManager, bytes32 dealId) public view returns (bool) {
        return _legalOpinionStorage().gpSignOffs[dealManager][dealId];
    }

    /// @notice The formal opinion on record for a deal
    function opinions(address dealManager, bytes32 dealId) public view returns (OpinionRecord memory) {
        return _legalOpinionStorage().opinions[dealManager][dealId];
    }

    function _legalOpinionStorage() private pure returns (LegalOpinionStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
