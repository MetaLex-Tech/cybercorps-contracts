/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import {BorgAuth, IBorgAuthACL} from "../libs/auth.sol";

/// @title ICyberAgreementRegistry
/// @notice All functions, events and errors of the agreement registry. Clients use this interface for the proxy.
/// `CyberAgreementRegistry` is the implementation. It sends each call to the facet that holds the function.
interface ICyberAgreementRegistry is IBorgAuthACL {
    struct Template {
        string legalContractUri;
        string title;
        string[] globalFields;
        string[] partyFields;
    }

    struct ContractData {
        bytes32 templateId;
        string[] globalValues;
        address[] parties;
        uint256 numSignatures;
        bytes32 transactionHash;
    }

    /// @notice A check that a party must pass to sign a creator-bound agreement.
    /// @param kind The type of check, for example `keccak256("MetaLeX.SignerCondition.ZKPassport.v1")`.
    /// @param params The creator's settings for this check, as the struct that `kind` defines. They are part of
    /// the agreement id.
    struct SignerCondition {
        bytes32 kind;
        bytes params;
    }

    // Agreements

    event TemplateCreated(
        bytes32 indexed templateId,
        string indexed title,
        string legalContractUri,
        string[] globalFields,
        string[] signerFields
    );

    event ContractCreated(bytes32 indexed contractId, bytes32 indexed templateId, address[] parties);

    event AgreementSigned(bytes32 indexed contractId, address indexed party, uint256 timestamp);

    event ContractFullySigned(bytes32 indexed contractId, uint256 timestamp);

    event VoidRequested(bytes32 indexed contractId, address indexed party);

    event ContractVoided(bytes32 indexed contractId, address[] voidSigners, uint256 timestamp);

    event ContractFinalized(bytes32 indexed contractId, address finalizer, uint256 timestamp);

    event DelegationSet(address indexed delegator, address indexed delegate, uint256 expiry);
    event DelegationRevoked(address indexed delegator, address indexed delegate);

    error TemplateAlreadyExists();
    error TemplateDoesNotExist();
    error ContractAlreadyExists();
    error ContractDoesNotExist();
    error NotAParty();
    error SignatureVerificationFailed();
    error AlreadySigned();
    error MismatchedFieldsLength();
    error FirstPartyZeroAddress();
    error DuplicateParty();
    error TitleEmpty();
    error InvalidPartyCount();
    error ClosedAgreementPartyValueMismatch();
    error ContractAlreadyVoided();
    error NotFinalizer();
    error ContractAlreadyFinalized();
    error ContractNotFullySigned();
    error ContractExpired();
    error InvalidSecret();
    error MismatchedPartyValuesLength();
    error FinalizerNotDefined();
    error DelegateZeroAddress();
    error DelegateIsSelf();
    error ExpiryNotInFuture();

    // Signer conditions on creator-bound agreements. Each kind defines the structs inside `params`, evidence,
    // `result` and `config`.

    event SignerConditionSet(
        bytes32 indexed contractId, address indexed party, uint256 index, bytes32 kind, bytes params
    );
    event SignerConditionMet(
        bytes32 indexed contractId, address indexed party, uint256 index, bytes32 kind, bytes result
    );
    event SignerConditionConfigSet(bytes32 indexed kind, bytes config);

    error SignerConditionsLengthMismatch();
    error UnknownSignerConditionKind(bytes32 kind);
    error EvidenceRequired();
    error NoSignerConditions();
    error EvidenceLengthMismatch();

    // ZKPassport signer condition

    error ZKPassportNotConfigured();
    error InvalidZKPassportConditionParams();
    error InvalidVerifier();
    error DevModeProof();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidBoundSender();
    error InvalidBoundContractId();
    error UniqueIdentifierMismatch();
    error UniqueIdentifierAlreadyUsed();

    // Router, upgrades and auth. OpenZeppelin and BorgAuth code declares these too.

    event Initialized(uint64 version);
    event Upgraded(address indexed implementation);

