# CyberAgreement V2 Template Specification

## Overview

Agreement templates define the structure and validation of agreement data for PDF generation via Typst. The system supports **two template types** with a unified interface:

### Template Types

**1. Smart Contract Templates**
- Solidity contracts implementing `IAgreementTemplate`
- Store template data on-chain (ABI-encoded bytes)
- Can read blockchain state and compute derived values
- (Optional) Validation logic on-chain
- **BEST WHEN** the agreement needs to be integrated with other smart contracts, where the behaviour will depend on the terms of the agreement (for example, a vesting schedule)

**2. Basic Templates (Arweave-Only)**
- No Solidity contract required
- Template data stored on Arweave
- Lighter weight for simple agreements without on-chain computation needs
- Lower deployment cost and complexity
- **BEST WHEN** the agreement is a standalone legal document whose smart contract integration is either not required, or limited to just a "signed" or "not signed" approach.

Both types share the same registry interface and produce the same output format for PDF generation.

### Template Components

All templates consist of:
- A `template.json` metadata file (stored on Arweave) - defines input/output schema
- A Typst file for PDF generation (stored on Arweave) - defines document layout. 
- **Smart Contract Templates only**: A Solidity contract implementing `IAgreementTemplate`

## Architecture (smart contract templates)

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Encode Input │  │ Call         │  │ Decode Output        │   │
│  │ (using ABI)  │→ │ getWording   │→ │ (using ABI)          │   │
│  └──────────────┘  │ Values       │  └──────────────────────┘   │
│                    └──────────────┘                             │
│                           ↓                                     │
│             Arweave (template.json, template.typ)               │
└─────────────────────────────────────────────────────────────────┘
                                    ↓
┌────────────────────────────────────────────────────────────────┐
│                     SMART CONTRACT                             │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              IAgreementTemplate                        │    │
│  │  ┌─────────────┐  ┌───────────────┐  ┌──────────────┐  │    │
│  │  │ Decode Input│  │ Read Chain    │  │ Encode Output│  │    │
│  │  │ Struct      │→ │ State         │→ │ Struct       │  │    │
│  │  └─────────────┘  └───────────────┘  └──────────────┘  │    │
│  └────────────────────────────────────────────────────────┘    │
│                           ↓                                    │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              Agreement Registry                        │    │
│  │  Stores: template address + templateData (bytes)       │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────┘
```

## Interface

### IAgreementTemplate

```solidity
interface IAgreementTemplate is IERC165 {
    /// @notice Returns Arweave transaction ID containing template.json and template.typ
    /// @return Arweave URI in format "ar://<transaction-id>"
    function contentUri() external view returns (string memory);
    
    /// @notice Returns computed wording values by reading blockchain state
    /// @param templateData ABI-encoded template input struct
    /// @return ABI-encoded output struct with values for PDF generation
    function getWordingValues(bytes memory templateData) external view returns (bytes memory);
    
    /// @notice Returns conditions that must pass before agreement can be finalized
    /// @return Array of condition contract addresses
    function getClosingConditions() external view returns (address[] memory);
    
    /// @notice Optionally validates template data (OPTIONAL - returns true if not implemented)
    /// @param templateData ABI-encoded template input struct  
    /// @return true if valid, false otherwise
    function validate(bytes memory templateData) external view returns (bool);
}
```

**Convention: ABI Type Exposure**

The interface uses `bytes memory` for flexibility, which means struct types don't automatically appear in the ABI. Templates MUST implement two additional functions to expose their types for tooling:

```solidity
/// @notice Decodes template data to expose input struct type in ABI
/// @param templateData ABI-encoded input struct
/// @return Decoded input struct
function decodeTemplateData(bytes memory templateData) 
    external 
    view 
    returns (InputStruct memory);

/// @notice Returns output struct to expose type in ABI  
/// @return Output struct (may be empty/default - only for type info)
function getOutputStruct() 
    external 
    view 
    returns (OutputStruct memory);
