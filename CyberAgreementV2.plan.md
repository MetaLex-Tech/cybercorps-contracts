# CyberAgreement Registry V2 Implementation Plan

## Executive Summary

A new standalone CyberAgreement Registry (V2) that replaces string-based values with typed data structures using template contracts. This enables better smart contract integration and produces standalone PDF outputs via Typst templates.

**Key Decisions:**
- Fresh V2 contract (not an upgrade to V1)
- Templates are deployed smart contracts implementing `IAgreementTemplate`
- Data is stored as typed bytes (template-specific structs)
- Frontend integration uses off-chain JSON schemas (Option 2)
- ERC165 interface detection for extensibility
- Party data is merged into `IAgreementTemplate` (not a separate interface)
- Template categorization/indexing handled off-chain (no `templateType()` function)

---

## Architecture Overview

### Core Components

1. **CyberAgreementRegistryV2** - Main registry contract
2. **IAgreementTemplate** - Interface for all templates (includes party data functions)
3. **AgreementTemplateBase** - Abstract base contract providing default party data implementation
4. **Example Templates** - Reference implementations

### Data Flow

```
Template Deployment
├── Deploy template contract
├── Set templateContentUri (points to .typ file + schema.json)
└── Configure closing conditions (optional)

Agreement Creation
├── Frontend fetches schema.json from templateContentUri
├── Renders form based on schema
├── User fills in typed data
├── Frontend encodes data via template.encodeTemplateData()
└── Registry validates and stores agreement

Agreement Signing
├── Party signs EIP-712 hash of agreement data
├── Signature stored on-chain
├── Once all parties signed → auto-finalize or wait for finalizer
└── Closing conditions checked during finalization

PDF Generation (Off-Chain)
├── Fetch template.typ from templateContentUri
├── Call template.getLegalWordingValues() to get string mappings
├── Substitute values into Typst template
└── Generate standalone PDF
```

---

## Interfaces

### IAgreementTemplate

```solidity
interface IAgreementTemplate is IERC165 {
    // Party type and data struct
    enum PartyType { Individual, Company }
    
    struct PartyData {
        string name;
        PartyType partyType;
        string contactDetails;
        string jurisdiction;  // Required if partyType == Company
    }
    
    // URI to .typ file and schema.json (e.g., "ipfs://QmHash/")
    function templateContentUri() external view returns (string memory);
    
    // Encode/decode template-specific data structs to/from bytes
    function encodeTemplateData(bytes memory data) external pure returns (bytes memory);
    function decodeTemplateData(bytes memory data) external pure returns (bytes memory);
    
    // Validate template data before agreement creation
    function validateTemplateData(bytes memory data) external view returns (bool);
    
    // Convert typed data to string key-value pairs for PDF generation
    function getLegalWordingValues(bytes memory data) external view returns (string[] memory keys, string[] memory values);
    
    // Get closing conditions that must pass before finalization
    function getClosingConditions() external view returns (ICondition[] memory);
    
    // Encode/decode party data structs
    function encodePartyData(PartyData memory data) external pure returns (bytes memory);
    function decodePartyData(bytes memory data) external pure returns (PartyData memory);
    
    // Validate party data before agreement signing
    function validatePartyData(PartyData memory data) external view returns (bool);
}
```

**Key Points:**
- Extends `IERC165` for interface detection
- `templateContentUri()` points to directory containing `template.typ` and `schema.json`
- `encodeTemplateData()` includes validation logic
- `getLegalWordingValues()` transforms typed data to human-readable strings
- `getClosingConditions()` returns ICondition contracts checked during finalization
- Party data functions (encodePartyData, decodePartyData, validatePartyData) handle party-specific details

### ICyberAgreementRegistryV2

