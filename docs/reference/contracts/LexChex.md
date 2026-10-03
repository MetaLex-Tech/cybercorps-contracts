# LexChex / LeXcheXBadge / LeXcheXMinter

MetaLeX's onchain credentials. Every credential is a **soulbound**
(non-transferable) NFT implementing
[ERC-5484](https://eips.ethereum.org/EIPS/eip-5484). Two credential
contracts are deployed side by side:

* **LeXcheX** is the accreditation credential, with one `Accreditation`
  record per token.
* **LeXcheXBadge** is the unified credential registry (`VERSION = 2`). One
  deployment carries KYC/AML facts, accreditation statuses and SPV-scoped
  entitlements as typed fact-keys. Its admins (its BorgAuth) run it and
  can delegate issuing authority per fact-key to other issuers, so several
  credentialing operators can share one registry.

* **Sources:** [`src/creds/lexchex.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchex.sol),
  [`src/creds/lexchexBadge.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchexBadge.sol),
  [`src/creds/lexchexMinter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchexMinter.sol)
* **Interfaces:** [`ILexChex.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILexChex.sol),
  [`ILexChexBadge.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILexChexBadge.sol)

## ERC-5484 (soulbound)

Both interfaces extend `IERC5484`, which defines `burnAuth(tokenId)`
returning a `BurnAuth` enum (`IssuerOnly`, `OwnerOnly`, `Both`, `Neither`)
and an `Issued` event. Credentials cannot move between wallets.
LeXcheXBadge tokens are **never burnable** (`burnAuth` always returns
`Neither`): revocation is by voiding, so every credential, whether voided,
expired or superseded, stays onchain for audit.

## LeXcheX (accreditation credential)

```solidity
function mint(address to, Accreditation acc) external returns (uint256);
function burn(uint256 tokenId) external;
function void(uint256 id, string reason) external;               // onlyOwner
function setAccreditation(uint256 tokenId, Accreditation acc) external;
function accreditations(uint256 tokenId) external view returns (Accreditation);
function getAccreditation(uint256 tokenId) external view returns (Accreditation);
function getAccreditationByOwner(address owner) external view returns (uint256);
function getTokenIdsByOwner(address owner) external view returns (uint256[]);
function hasValidLexCheX(address owner) external view returns (bool);
function isValid(uint256 tokenId) external view returns (bool);
function balanceOf(address owner) external view returns (uint256);
function burnAuth(uint256 tokenId) external view returns (BurnAuth);
```

The `Accreditation` struct (name, type, jurisdiction, contact, issuance
and expiry dates, void reason, backing agreement id and registry,
authority signature) is defined in
[`src/creds/storage/lexchexStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/storage/lexchexStorage.sol).
`hasValidLexCheX(owner)` answers whether an address holds a currently
valid credential, and `isValid` applies the three-part test: issued, not
voided, not expired.

## LeXcheXBadge (unified credential registry)

Each token is an immutable `Credential`. Its `asserts` bitmask of `K_*`
fact-keys is the sole authority axis: a field answers a read only when its
key is asserted.

* Value keys: `K_INVESTOR_TYPE`, `K_INVESTOR_JURISDICTION`,
  `K_LOOKTHROUGH_JURISDICTION` (the ICA §3(c)(1)(A) classification, kept
  separate from physical jurisdiction), `K_US_STATE`, `K_BO_COUNT`,
  `K_DATA`.
* Status keys: `K_ACCREDITED`, `K_QP`, `K_QIB`, `K_BAD_ACTOR_CLEAR`,
  `K_NON_US`.
* SPV-scoped keys: `K_SPV_WHITELIST`, `K_SYNDICATE`.

The `Credential` struct also carries `investorName`; the `issuer` address
that minted it, which consumers filter on to choose whose word they take;
a `scope`, naming the SPV the credential is about (any key may carry one,
and the SPV-scoped keys require it); issuance and expiry dates; the
backing `agreementId`; and an `evidenceHash` anchoring the offchain
diligence record.

```solidity
// Issuing authority
function setIssuerKeys(address issuer, uint256 keys) external;                 // onlyAdmin
function issuerKeys(address issuer) external view returns (uint256);

// Lifecycle
function mint(address to, Credential cred) external returns (uint256 tokenId); // admin, or issuer within its granted keys
function supersede(uint256 staleTokenId, Credential cred, string reason)
    external returns (uint256 tokenId);                                        // void + mint, under the same rules
function void(uint256 tokenId, string reason) external;                        // credential's own issuer, or any admin

function sweep(address holder) external;                       // permissionless
function sweepHolders(address[] holders) external;             // permissionless
function sweepTokens(uint256[] tokenIds) external returns (uint256 evicted); // permissionless

function isValid(uint256 tokenId) external view returns (bool);

// Filtered reads: full form plus shortcuts (kindKey only / + issuers / + scope)
function hasValidCredentialOf(address owner, uint256 kindKey,
    address[] issuers, address scope, address hook, bytes hookData) external view returns (bool);
function hasValidCredentialOf(address owner, uint256 kindKey) external view returns (bool);
function hasValidCredentialOf(address owner, uint256 kindKey, address[] issuers) external view returns (bool);
function hasValidCredentialOf(address owner, uint256 kindKey, address scope) external view returns (bool);
function getMostRecentValidWith(address owner, uint256 kindKey,
    address[] issuers, address scope, address hook, bytes hookData)
    external view returns (uint256 tokenId, bool found);        // + the same three shortcuts
function earliestValidIssuance(address owner, uint256 kindKey,
    address[] issuers, address scope, address hook, bytes hookData)
    external view returns (uint64);                             // + a kindKey-only shortcut

function hasValidWhitelistFor(address owner, address spv) external view returns (bool);
function hasValidSyndicateFor(address owner, address spv) external view returns (bool);
function hasValidLexCheX(address owner) external view returns (bool); // LeXcheX-compatible read

function getInvestorType(address owner) external view returns (InvestorType value, uint64 expiry);
function getUsState(address owner) external view returns (bytes2 value, uint64 expiry);
function getEffectiveBeneficialOwnerCount(address owner) external view returns (uint32 value, uint64 expiry);
function getInvestorJurisdiction(address owner) external view returns (string value, uint64 expiry);
function getLookThroughJurisdiction(address owner) external view returns (string value, uint64 expiry);
function getData(address owner) external view returns (bytes value, uint64 expiry);

function getTokenIdsByOwner(address owner) external view returns (uint256[]); // full audit history
function getActiveTokenIds(address owner) external view returns (uint256[]);  // not voided, not yet swept; may include expired, so check isValid per id
function getCredential(uint256 tokenId) external view returns (Credential);
function getCredentialByOwner(address owner) external view returns (uint256);
```

Key semantics:

* **Per-issuer authority.** `setIssuerKeys(issuer, keys)` (admin-only) is
  the entire grant. `mint` rejects any asserted key outside the caller's
  mask (`LexChexBadge_KeysNotAuthorized`), and a delegated issuer neither
  needs nor receives a BorgAuth role. Admins (checked through `AUTH`, so
  role adapters count) may assert any key. `mint` stamps `cred.issuer`
  with the caller. `void` is issuer-scoped: an issuer voids only its own
  credentials, with no grant required, so an issuer cut off from minting
  can still clean up its own work, and an admin can void any credential.
  `supersede` voids and re-issues in one call under the same rules.
* **Immutable, append-only.** Credentials are never edited or burned. To
  change a fact, mint a newer credential (the most recent valid one wins);
  to retract one, void it.
* **Union reads.** `hasValidCredentialOf(owner, kindKey, …)` passes when
  the owner's valid credentials *together* assert every fact-key in
  `kindKey`. The keys need not sit on one credential.
* **Query filters.** Every read (`hasValidCredentialOf`,
  `getMostRecentValidWith`, `earliestValidIssuance`) takes the same four
  optional filters, each off by default: `issuers` (only credentials from
  these issuers count; empty accepts any), `scope` (the SPV a credential
  must name; zero accepts any), and `hook` / `hookData` (an
  `ICredentialQueryHook` the caller supplies to test each credential,
  typically to interpret `Credential.data`, whose schema the badge never
  learns). Filters apply per credential. A fully empty query reverts
  (`LexChexBadge_EmptyQuery`), so a blank parameterization cannot admit
  everyone. Shortcut overloads cover the common forms.
* **Authoritative reads.** `getMostRecentValidWith` resolves the owner's
  authoritative credential: the most recent valid one carrying *all* of
  `kindKey` on a single record (ties go to the higher tokenId) that clears
  every filter. The value getters run this read. Use it directly when
  matches can contradict each other, for example two credentials naming
  different U.S. states, or an issuer tier where a newer seat demotes an
  older one.
* **Value getters return `(value, expiry)`**, where `expiry` belongs to
  the credential answering the read. When no valid credential asserts the
  fact, they return the field's empty value (`0`, `""`, `bytes2(0)`)
  instead of reverting. The badge does not interpret an empty answer: each
  downstream condition decides whether an unknown fails open or closed.
* **Bounded active set.** Compliance reads scan the holder's active set:
  entries not voided and not yet swept. `void` evicts at once, but expiry
  eviction waits. An expired credential stays in the set (and in
  `getActiveTokenIds`) until a permissionless `sweep*` keeper call evicts
  it, with `sweepTokens` working in calldata-bounded batches.
  Validity-sensitive reads check expiry per credential, but clients
  consuming `getActiveTokenIds` must apply `isValid` per id. The full
  ERC-721 enumeration is kept for audit.

**Events:** `CredentialIssued`, `CredentialVoided`, `CredentialSwept`,
`IssuerKeysUpdated` (the issuer's complete new key set, not a delta), plus
ERC-5484 `Issued`.

## LeXcheXMinter

The issuance gateway for LeXcheX credentials
(`initialize(_auth, _lexchex, _dealRegistry, _treasury)`):

* `requestMint` verifies an EIP-712 **authority signature** from a
  BorgAuth admin over the `MintRequest`, takes the mint fee to the
  treasury, creates and signs the backing agreement in the
  CyberAgreementRegistry, mints the LeXcheX, and finalizes the agreement.
  The subject's agreement signature is relayed to the registry's
  `signContractFor`, so it must use the configured registry's
  `SignatureData` type, with the subject as `signer` where the type has
  that field (see
  [CyberAgreementRegistry](CyberAgreementRegistry.md#data-model)).
* `requestMintFor` is an admin-only variant that skips the
  authority-signature check. RoundManager auto-credentialing uses it
  during allocation.
* `adminMintFor` is an admin-only mint without a backing agreement.
* `requestRenewal` and `requestRenewalFor` are the renewal counterparts.
  The signed subject is bound to the actual token owner, which prevents
  cross-account renewals.
* Configuration: `setLexchex`, `setDealRegistry`, `setTreasury` (all
  `onlyOwner`).

**Events:** `MintRequested`, `MintCompleted`, `RenewalRequested`,
`RenewalCompleted`.

## Where the protocol reads credentials

* A LexChex condition (see [Conditions](../conditions.md)) wraps the
  validity checks so they can gate issuance, rounds, scripification, deals
  and secondary trades. The secondary-trading conditions read the badge's
  fact-keys (accreditation, QP/QIB, Reg S non-US status, jurisdictions,
  beneficial-owner counts).
* The [LedgerEntryToken](LedgerEntryToken.md) look-through holder tally
  reads beneficial-owner counts and US residency from a configured
  LeXcheXBadge.
* The LeXcheX app and oracle in
  [metalex-webapp](https://github.com/MetaLex-Tech/metalex-webapp) run the
  offchain verification behind a mint.
