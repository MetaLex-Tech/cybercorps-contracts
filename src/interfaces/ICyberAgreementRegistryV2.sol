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

/**
 * @title ICyberAgreementRegistryV2
 * @notice Interface for the CyberAgreement Registry V2 contract
 * @dev V2 replaces string-based values with typed data structures using template contracts.
 *      The implementation stores agreements with the following structure:
 *      - address template: Template contract address
 *      - bytes templateData: Encoded template-specific data
 *      - address[] parties: Array of party addresses
 *      - mapping(address => bytes) partyData: Template-specific party data per party
 *      - mapping(address => uint256) signedAt: Timestamp of signature per party
 *      - mapping(address => bytes) signatures: EIP-712 signature per party
 *      - mapping(address => SignatureMetadata) signatureMetadata: Metadata about how signature was made
 *      - address finalizer: Optional finalizer address
 *      - bool finalized: Whether agreement is finalized
 *      - bool voided: Whether agreement is voided
 *      - uint256 expiry: Expiration timestamp
 *      - mapping(address => bool) voidRequestedBy: Tracks which parties requested void
 *      - uint256 voidRequestCount: Number of parties that requested void
 */
interface ICyberAgreementRegistryV2 {
    /**
     * @notice Enum representing the status of an agreement
     */
    enum AgreementStatus {
        Draft,           // Created, not all parties signed
        PendingChanges,  // Amendment proposed, awaiting acceptance
        FullySigned,     // All parties signed, awaiting finalization
        Finalized,       // Complete
        Voided           // Agreement voided by parties
    }

    /**
     * @notice Struct containing full signature information for a party
     * @param signature The EIP-712 signature bytes
     * @param delegatedSigner The address that signed on behalf of the party (zero address if direct signature)
     * @param escrowSigner The address that escrowed the signature (zero address if not escrowed)
     */
    struct SignatureInfo {
        bytes signature;
        address delegatedSigner;
        address escrowSigner;
    }

    /**
     * @notice Struct containing information about a pending amendment
     * @param agreementId The agreement this change applies to
     * @param newPatchUris Proposed patch URIs to add
     * @param proposedTemplateData Proposed new template data (empty if unchanged)
     * @param proposer Address that proposed the change
     * @param proposedAt Timestamp when proposed
     * @param acceptances Count of parties that have accepted
     */
    struct PendingChange {
        bytes32 agreementId;
        string[] newPatchUris;
        bytes proposedTemplateData;
        address proposer;
        uint256 proposedAt;
        uint256 acceptances;
    }

    /**
     * @notice Emitted when a new agreement is created
     * @param agreementId The unique identifier for the agreement
     * @param template The template contract address
     * @param parties Array of party addresses
     */
    event AgreementCreated(bytes32 indexed agreementId, address indexed template, address[] parties);

    /**
     * @notice Emitted when a party signs an agreement
     * @param agreementId The agreement identifier
     * @param party The address of the signing party
     * @param timestamp The block timestamp of the signature
     */
    event AgreementSigned(bytes32 indexed agreementId, address indexed party, uint256 timestamp);

    /**
     * @notice Emitted when an agreement is voided
     * @param agreementId The agreement identifier
     * @param timestamp The block timestamp of voiding
     */
    event AgreementVoided(bytes32 indexed agreementId, uint256 timestamp);

    /**
     * @notice Emitted when an agreement is finalized
     * @param agreementId The agreement identifier
     * @param finalizer The address that finalized the agreement
     * @param timestamp The block timestamp of finalization
     */
    event AgreementFinalized(bytes32 indexed agreementId, address finalizer, uint256 timestamp);

    /**
     * @notice Emitted when all parties have signed the agreement
     * @param agreementId The agreement identifier
     * @param timestamp The block timestamp when fully signed
     */
    event AgreementFullySigned(bytes32 indexed agreementId, uint256 timestamp);

    /**
     * @notice Emitted when an amendment is proposed
     * @param agreementId The agreement identifier
     * @param proposer The address that proposed the amendment
     * @param patchUris The proposed patch URIs
     */
    event AmendmentProposed(bytes32 indexed agreementId, address indexed proposer, string[] patchUris);

    /**
     * @notice Emitted when a party accepts an amendment
     * @param agreementId The agreement identifier
     * @param acceptor The address that accepted the amendment
     */
    event AmendmentAccepted(bytes32 indexed agreementId, address indexed acceptor);