```solidity
interface ICyberAgreementRegistryV2 {
    // Events
    event AgreementCreated(bytes32 indexed agreementId, address indexed template, address[] parties);
    event AgreementSigned(bytes32 indexed agreementId, address indexed party, uint256 timestamp);
    event AgreementVoided(bytes32 indexed agreementId, address[] voidSigners, uint256 timestamp);
    event AgreementFinalized(bytes32 indexed agreementId, address finalizer, uint256 timestamp);
    event AgreementFullySigned(bytes32 indexed agreementId, uint256 timestamp);
    
    // Create a new agreement
    function createAgreement(
        address template,
        bytes calldata templateData,
        address[] calldata parties,
        bytes[] calldata partyData,  // Array of encoded party data, indexed by party
        address finalizer,
        uint256 expiry
    ) external returns (bytes32 agreementId);
    
    // Sign agreement (for msg.sender)
    function signAgreement(
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external;
    
    // Sign agreement on behalf of another party
    function signAgreementFor(
        address signer,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external;
    
    // Void agreement
    function voidAgreement(
        bytes32 agreementId,
        bytes calldata signature
    ) external;
    
    // Finalize agreement after all signatures and conditions met
    function finalizeAgreement(bytes32 agreementId) external;
    
    // View functions
    function getAgreement(bytes32 agreementId) external view returns (
        address template,
        bytes memory templateData,
        address[] memory parties,
        uint256[] memory signedAt,
        bool isComplete,
        bool finalized,
        bool voided
    );
    
    function getPartyData(bytes32 agreementId, address party) external view returns (bytes memory);
    function getPartySignature(bytes32 agreementId, address party) external view returns (bytes memory);
    function hasSigned(bytes32 agreementId, address party) external view returns (bool);
    function allPartiesSigned(bytes32 agreementId) external view returns (bool);
    function isVoided(bytes32 agreementId) external view returns (bool);
    function isFinalized(bytes32 agreementId) external view returns (bool);
    function getAgreementsForParty(address party) external view returns (bytes32[] memory);
    function getAgreementHash(bytes32 agreementId) external view returns (bytes32);
    function getVoidRequestedBy(bytes32 agreementId) external view returns (address[] memory);
}
```

**Key Changes from V1:**
- No string-based values - all data is bytes (template-specific)
- Template is a contract address, not bytes32 ID
- Party data stored as bytes (template-specific encoding)
- Consistent use of mappings for per-party data
- Simplified - no standalone template creation

---

## Implementation Checklist

### Phase 1: Core Interfaces and Base

- [x] Create `src/interfaces/IAgreementTemplate.sol`
  - [x] Define interface extending IERC165
  - [x] Define PartyType enum (Individual, Company)
  - [x] Define PartyData struct (name, partyType, contactDetails, jurisdiction)
  - [x] Add templateContentUri() function
  - [x] Add encodeTemplateData() / decodeTemplateData() functions
  - [x] Add validateTemplateData() function
  - [x] Add getLegalWordingValues() function
  - [x] Add getClosingConditions() function
  - [x] Add encodePartyData() / decodePartyData() functions
  - [x] Add validatePartyData() function

- [x] Create `src/interfaces/ICyberAgreementRegistryV2.sol`
  - [x] Define all events (AgreementCreated, AgreementSigned, AgreementVoided, AgreementFinalized, AgreementFullySigned)
  - [x] Add createAgreement function
  - [x] Add signAgreement and signAgreementFor functions
  - [x] Add voidAgreement function
  - [x] Add finalizeAgreement function
  - [x] Add all view functions (getAgreement, getPartyData, getPartySignature, hasSigned, allPartiesSigned, isVoided, isFinalized, getAgreementsForParty, getAgreementHash, getVoidRequestedBy)

- [x] Create `src/templates/AgreementTemplateBase.sol`
  - [x] Define abstract contract implementing IAgreementTemplate
  - [x] Import ERC165 and implement supportsInterface()
  - [x] Define state variables (_templateContentUri, _closingConditions)
  - [x] Implement templateContentUri()
  - [x] Implement getClosingConditions()
  - [x] Implement default encodePartyData() / decodePartyData() using abi.encode/decode
  - [x] Implement default validatePartyData() (checks name, contact required; jurisdiction required for Company)
  - [x] Add internal setter functions (_setTemplateContentUri, _addClosingCondition, _removeClosingCondition)
  - [x] Include PartyDataLib helper library
  - [x] Add 40-slot storage gap for upgradeability

