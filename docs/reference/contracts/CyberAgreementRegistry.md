# CyberAgreementRegistry

An onchain registry of legal-agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds reference it for their
underlying agreements.

* **Source:** [`src/CyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberAgreementRegistry.sol)
  / interface [`ICyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberAgreementRegistry.sol)
* **Pattern:** UUPS proxy (`Initializable`, `UUPSUpgradeable`,
  `BorgAuthACL`); EIP-712 domain `EIP712Domain(string name,string
  version,uint256 chainId,address verifyingContract)` with name
  `"CyberAgreementRegistry"`, version `"1"`, the chain id and the registry
  proxy address. `DOMAIN_SEPARATOR()` and `version()` are public getters.

## Data model

```solidity
struct Template {                              // declared in ICyberAgreementRegistry
    string legalContractUri;   // canonical legal text
    string title;
    string[] globalFields;     // field names common to the whole contract
    string[] partyFields;      // field names filled per signing party
}

struct AgreementData {
    bytes32 templateId;
    string[] globalValues;
    address[] parties;                        // address(0) = open slot
    mapping(address => string[]) partyValues;
    mapping(address => uint256) signedAt;
    uint256 numSignatures;
    address finalizer;
    bool finalized;
    bool voided;
    bytes32 secretHash;
    uint256 expiry;
    address[] voidRequestedBy;
}

// What each party signs (EIP-712)
struct SignatureData {
    bytes32 contractId;
    address signer;            // the party this signature consents for
    string legalContractUri;
    string[] globalFields;
    string[] partyFields;
    string[] globalValues;
    string[] partyValues;      // the signing party's own values
}

bytes32 public constant SIGNATUREDATA_TYPEHASH = keccak256(
    "SignatureData(bytes32 contractId,address signer,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues)"
); // = 0xe37d17c3ab7740aee31093101f9d27d139a5c3b35324b266efe5d085d6486f05

bytes32 public VOIDSIGNATUREDATA_TYPEHASH; // keccak256("VoidSignatureData(bytes32 contractId,address party)")
```

The `contractId` is `keccak256(abi.encode(templateId, salt, globalValues,
parties, secretHash, finalizer))` — `secretHash` and `finalizer` are
deliberately bound into the id so a front-runner cannot seize the same id
with hostile terms; `expiry` is deliberately **not** bound so presigned
offchain signatures stay verifiable.

The `signer` field binds a signature to one party. A delegate can hold
delegations from several parties, and without the field one delegate
signature over the same agreement would verify for each of them. The
string fields are hashed as EIP-712 requires: `legalContractUri` as
`keccak256(bytes(uri))`, each `string[]` as the `keccak256` of the
concatenated `keccak256` of its elements.

{% hint style="warning" %}
**Registry versions on live chains.** Checked onchain on 2026-10-02: the
registry proxy `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` on Ethereum,
Base and Arbitrum runs this implementation. `SIGNATUREDATA_TYPEHASH()`
returns `0xe37d17c3…6f05`, and a simulated `createContract` returns the
six-field id above. The separate zkSync Era registry
(`0x07E0a0BeC742f90f7879830bC917E783dA6a6357`) still returns
`0x49ba7af1fd9b42077b5e2bf090b7deb0f443e9ae99b46ce66b4859e28d670da4`, the
older type without `signer`. Older registry implementations also derived
ids from fewer fields. Read `SIGNATUREDATA_TYPEHASH()` on the registry you
are about to sign against before choosing the typed data or the id
formula, and prefer the id from the `ContractCreated` event or an
`eth_call` of `createContract` where the flow allows it. Agreements created
before an upgrade keep the ids they were created with.
{% endhint %}

## Functions

```solidity
function createTemplate(bytes32 templateId, string title, string legalContractUri,
    string[] globalFields, string[] partyFields) external;      // permissionless

function createContract(bytes32 templateId, uint256 salt, string[] globalValues,
    address[] parties, string[][] partyValues, bytes32 secretHash,
    address finalizer, uint256 expiry) external returns (bytes32 contractId);

function createStandaloneContractAndSign(string title, string legalContractUri,
    string[] globalFields, string[] partyFields, uint256 salt,
    string[] globalValues, address[] parties, string[][] partyValues,
    uint256 expiry, bytes signature) external returns (bytes32 contractId);
function createStandaloneContractAndSignFor(/* ...as above, plus */ address signer,
    bytes signature) external returns (bytes32 contractId);

function signContract(bytes32 contractId, string[] partyValues, bytes signature,
    bool fillUnallocated, string secret) external;
function signContractFor(address signer, bytes32 contractId, string[] partyValues,
    bytes signature, bool fillUnallocated, string secret) external;
function signContractWithEscrow(address escrowSigner, bytes32 contractId,
    string[] partyValues, bytes signature, bool fillUnallocated, string secret)
    external; // onlyDefinedFinalizer

function setDelegation(address delegate, uint256 expiry) external;
function revokeDelegation() external;

function voidContractFor(bytes32 contractId, address party, bytes signature) external;
function finalizeContract(bytes32 contractId) external; // onlyFinalizerIfSet
```