```

These functions are used by:
- **Deployment scripts** to extract struct definitions and generate template.json
- **Frontends** to understand how to encode/decode data for the template

The registry continues to store raw `bytes` and calls `getWordingValues(bytes)`.

## Agreement Registry Structure

The registry uses a **unified Agreement struct** that supports both Smart Contract and Basic templates:

```solidity
struct Agreement {
    address template;           // Smart contract address OR address(0) for basic
    string templateUri;         // URI to template.json (e.g., "ar://<txid>" or "ipfs://<hash>")
    bytes templateData;         // ABI-encoded struct (smart) OR Arweave TXID (basic)
    address[] parties;
    mapping(address => bytes) partyData; // ABI-encoded struct (smart) OR Arweave TXID (basic)
    mapping(address => uint256) signedAt;
    mapping(address => ICyberAgreementRegistryV2.SignatureInfo) signatureInfo;
    address finalizer;
    bool finalized;
    bool voided;
    uint256 expiry;
    mapping(address => bool) voidRequestedBy;
    uint256 voidRequestCount;
    uint256 salt;
    string[] agreementPatchUris;
    ICyberAgreementRegistryV2.AgreementStatus status;
}
```

### Discrimination Logic

**Check `template` field:**
- `template != address(0)` → **Smart Contract Template**
  - Use `templateUri` field (should match `template.contentUri()`)
  - Call `IAgreementTemplate(template).getWordingValues(templateData)` for values
  - `templateData` contains ABI-encoded input struct
  - `partyData[address]` contains ABI-encoded party struct
  
- `template == address(0)` → **Basic Template**
  - Use `templateUri` field directly (points to template.json)
  - `templateData` contains Arweave TXID of agreement instance data
  - `partyData[address]` contains Arweave TXID of party instance data
  - Load agreement and party values directly from Arweave (no on-chain computation)

### Template URI Resolution

**Smart Contract Templates:**
```
template.json location = agreement.templateUri  // Should match template.contentUri()
template.typ location = from template.json "typst.base" field
```

**Basic Templates:**
```
template.json location = agreement.templateUri  // e.g., "ar://<txid>" or "ipfs://<hash>"
template.typ location = from template.json "typst.base" field
```

Both template types store `template.json` with the same schema, enabling shared tooling and frontends. The `templateUri` field supports multiple storage protocols (Arweave, IPFS, etc.).

### ICondition

```solidity
interface ICondition {
    /// @notice Check if condition is satisfied for an agreement
    /// @param agreementId The unique identifier of the agreement
    /// @return true if condition passes
    function check(bytes32 agreementId) external view returns (bool);
}
```

## Basic Templates (Arweave-Only)

Basic templates are the simplest form of agreement template, requiring no Solidity contract deployment.

### When to Use Basic Templates

- Simple agreements without on-chain data requirements
- Static legal documents with just party information and dates
- Lower deployment cost is priority
- No need for on-chain validation or conditions
- Agreements that don't reference blockchain state

### Basic Template Structure

**template.json (stored on Arweave):**
```json
{
  "$schema": "https://cyberagreement.io/schemas/template/1.0.0/template.json",
  "name": "Simple NDA",
  "version": "1.0.0",
  "contentUri": "ar://BASE_TEMPLATE_TXID",
  "agreementType": "simple",
  "contractFields": [
    {
      "name": "effectiveDate",
      "type": "date",
      "description": "The date the agreement becomes effective."
    }
  ],
  "partyFields": [
    "name",
    "contactDetails",
    "role",
    {
      "name": "alias",
      "type": "string",
      "description": "The alias of this party"
    }
  ],
  "typst": {
    "base": "ar://TEMPLATE_TYP_TXID"
  },
  "files": {
    "template": "template.typ",
    "schema": "template.json"
  }
}
```

**Agreement Data (stored separately on Arweave):**

Agreement data on arweave is split into several parts:

1. Values of the fields for the whole agreement
2. Values of the fields for each party

#### For the agreement:

 ```json
{
  "chainId": 84532, // chainId of agreement
  "registryAddress": "0x...", // address of CyberAgreementRegistryV2 
  "agreementId": "0x...", // agreement id
  "contractFields": { // the actual values for this party
    "effectiveDate": 1735689600,
    // ..etc 
  }
}
```

#### For each party:

 ```json
{
  "chainId": 84532, // chainId of agreement
  "registryAddress": "0x...", // address of CyberAgreementRegistryV2 
  "agreementId": "0x...", // agreement id
  "partyAddress": "0x...", // address of party
  "partyFields": { // the actual values for this party
    "name": "John Doe",
    "alias": "Corp A",
    // ..etc 
  }
}
```

### Agreement Creation Flow (Basic)

1. **Upload base template** to Arweave (template.json + template.typ) → Get BASE_TXID
2. **Proposing User fills form** based on contractFields
3. **Upload agreement instance** to Arweave (filled values) → Get INSTANCE_TXID
4. **Each party fills** their partyFields and uploads to Arweave → Get PARTY_TXID
5. **Call registry** with template = address(0), templateUri = "ar://BASE_TXID", templateData = abi.encode("ar://INSTANCE_TXID"), and partyData = abi.encode("ar://PARTY_TXID") for each party
6. **Registry stores** the references (no on-chain validation)

### Content URI Pattern for Basic Templates

For basic templates, the Arweave structure supports shared base templates:

```
ar://BASE_TEMPLATE_TXID/template.json   # Schema definition
ar://BASE_TEMPLATE_TXID/template.typ    # Shared layout
ar://INSTANCE_TXID/agreement.json       # Instance-specific data
ar://INSTANCE_TXID/party.json           # Party-specific data
```

This allows multiple agreements to reuse the same base template (e.g., all NDAs use the same layout, different values).

## Smart Contract Templates

Smart contract templates provide full on-chain computation and validation capabilities.

### When to Use Smart Contract Templates

- Agreements referencing on-chain data (token balances, prices, etc.)
- Complex validation logic required
- Integration with other smart contracts
- Conditional logic or time-based checks
- Need for `ICondition` implementations

## Contract Structure

### Minimal Template Example

```solidity
pragma solidity 0.8.28;

