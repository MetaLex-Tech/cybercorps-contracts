// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../libs/auth.sol";
import "../interfaces/IZKPassportVerifier.sol";
import "../interfaces/ILexChexBadge.sol";
import {Credential} from "./storage/lexchexBadgeStorage.sol";

/// @title  ZKPassportBadgeIssuer - mints LeXcheXBadge credentials from a ZKPassport proof
/// @author MetaLeX Labs, Inc.
/// @notice A wallet asks for a set of facts (e.g. "not a national of these countries") and submits
/// a ZKPassport proof; this contract runs each fact's check and, if they pass, files the credential on the badge.
/// It holds ADMIN_ROLE and calls badge.mint/supersede; the badge just stores facts and answers yes/no.
/// @dev
/// - Anyone can submit; the proof is bound to a wallet, so the credential always goes to that wallet.
/// - Specify a set of fact-keys. _enforce runs the check each key needs; a key with no
///   check can't be minted. Only K_ZKP_* keys are allowed, so this issuer can't assert unrelated keys.
/// - No PII on-chain; the proof id is kept only as evidenceHash for audit.
/// - Not a personhood check: same passport can be reused by multiple mints to different wallets.
/// - Re-proving the same fact-set renews it in place (supersede); a holder can drop their own with void(), and an
///   admin can revoke anyone's with the three-argument void(). Nothing is ever burned — old records stay for audit.
contract ZKPassportBadgeIssuer is Initializable, UUPSUpgradeable, BorgAuthACL {
    error InvalidVerifier();
    error InvalidBadge();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidFactKeys();
    error UnverifiedFactKey();
    error InvalidNationalityList();
    error NationalityNotExcluded();
    error InvalidMaxValidityPeriod();
    error MaxValidityPeriodExceeded();
    error ProofExpired();
    error StaleProof();
    error NoLiveCredential();

    /// @dev Deterministic verifier address from ZKPassport docs.
    address public constant DEFAULT_ZKPASSPORT_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    struct IssuerStorage {
        IZKPassportVerifier verifier;
        ILexChexBadge badge;
        string expectedDomain;
        string expectedScope;
        mapping(address => mapping(uint256 => mapping(address => uint256))) current; // badge => factKeys => wallet => tokenId+1
        uint256 maxValidityPeriod; // ceiling on how long a credential minted here may last
        mapping(address => uint256) lastProofTimestamp; // wallet => proofs must be newer than this
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.creds.zkpassport-badge-issuer.storage.v1");

    event VerifierUpdated(address verifier);
    event BadgeUpdated(address badge);
    event CredentialProofMinted(
        bytes32 indexed uniqueIdentifier, uint256 indexed factKeys, address indexed account, uint256 tokenId, uint64 expiresAt
    );
    event CredentialProofRenewed(
        bytes32 indexed uniqueIdentifier, uint256 indexed factKeys, address indexed account, uint256 staleTokenId, uint256 tokenId, uint64 expiresAt
    );
    event CredentialSelfVoided(uint256 indexed factKeys, address indexed account, uint256 tokenId);
    event CredentialRevoked(uint256 indexed factKeys, address indexed account, uint256 tokenId, string reason);
    event MaxValidityPeriodUpdated(uint256 maxValidityPeriod);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _badge,
        string memory _expectedDomain,
        string memory _expectedScope,
        address _verifier,
        uint256 _maxValidityPeriod
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        IssuerStorage storage $ = _issuerStorage();

        if (_badge == address(0)) revert InvalidBadge();
        $.badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);

        $.expectedDomain = _expectedDomain;
        $.expectedScope = _expectedScope;

        if (_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        $.maxValidityPeriod = _maxValidityPeriod;
        emit MaxValidityPeriodUpdated(_maxValidityPeriod);

        address resolvedVerifier = _verifier == address(0) ? DEFAULT_ZKPASSPORT_VERIFIER : _verifier;
        if (resolvedVerifier == address(0)) revert InvalidVerifier();
        $.verifier = IZKPassportVerifier(resolvedVerifier);
        emit VerifierUpdated(resolvedVerifier);
    }

    // ── Admin config ─────────────────────────────────────────────────────────

    function updateVerifier(address _verifier) external onlyAdmin {
        if (_verifier == address(0)) revert InvalidVerifier();
        _issuerStorage().verifier = IZKPassportVerifier(_verifier);
        emit VerifierUpdated(_verifier);
    }

    /// @dev Tracked ids are per badge, so switching swaps the whole set — see _tracked.
    function updateBadge(address _badge) external onlyAdmin {
        if (_badge == address(0)) revert InvalidBadge();
        _issuerStorage().badge = ILexChexBadge(_badge);
        emit BadgeUpdated(_badge);
    }

    function updateMaxValidityPeriod(uint256 _maxValidityPeriod) external onlyAdmin {
        if (_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        _issuerStorage().maxValidityPeriod = _maxValidityPeriod;
        emit MaxValidityPeriodUpdated(_maxValidityPeriod);
    }

    // ── Issuance ─────────────────────────────────────────────────────────────

    /// @notice Mint a fact-set that does NOT include K_ZKP_NATIONALITY_OUT (which needs a country list).
    function submitProofAndMint(ProofVerificationParams calldata params, uint256 factKeys)
        external
        returns (uint256 tokenId)
    {
        return _submit(params, factKeys, new string[](0));
    }

    /// @notice Mint a fact-set including K_ZKP_NATIONALITY_OUT: `zkpNationalityOut` is the country codes the proof
    /// must verify the holder is excluded from, recorded on the credential.
    function submitProofAndMint(ProofVerificationParams calldata params, uint256 factKeys, string[] calldata zkpNationalityOut)
        external
        returns (uint256 tokenId)
    {
        return _submit(params, factKeys, zkpNationalityOut);
    }

    /// @dev Verify a ZKPassport proof and mint (or renew) `factKeys` to the proof-bound wallet. Submittable by
    /// anyone: the credential goes to the bound sender, not the caller.
    function _submit(ProofVerificationParams calldata params, uint256 factKeys, string[] memory zkpNationalityOut)
        internal
        returns (uint256 tokenId)
    {
        // ZK-provenance keys only, so this issuer can never assert a manual-KYC key.
        if (factKeys == 0 || (factKeys & ~ZKP_KEYS) != 0) revert InvalidFactKeys();
        // The country list is required iff the nationality fact is requested, and forbidden otherwise.
        if ((factKeys & K_ZKP_NATIONALITY_OUT != 0) != (zkpNationalityOut.length != 0)) revert InvalidNationalityList();

        IssuerStorage storage $ = _issuerStorage();

        (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper) = $.verifier.verify(params);
        if (!verified || address(helper) == address(0)) revert InvalidProof();

        if (!helper.verifyScopes(params.proofVerificationData.publicInputs, $.expectedDomain, $.expectedScope)) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(params.committedInputs);
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();
        address account = boundData.senderAddress;

        uint256 proofTimestamp = helper.getProofTimestamp(params.proofVerificationData.publicInputs);

        // A wallet's proofs only move forward in time. Anyone can submit and the same calldata verifies over and
        // over, so without this a bystander could replay an old proof to bring back a credential the holder self-
        // voided or an admin revoked. Either void() pushes this floor to now, so proofs made before the drop are
        // refused too and re-standing needs a fresh proof, checked against today's facts. Note this only covers
        // drops made here — voiding on the badge directly sets no floor.
        if (proofTimestamp <= $.lastProofTimestamp[account]) revert StaleProof();
        $.lastProofTimestamp[account] = proofTimestamp;

        // Every requested fact must have its check pass, or we refuse to mint it (also blocks a fact-key with no
        // matching check).
        if (_enforce(factKeys, helper, params, proofTimestamp, zkpNationalityOut) != factKeys) revert UnverifiedFactKey();

        // The proof does not cover validityPeriodInSeconds — the submitter just types it in and does not need a new proof
        // to verify whatever it says. Without a cap a holder could hand themselves a credential that never needs
        // re-proving. Checked before the addition so an absurd period can't overflow instead.
        uint256 validityPeriod = params.serviceConfig.validityPeriodInSeconds;
        uint256 maxPeriod = $.maxValidityPeriod;
        if (validityPeriod > maxPeriod) revert MaxValidityPeriodExceeded();

        // The badge requires a strictly-future expiry (mint reverts on expiry <= now). Cap the date as well: the
        // proof's own timestamp could sit in the future.
        uint256 expiresAt = proofTimestamp + validityPeriod;
        if (expiresAt <= block.timestamp) revert ProofExpired();
        if (expiresAt > block.timestamp + maxPeriod) revert MaxValidityPeriodExceeded();

        // Predicate-only, immutable credential; VALUE fields empty except the recorded exclusion list. The
        // uniqueIdentifier is kept solely as an audit anchor, not asserted as a readable fact.
        Credential memory cred;
        cred.asserts = factKeys;
        cred.categoryId = bytes32(factKeys);        // free-form label mirrors the fact-set
        cred.evidenceHash = uniqueIdentifier;       // audit anchor tying the credential to its proof
        cred.expiryDate = uint64(expiresAt);
        if (factKeys & K_ZKP_NATIONALITY_OUT != 0) cred.zkpNationalityOut = zkpNationalityOut;

        ILexChexBadge badgeContract = $.badge;
        mapping(uint256 => mapping(address => uint256)) storage tracked = _tracked($);
        uint256 stored = tracked[factKeys][account];
        if (stored != 0) {
            uint256 staleId = stored - 1;
            // Renew the live credential in one call (void + re-mint) so the active set stays lean. A stale
            // credential that is already voided/expired is not superseded — just replaced by a fresh mint.
            if (badgeContract.isValid(staleId)) {
                tokenId = badgeContract.supersede(staleId, cred, "zkpassport-renewal");
                tracked[factKeys][account] = tokenId + 1;
                emit CredentialProofRenewed(uniqueIdentifier, factKeys, account, staleId, tokenId, uint64(expiresAt));
                return tokenId;
            }
        }

        tokenId = badgeContract.mint(account, cred);
        tracked[factKeys][account] = tokenId + 1;
        emit CredentialProofMinted(uniqueIdentifier, factKeys, account, tokenId, uint64(expiresAt));
    }

    /// @notice Drop your own credential for `factKeys`. Self-service: no admin needed, and you can only void your
    /// own (the credential minted to msg.sender). The record is retained on the badge for audit.
    function void(uint256 factKeys) external {
        uint256 tokenId = _void(factKeys, msg.sender, "self-void");
        emit CredentialSelfVoided(factKeys, msg.sender, tokenId);
    }

    /// @notice Admin revocation of anyone's `factKeys` credential — failed re-check, a sanctions hit, whatever
    /// `reason` records. Revoke here rather than on the badge: this is what sets the freshness floor, so a proof
    /// made before the revoke can't be used to mint the credential straight back.
    function void(uint256 factKeys, address account, string calldata reason) external onlyAdmin {
        uint256 tokenId = _void(factKeys, account, reason);
        emit CredentialRevoked(factKeys, account, tokenId, reason);
    }

    /// @dev Drop `account`'s tracked credential for `factKeys` and raise their freshness floor to now, so a proof
    /// made before this can't put it back. Only proofs never submitted could do that, but a drop should mean
    /// something. The floor is per wallet, so it also blocks older proofs for that wallet's other fact-sets.
    function _void(uint256 factKeys, address account, string memory reason) internal returns (uint256 tokenId) {
        IssuerStorage storage $ = _issuerStorage();
        mapping(uint256 => mapping(address => uint256)) storage tracked = _tracked($);
        uint256 stored = tracked[factKeys][account];
        if (stored == 0) revert NoLiveCredential();
        tokenId = stored - 1;
        if (!$.badge.isValid(tokenId)) revert NoLiveCredential();

        tracked[factKeys][account] = 0;
        if (block.timestamp > $.lastProofTimestamp[account]) $.lastProofTimestamp[account] = block.timestamp;

        $.badge.void(tokenId, reason);
    }

    /// @dev Thin, overridable check layer: run the check each requested fact-key needs and return the mask
    /// actually checked. _submit reverts unless that covers `factKeys`, so a fact is never minted without its
    /// check. Override to change a check or teach the issuer a new K_ZKP_* key.
    function _enforce(
        uint256 factKeys,
        IZKPassportHelper helper,
        ProofVerificationParams calldata params,
        uint256 proofTimestamp,
        string[] memory zkpNationalityOut
    ) internal view virtual returns (uint256 verifiedKeys) {
        if (factKeys & K_ZKP_NATIONALITY_OUT != 0) {
            if (!helper.isNationalityOut(zkpNationalityOut, params.committedInputs)) revert NationalityNotExcluded();
            verifiedKeys |= K_ZKP_NATIONALITY_OUT;
        }
        if (factKeys & K_ZKP_BAD_ACTOR_CLEAR != 0) {
            helper.enforceSanctionsRoot(proofTimestamp, true, params.committedInputs); // strict
            verifiedKeys |= K_ZKP_BAD_ACTOR_CLEAR;
        }
    }

    // ── Reads ────────────────────────────────────────────────────────────────

    function verifier() external view returns (IZKPassportVerifier) { return _issuerStorage().verifier; }
    function badge() external view returns (ILexChexBadge) { return _issuerStorage().badge; }
    function expectedDomain() external view returns (string memory) { return _issuerStorage().expectedDomain; }
    function expectedScope() external view returns (string memory) { return _issuerStorage().expectedScope; }
    function maxValidityPeriod() external view returns (uint256) { return _issuerStorage().maxValidityPeriod; }

    /// @notice The next proof for `wallet` must be newer than this. Set by the newest proof already used, and
    /// raised to the time of the wallet's last void().
    function lastProofTimestampOf(address wallet) external view returns (uint256) {
        return _issuerStorage().lastProofTimestamp[wallet];
    }

    /// @notice The current credential this issuer tracks for (fact-set, wallet) on the badge in use, if any.
    /// `exists` only reports that a credential was issued here — call badge.isValid to learn whether it is still
    /// live.
    function currentTokenOf(uint256 factKeys, address wallet) external view returns (uint256 tokenId, bool exists) {
        uint256 stored = _tracked(_issuerStorage())[factKeys][wallet];
        if (stored == 0) return (0, false);
        return (stored - 1, true);
    }

    /// @dev Every badge numbers its tokens from 0. Keying by badge stops a badge swap from pointing a saved id
    /// at a stranger's credential.
    function _tracked(IssuerStorage storage $)
        private
        view
        returns (mapping(uint256 => mapping(address => uint256)) storage)
    {
        return $.current[address($.badge)];
    }

    function _issuerStorage() private pure returns (IssuerStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