### Phase 2: Registry Implementation

- [x] Create `src/CyberAgreementRegistryV2.sol`
  - [x] Import required OpenZeppelin contracts (Initializable, UUPSUpgradeable)
  - [x] Import interfaces (IAgreementTemplate, ICondition)
  - [x] Define contract inheriting from Initializable, UUPSUpgradeable, BorgAuthACL
  - [x] Define EIP-712 domain constants and typehashes
  - [x] Define storage mappings (agreements, agreementsForParty, delegations)
  - [x] Implement initialize() function
  - [x] Implement createAgreement() with template validation via ERC165
  - [x] Implement signAgreement() and signAgreementFor()
    - [x] Add auto-finalization logic when all parties signed AND finalizer == address(0)
    - [x] Check closing conditions before auto-finalizing (skip if any condition fails)
  - [x] Implement voidAgreement()
  - [x] Implement finalizeAgreement() with closing condition checks
  - [x] Implement all view functions
  - [x] Implement EIP-712 hashing functions
  - [x] Implement delegation support
  - [x] Implement _authorizeUpgrade()

### Phase 3: Example Template Implementation

- [x] Create `src/templates/examples/SimpleSaleAgreementTemplate.sol`
  - [x] Define SaleAgreementData struct
  - [x] Inherit from AgreementTemplateBase and UUPSUpgradeable
  - [x] Implement initialize() with auth and content URI
  - [x] Implement encode/decode for SaleAgreementData with validation
  - [x] Implement validateTemplateData()
  - [x] Implement getLegalWordingValues() with conversions
  - [x] Add helper functions (addressToString, uint256ToString, etc.)
  - [x] Implement _authorizeUpgrade()

### Phase 4: Testing

- [ ] Create `test/CyberAgreementRegistryV2/CyberAgreementRegistryV2.t.sol`
  - [ ] Test agreement creation
  - [ ] Test signing with valid/invalid signatures
  - [ ] Test delegation flow
  - [ ] Test voiding
  - [ ] Test finalization with conditions
  - [ ] Test expiry handling

- [ ] Create `test/CyberAgreementRegistryV2/AgreementTemplateBase.t.sol`
  - [ ] Test base template functionality
  - [ ] Test party data encoding/decoding

- [ ] Create `test/CyberAgreementRegistryV2/SimpleSaleAgreementTemplate.t.sol`
  - [ ] Test template initialization
  - [ ] Test data validation
  - [ ] Test legal wording value generation

- [ ] Create `test/CyberAgreementRegistryV2/Integration.t.sol`
  - [ ] Test complete workflow: create, sign, finalize
  - [ ] Test with closing conditions

### Phase 5: Frontend Schema

- [ ] Define JSON Schema format for templates
  ```json
  {
    "fields": [
      {
        "name": "assetAddress",
        "type": "address",
        "label": "Asset Contract Address",
        "description": "The ERC20 or NFT contract address",
        "required": true
      },
      {
        "name": "assetAmount",
        "type": "uint256",
        "label": "Asset Amount",
        "description": "Amount of tokens or NFT ID",
        "required": true
      }
    ],
    "partyFields": [
      {
        "name": "name",
        "type": "string",
        "label": "Full Name",
        "required": true
      },
      {
        "name": "partyType",
        "type": "enum",
        "label": "Party Type",
        "options": ["Individual", "Company"],
        "required": true
      },
      {
        "name": "contactDetails",
        "type": "string",
        "label": "Contact Information",
        "required": true
      },
      {
        "name": "jurisdiction",
        "type": "string",
        "label": "Jurisdiction",
        "required": false,
        "conditional": "partyType === 'Company'"
      }
    ]
  }
  ```

