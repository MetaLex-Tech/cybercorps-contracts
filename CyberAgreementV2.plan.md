# CyberAgreement Registry V2 Implementation Plan

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

## Amendment and Patch System

### Overview

V2 supports a flexible amendment system using git-style patches that allows templates to be based on other templates and agreements to be modified through mutual consent before finalization.

### Template Composition

Templates are composed of layered components:

1. **Styling** (.typ) - Visual formatting (defaults to MetaLeX style)
2. **Base Wording** (.typ) - The foundational legal text
3. **Template Patches** (array of .typ patch URIs) - Modifications applied to the base
4. **System Inputs** - Data from template and party fields

#### Template Inheritance

- Templates can be based on existing templates (e.g., "YC SAFE with modifications")
- Inheritance is metadata-only: stored in ARWeave metadata, not on-chain
- Template B referencing Template A's base would have Template A's patches applied first, then Template B's patches
- To patch an existing template, deploy a new template contract with the patch array

#### Patch Format

- Patches use git unified diff format
- Stored as separate ARWeave transactions
- Applied sequentially: Base + Patch 1 + Patch 2 + ...
- Each patch applies to the result of all previous patches
- No on-chain verification of patch validity (social/trust-based)

### Agreement Amendments

Agreements support dynamic amendments before finalization:

1. **Agreement Patch Array** - Additional patches specific to this agreement instance
2. **Application Order**: Base > Template Patches > Agreement Patches
3. **Pending Changes Tracking** - Modifications proposed but not yet agreed to

#### Amendment Flow

```
Agreement Creation
├── Base template content loaded from templateContentUri
├── Template patches applied (if any)
└── Initial agreementPatchUris array is empty

Amendment Proposal
├── Party proposes: new patch URIs and/or templateData changes
├── Proposal stored as PendingChange
├── All existing signatures nullified
└── Agreement status becomes "pending_changes"

Amendment Acceptance
├── Other parties review proposed changes
├── Each party can accept the amendment
└── Once all parties accept: apply changes, reset signatures

Amendment Rejection
├── If any party rejects: proposal discarded
└── Agreement returns to previous state
```

### Smart Contract Storage

#### Enhanced Agreement Structure

```solidity
enum AgreementStatus { 
    Draft,           // Created, not all parties signed
    PendingChanges,  // Amendment proposed, awaiting acceptance
    FullySigned,     // All parties signed, awaiting finalization
    Finalized,       // Complete
    Voided           // Agreement voided by parties
}

struct Agreement {
    address template;
    bytes templateData;
    bytes[] partyData;            // Per-party data, indexed by parties array
    string[] agreementPatchUris;  // Agreement-specific patches
    address[] parties;
    bytes[] signatures;
    AgreementStatus status;
    uint256 expiry;
    address finalizer;
}

struct PendingChange {
    bytes32 agreementId;
    string[] newPatchUris;      // Proposed patches to add
    bytes proposedTemplateData; // Optional: new template data
    address proposer;
    uint256 proposedAt;
    mapping(address => bool) acceptedBy;
    uint256 acceptances;
}

mapping(bytes32 => Agreement) public agreements;
mapping(bytes32 => PendingChange) public pendingChanges;
```

#### Key Behaviors

1. **Modification Nullifies Signatures**: Any change to agreement data (patches or templateData) clears all signatures and returns status to Draft/PendingChanges
2. **Mutual Consent Required**: All parties must accept pending changes before application
3. **Rejection**: If any party rejects, the pending change is discarded
4. **Template Data Mutable**: Can be modified until agreement is finalized
5. **Multiple Amendments**: Parties can propose multiple sequential amendments

### Interface Additions

```solidity
// Propose an amendment to the agreement
function proposeAmendment(
    bytes32 agreementId,
    string[] calldata newPatchUris,
    bytes calldata newTemplateData
) external;

// Accept a proposed amendment
function acceptAmendment(bytes32 agreementId) external;

// Reject a proposed amendment
function rejectAmendment(bytes32 agreementId) external;

// View pending changes
function getPendingChange(bytes32 agreementId) external view returns (
    string[] memory patchUris,
    bytes memory templateData,
    address proposer,
    uint256 acceptances,
    bool hasAccepted
);

// Events
event AmendmentProposed(
    bytes32 indexed agreementId,
    address indexed proposer,
    string[] patchUris
);
event AmendmentAccepted(bytes32 indexed agreementId, address indexed acceptor);
event AmendmentRejected(bytes32 indexed agreementId, address indexed rejector);
event AmendmentApplied(bytes32 indexed agreementId);
event SignaturesCleared(bytes32 indexed agreementId);
```

### ARWeave Storage Structure

**TBD: Final directory structure and file naming conventions to be determined.**

Templates should follow a directory structure:

```
template-content-uri/
├── template.typ          # Base legal wording
├── template.patches.json # Array of patch URIs (optional)
├── schema.json           # Frontend form schema
├── metadata.json         # 
│   ├── basedOn           # Reference to parent template (if any)
│   ├── version
│   └── description
└── style.typ             # MetaLeX styling (optional)
```

Patches are stored as separate ARWeave transactions containing the unified diff content.

### PDF Generation with Patches

Off-chain rendering process:

1. Fetch base `template.typ` from template's `templateContentUri`
2. Fetch and apply each template patch in order
3. Fetch and apply each agreement patch in order
4. Fetch styling file (or use default)
5. Call `template.getLegalWordingValues()` to get populated values
6. Substitute values and generate PDF

### Considerations

**Patch Conflicts**
- No automatic conflict resolution
- If patches conflict, renderer fails gracefully
- Social coordination required for complex modifications

**Gas Optimization**
- Store only patch URIs on-chain, not content
- Content is immutable on ARWeave
- No verification hashes stored (trust ARWeave permanence)

**Version History**
- Full history preserved via patch chain
- Each amendment adds to agreementPatchUris array
- Previous states can be reconstructed by rendering with fewer patches

**Template Inheritance Chains**
- Can become deep if templates are based on templates based on templates
- Off-chain resolution required to trace full inheritance
- Consider caching resolved content for performance

## Next Steps

1. ✅ Phase 1 complete (interfaces and base contract created)
2. ✅ Phase 2 complete (registry implementation)
3. ✅ Phase 3 complete (example template implementation)
4. Update interfaces and contracts to support amendment system
5. Begin Phase 4: Testing (include amendment flow tests)
6. Create parallel tracking issue for frontend development
7. Schedule architecture review after testing
8. Set up testnet deployment for integration testing