    /**
     * @notice Emitted when a party rejects an amendment
     * @param agreementId The agreement identifier
     * @param rejector The address that rejected the amendment
     */
    event AmendmentRejected(bytes32 indexed agreementId, address indexed rejector);

    /**
     * @notice Emitted when an amendment is applied
     * @param agreementId The agreement identifier
     */
    event AmendmentApplied(bytes32 indexed agreementId);

    /**
     * @notice Emitted when signatures are cleared due to amendment
     * @param agreementId The agreement identifier
     */
    event SignaturesCleared(bytes32 indexed agreementId);

    /**
     * @notice Creates a new agreement
     * @param template The template contract address
     * @param templateData Encoded template-specific data
     * @param parties Array of party addresses
     * @param partyData Array of encoded party data, indexed by party
     * @param finalizer Optional finalizer address (use zero address for auto-finalize)
     * @param expiry Timestamp after which the agreement expires (0 for no expiry)
     * @return agreementId The unique identifier for the created agreement
     */
    function createAgreement(
        address template,
        bytes calldata templateData,
        address[] calldata parties,
        bytes[] calldata partyData,
        address finalizer,
        uint256 expiry
    ) external returns (bytes32 agreementId);

    /**
     * @notice Signs an agreement (for msg.sender)
     * @param agreementId The agreement identifier
     * @param partyData Encoded party data for the signing party
     * @param signature EIP-712 signature of the agreement data
     * @param fillUnallocated Whether to fill an unallocated (zero address) party slot
     * @param secret Optional secret for additional validation (empty string if unused)
     */
    function signAgreement(
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external;

    /**
     * @notice Signs an agreement on behalf of another party
     * @param signer The address of the party being signed for
     * @param agreementId The agreement identifier
     * @param partyData Encoded party data for the signing party
     * @param signature EIP-712 signature of the agreement data
     * @param fillUnallocated Whether to fill an unallocated (zero address) party slot
     * @param secret Optional secret for additional validation (empty string if unused)
     */
    function signAgreementFor(
        address signer,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external;

    /**
     * @notice Signs an agreement with escrowed signatures
     * @dev Allows a finalizer contract to escrow signatures on behalf of parties.
     *      Requires a predefined finalizer to enforce proper access control.
     * @param escrowSigner The address of the party whose signature is being escrowed
     * @param agreementId The agreement identifier
     * @param partyData Encoded party data for the escrow signer
     * @param signature EIP-712 signature of the agreement data by the escrow signer
     * @param fillUnallocated Whether to fill an unallocated (zero address) party slot
     * @param secret Optional secret for additional validation (empty string if unused)
     */
    function signAgreementWithEscrow(
        address escrowSigner,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external;

    /**
     * @notice Voids an agreement
     * @param agreementId The agreement identifier
     * @param signature EIP-712 signature authorizing voiding
     */
    function voidAgreement(bytes32 agreementId, bytes calldata signature) external;

    /**
     * @notice Finalizes an agreement after all signatures and conditions are met
     * @param agreementId The agreement identifier
     * @dev Checks all closing conditions before finalization
     */
    function finalizeAgreement(bytes32 agreementId) external;

    /**
     * @notice Proposes an amendment to the agreement
     * @param agreementId The agreement identifier
     * @param newPatchUris Array of new patch URIs to add (empty if none)
     * @param newTemplateData New template data (empty if unchanged)
     * @dev Clears all existing signatures and sets status to PendingChanges
     */
    function proposeAmendment(
        bytes32 agreementId,
        string[] calldata newPatchUris,
        bytes calldata newTemplateData
    ) external;

    /**
     * @notice Accepts a proposed amendment
     * @param agreementId The agreement identifier
     * @dev Once all parties accept, the amendment is applied automatically
     */
    function acceptAmendment(bytes32 agreementId) external;

    /**
     * @notice Rejects a proposed amendment
     * @param agreementId The agreement identifier
     * @dev Discards the pending change and returns agreement to Draft status
     */
    function rejectAmendment(bytes32 agreementId) external;

    /**
     * @notice Returns agreement details
     * @param agreementId The agreement identifier
     * @return template The template contract address
     * @return templateData The encoded template data
     * @return parties Array of party addresses
     * @return signedAt Array of timestamps for each party's signature (0 if not signed)
     * @return isComplete Whether all parties have signed
     * @return finalized Whether the agreement has been finalized
     * @return voided Whether the agreement has been voided
     * @return status The current agreement status
     */
    function getAgreement(bytes32 agreementId) external view returns (
        address template,
        bytes memory templateData,
        address[] memory parties,
        uint256[] memory signedAt,
        bool isComplete,
        bool finalized,
        bool voided,
        AgreementStatus status
    );

    /**
     * @notice Returns party-specific data for an agreement
     * @param agreementId The agreement identifier
     * @param party The party address
     * @return bytes memory The encoded party data
     */
    function getPartyData(bytes32 agreementId, address party) external view returns (bytes memory);

    /**
     * @notice Returns the signature for a party
     * @param agreementId The agreement identifier
     * @param party The party address
     * @return bytes memory The EIP-712 signature
     */
    function getPartySignature(bytes32 agreementId, address party) external view returns (bytes memory);

    /**
     * @notice Checks if a party has signed the agreement
     * @param agreementId The agreement identifier
     * @param party The party address
     * @return bool True if the party has signed
     */
    function hasSigned(bytes32 agreementId, address party) external view returns (bool);

    /**
     * @notice Checks if all parties have signed the agreement
     * @param agreementId The agreement identifier
     * @return bool True if all parties have signed
     */
    function allPartiesSigned(bytes32 agreementId) external view returns (bool);

    /**
     * @notice Checks if an agreement has been voided
     * @param agreementId The agreement identifier
     * @return bool True if the agreement is voided
     */
    function isVoided(bytes32 agreementId) external view returns (bool);

    /**
     * @notice Checks if an agreement has been finalized
     * @param agreementId The agreement identifier
     * @return bool True if the agreement is finalized
     */
    function isFinalized(bytes32 agreementId) external view returns (bool);

    /**
     * @notice Returns all agreements for a party
     * @param party The party address
     * @return bytes32[] memory Array of agreement IDs
     */
    function getAgreementsForParty(address party) external view returns (bytes32[] memory);

    /**
     * @notice Returns the EIP-712 hash for a specific signer with their party data
     * @param agreementId The agreement identifier
     * @param partyData The signer's encoded party data
     * @return bytes32 The agreement hash for the signer to sign
     */
    function getAgreementHashForSigner(bytes32 agreementId, bytes memory partyData) external view returns (bytes32);

    /**
     * @notice Checks if a party has requested voiding
     * @param agreementId The agreement identifier
     * @param party The party address to check
     * @return bool True if the party requested void
     */
    function hasRequestedVoid(bytes32 agreementId, address party) external view returns (bool);

    /**
     * @notice Returns the number of parties that requested voiding
     * @param agreementId The agreement identifier
     * @return uint256 The count of void requests
     */
    function getVoidRequestCount(bytes32 agreementId) external view returns (uint256);

    /**
     * @notice Returns full signature information for a party
     * @param agreementId The agreement identifier
     * @param party The party address
     * @return SignatureInfo The signature info struct containing signature and metadata
     */
    function getSignatureInfo(bytes32 agreementId, address party) external view returns (SignatureInfo memory);

    /**
     * @notice Returns the current status of an agreement
     * @param agreementId The agreement identifier
     * @return AgreementStatus The current status
     */
    function getAgreementStatus(bytes32 agreementId) external view returns (AgreementStatus);

    /**
     * @notice Returns the pending change for an agreement
     * @param agreementId The agreement identifier
     * @return patchUris The proposed patch URIs
     * @return templateData The proposed template data
     * @return proposer The address that proposed the change
     * @return proposedAt The timestamp when proposed
     * @return acceptances The number of acceptances
     * @return hasAccepted Whether the caller has accepted
     */
    function getPendingChange(bytes32 agreementId) external view returns (
        string[] memory patchUris,
        bytes memory templateData,
        address proposer,
        uint256 proposedAt,
        uint256 acceptances,
        bool hasAccepted
    );

    /**
     * @notice Returns the agreement patch URIs
     * @param agreementId The agreement identifier
     * @return string[] memory Array of patch URIs
     */
    function getAgreementPatchUris(bytes32 agreementId) external view returns (string[] memory);
}