- [ ] Document schema.json location convention (same base URI as template.typ)
- [ ] Create TypeScript types for schema structure

### Phase 6: Deployment Scripts

- [ ] Create `script/DeployCyberAgreementV2.s.sol`
  - [ ] Deploy CyberAgreementRegistryV2 implementation
  - [ ] Deploy and initialize ERC1967Proxy
  - [ ] Deploy SimpleSaleAgreementTemplate
  - [ ] Initialize template with auth and content URI
  - [ ] Log deployed addresses

---

## Key Implementation Details

### EIP-712 Domain and Types

```solidity
// Domain separator
bytes32 public DOMAIN_SEPARATOR = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256(bytes("CyberAgreementRegistryV2")),
    keccak256(bytes("1")),
    block.chainid,
    address(this)
));

// Agreement signature typehash
bytes32 public AGREEMENT_TYPEHASH = keccak256(
    "AgreementSignatureData(bytes32 agreementId,address template,bytes templateData,address[] parties,bytes[] partyData)"
);

// Void signature typehash
bytes32 public VOID_TYPEHASH = keccak256(
    "VoidSignatureData(bytes32 agreementId,address party)"
);

struct AgreementSignatureData {
    bytes32 agreementId;
    address template;
    bytes templateData;
    address[] parties;
    bytes[] partyData;
}

struct VoidSignatureData {
    bytes32 agreementId;
    address party;
}
```

### Agreement ID Generation

```solidity
function _generateAgreementId(
    address template,
    bytes memory templateData,
    address[] memory parties,
    uint256 salt
) internal pure returns (bytes32) {
    return keccak256(abi.encode(template, templateData, parties, salt));
}
```

Use salt parameter to allow identical agreements with different IDs.

### Auto-Finalization Flow

When all parties have signed:

```solidity
function signAgreement(...) external {
    // ... signature verification and storage ...
    
    if (allPartiesSigned(agreementId)) {
        emit AgreementFullySigned(agreementId, block.timestamp);
        
        // Auto-finalize if no finalizer is set AND closing conditions pass (or none exist)
        if (agreement.finalizer == address(0)) {
            IAgreementTemplate template = IAgreementTemplate(agreement.template);
            ICondition[] memory conditions = template.getClosingConditions();
            
            bool conditionsPass = true;
            for (uint256 i = 0; i < conditions.length; i++) {
                if (!conditions[i].checkCondition(address(this), this.finalizeAgreement.selector, abi.encode(agreementId))) {
                    conditionsPass = false;
                    break;
                }
            }
            
            if (conditionsPass) {
                agreement.finalized = true;
                emit AgreementFinalized(agreementId, msg.sender, block.timestamp);
            }
            // If conditions don't pass, agreement remains fully signed but not finalized
            // Caller must manually call finalizeAgreement() later when conditions pass
        }
    }
}
```

**Key Points:**
- Auto-finalization only occurs when `finalizer == address(0)`
- If template has closing conditions, they must ALL pass for auto-finalization
- If conditions don't pass during auto-finalization, emit `AgreementFullySigned` but NOT `AgreementFinalized`
- Anyone can call `finalizeAgreement()` later to check conditions and finalize

### Closing Conditions Flow

```solidity
function finalizeAgreement(bytes32 agreementId) public {
    Agreement storage agreement = agreements[agreementId];
    
    // ... validation checks ...
    
    // Check closing conditions
    IAgreementTemplate template = IAgreementTemplate(agreement.template);
    ICondition[] memory conditions = template.getClosingConditions();
    
    for (uint256 i = 0; i < conditions.length; i++) {
        require(
            conditions[i].checkCondition(
                address(this), 
                this.finalizeAgreement.selector, 
                abi.encode(agreementId)
            ),
            "Closing condition not met"
        );
    }
    
    agreement.finalized = true;
    emit AgreementFinalized(agreementId, msg.sender, block.timestamp);
}
```

### Delegation Support