    error FunctionNotFound(bytes4 selector);
    error BorgAuthACL_ZeroAddress();
    error InvalidInitialization();
    error NotInitializing();
    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);
    error ERC1967InvalidImplementation(address implementation);
    error ERC1967NonPayable();
    error AddressEmptyCode(address target);
    error FailedCall();
    error ECDSAInvalidSignature();
    error ECDSAInvalidSignatureLength(uint256 length);
    error ECDSAInvalidSignatureS(bytes32 s);
    error StringsInsufficientHexLength(uint256 value, uint256 length);

    // Router

    function initialize(address _auth) external;

    /// @notice The facet that holds the function with `selector`. Zero if no facet holds it.
    function facetOf(bytes4 selector) external view returns (address);

    function userRoles(address user) external view returns (uint256);

    function UPGRADE_INTERFACE_VERSION() external view returns (string memory);

    function proxiableUUID() external view returns (bytes32);

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;

    // CyberAgreementFacet

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external;

    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes32 secretHash,
        address finalizer,
        uint256 expiry
    ) external returns (bytes32);

    function createStandaloneContractAndSign(
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        bytes calldata signature
    ) external returns (bytes32 contractId);

    function createStandaloneContractAndSignFor(
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        address signer,
        bytes calldata signature
    ) external returns (bytes32 contractId);

    function signContract(
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external;

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external;

    function signContractWithEscrow(
        address escrowSigner,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external;

    //function voidContractFor(bytes32 contractId, address party, bytes calldata signature) public {
    function voidContractFor(bytes32 contractId, address party, bytes calldata signature) external;

    function finalizeContract(bytes32 contractId) external;

    function setDelegation(address delegate, uint256 expiry) external;

    function revokeDelegation() external;

    // CyberAgreementBoundFacet

    function createBoundContract(
        Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry
    ) external returns (bytes32 templateId, bytes32 contractId);

    function createBoundContract(
        Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions
    ) external returns (bytes32 templateId, bytes32 contractId);

    function createBoundContractAndSignFor(
        Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        bytes calldata creatorSignature
    ) external returns (bytes32 templateId, bytes32 contractId);

    function createBoundContractAndSignFor(
        Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions,
        bytes[] memory creatorEvidence,
        bytes calldata creatorSignature
    ) external returns (bytes32 templateId, bytes32 contractId);

    function boundIdsOf(
        address creator,
        Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions
    ) external pure returns (bytes32 templateId, bytes32 contractId);

    function signContractWithEvidenceFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes[] memory evidence,
        bytes calldata signature
    ) external;

    function setSignerConditionConfig(bytes32 kind, bytes calldata config) external;

    function getSignerConditionConfig(bytes32 kind) external view returns (bytes memory);

    // CyberAgreementViewFacet

    function name() external view returns (string memory);

    function version() external view returns (string memory);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function SIGNATUREDATA_TYPEHASH() external view returns (bytes32);

    function VOIDSIGNATUREDATA_TYPEHASH() external view returns (bytes32);

    function SIGNATUREWITHEVIDENCEDATA_TYPEHASH() external view returns (bytes32);

    function BOUND_TEMPLATE_DOMAIN() external view returns (bytes32);

    function BOUND_AGREEMENT_DOMAIN() external view returns (bytes32);

    function CONDITIONED_BOUND_AGREEMENT_DOMAIN() external view returns (bytes32);

    function templates(bytes32 templateId) external view returns (string memory legalContractUri, string memory title);

    function agreements(bytes32 contractId)
        external
        view
        returns (
            bytes32 templateId,
            uint256 numSignatures,
            address finalizer,
            bool finalized,
            bool voided,
            bytes32 secretHash,
            uint256 expiry
        );

    function agreementsForParty(address party, uint256 index) external view returns (bytes32);

    function delegations(address delegator) external view returns (address delegate, uint256 expiry);

    function getDelegation(address delegator) external view returns (address delegate, uint256 expiry);

    function isValidDelegation(address delegator) external view returns (bool);

    function isValidDelegate(address delegator, address delegate) external view returns (bool);

    function getParties(bytes32 contractId) external view returns (address[] memory);

    function hasSigned(bytes32 contractId, address signer) external view returns (bool);

    function getSignatureTimestamp(bytes32 contractId, address signer) external view returns (uint256);

    function allPartiesSigned(bytes32 contractId) external view returns (bool);

    function getContractDetails(bytes32 contractId)
        external
        view
        returns (
            bytes32 templateId,
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory partyFields,
            string[] memory globalValues,
            address[] memory parties,
            string[][] memory partyValues,
            uint256[] memory signedAt,
            uint256 numSignatures,
            bool isComplete
        );

    function getTemplateDetails(bytes32 templateId)
        external
        view
        returns (
            string memory legalContractUri,
            string memory title,
            string[] memory globalFields,
            string[] memory signerFields
        );

    function getSignerValues(bytes32 contractId, address signer) external view returns (string[] memory signerValues);

    function isVoided(bytes32 contractId) external view returns (bool);

    function getAgreementsForParty(address party) external view returns (bytes32[] memory);

    function getVoidRequestedBy(bytes32 contractId) external view returns (address[] memory);

    function getContractJson(bytes32 contractId) external view returns (string memory);

    function isFinalized(bytes32 contractId) external view returns (bool);

    function _bytes32ToString(bytes32 _bytes32) external pure returns (string memory);
}
