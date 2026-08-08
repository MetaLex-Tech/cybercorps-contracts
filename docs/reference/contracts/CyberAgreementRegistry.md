# CyberAgreementRegistry

An onchain registry of legal-agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds reference it for their
underlying agreements.

* **Source:** [`src/CyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberAgreementRegistry.sol)
  / interface [`ICyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberAgreementRegistry.sol)
* **Pattern:** UUPS proxy (`Initializable`, `UUPSUpgradeable`,
  `BorgAuthACL`); EIP-712 domain `"CyberAgreementRegistry"` version `"1"`.

## Data model

```solidity
struct Template {
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
```

The `contractId` is `keccak256(abi.encode(templateId, salt, globalValues,
parties, secretHash, finalizer))` — `secretHash` and `finalizer` are
deliberately bound into the id so a front-runner cannot seize the same id
with hostile terms; `expiry` is deliberately **not** bound so presigned
offchain signatures stay verifiable.

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
* Each party signs an EIP-712 `SignatureData` payload (contract id, legal
  URI, field schema, global values, and their party values) —
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
  delegate is not treated as the party itself.
* When all parties have signed, the registry emits `ContractFullySigned`.
  With no finalizer set, the contract auto-finalizes at that point;
  otherwise the finalizer calls `finalizeContract`.
* `voidContractFor` records a party's void request (event `VoidRequested`).
  The contract becomes voided when **all** parties have requested, when it
  has expired, or when the proposing party (index 0) voids while still the
  only signer. The finalizer may submit void requests without a signature;
  anyone else needs the party's EIP-712 `VoidSignatureData` signature.
  Finalized contracts cannot be voided.

## Events

`TemplateCreated`, `ContractCreated`, `AgreementSigned`,
`ContractFullySigned`, `ContractFinalized`, `VoidRequested`,
`ContractVoided`, `DelegationSet`, `DelegationRevoked`.