```solidity
struct Delegation {
    address delegate;
    uint256 expiry;
}

mapping(address => Delegation) public delegations;

function _isValidDelegation(address delegator, address delegate) internal view returns (bool) {
    Delegation storage delegation = delegations[delegator];
    return delegation.delegate == delegate && 
           (delegation.expiry == 0 || delegation.expiry > block.timestamp);
}
```

Checked in signature verification - recovered signer can be either the party or their valid delegate.

---

## Things to Be Aware Of

### Security Considerations

1. **Template Validation**
   - Always verify template implements IAgreementTemplate via ERC165 before creating agreement
   - Reject templates that don't support the required interface

2. **Signature Verification**
   - Use EIP-712 for all signatures to prevent replay attacks
   - Verify domain separator matches current chain/contract
   - Check for delegation in signature recovery

3. **Reentrancy**
   - Closing conditions are external calls during finalizeAgreement()
   - Use Checks-Effects-Interactions pattern
   - Consider adding reentrancy guard if conditions could callback

4. **Data Validation**
   - Template's validateTemplateData() should be called before storing
   - Don't trust template data - validate everything
   - Party data should also be validated by template if applicable

### Gas Considerations

1. **Storage Layout**
   - Agreement struct uses mappings which are efficient
   - Keep party arrays small (agreements with many parties are rare)
   - Consider max party limit if gas becomes issue

2. **Signature Verification**
   - ECDSA recovery is gas-intensive but necessary
   - Consider batch signing in future versions

3. **Closing Conditions**
   - Each condition is an external call
   - Limit number of conditions or cache results

### Upgrade Considerations

1. **Storage Gaps**
   - Leave adequate __gap in all upgradeable contracts
   - Follow existing pattern from V1 (40 slots)

2. **Interface Changes**
   - ICyberAgreementRegistryV2 is fixed for this version
   - Future changes require V3 or interface extensions

3. **Template Compatibility**
   - Templates are separate upgradeable contracts
   - Template upgrades don't affect existing agreements
   - Agreement stores template address at creation time

### Integration Considerations

1. **Off-Chain Dependencies**
   - Frontend relies on templateContentUri being accessible
   - IPFS pinning or reliable HTTP hosting required
   - Schema.json must match template's expected data structure

2. **PDF Generation**
   - Entirely off-chain process
   - Requires Typst compiler
   - Consider documenting recommended infrastructure

3. **Type Safety**
   - TypeScript types should be generated from Solidity structs
   - Encode/decode must match exactly between frontend and template
   - Consider using viem's encodeAbiParameters for encoding

### Migration from V1

- V1 and V2 will run in parallel
- No migration path for existing V1 agreements
- Frontend should support both registries during transition
- Consider V1 deprecation timeline

---

## Success Criteria

1. ✅ Agreement creation with typed template data
2. ✅ EIP-712 signature verification for all parties
3. ✅ Closing conditions checked during finalization
4. ✅ Delegation support for signing
5. ✅ Voiding with multi-party or proposer-only flow
6. ✅ Template validation via ERC165
7. ✅ PDF generation values available via getLegalWordingValues()
8. ✅ Frontend can dynamically render forms from schema.json
9. ✅ Comprehensive test coverage (>90%)
10. ✅ Deployment scripts ready for mainnet

---

## Timeline Estimate

- Phase 1 (Interfaces and Base): 1 day
- Phase 2 (Registry): 3 days
- Phase 3 (Example Template): 1 day
- Phase 4 (Testing): 3 days
- Phase 5 (Frontend Schema): 1 day
- Phase 6 (Deployment): 1 day

**Total: ~10 days**

---

## Next Steps

1. ✅ Phase 1 complete (interfaces and base contract created)
2. ✅ Phase 2 complete (registry implementation)
3. ✅ Phase 3 complete (example template implementation)
4. Begin Phase 4: Testing
5. Create parallel tracking issue for frontend development
6. Schedule architecture review after testing
7. Set up testnet deployment for integration testing