import {IAgreementTemplate} from "./IAgreementTemplate.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TokenSwapTemplate is IAgreementTemplate {
    // Immutable state
    string public contentUri;
    address[] public closingConditions;
    
    // Template-specific input struct
    struct SwapInput {
        address tokenAddress;
        uint256 amount;
        address recipient;
    }
    
    // Template-specific output struct
    struct SwapOutput {
        address tokenAddress;
        string tokenName;
        string tokenSymbol;
        uint8 decimals;
        uint256 rawAmount;
        string formattedAmount;
    }
    
    // Optional: Template-specific party data struct
    struct PartyData {
        string name;
        string contact;
        bool isCompany;
    }
    
    constructor(string memory _contentUri, address[] memory _conditions) {
        contentUri = _contentUri;
        closingConditions = _conditions;
    }
    
    function getWordingValues(bytes memory templateData) 
        external 
        view 
        returns (bytes memory) 
    {
        // 1. Decode input
        SwapInput memory input = abi.decode(templateData, (SwapInput));
        
        // 2. Read on-chain state
        IERC20Metadata token = IERC20Metadata(input.tokenAddress);
        
        // 3. Compute derived values
        string memory formatted = formatWithDecimals(input.amount, token.decimals());
        
        // 4. Encode and return output
        SwapOutput memory output = SwapOutput({
            tokenAddress: input.tokenAddress,
            tokenName: token.name(),
            tokenSymbol: token.symbol(),
            decimals: token.decimals(),
            rawAmount: input.amount,
            formattedAmount: formatted
        });
        
        return abi.encode(output);
    }
    
    function validate(bytes memory templateData) 
        external 
        view 
        returns (bool) 
    {
        try this.getWordingValues(templateData) returns (bytes memory) {
            SwapInput memory input = abi.decode(templateData, (SwapInput));
            return input.tokenAddress != address(0) && input.amount > 0;
        } catch {
            return false;
        }
    }
    
    function getClosingConditions() external view returns (address[] memory) {
        return closingConditions;
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAgreementTemplate).interfaceId 
            || interfaceId == type(IERC165).interfaceId;
    }

    // Convention: Expose input struct type via decode function
    function decodeTemplateData(bytes memory templateData) 
        external 
        pure 
        returns (SwapInput memory) 
    {
        return abi.decode(templateData, (SwapInput));
    }

    // Convention: Expose output struct type via getter
    function getOutputStruct() external pure returns (SwapOutput memory) {
        SwapOutput memory output;
        return output;
    }
}
```

## template.json Schema

Schema files are versioned via the $id URL path (e.g., `https://cyberagreement.io/schemas/template/1.0.0/template.json`). The schema uses conditional validation to support both Smart Contract and Simple templates with a unified interface.

