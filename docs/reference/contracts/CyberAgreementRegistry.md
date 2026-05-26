# CyberAgreementRegistry

An onchain registry of legal-agreement **templates** and executed,
multi-party-signed **contracts**. Deals and rounds reference it for their
underlying agreements.

* **Source:** [`src/CyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberAgreementRegistry.sol)
  / interface [`ICyberAgreementRegistry.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ICyberAgreementRegistry.sol)

## Data model

```solidity
struct Template {
    string legalContractUri;   // canonical legal text
    string title;
    string[] globalFields;     // field names common to the whole contract
    string[] partyFields;      // field names filled per signing party
}

struct ContractData {
    bytes32 templateId;
    string[] globalValues;
    address[] parties;
    uint256 numSignatures;
    bytes32 transactionHash;
}
```

## Functions

```solidity
function createTemplate(bytes32 templateId, string title, string legalContractUri,
    string[] globalFields, string[] partyFields) external;

function createContract(bytes32 templateId, uint256 salt, string[] globalValues,
    address[] parties, string[][] partyValues, bytes32 secretHash,
    address finalizer, uint256 expiry) external returns (bytes32 contractId);

function signContract(bytes32 contractId, string[] partyValues,
    bool fillUnallocated, string secret) external;
function signContractFor(address signer, bytes32 contractId, string[] partyValues,
    bytes signature, bool fillUnallocated, string secret) external;
function signContractWithEscrow(address escrowSigner, bytes32 contractId,
    string[] partyValues, bytes signature, bool fillUnallocated, string secret) external;

function voidContractFor(bytes32 contractId, address party, bytes signature) external;
function finalizeContract(bytes32 contractId) external;
```

## Views

`getParties`, `hasSigned`, `getSignatureTimestamp`, `allPartiesSigned`,
`getContractDetails`, `getTemplateDetails`, `getSignerValues`, `isVoided`,
`getAgreementsForParty`, `getContractJson`, `getContractTransactionHash`,
`isFinalized`, `allPartiesFinalized`.

## How signing works

* `createTemplate` registers a reusable template (id, title, legal URI,
  field schema).
* `createContract` instantiates an executable contract from a template, with
  its global values, parties, and per-party values; `finalizer` and `expiry`
  bound it.
* Each party signs — `signContract` (self), `signContractFor` (relayed with
  an EIP-712 signature), or `signContractWithEscrow` (using a pre-escrowed
  signature). `fillUnallocated` lets a signer occupy an empty party slot.
* When all parties have signed, the registry emits `ContractFullySigned`;
  `finalizeContract` completes it.

## Events

`TemplateCreated`, `ContractCreated`, `AgreementSigned`,
`ContractFullySigned`.
