// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {
    ILexChexBadge,
    InvestorType,
    K_ACCREDITED,
    K_BAD_ACTOR_CLEAR,
    K_BO_COUNT,
    K_DATA,
    K_INVESTOR_JURISDICTION,
    K_INVESTOR_TYPE,
    K_LOOKTHROUGH_JURISDICTION,
    K_NON_US,
    K_QIB,
    K_QP,
    K_SPV_WHITELIST,
    K_SYNDICATE,
    K_US_STATE
} from "../src/interfaces/ILexChexBadge.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

/// @title LeXcheXBadgeIndexerTest
/// @notice The website can't read the chain on every page load, so a service (Ponder) watches the badge's
/// events and keeps its own copy — that copy is what decides who sees which offers, and what the admin panel
/// shows. If the events leave something out, that copy is wrong and people get let into the wrong deals.
/// These tests build a copy of the registry from the events and check it answers exactly like the chain.
/// @dev The indexer here reads log data only, never contract storage. Each test runs a real badge lifecycle,
/// replays the logs through it, then compares every record and every read against the badge itself.
///
/// The one thing the badge never logs is a badge going out of date. That happens on a date, not in a
/// transaction, so there is nothing to log. The copy holds the expiry date and checks it against the clock,
/// same as the badge does.
///
/// Coverage. Every test also runs the full registry check (supply, all record fields, all reads, all holders).
///
/// | Test                              | Chain events          | The point                                    |
/// |-----------------------------------|-----------------------|----------------------------------------------|
/// | RegistryLifecycle_...             | mint, supersede, void | Two people, every kind of fact, end to end   |
/// | RecencyAndAssertsAuthority_...    | mint                  | Newest badge that mentions the fact wins     |
/// | Expiry_ReDerivedWithoutAnyEvent   | none (warp only)      | A badge goes out of date with nothing logged |
/// | Sweep_LogsEachDrop...             | mint, sweep           | Cleanup is logged and changes no answer      |
/// | ScopedEntitlements_...            | mint, void            | Access to one SPV doesn't work on another    |
/// | AppendOnlyRegistry_...            | mint, supersede       | Badges are only added and cancelled          |
contract LeXcheXBadgeIndexerTest is Test {
    // ─────────────────────────────────────────────────────────────────────────
    // Off-chain indexer model — populated only from emitted logs
    // ─────────────────────────────────────────────────────────────────────────

    struct IdxCredential {
        bool exists;
        uint256 tokenId; // from CredentialIssued's indexed topic
        address holder;
        Credential cred; // the record as the logs described it (voided reason patched in by CredentialVoided)
        bool issuedSeen; // the ERC-5484 Issued companion event was observed
        uint8 burnAuth;
        uint256 mints; // ERC-721 Transfers from the zero address
        uint256 moves; // ERC-721 Transfers between holders (soulbound ⇒ must stay 0)
    }

    mapping(uint256 => IdxCredential) internal idxCreds;
    uint256[] internal idxTokenIds;
    // Per holder, in mint order — which is also ERC-721 enumeration order, since credentials are soulbound and
    // never burned, so nothing ever reorders the holder's list.
    mapping(address => uint256[]) internal idxHolderTokens;
    address[] internal idxHolders;
    mapping(address => bool) internal idxKnownHolder;

    // The badge's own active set, mirrored: minting adds, voiding and sweeping remove. Answers never come from
    // this — they come from the holder's full history filtered by validity. It is kept only to show the list
    // the badge walks is now reconstructable too, which it was not before CredentialSwept existed.
    mapping(address => uint256[]) internal idxActive;
    mapping(uint256 => bool) internal idxIsActive;

    // Event topic0 hashes taken straight from the declarations, so they can't drift from the emitted signatures.
    bytes32 immutable TOPIC_CREDENTIAL_ISSUED = ILexChexBadge.CredentialIssued.selector;
    bytes32 immutable TOPIC_CREDENTIAL_VOIDED = ILexChexBadge.CredentialVoided.selector;
    bytes32 immutable TOPIC_CREDENTIAL_SWEPT = ILexChexBadge.CredentialSwept.selector;
    bytes32 immutable TOPIC_ISSUED = IERC5484.Issued.selector;
    bytes32 immutable TOPIC_TRANSFER = IERC721.Transfer.selector;

    // ─────────────────────────────────────────────────────────────────────────
    // Chain fixtures
    // ─────────────────────────────────────────────────────────────────────────

    address owner;
    address alice;
    address bob;
    address spvA;
    address spvB;
    LeXcheXBadge badge;

    // What every holder assertion probes: each fact-key on its own, and each SPV. Kept at contract level so
    // the assertion helpers stay single-argument.
    uint256[] internal probeKeys;
    address[] internal probeSpvs;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spvA = makeAddr("spvA");
        spvB = makeAddr("spvB");

        BorgAuth auth = new BorgAuth(owner);
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth))))
            )
        );

        probeKeys = [
            K_INVESTOR_TYPE,
            K_INVESTOR_JURISDICTION,
            K_LOOKTHROUGH_JURISDICTION,
            K_US_STATE,
            K_BO_COUNT,
            K_DATA,
            K_ACCREDITED,
            K_QP,
            K_QIB,
            K_BAD_ACTOR_CLEAR,
            K_NON_US,
            K_SPV_WHITELIST,
            K_SYNDICATE,
            // A combination, probed because the two reads answer it differently: eligibility adds credentials
            // up, seasoning needs one credential carrying the whole set.
            K_ACCREDITED | K_QP
        ];
        probeSpvs = [spvA, spvB];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Credential builders
    // ─────────────────────────────────────────────────────────────────────────

    function _cred(uint256 asserts) internal view returns (Credential memory c) {
        c.asserts = asserts;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        c.agreementId = keccak256(abi.encodePacked("agreement", asserts, block.timestamp));
        c.evidenceHash = keccak256(abi.encodePacked("evidence", asserts, block.timestamp));
    }

    /// @dev Individual with a physical jurisdiction and U.S. state.
    function _kyc(string memory jurisdiction, bytes2 state) internal view returns (Credential memory c) {
        c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_US_STATE);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorName = "Alice Individual";
        c.investorJurisdiction = jurisdiction;
        c.usState = state;
    }

    /// @dev Entity feeder: physical domicile and §3(c)(1)(A) look-through classification kept separate.
    function _entity(string memory domicile, string memory lookThrough, uint32 boCount)
        internal
        view
        returns (Credential memory c)
    {
        c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_BO_COUNT);
        c.investorType = InvestorType.ENTITY;
        c.investorName = "Bob Feeder Ltd.";
        c.investorJurisdiction = domicile;
        c.lookThroughJurisdiction = lookThrough;
        c.beneficialOwnerCount = boCount;
    }

    function _jurisdictionOnly(string memory j) internal view returns (Credential memory c) {
        c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = j;
    }

    function _scoped(uint256 keys, address spv) internal view returns (Credential memory c) {
        c = _cred(keys);
        c.scope = spv;
    }

    function _expiring(uint256 keys, uint256 lifetime) internal view returns (Credential memory c) {
        c = _cred(keys);
        c.expiryDate = uint64(block.timestamp + lifetime);
    }

    function _mint(address to, Credential memory c) internal returns (uint256) {
        vm.prank(owner);
        return badge.mint(to, c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // The indexer — consumes logs only
    // ─────────────────────────────────────────────────────────────────────────

    function _index(Vm.Log[] memory logs) internal {
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.emitter != address(badge) || log.topics.length == 0) continue;
            bytes32 topic = log.topics[0];
            if (topic == TOPIC_CREDENTIAL_ISSUED) _handleCredentialIssued(log);
            else if (topic == TOPIC_CREDENTIAL_VOIDED) _handleCredentialVoided(log);
            else if (topic == TOPIC_CREDENTIAL_SWEPT) _handleCredentialSwept(log);
            else if (topic == TOPIC_ISSUED) _handleIssued(log);
            else if (topic == TOPIC_TRANSFER) _handleTransfer(log);
        }
    }

    function _addr(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function _handleCredentialIssued(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=owner, [2]=tokenId; data: the whole Credential record.
        address holder = _addr(log.topics[1]);
        uint256 tokenId = uint256(log.topics[2]);
        Credential memory cred = abi.decode(log.data, (Credential));

        IdxCredential storage c = idxCreds[tokenId];
        require(!c.exists, "indexer: credential issued twice");
        c.exists = true;
        c.tokenId = tokenId;
        c.holder = holder;
        c.cred = cred;

        idxTokenIds.push(tokenId);
        idxHolderTokens[holder].push(tokenId);
        idxActive[holder].push(tokenId);
        idxIsActive[tokenId] = true;
        if (!idxKnownHolder[holder]) {
            idxKnownHolder[holder] = true;
            idxHolders.push(holder);
        }
    }

    function _handleCredentialVoided(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=owner, [2]=tokenId; data: reason.
        uint256 tokenId = uint256(log.topics[2]);
        IdxCredential storage c = idxCreds[tokenId];
        require(c.exists, "indexer: void before issue");
        require(c.holder == _addr(log.topics[1]), "indexer: void names another holder");
        c.cred.voided = abi.decode(log.data, (string));
        idxIsActive[tokenId] = false;
    }

    function _handleCredentialSwept(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=owner, [2]=tokenId. Housekeeping only — the credential stopped counting at its
        // expiry, which the indexer already knew. All this adds is the badge's own list of what it still walks.
        uint256 tokenId = uint256(log.topics[2]);
        require(idxCreds[tokenId].exists, "indexer: sweep before issue");
        require(!_idxIsValid(tokenId), "indexer: a still-good credential was swept");
        idxIsActive[tokenId] = false;
    }

    function _handleIssued(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=from, [2]=to, [3]=tokenId; data: burnAuth.
        require(_addr(log.topics[1]) == address(0), "indexer: issued from a prior holder");
        IdxCredential storage c = idxCreds[uint256(log.topics[3])];
        c.issuedSeen = true;
        c.burnAuth = uint8(abi.decode(log.data, (uint256)));
    }

    function _handleTransfer(Vm.Log memory log) private {
        // topics: [0]=sig, [1]=from, [2]=to, [3]=tokenId. Separating the mint from any later move is what makes
        // the log stream itself show an append-only registry.
        IdxCredential storage c = idxCreds[uint256(log.topics[3])];
        if (_addr(log.topics[1]) == address(0)) ++c.mints;
        else ++c.moves;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Indexer-side reads — what a Ponder handler computes from the indexed rows
    // ─────────────────────────────────────────────────────────────────────────

    function _idxIsValid(uint256 tokenId) internal view returns (bool) {
        IdxCredential storage c = idxCreds[tokenId];
        if (!c.exists) return false;
        if (bytes(c.cred.voided).length > 0) return false;
        if (block.timestamp > c.cred.expiryDate) return false;
        return true;
    }

    /// @dev The holder's authoritative credential for `key`, resolved exactly as the contract does: most recent
    /// by issuanceDate, ties to the higher token id, and only credentials that assert every requested key.
    /// Scans the holder's whole history rather than the on-chain active set — equivalent, because everything
    /// the active set drops (voided, expired) is already invalid here.
    function _idxMostRecentValidWith(address holder, uint256 key) internal view returns (uint256 tokenId, bool found) {
        if (key == 0) return (0, false);

        uint64 latest = 0;
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 candidate = ids[i];
            if (!_idxIsValid(candidate)) continue;
            Credential storage cred = idxCreds[candidate].cred;
            if ((cred.asserts & key) != key) continue;
            if (!found || cred.issuanceDate > latest || (cred.issuanceDate == latest && candidate > tokenId)) {
                latest = cred.issuanceDate;
                tokenId = candidate;
                found = true;
            }
        }
    }

    /// @dev Mirrors the contract: the holder's valid credentials TOGETHER have to cover `key`, so statuses
    /// attested on separate credentials still add up. Not built on _idxMostRecentValidWith — that one picks a
    /// single credential, which would force every key onto one of them.
    function _idxHasValidCredentialOf(address holder, uint256 key) internal view returns (bool) {
        if (key == 0) return false;

        uint256 covered;
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            if (!_idxIsValid(ids[i])) continue;
            covered |= idxCreds[ids[i]].cred.asserts;
            if ((covered & key) == key) return true;
        }
        return false;
    }

    function _idxHasValidScopedCredentialOf(address holder, uint256 scopeKey, address spv)
        internal
        view
        returns (bool)
    {
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            Credential storage cred = idxCreds[ids[i]].cred;
            if ((cred.asserts & scopeKey) != 0 && cred.scope == spv && _idxIsValid(ids[i])) return true;
        }
        return false;
    }

    function _idxInvestorType(address holder) internal view returns (InvestorType) {
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_INVESTOR_TYPE);
        return found ? idxCreds[tokenId].cred.investorType : InvestorType.UNSET;
    }

    function _idxUsState(address holder) internal view returns (bytes2) {
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_US_STATE);
        return found ? idxCreds[tokenId].cred.usState : bytes2(0);
    }

    function _idxBeneficialOwnerCount(address holder) internal view returns (uint32) {
        if (_idxInvestorType(holder) == InvestorType.INDIVIDUAL) return 1;
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_BO_COUNT);
        return found ? idxCreds[tokenId].cred.beneficialOwnerCount : 0;
    }

    function _idxData(address holder) internal view returns (bytes memory) {
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_DATA);
        if (!found) return "";
        return idxCreds[tokenId].cred.data;
    }

    function _idxInvestorJurisdiction(address holder) internal view returns (string memory) {
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_INVESTOR_JURISDICTION);
        return found ? idxCreds[tokenId].cred.investorJurisdiction : "";
    }

    function _idxLookThroughJurisdiction(address holder) internal view returns (string memory) {
        (uint256 tokenId, bool found) = _idxMostRecentValidWith(holder, K_LOOKTHROUGH_JURISDICTION);
        return found ? idxCreds[tokenId].cred.lookThroughJurisdiction : "";
    }

    function _idxEarliestValidIssuance(address holder, uint256 key) internal view returns (uint64 earliest) {
        if (key == 0) return 0;
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            if (!_idxIsValid(tokenId)) continue;
            Credential storage cred = idxCreds[tokenId].cred;
            if ((cred.asserts & key) != key) continue;
            if (earliest == 0 || cred.issuanceDate < earliest) earliest = cred.issuanceDate;
        }
    }

    function _idxHasValidLexCheX(address holder) internal view returns (bool) {
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            if (_idxIsValid(ids[i])) return true;
        }
        return false;
    }

    /// @dev Lowest-token-id valid credential — the enumeration order the contract walks.
    function _idxCredentialByOwner(address holder) internal view returns (uint256 tokenId, bool found) {
        uint256[] storage ids = idxHolderTokens[holder];
        for (uint256 i = 0; i < ids.length; i++) {
            if (_idxIsValid(ids[i])) return (ids[i], true);
        }
        return (0, false);
    }

    /// @dev The badge's active list as the indexer has it: minted, not voided, not yet swept.
    function _idxActiveTokens(address holder) internal view returns (uint256[] memory active) {
        uint256[] storage ids = idxActive[holder];
        uint256 count;
        for (uint256 i = 0; i < ids.length; i++) {
            if (idxIsActive[ids[i]]) ++count;
        }
        active = new uint256[](count);
        uint256 j;
        for (uint256 i = 0; i < ids.length; i++) {
            if (idxIsActive[ids[i]]) active[j++] = ids[i];
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reconstruction assertions — indexer state vs on-chain truth
    // ─────────────────────────────────────────────────────────────────────────

    function _assertCredentialReconstructed(uint256 tokenId) internal view {
        IdxCredential storage i = idxCreds[tokenId];
        Credential memory c = badge.getCredential(tokenId);
        assertTrue(i.exists, "credential reconstructed from logs");
        assertEq(i.cred.asserts, c.asserts, "asserts");
        assertEq(i.cred.issuer, c.issuer, "issuer");
        assertEq(i.cred.investorName, c.investorName, "investorName");
        assertEq(i.cred.investorJurisdiction, c.investorJurisdiction, "investorJurisdiction");
        assertEq(i.cred.lookThroughJurisdiction, c.lookThroughJurisdiction, "lookThroughJurisdiction");
        assertEq(uint256(i.cred.investorType), uint256(c.investorType), "investorType");
        assertEq(bytes32(i.cred.usState), bytes32(c.usState), "usState");
        assertEq(uint256(i.cred.beneficialOwnerCount), uint256(c.beneficialOwnerCount), "beneficialOwnerCount");
        assertEq(i.cred.scope, c.scope, "scope");
        assertEq(uint256(i.cred.issuanceDate), uint256(c.issuanceDate), "issuanceDate");
        assertEq(uint256(i.cred.expiryDate), uint256(c.expiryDate), "expiryDate");
        assertEq(i.cred.voided, c.voided, "voided reason");
        assertEq(i.cred.agreementId, c.agreementId, "agreementId");
        assertEq(i.cred.evidenceHash, c.evidenceHash, "evidenceHash");
        assertEq(i.cred.data, c.data, "data");
        // Derived per-token state.
        assertEq(_idxIsValid(tokenId), badge.isValid(tokenId), "validity");
        assertEq(i.holder, badge.ownerOf(tokenId), "holder");
        assertTrue(i.issuedSeen, "ERC-5484 Issued observed");
        assertEq(uint256(i.burnAuth), uint256(badge.burnAuth(tokenId)), "burn authority");
        // Soulbound: one mint in, nothing out.
        assertEq(i.mints, 1, "exactly one mint transfer");
        assertEq(i.moves, 0, "no post-mint transfer");
    }

    /// @dev Every read the conditions and the UI make against this holder, answered from the logs.
    function _assertHolderReconstructed(address holder) internal {
        (InvestorType investorType,) = badge.getInvestorType(holder);
        (bytes2 usState,) = badge.getUsState(holder);
        (uint32 boCount,) = badge.getEffectiveBeneficialOwnerCount(holder);
        (bytes memory data,) = badge.getData(holder);
        (string memory jurisdiction,) = badge.getInvestorJurisdiction(holder);
        (string memory lookThrough,) = badge.getLookThroughJurisdiction(holder);

        assertEq(uint256(_idxInvestorType(holder)), uint256(investorType), "getInvestorType");
        assertEq(bytes32(_idxUsState(holder)), bytes32(usState), "getUsState");
        assertEq(uint256(_idxBeneficialOwnerCount(holder)), uint256(boCount), "getEffectiveBeneficialOwnerCount");
        assertEq(_idxData(holder), data, "getData");
        assertEq(_idxInvestorJurisdiction(holder), jurisdiction, "getInvestorJurisdiction");
        assertEq(_idxLookThroughJurisdiction(holder), lookThrough, "getLookThroughJurisdiction");
        assertEq(_idxHasValidLexCheX(holder), badge.hasValidLexCheX(holder), "hasValidLexCheX");

        for (uint256 i = 0; i < probeKeys.length; i++) {
            uint256 key = probeKeys[i];
            assertEq(
                _idxHasValidCredentialOf(holder, key), badge.hasValidCredentialOf(holder, key), "hasValidCredentialOf"
            );
            assertEq(
                uint256(_idxEarliestValidIssuance(holder, key)),
                uint256(badge.earliestValidIssuance(holder, key)),
                "earliestValidIssuance"
            );
        }
        for (uint256 i = 0; i < probeSpvs.length; i++) {
            address spv = probeSpvs[i];
            assertEq(
                _idxHasValidScopedCredentialOf(holder, K_SPV_WHITELIST, spv),
                badge.hasValidWhitelistFor(holder, spv),
                "hasValidWhitelistFor"
            );
            assertEq(
                _idxHasValidScopedCredentialOf(holder, K_SYNDICATE, spv),
                badge.hasValidSyndicateFor(holder, spv),
                "hasValidSyndicateFor"
            );
        }
        // ERC-721 enumeration is the full audit record: every credential ever issued to the holder, in mint
        // order, voided and expired ones included.
        uint256[] memory chainTokens = badge.getTokenIdsByOwner(holder);
        uint256[] storage indexedTokens = idxHolderTokens[holder];
        assertEq(chainTokens.length, indexedTokens.length, "token count");
        assertEq(badge.balanceOf(holder), indexedTokens.length, "balanceOf");
        for (uint256 i = 0; i < chainTokens.length; i++) {
            assertEq(indexedTokens[i], chainTokens[i], "enumerated token id");
        }

        (uint256 expectedId, bool found) = _idxCredentialByOwner(holder);
        if (found) {
            assertEq(badge.getCredentialByOwner(holder), expectedId, "getCredentialByOwner");
        } else {
            vm.expectRevert(ILexChexBadge.LexChexBadge_NoValidCredential.selector);
            badge.getCredentialByOwner(holder);
        }

        _assertActiveSetsMatch(holder);
    }

    /// @dev The list the badge walks when answering. Mints, voids and sweeps are all logged, so the indexer
    /// holds the same members — compared as a set, since the badge reorders its array as it removes.
    function _assertActiveSetsMatch(address holder) internal view {
        uint256[] memory chainActive = badge.getActiveTokenIds(holder);
        uint256[] memory indexedActive = _idxActiveTokens(holder);

        assertEq(indexedActive.length, chainActive.length, "active set size");
        for (uint256 i = 0; i < chainActive.length; i++) {
            assertTrue(idxIsActive[chainActive[i]], "the badge still walks it, so the indexer must too");
        }
        for (uint256 i = 0; i < indexedActive.length; i++) {
            assertTrue(_chainActiveContains(chainActive, indexedActive[i]), "and nothing extra on the indexer side");
        }
    }

    function _chainActiveContains(uint256[] memory chainActive, uint256 tokenId) private pure returns (bool) {
        for (uint256 i = 0; i < chainActive.length; i++) {
            if (chainActive[i] == tokenId) return true;
        }
        return false;
    }

    /// @dev The whole registry: supply, every credential record, every holder's reads.
    function _assertRegistryReconstructed() internal {
        assertEq(idxTokenIds.length, badge.totalSupply(), "supply reconstructed from CredentialIssued events");
        for (uint256 i = 0; i < idxTokenIds.length; i++) {
            _assertCredentialReconstructed(idxTokenIds[i]);
        }
        for (uint256 i = 0; i < idxHolders.length; i++) {
            _assertHolderReconstructed(idxHolders[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Scenarios
    // ─────────────────────────────────────────────────────────────────────────

    // The everyday case: two people get badges, one moves house, one loses access, one badge runs out. Replay
    // the logs and every answer should come out the same as on chain.
    function test_Indexer_RegistryLifecycle_MintSupersedeVoidExpire() public {
        vm.recordLogs();

        // Alice: a person, KYC'd, lives in NY. Plus a second badge saying she's accredited.
        uint256 aliceNy = _mint(alice, _kyc("US", "NY"));
        _mint(alice, _cred(K_ACCREDITED));

        // Bob: a company registered offshore that still counts as U.S. for fund-size rules. Plus access to
        // spvA, a blob of data the badge just carries around, and a QP badge that expires in 10 days.
        _mint(bob, _entity("KY", "US", 6));
        uint256 bobWhitelist = _mint(bob, _scoped(K_SPV_WHITELIST, spvA));
        Credential memory payload = _cred(K_DATA);
        payload.data = hex"c0ffee01";
        _mint(bob, payload);
        _mint(bob, _expiring(K_QP, 10 days));

        vm.warp(block.timestamp + 30 days);
        // Alice moves to TX. supersede kills the NY badge and mints the TX one in one go.
        vm.prank(owner);
        uint256 aliceTx = badge.supersede(aliceNy, _kyc("US", "TX"), "relocated to TX");
        // Bob's access to spvA is pulled.
        vm.prank(owner);
        badge.void(bobWhitelist, "delisted");
        // Bob's QP badge ran out 20 days ago. Nothing happened on chain when it did.

        _index(vm.getRecordedLogs());

        assertEq(idxTokenIds.length, 7, "seven credentials indexed");
        assertEq(idxHolders.length, 2, "two holders discovered");
        _assertRegistryReconstructed();

        // Write out what the indexer ended up with, so the end state is readable here.
        assertEq(bytes32(_idxUsState(alice)), bytes32(bytes2("TX")), "she reads as TX now, not NY");
        assertEq(idxCreds[aliceNy].cred.voided, "relocated to TX", "the dead badge is kept, with its reason");
        assertEq(idxCreds[aliceTx].cred.investorName, "Alice Individual", "her name came through in the log");
        assertTrue(_idxHasValidCredentialOf(alice, K_ACCREDITED), "her other badge still works");

        assertEq(_idxLookThroughJurisdiction(bob), "US", "counts as U.S. for fund-size rules");
        assertEq(_idxInvestorJurisdiction(bob), "KY", "but is still registered offshore");
        assertEq(uint256(_idxBeneficialOwnerCount(bob)), 6, "six people behind the company");
        assertEq(_idxData(bob), hex"c0ffee01", "the data blob came through byte for byte");
        assertFalse(_idxHasValidScopedCredentialOf(bob, K_SPV_WHITELIST, spvA), "his spvA access is gone");
        assertFalse(_idxHasValidCredentialOf(bob, K_QP), "his QP badge ran out, and nothing said so");
    }

    // When someone has several badges, which one answers? The newest one that actually mentions the fact. A
    // newer badge that says nothing about a fact leaves the older answer standing. Badges minted in the same
    // block are the same age, so the higher token id wins. The indexer has to pick the same way.
    function test_Indexer_RecencyAndAssertsAuthority_FromLogsAlone() public {
        vm.recordLogs();

        // Old badge: offshore person, lives in NY, counts as U.S. for fund-size rules.
        Credential memory older =
            _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE);
        older.investorType = InvestorType.INDIVIDUAL;
        older.investorJurisdiction = "KY";
        older.lookThroughJurisdiction = "US";
        older.usState = "NY";
        _mint(alice, older);

        vm.warp(block.timestamp + 1 days);
        // A day later: new badge, moved to CA. It says nothing about the fund-size classification.
        _mint(alice, _kyc("KY", "CA"));
        // Two more in the same block as that one, so all three are the same age.
        uint256 tieLoser = _mint(alice, _jurisdictionOnly("FR"));
        uint256 tieWinner = _mint(alice, _jurisdictionOnly("DE"));

        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertGt(tieWinner, tieLoser, "the DE badge was minted second");
        assertEq(bytes32(_idxUsState(alice)), bytes32(bytes2("CA")), "the newer badge's state wins");
        assertEq(_idxLookThroughJurisdiction(alice), "US", "the newer badge didn't mention this, so US stands");
        assertEq(_idxInvestorJurisdiction(alice), "DE", "same age, so the later token id wins");
    }

    // Someone can qualify on two counts without one badge saying both — the accredited badge and the QP badge
    // are separate pieces of paper. Eligibility adds them up; the seasoning date cannot, because two badges
    // issued on different days give no one date to report. The indexer has to answer both the same way.
    function test_Indexer_SeparateStatusBadges_AddUpForEligibilityNotSeasoning() public {
        vm.recordLogs();
        _mint(alice, _cred(K_ACCREDITED));
        vm.warp(block.timestamp + 5 days);
        _mint(alice, _cred(K_QP));
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertTrue(_idxHasValidCredentialOf(alice, K_ACCREDITED | K_QP), "two badges, both count");
        assertEq(uint256(_idxEarliestValidIssuance(alice, K_ACCREDITED | K_QP)), 0, "no one badge says both");

        // One badge saying both does have a date, and it is that badge's.
        vm.recordLogs();
        uint256 combined = _mint(bob, _cred(K_ACCREDITED | K_QP));
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertEq(
            uint256(_idxEarliestValidIssuance(bob, K_ACCREDITED | K_QP)),
            uint256(badge.getCredential(combined).issuanceDate)
        );
    }

    // A badge going out of date is not a transaction, so nothing is logged when it happens. The indexer wrote
    // down the expiry date when the badge was minted, and checks it against the clock every time it answers.
    // So it keeps up with the chain without being told anything.
    function test_Indexer_Expiry_ReDerivedWithoutAnyEvent() public {
        vm.recordLogs();
        _mint(alice, _expiring(K_ACCREDITED, 10 days));
        _mint(alice, _kyc("US", "CA"));
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertTrue(_idxHasValidCredentialOf(alice, K_ACCREDITED), "still good, 10 days to go");

        // Jump past the expiry date. Feed the indexer whatever happened in between — which is nothing.
        vm.recordLogs();
        vm.warp(block.timestamp + 11 days);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "nothing is logged when a badge goes out of date");
        _index(logs);

        _assertRegistryReconstructed();
        assertFalse(_idxHasValidCredentialOf(alice, K_ACCREDITED), "out of date, and the indexer knows");
        assertTrue(_idxHasValidCredentialOf(alice, K_INVESTOR_TYPE), "her other badge is still good");
    }

    // sweep() is a cleanup call: it drops out-of-date badges from the list the badge walks when answering, to
    // keep that walk cheap. It changes no answer — only badges that already stopped counting can be dropped —
    // but it does log each drop, which is how a keeper sees its run did work and how the indexer keeps the
    // list itself in step.
    function test_Indexer_Sweep_LogsEachDropAndChangesNoAnswer() public {
        vm.recordLogs();
        uint256 lapsing = _mint(alice, _expiring(K_ACCREDITED, 10 days));
        _mint(alice, _kyc("US", "CA"));
        _index(vm.getRecordedLogs());

        vm.warp(block.timestamp + 11 days);
        // Reads already ignore the stale badge, before anyone sweeps.
        _assertRegistryReconstructed();

        vm.recordLogs();
        badge.sweep(alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one log for the one badge dropped");
        _index(logs);

        // Both sides now walk one badge, and no answer moved.
        assertEq(badge.getActiveTokenIds(alice).length, 1, "chain dropped the stale one");
        assertEq(_idxActiveTokens(alice).length, 1, "so did the indexer");
        _assertRegistryReconstructed();

        // Dropped from the walk, but not deleted — the record is still there, exactly as the indexer has it.
        assertFalse(badge.isValid(lapsing), "the dropped badge no longer counts");
        assertEq(
            uint256(badge.getCredential(lapsing).expiryDate),
            uint256(idxCreds[lapsing].cred.expiryDate),
            "the record itself is kept"
        );

        // Sweeping again drops nothing, so it says nothing.
        vm.recordLogs();
        badge.sweep(alice);
        assertEq(vm.getRecordedLogs().length, 0, "nothing left to drop, nothing to report");
    }

    // Most badges are about the person: accredited, lives in CA. Two are about the person AND one particular
    // SPV — a whitelist (let into that SPV's offers) and a syndicate seat (in that SPV's inner circle). Each
    // names its SPV. Two easy ways to get this wrong off chain: store a plain "alice is whitelisted" flag and
    // lose which SPV, or treat the two as the same thing. Both would let people into deals they can't join.
    function test_Indexer_ScopedEntitlements_ReconstructedPerSpv() public {
        vm.recordLogs();
        uint256 whitelistA = _mint(alice, _scoped(K_SPV_WHITELIST, spvA));
        _mint(alice, _scoped(K_SYNDICATE, spvB));
        // One badge can carry both, for the same SPV.
        _mint(bob, _scoped(K_SPV_WHITELIST | K_SYNDICATE, spvB));
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertTrue(_idxHasValidScopedCredentialOf(alice, K_SPV_WHITELIST, spvA), "alice is let into spvA");
        assertFalse(_idxHasValidScopedCredentialOf(alice, K_SPV_WHITELIST, spvB), "which doesn't let her into spvB");
        assertFalse(_idxHasValidScopedCredentialOf(alice, K_SYNDICATE, spvA), "and isn't a seat in spvA's circle");
        assertTrue(_idxHasValidScopedCredentialOf(alice, K_SYNDICATE, spvB), "her seat is in spvB's circle");
        assertTrue(_idxHasValidScopedCredentialOf(bob, K_SPV_WHITELIST, spvB), "bob's badge covers both");
        assertTrue(_idxHasValidScopedCredentialOf(bob, K_SYNDICATE, spvB), "bob's badge covers both");

        // Take alice's spvA access away. The indexer should pick that up from the log and nothing else.
        vm.recordLogs();
        vm.prank(owner);
        badge.void(whitelistA, "delisted");
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertFalse(_idxHasValidScopedCredentialOf(alice, K_SPV_WHITELIST, spvA), "she's out of spvA");
        assertTrue(_idxHasValidScopedCredentialOf(alice, K_SYNDICATE, spvB), "her spvB seat is untouched");
    }

    // Badges can't be edited, moved, or destroyed — only added and cancelled. The logs alone should show that:
    // one mint per badge, never a transfer to someone else, and cancelled badges still in the holder's list.
    function test_Indexer_AppendOnlyRegistry_FromLogsAlone() public {
        vm.recordLogs();
        uint256 first = _mint(alice, _kyc("US", "NY"));
        _mint(alice, _cred(K_ACCREDITED));
        vm.prank(owner);
        uint256 replacement = badge.supersede(first, _kyc("US", "TX"), "relocated to TX");
        _index(vm.getRecordedLogs());

        _assertRegistryReconstructed();
        assertEq(idxTokenIds.length, 3, "the move minted a third badge instead of editing the first");
        for (uint256 i = 0; i < idxTokenIds.length; i++) {
            IdxCredential storage c = idxCreds[idxTokenIds[i]];
            assertEq(uint256(c.burnAuth), uint256(IERC5484.BurnAuth.Neither), "nobody can burn a badge");
        }

        // The old badge is still on her list, so the indexer's history has no holes in it.
        assertEq(idxHolderTokens[alice].length, 3, "the cancelled badge is still listed");
        assertFalse(_idxIsValid(first), "it just doesn't count any more");
        assertTrue(_idxIsValid(replacement), "the new one counts instead");
        assertEq(idxCreds[first].holder, idxCreds[replacement].holder, "and it went to the same person");
    }
}