## Views

`getParties`, `hasSigned`, `getSignatureTimestamp`, `allPartiesSigned`,
`getContractDetails`, `getTemplateDetails`, `getSignerValues`, `isVoided`,
`isFinalized`, `getAgreementsForParty`, `getVoidRequestedBy`,
`getContractJson`, `getDelegation`, `isValidDelegation`, `isValidDelegate`.

## How signing works

* `createTemplate` registers a reusable template (id, title, legal URI,
  field schema). Template creation is **permissionless** — anyone can
  register a template, and duplicate ids revert `TemplateAlreadyExists`.
* `createContract` instantiates an executable contract from a template, with
  its global values, parties, and per-party values; `finalizer` and `expiry`
  bound it. Parties left as `address(0)` are open slots a later signer can
  claim with `fillUnallocated` (gated by `secretHash` if set).
* `createStandaloneContractAndSign(For)` prepares, templates (just-in-time,
  if the derived template doesn't exist yet), creates, and signs an
  agreement in one transaction — for single-party agreements that is one
  transaction and done. Standalone contracts always have
  `finalizer = address(0)`.
* Each party signs an EIP-712 `SignatureData` payload (contract id, the
  party's own address as `signer`, legal URI, field schema, global values,
  and their party values) —
  `signContract` (self), `signContractFor` (relayed), or
  `signContractWithEscrow` (a pre-escrowed signature, submittable only by
  the contract's defined finalizer, e.g. a RoundManager holding an
  officer's escrowed signature). `signContract` / `signContractFor` verify
  the signature onchain — and when a finalizer is set, only the finalizer
  or the signer themself may submit. `signContractWithEscrow` does not
  re-verify; it requires a defined finalizer and relies on that (vetted
  contract) finalizer for access control.
* A party may standing-delegate signing to another address
  (`setDelegation` / `revokeDelegation`, with optional expiry): signature
  verification accepts a valid, unexpired delegate's EIP-712 signature in
  place of the party's own. Delegation affects signature recovery only — a
  delegate is not treated as the party itself. The delegate signs with
  `signer` set to the delegating party, so the signature counts for that
  party alone. `setDelegation` reverts `DelegateZeroAddress`,
  `DelegateIsSelf`, or `ExpiryNotInFuture` (a nonzero expiry at or before
  the current block); `expiry == 0` means the delegation does not expire.
  The same delegate check applies to `VoidSignatureData` signatures.
* When all parties have signed, the registry emits `ContractFullySigned`.
  With no finalizer set, the contract auto-finalizes at that point;
  otherwise the finalizer calls `finalizeContract`.
* `voidContractFor` records a party's void request (event `VoidRequested`).
  The contract becomes voided when every **allocated** party has requested
  (unfilled `address(0)` slots in an open agreement cannot request, so they
  don't count toward unanimity — though a party who fills a slot must then
  also request), when its nonzero expiry has passed, or when the proposing
  party (index 0) voids while still the only signer. The finalizer may
  submit void requests without a signature; anyone else needs the party's
  EIP-712 `VoidSignatureData` signature. Finalized contracts cannot be
  voided.

{% hint style="info" %}
`expiry == 0` means **no deadline**, in the void path just as in signing and
finalization: the expired branch never applies, so a zero-expiry agreement
voids only by unanimous request of its allocated parties (or by the
proposer while sole signer).
{% endhint %}

`getContractJson(contractId)` returns the agreement as a JSON string
(template id, title, legal URI, global fields, per-party values with
`signedAt`, signature count, `isComplete`, `voided`, `voidRequestedBy`,
`finalized`). Titles, URIs, field names and values are JSON-escaped, so a
quote or backslash typed into a field cannot break the document.

## Events

`TemplateCreated`, `ContractCreated`, `AgreementSigned`, and
`ContractFullySigned` are declared in `ICyberAgreementRegistry`;
`ContractFinalized`, `VoidRequested`, `ContractVoided`, `DelegationSet`,
and `DelegationRevoked` in the contract. All are emitted by the registry
proxy.