### Schema Location

Schemas are organized by version in the `schema/` directory:
- `schema/1.0.0/template.json` - Main template schema
- `schema/1.0.0/agreement-data.json` - Agreement data schema for simple templates
- `schema/1.0.0/party-data.json` - Party data schema for simple templates

### Common Fields (All Templates)

All templates share these common fields:

```json
{
  "$schema": "https://cyberagreement.io/schemas/template/1.0.0/template.json",
  "name": "Template Name",
  "version": "1.0.0",
  "contentUri": "ar://TXID",
  "agreementType": "smart|simple",
  "typst": {
    "base": "ar://TXID or ./path",
    "style": "ar://TXID or ./path",
    "patch": "ar://TXID or ./path"
  },
  "files": {
    "template": "template.typ",
    "schema": "template.json",
    "styling": "style.typ"
  }
}
```

**Required Fields:**
- `name` - Human-readable template name
- `version` - Semantic version (e.g., "1.0.0")
- `contentUri` - URI to template content (ar://TXID or ipfs://hash)
- `agreementType` - Either "smart" or "simple"
- `typst.base` - Path to base template file

### Smart Contract Templates

When `agreementType` is "smart", these additional fields are required:

```json
{
  "agreementType": "smart",
  "inputStruct": {
    "name": "InputStructName",
    "type": "tuple",
    "components": [
      {"name": "fieldName", "type": "address"}
    ]
  },
  "outputStruct": {
    "name": "OutputStructName",
    "type": "tuple",
    "components": [
      {"name": "fieldName", "type": "string", "description": "Field description"}
    ]
  },
  "partyDataStruct": {
    "name": "PartyDataStructName",
    "type": "tuple",
    "components": [
      {"name": "fieldName", "type": "string", "required": true}
    ]
  }
}
```

### Simple Templates

When `agreementType` is "simple", these additional fields are required:

```json
{
  "agreementType": "simple",
  "contractFields": [
    {
      "name": "effectiveDate",
      "type": "date",
      "description": "When the agreement becomes effective",
      "required": true
    }
  ],
  "partyFields": [
    "name",
    "contactDetails",
    "role",
    {
      "name": "customField",
      "type": "string",
      "description": "Custom party field"
    }
  ]
}
```

**Preset Party Field Shorthands:**
- `name` - Full legal name of the party
- `contactDetails` - Contact information for the party
- `role` - Role of the party in the agreement
- `entityType` - Type of legal entity (individual, company, dao, trust, partnership)
- `jurisdiction` - Legal jurisdiction of the party
- `walletAddress` - Primary wallet address for blockchain interactions
- `signingAuthority` - Name and title of person authorized to sign
- `taxId` - Tax identification number

Custom field objects can be mixed with preset shorthands in the `partyFields` array.

### Supported Field Types

For simple templates, the following types are supported:
- `string` - Text value
- `number` - Numeric value
- `boolean` - True/false value
- `date` - Date value (stored as Unix timestamp)
- `address` - Ethereum address
- `bytes32` - 32-byte value
- `uint256` - Unsigned 256-bit integer
- `int256` - Signed 256-bit integer
- `bytes` - Variable-length byte array

## Example: Smart Contract Template

```json
{
  "$schema": "https://cyberagreement.io/schemas/template/1.0.0/template.json",
  "name": "ERC20 Token Swap Agreement",
  "description": "Agreement for swapping ERC20 tokens with on-chain metadata resolution",
  "version": "1.0.0",
  "contentUri": "ar://AQJd3Lh...",
  "agreementType": "smart",
  "inputStruct": {
    "name": "SwapInput",
    "type": "tuple",
    "components": [
      {"name": "tokenAddress", "type": "address"},
      {"name": "amount", "type": "uint256"},
      {"name": "recipient", "type": "address"}
    ]
  },
  "outputStruct": {
    "name": "SwapOutput",
    "type": "tuple",
    "components": [
      {"name": "tokenAddress", "type": "address", "description": "Token contract address"},
      {"name": "tokenName", "type": "string", "description": "Human-readable token name"},
      {"name": "tokenSymbol", "type": "string", "description": "Token symbol"},
      {"name": "decimals", "type": "uint8", "description": "Token decimals"},
      {"name": "rawAmount", "type": "uint256", "description": "Amount in base units"},
      {"name": "formattedAmount", "type": "string", "description": "Amount formatted with decimals"}
    ]
  },
  "partyDataStruct": {
    "name": "PartyData",
    "type": "tuple",
    "components": [
      {"name": "name", "type": "string", "required": true},
      {"name": "contact", "type": "string", "required": true},
      {"name": "isCompany", "type": "bool", "required": false}
    ]
  },
  "typst": {
    "base": "./template.typ"
  },
  "files": {
    "template": "template.typ",
    "schema": "template.json"
  }
}
```

## Data Flow

### Creating an Agreement

**For Smart Contract Templates:**
1. **Frontend** loads template.json from Arweave (via `template.contentUri()`)
2. **User** fills form fields defined by `inputStruct`
3. **Frontend** encodes form data using `inputStruct` ABI → `bytes memory templateData`
4. **Frontend** (optional) calls `template.validate(templateData)` to pre-check
5. **Frontend** calls `registry.createAgreement(template, templateUri, templateData, parties, ...)`
6. **Registry** stores: template address + templateUri + templateData bytes + party signatures

**For Basic Templates:**
1. **Frontend** loads template.json from Arweave using `templateUri`
2. **User** fills form fields defined by `contractFields`
3. **Frontend** stores form data as JSON on Arweave → receives TXID
4. **Frontend** calls `registry.createAgreement(address(0), templateUri, abi.encode(TXID), parties, ...)`
5. **Registry** stores: address(0) + templateUri + TXID bytes + party signatures

### Generating PDF

**For Smart Contract Templates:**
1. **Frontend** retrieves agreement from registry
2. **Frontend** calls `template.getWordingValues(agreement.templateData)`
3. **Contract** decodes input, reads chain state, encodes output
4. **Frontend** decodes response using `outputStruct` ABI
5. **Frontend** combines values with typst base file (from `typst.base`) from Arweave
6. **Typst** generates PDF with embedded values

**For Basic Templates:**
1. **Frontend** retrieves agreement from registry
2. **Frontend** decodes `templateData` to get Arweave TXID
3. **Frontend** loads agreement values directly from Arweave (JSON data)
4. **Frontend** combines values with typst base file (from `typst.base`) from Arweave
5. **Typst** generates PDF with embedded values

Optionally, if `typst.style` or `typst.patch` are defined, they can be applied to customize the output for both template types.

## Design Principles

1. **Unified Interface**: Single registry supports both Smart Contract and Basic templates via discrimination
2. **Minimal Interface**: Core functionality in 4 interface functions (Smart Contract) or zero (Basic)
3. **Immutable**: Templates are deployed once and never upgraded
4. **Self-Describing**: All metadata in template.json on Arweave for both types
5. **Flexible**: Each template defines its own input/output/party structs
6. **Optional Validation**: Smart contract templates may implement validation; Basic templates rely on frontend
7. **Progressive Enhancement**: Start with Basic, upgrade to Smart Contract when on-chain logic needed
8. **Gas Efficient**: No unnecessary encoding/decoding, direct struct ABI encoding (Smart Contract)
9. **ABI Convention**: Struct types exposed via convention functions (Smart Contract templates only)

## Deployment Workflow

### For Basic Template Developers

1. **Write template.json**: Define input/output schema and metadata (no Solidity)
2. **Write template.typ**: Create Typst layout for PDF generation
3. **Upload to Arweave**: template.json + template.typ → Get `BASE_TXID`
4. **Reuse**: Each agreement instance references `BASE_TXID` for the layout

### For Smart Contract Template Developers

1. **Develop**: Write Solidity contract implementing `IAgreementTemplate` with `decodeTemplateData()` and `getOutputStruct()`
2. **Compile**: Forge build generates ABI with struct definitions in convention functions
3. **Extract**: Deployment script reads ABI from `decodeTemplateData()` return type and `getOutputStruct()` return type
4. **Create template.json**: Fill in metadata and struct definitions
5. **Upload to Arweave**: template.json + typst base file + optional style/patch files
6. **Deploy Contract**: Constructor receives Arweave URI and conditions
7. **Register**: (Optional) Add to template registry for discovery

### Suggested Script Flow

```bash
# 1. Compile contract
forge build

# 2. Extract ABIs from getter functions and generate template.json
# Script reads compiled output, finds getInputStructType() and getOutputStructType() 
# in the ABI to extract struct definitions
bun ./scripts/generate-json.ts ./src/templates/TokenSwapTemplate

# 3. Validate template.json against schema
bun ./scripts/validate-template.ts template.json

# 4. Upload to Arweave
# Bundles: template.json, template.typ, optional assets
bun ./scripts/upload-arweave.ts ./src/templates/TokenSwapTemplate

# 5. Deploy to target chain(s)
bun ./scripts/deploy.ts ./src/templates/TokenSwapTemplate --verify

# Or manually with forge:
# forge create TokenSwapTemplate \
#   --constructor-args "ar://<arweave-id>" "[]" \
#   --rpc-url $RPC_URL

# 6. Verify contract
forge verify-contract <address> TokenSwapTemplate --chain-id 84532
```

## Registry Integration

The `CyberAgreementRegistryV2` uses a unified storage model:

### Stored Fields

- `template`: 
  - **Smart Contract**: Address of IAgreementTemplate contract
  - **Basic**: `address(0)` (sentinel value)
- `templateUri`:
  - **Both Types**: URI string pointing to template.json (e.g., "ar://<txid>", "ipfs://<hash>")
- `templateData`: 
  - **Smart Contract**: Raw bytes (ABI-encoded input struct)
  - **Basic**: Raw bytes (Arweave TXID of agreement instance JSON)
- `parties`: Array of party addresses
- `partyData`: Array of raw bytes (optional, template-specific party data)

### Template Type Detection

```solidity
function isBasicTemplate(Agreement storage agreement) internal pure returns (bool) {
    return agreement.template == address(0);
}
```

### Template URI Access

The `templateUri` field is stored directly in the Agreement struct and is accessible for both template types:

```solidity
function getTemplateUri(bytes32 agreementId) external view returns (string memory) {
    return agreements[agreementId].templateUri;
}
```

For Smart Contract templates, this should match `IAgreementTemplate(template).contentUri()`.

### What the Registry Does NOT Do

- Decode template data (opaque bytes, interpretation depends on template type)
- Validate data (optional hook in smart contract templates only)
- Know struct definitions (from template.json referenced by templateUri)
- Distinguish between types without checking `template` field

## Template Type Comparison

| Feature | Basic Templates | Smart Contract Templates |
|---------|----------------|-------------------------|
| **Solidity Contract** | ❌ None required | ✅ Required (IAgreementTemplate) |
| **Deployment Cost** | Gas for registry call only | Gas for contract + registry |
| **On-Chain Logic** | ❌ None | ✅ Full capability |
| **On-Chain Validation** | ❌ Frontend only | ✅ Contract validation |
| **Read Chain State** | ❌ Not possible | ✅ ERC20 metadata, prices, etc. |
| **ICondition Support** | ❌ None | ✅ Closing conditions |
| **templateData Format** | Arweave TXID (bytes) | ABI-encoded struct |
| **template Field** | `address(0)` | Contract address |
| **Best For** | Simple agreements, static docs | Complex logic, on-chain data |
| **Upgrade Path** | Deploy Smart Contract later | Immutable once deployed |

### Decision Guide

**Use Basic Templates when:**
- Agreement doesn't reference blockchain state
- No complex validation required
- Cost minimization is priority
- Simple legal documents (NDAs, basic contracts)

**Use Smart Contract Templates when:**
- Need to read token balances, prices, or other on-chain data
- Complex validation logic (e.g., minimum balance checks)
- Time-dependent logic (e.g., vesting schedules)
- Integration with other DeFi protocols
- Need closing conditions (ICondition)

## Best Practices

1. **Keep Templates Simple**: Focus on data transformation, not complex logic
2. **Handle Errors Gracefully**: Use try/catch when reading external contracts
3. **Document Output Fields**: Include descriptions in template.json
4. **Test Thoroughly**: Verify all encoding/decoding paths work correctly
5. **Version Carefully**: Immutable contracts require careful initial testing
6. **Use Standard Types**: Prefer standard types over custom for better tooling support

## Future Enhancements

- **Validation Rules**: Expand template.json with declarative validation rules for Basic templates
- **Multi-Chain**: Support for reading state from multiple chains (Smart Contract only)
- **Composability**: Templates that reference other agreements
- **Events**: Standard events for template discovery and indexing
- **Migration Path**: Standardized way to "upgrade" Basic agreements to Smart Contract equivalents

## Appendix: Migrating from Basic to Smart Contract

While agreements are immutable, new agreements can use Smart Contract templates when on-chain features are needed:

1. **Create new Smart Contract template** with same input/output schema
2. **Add on-chain logic** for validation, data fetching, or conditions
3. **Deploy** and use for future agreements
4. **Existing Basic agreements** remain valid and referenceable

The shared `template.json` schema ensures frontends can handle both types seamlessly.

## Appendix: Default Party Data Struct

Templates that don't specify custom party data use:

```solidity
struct PartyData {
    string name;
    string contactDetails;
    bool isCompany;
}
```

This provides a minimal baseline while allowing templates to extend as needed.

## Appendix: JSON Schema Files

Schema files are maintained in the `packages/template-builder/schema/` directory with versioned subdirectories:

### Schema Structure

```
schema/
├── 1.0.0/
│   ├── template.json          # Main template schema
│   ├── agreement-data.json    # Agreement data for simple templates
│   └── party-data.json        # Party data for simple templates
```

### Referencing Schemas

Templates should reference the schema via the `$schema` field:

```json
{
  "$schema": "https://cyberagreement.io/schemas/template/1.0.0/template.json",
  "name": "My Template",
  ...
}
```

### Schema Versioning

Schemas follow semantic versioning in the URL path:
- Major version changes indicate breaking changes
- Minor/patch versions are additive or fixes
- Templates pin to a specific major version in their `$schema` reference

### Simple Template Data Schemas

For simple templates, agreement and party data are stored on Arweave. The schemas define:

**Agreement Data** (`agreement-data.json`):
- `chainId` - Chain ID of the agreement
- `registryAddress` - Registry contract address
- `agreementId` - Unique agreement identifier
- `contractFields` - Object containing field values defined in template

**Party Data** (`party-data.json`):
- `chainId` - Chain ID of the agreement
- `registryAddress` - Registry contract address
- `agreementId` - Agreement identifier
- `partyAddress` - Party's Ethereum address
- `partyFields` - Object containing preset and custom field values

== Logs ==
  CyberAgreementRegistryV2 Implementation: `0x432557742048745Cf8be0a488015B2652e4cf9c0`
  CyberAgreementRegistryV2 Proxy: `0xA8d28D3081D00A72eF8F6C7840E7875B837b5791`
  BorgAuth: `0x91892FB96ce6A8fF9166b9EDdb503375B10210B1`
  
This has an unsigned contract created:

0x9ab9136458068d4c1c7069039ffac29b0eba9850828e1e24c0fa8eb46180bfdc
