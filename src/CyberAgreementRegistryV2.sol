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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IAgreementTemplate} from "./interfaces/IAgreementTemplate.sol";
import {ICondition} from "./interfaces/ICondition.sol";
import {ICyberAgreementRegistryV2} from "./interfaces/ICyberAgreementRegistryV2.sol";
import {BorgAuthACL} from "./libs/auth.sol";

/**
 * @title CyberAgreementRegistryV2
 * @notice V2 registry for cyber agreements with typed template data
 * @dev Replaces string-based values with typed data structures using template contracts.
 *      Templates are smart contracts that define validation and conversion logic.
 */
contract CyberAgreementRegistryV2 is
    Initializable,
    UUPSUpgradeable,
    BorgAuthACL,
    ICyberAgreementRegistryV2
{
    using ECDSA for bytes32;

    // Domain separator for EIP-712
    bytes32 public DOMAIN_SEPARATOR;

    // EIP-712 Type hashes
    bytes32 public AGREEMENT_TYPEHASH;
    bytes32 public VOID_TYPEHASH;

    // Contract version
    string public constant VERSION = "1";

    // Storage for agreements
    struct Agreement {
        address template;
        bytes templateData;
        address[] parties;
        mapping(address => bytes) partyData;
        mapping(address => uint256) signedAt;
        mapping(address => ICyberAgreementRegistryV2.SignatureInfo) signatureInfo;
        address finalizer;
        bool finalized;
        bool voided;
        uint256 expiry;
        mapping(address => bool) voidRequestedBy;
        uint256 voidRequestCount;
        uint256 salt; // Used for unique agreement ID generation
        string[] agreementPatchUris; // Agreement-specific patches
        ICyberAgreementRegistryV2.AgreementStatus status; // Current agreement status
    }

    // Internal struct for pending amendment storage (extends interface struct with mappings)
    struct PendingChangeStorage {
        bytes32 agreementId;
        string[] newPatchUris;
        bytes proposedTemplateData;
        address proposer;
        uint256 proposedAt;
        mapping(address => bool) acceptedBy;
        uint256 acceptances;
        bool active; // Whether this pending change is active
    }

    // Delegation struct
    struct Delegation {
        address delegate;
        uint256 expiry;
    }

    // Storage mappings
    mapping(bytes32 => Agreement) internal agreements;
    mapping(address => bytes32[]) internal agreementsForParty;
    mapping(address => Delegation) public delegations;
    mapping(bytes32 => PendingChangeStorage) public pendingChanges;

    // Storage gap for upgradeability
    uint256[38] private __gap;

    // Custom errors
    error InvalidTemplate();
    error TemplateDoesNotSupportInterface();
    error AgreementAlreadyExists();
    error AgreementDoesNotExist();
    error AgreementExpired();
    error AgreementAlreadyVoided();
    error AgreementAlreadyFinalized();
    error NotAParty();
    error PartyDataLengthMismatch();
    error AlreadySigned();
    error InvalidSignature();
    error InvalidDelegation();
    error InvalidPartyCount();
    error NotFinalizer();
    error FinalizerNotDefined();
    error ConditionsNotMet();
    error NotFullySigned();
    error VoidAlreadyRequested();
    error InvalidSecret();
    error AmendmentAlreadyPending();
    error NoPendingAmendment();
    error AlreadyAccepted();
    error AmendmentNotReady();
    error InvalidAmendmentData();
    error AgreementNotDraft();
    error AgreementNotPendingChanges();

    /**
     * @notice Initializes the contract
     * @param _auth Address of the BorgAuth contract
     */
    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        // Initialize EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("CyberAgreementRegistryV2")),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );

        // Initialize EIP-712 type hashes
        // Note: partyData is now the signer's individual party data, not all parties
        AGREEMENT_TYPEHASH = keccak256(
            "AgreementSignatureData(bytes32 agreementId,address template,bytes templateData,address[] parties,bytes partyData)"
        );

        VOID_TYPEHASH = keccak256(
            "VoidSignatureData(bytes32 agreementId,address party)"
        );
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function createAgreement(
        address template,
        bytes calldata templateData,
        address[] calldata parties,
        bytes[] calldata partyData,
        address finalizer,
        uint256 expiry
    ) external returns (bytes32 agreementId) {
        // Validate template supports IAgreementTemplate via ERC165
        if (!IERC165(template).supportsInterface(type(IAgreementTemplate).interfaceId)) {
            revert TemplateDoesNotSupportInterface();
        }

        // Validate template data
        IAgreementTemplate templateContract = IAgreementTemplate(template);
        if (!templateContract.validate(templateData)) {
            revert InvalidTemplate();
        }

        // Validate parties array
        if (parties.length == 0) {
            revert InvalidPartyCount();
        }

        // Party data is optional - if provided, validate it
        if (partyData.length > 0 && partyData.length != parties.length) {
            revert PartyDataLengthMismatch();
        }

        // Generate unique agreement ID using salt
        uint256 salt = uint256(keccak256(abi.encode(block.timestamp, msg.sender, block.number)));
        agreementId = _generateAgreementId(template, templateData, parties, salt);

        // Check agreement doesn't already exist
        if (agreements[agreementId].parties.length > 0) {
            revert AgreementAlreadyExists();
        }

        // Create agreement storage
        Agreement storage agreement = agreements[agreementId];
        agreement.template = template;
        agreement.templateData = templateData;
        agreement.parties = parties;
        agreement.finalizer = finalizer;
        agreement.expiry = expiry;
        agreement.salt = salt;
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Draft;

        // Store party data and track agreements per party
        for (uint256 i = 0; i < parties.length; i++) {
            // Store party data if provided (validation is handled by frontend or template)
            if (partyData.length > 0 && partyData[i].length > 0) {
                agreement.partyData[parties[i]] = partyData[i];
            }
            agreementsForParty[parties[i]].push(agreementId);
        }

        emit AgreementCreated(agreementId, template, parties);

        return agreementId;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function signAgreement(
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external {
        _signAgreement(msg.sender, agreementId, partyData, signature, fillUnallocated, secret);
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function signAgreementFor(
        address signer,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external {
        _signAgreement(signer, agreementId, partyData, signature, fillUnallocated, secret);
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Signs an agreement with escrowed signatures
     * @dev Requires a predefined finalizer (smart contract) to enforce proper access control.
     *      The escrow signer provides the signature, but the finalizer contract controls authorization.
     *      Prevents exploits by requiring finalizer to be defined (see test_RevertIf_signContractWithEscrowUndefinedFinalizer).
     */
    function signAgreementWithEscrow(
        address escrowSigner,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata secret
    ) external {
        Agreement storage agreement = agreements[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Require a predefined finalizer to prevent unauthorized escrow signatures
        // This prevents exploits where an attacker could escrow signatures without authorization
        if (agreement.finalizer == address(0)) {
            revert FinalizerNotDefined();
        }

        // Only the finalizer can escrow signatures
        if (agreement.finalizer != msg.sender) {
            revert NotFinalizer();
        }

        // Check not expired
        if (agreement.expiry > 0 && block.timestamp > agreement.expiry) {
            revert AgreementExpired();
        }

        // Check not voided
        if (agreement.voided) {
            revert AgreementAlreadyVoided();
        }

        // Check not finalized
        if (agreement.finalized) {
            revert AgreementAlreadyFinalized();
        }

        // Check escrow signer not already signed
        if (agreement.signedAt[escrowSigner] > 0) {
            revert AlreadySigned();
        }

        // Find party index
        uint256 partyIndex = _findPartyIndex(agreement, escrowSigner, fillUnallocated);
        if (partyIndex == type(uint256).max) {
            revert NotAParty();
        }

        // Verify signature (party data validation is optional, handled by template or frontend)
        _validatePartySignature(agreement, escrowSigner, partyData, signature, agreementId);

        // Handle fillUnallocated - replace zero address with escrow signer
        if (fillUnallocated && agreement.parties[partyIndex] == address(0)) {
            agreement.parties[partyIndex] = escrowSigner;
            agreementsForParty[escrowSigner].push(agreementId);
        }

        // Store party data
        agreement.partyData[escrowSigner] = partyData;

        // Store signature info with escrow signer tracking
        address recoveredSigner = _recoverSigner(
            getAgreementHashForSigner(agreementId, partyData),
            signature
        );
        agreement.signatureInfo[escrowSigner] = ICyberAgreementRegistryV2.SignatureInfo({
            signature: signature,
            delegatedSigner: recoveredSigner != escrowSigner ? recoveredSigner : address(0),
            escrowSigner: escrowSigner
        });
        agreement.signedAt[escrowSigner] = block.timestamp;

        emit AgreementSigned(agreementId, escrowSigner, block.timestamp);

        // Check if all parties signed and auto-finalize if appropriate
        _checkAndAutoFinalize(agreement, agreementId);
    }

    /**
     * @notice Internal function to handle agreement signing
     */
    function _signAgreement(
        address signer,
        bytes32 agreementId,
        bytes calldata partyData,
        bytes calldata signature,
        bool fillUnallocated,
        string calldata /*secret*/
    ) internal {
        Agreement storage agreement = agreements[agreementId];

        uint256 partyIndex = _validateAgreementForSigning(agreement, signer, fillUnallocated);

        // Verify signature (party data validation is optional, handled by template or frontend)
        _validatePartySignature(agreement, signer, partyData, signature, agreementId);

        // Handle fillUnallocated - replace zero address with signer
        if (fillUnallocated && agreement.parties[partyIndex] == address(0)) {
            agreement.parties[partyIndex] = signer;
            agreementsForParty[signer].push(agreementId);
        }

        // Store party data
        agreement.partyData[signer] = partyData;

        // Store signature info and timestamp
        address recoveredSigner = _recoverSigner(
            getAgreementHashForSigner(agreementId, partyData),
            signature
        );
        agreement.signatureInfo[signer] = ICyberAgreementRegistryV2.SignatureInfo({
            signature: signature,
            delegatedSigner: recoveredSigner != signer ? recoveredSigner : address(0),
            escrowSigner: address(0)
        });
        agreement.signedAt[signer] = block.timestamp;

        emit AgreementSigned(agreementId, signer, block.timestamp);

        // Check if all parties signed and auto-finalize if appropriate
        _checkAndAutoFinalize(agreement, agreementId);
    }

    /**
     * @notice Validates agreement state for signing
     */
    function _validateAgreementForSigning(
        Agreement storage agreement,
        address signer,
        bool fillUnallocated
    ) internal view returns (uint256 partyIndex) {
        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check not expired
        if (agreement.expiry > 0 && block.timestamp > agreement.expiry) {
            revert AgreementExpired();
        }

        // Check not voided
        if (agreement.voided) {
            revert AgreementAlreadyVoided();
        }

        // Check not finalized
        if (agreement.finalized) {
            revert AgreementAlreadyFinalized();
        }

        // Check agreement is in valid state for signing (Draft or PendingChanges)
        if (
            agreement.status != ICyberAgreementRegistryV2.AgreementStatus.Draft &&
            agreement.status != ICyberAgreementRegistryV2.AgreementStatus.PendingChanges
        ) {
            revert AgreementNotDraft();
        }

        // Find party index and validate
        partyIndex = _findPartyIndex(agreement, signer, fillUnallocated);
        if (partyIndex == type(uint256).max) {
            revert NotAParty();
        }

        // Check not already signed
        if (agreement.signedAt[signer] > 0) {
            revert AlreadySigned();
        }
    }

    /**
     * @notice Validates party signature
     * @dev Each party signs only their own party data, not all parties' data
     * @dev Party data validation is optional and handled by the template or frontend
     */
    function _validatePartySignature(
        Agreement storage agreement,
        address signer,
        bytes calldata partyData,
        bytes calldata signature,
        bytes32 agreementId
    ) internal view {
        // Verify EIP-712 signature
        bytes32 agreementHash = getAgreementHashForSigner(agreementId, partyData);
        address recoveredSigner = _recoverSigner(agreementHash, signature);

        // Check if recovered signer is the party or a valid delegate
        if (recoveredSigner != signer && !_isValidDelegation(signer, recoveredSigner)) {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Checks if all parties signed and auto-finalizes if appropriate
     */
    function _checkAndAutoFinalize(Agreement storage agreement, bytes32 agreementId) internal {
        if (_allPartiesSigned(agreement)) {
            agreement.status = ICyberAgreementRegistryV2.AgreementStatus.FullySigned;
            emit AgreementFullySigned(agreementId, block.timestamp);

            // Auto-finalize if no finalizer set and closing conditions pass
            if (agreement.finalizer == address(0)) {
                _tryAutoFinalize(agreementId);
            }
        }
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function voidAgreement(bytes32 agreementId, bytes calldata signature) external {
        Agreement storage agreement = agreements[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check not already voided
        if (agreement.voided) {
            revert AgreementAlreadyVoided();
        }

        // Check not finalized
        if (agreement.finalized) {
            revert AgreementAlreadyFinalized();
        }

        // Verify void signature
        bytes32 voidHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(VOID_TYPEHASH, agreementId, msg.sender))
            )
        );
        address recoveredSigner = _recoverSigner(voidHash, signature);

        // Check if signer is a party or valid delegate
        bool isParty = false;
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (
                agreement.parties[i] == recoveredSigner ||
                (agreement.parties[i] != address(0) &&
                    _isValidDelegation(agreement.parties[i], recoveredSigner))
            ) {
                isParty = true;

                // Check if this party already requested void
                if (agreement.voidRequestedBy[agreement.parties[i]]) {
                    revert VoidAlreadyRequested();
                }

                agreement.voidRequestedBy[agreement.parties[i]] = true;
                agreement.voidRequestCount++;
                break;
            }
        }

        if (!isParty) {
            revert NotAParty();
        }

        // Check if all parties requested void
        if (agreement.voidRequestCount == agreement.parties.length) {
            agreement.voided = true;
            agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Voided;
            emit AgreementVoided(agreementId, block.timestamp);
        }
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function finalizeAgreement(bytes32 agreementId) external {
        Agreement storage agreement = agreements[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check not voided
        if (agreement.voided) {
            revert AgreementAlreadyVoided();
        }

        // Check not already finalized
        if (agreement.finalized) {
            revert AgreementAlreadyFinalized();
        }

        // Check all parties signed
        if (!_allPartiesSigned(agreement)) {
            revert NotFullySigned();
        }

        // Check finalizer authorization if set
        if (agreement.finalizer != address(0) && agreement.finalizer != msg.sender) {
            revert NotFinalizer();
        }

        // Check closing conditions
        if (!_checkClosingConditions(agreement, agreementId, true)) {
            revert ConditionsNotMet();
        }

        agreement.finalized = true;
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Finalized;
        emit AgreementFinalized(agreementId, msg.sender, block.timestamp);
    }

    /**
     * @notice Attempts to auto-finalize an agreement when all parties have signed
     * @dev Only called when finalizer == address(0)
     */
    function _tryAutoFinalize(bytes32 agreementId) internal {
        Agreement storage agreement = agreements[agreementId];

        // Check closing conditions - don't revert on failure
        if (!_checkClosingConditions(agreement, agreementId, false)) {
            return;
        }

        // All conditions pass - finalize
        agreement.finalized = true;
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Finalized;
        emit AgreementFinalized(agreementId, address(0), block.timestamp);
    }

    /**
     * @notice Checks closing conditions for an agreement
     * @param agreement The agreement storage
     * @param agreementId The agreement identifier
     * @param revertOnFailure If true, function never returns false (reverts instead)
     * @return bool True if all conditions pass, false otherwise (only when revertOnFailure is false)
     */
    function _checkClosingConditions(
        Agreement storage agreement,
        bytes32 agreementId,
        bool revertOnFailure
    ) internal view returns (bool) {
        IAgreementTemplate template = IAgreementTemplate(agreement.template);
        address[] memory conditions = template.getClosingConditions();

        for (uint256 i = 0; i < conditions.length; i++) {
            if (!ICondition(conditions[i]).checkCondition(address(this), this.finalizeAgreement.selector, abi.encode(agreementId))) {
                if (revertOnFailure) {
                    revert ConditionsNotMet();
                }
                return false;
            }
        }
        return true;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getAgreement(
        bytes32 agreementId
    )
        external
        view
        returns (
            address template,
            bytes memory templateData,
            address[] memory parties,
            uint256[] memory signedAt,
            bool isComplete,
            bool finalized,
            bool voided,
            ICyberAgreementRegistryV2.AgreementStatus status
        )
    {
        Agreement storage agreement = agreements[agreementId];

        template = agreement.template;
        templateData = agreement.templateData;
        parties = agreement.parties;

        signedAt = new uint256[](parties.length);
        for (uint256 i = 0; i < parties.length; i++) {
            signedAt[i] = agreement.signedAt[parties[i]];
        }

        isComplete = _allPartiesSigned(agreement);
        finalized = agreement.finalized;
        voided = agreement.voided;
        status = agreement.status;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getPartyData(bytes32 agreementId, address party) external view returns (bytes memory) {
        return agreements[agreementId].partyData[party];
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getPartySignature(bytes32 agreementId, address party) external view returns (bytes memory) {
        return agreements[agreementId].signatureInfo[party].signature;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function hasSigned(bytes32 agreementId, address party) external view returns (bool) {
        return agreements[agreementId].signedAt[party] > 0;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function allPartiesSigned(bytes32 agreementId) external view returns (bool) {
        return _allPartiesSigned(agreements[agreementId]);
    }

    /**
     * @notice Internal function to check if all parties have signed
     */
    function _allPartiesSigned(Agreement storage agreement) internal view returns (bool) {
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (agreement.signedAt[agreement.parties[i]] == 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function isVoided(bytes32 agreementId) external view returns (bool) {
        return agreements[agreementId].voided;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function isFinalized(bytes32 agreementId) external view returns (bool) {
        return agreements[agreementId].finalized;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getAgreementsForParty(address party) external view returns (bytes32[] memory) {
        return agreementsForParty[party];
    }

    /**
     * @notice Computes the agreement hash for a specific signer with their party data
     * @param agreementId The agreement identifier
     * @param partyData The signer's party data
     * @return bytes32 The EIP-712 hash for signing
     */
    function getAgreementHashForSigner(bytes32 agreementId, bytes memory partyData) public view returns (bytes32) {
        Agreement storage agreement = agreements[agreementId];

        // Hash template data
        bytes32 templateDataHash = keccak256(agreement.templateData);

        // Hash parties array
        bytes32 partiesHash = keccak256(abi.encodePacked(agreement.parties));

        // Hash signer's party data only
        bytes32 partyDataHash = keccak256(partyData);

        // Create struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                AGREEMENT_TYPEHASH,
                agreementId,
                agreement.template,
                templateDataHash,
                partiesHash,
                partyDataHash
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function hasRequestedVoid(bytes32 agreementId, address party) external view returns (bool) {
        return agreements[agreementId].voidRequestedBy[party];
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getVoidRequestCount(bytes32 agreementId) external view returns (uint256) {
        return agreements[agreementId].voidRequestCount;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     */
    function getSignatureInfo(
        bytes32 agreementId,
        address party
    ) external view returns (ICyberAgreementRegistryV2.SignatureInfo memory) {
        return agreements[agreementId].signatureInfo[party];
    }

    /**
     * @notice Sets a delegation for the caller
     * @param delegate The address to delegate to
     * @param expiry The expiration timestamp (0 for no expiry)
     */
    function setDelegation(address delegate, uint256 expiry) external {
        delegations[msg.sender] = Delegation(delegate, expiry);
    }

    /**
     * @notice Revokes the caller's delegation
     */
    function revokeDelegation() external {
        delete delegations[msg.sender];
    }

    /**
     * @notice Checks if a delegation is valid
     * @param delegator The address that delegated
     * @param delegate The potential delegate
     * @return bool True if the delegation is valid
     */
    function _isValidDelegation(address delegator, address delegate) internal view returns (bool) {
        Delegation storage delegation = delegations[delegator];
        return delegation.delegate == delegate &&
               (delegation.expiry == 0 || delegation.expiry > block.timestamp);
    }

    /**
     * @notice Finds the index of a party in the agreement
     * @param agreement The agreement storage
     * @param party The party address to find
     * @param fillUnallocated Whether to match zero addresses
     * @return uint256 The index of the party, or max uint256 if not found
     */
    function _findPartyIndex(
        Agreement storage agreement,
        address party,
        bool fillUnallocated
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (agreement.parties[i] == party) {
                return i;
            }
            if (fillUnallocated && agreement.parties[i] == address(0)) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice Generates a unique agreement ID
     * @param template The template address
     * @param templateData The template data
     * @param parties The party addresses
     * @param salt A unique salt value
     * @return bytes32 The agreement ID
     */
    function _generateAgreementId(
        address template,
        bytes memory templateData,
        address[] memory parties,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(template, templateData, parties, salt));
    }

    /**
     * @notice Recovers the signer address from a signature
     * @param hash The signed hash
     * @param signature The signature bytes
     * @return address The recovered signer address
     */
    function _recoverSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
        return hash.recover(signature);
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Proposes an amendment to the agreement
     * @dev Clears all existing signatures and sets status to PendingChanges
     */
    function proposeAmendment(
        bytes32 agreementId,
        string[] calldata newPatchUris,
        bytes calldata newTemplateData
    ) external {
        Agreement storage agreement = agreements[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check not voided
        if (agreement.voided) {
            revert AgreementAlreadyVoided();
        }

        // Check not finalized
        if (agreement.finalized) {
            revert AgreementAlreadyFinalized();
        }

        // Check no pending amendment already exists
        if (pendingChanges[agreementId].active) {
            revert AmendmentAlreadyPending();
        }

        // Check sender is a party
        bool isParty = false;
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (agreement.parties[i] == msg.sender) {
                isParty = true;
                break;
            }
        }
        if (!isParty) {
            revert NotAParty();
        }

        // Validate that at least one change is being proposed
        if (newPatchUris.length == 0 && newTemplateData.length == 0) {
            revert InvalidAmendmentData();
        }

        // Validate new template data if provided
        if (newTemplateData.length > 0) {
            IAgreementTemplate template = IAgreementTemplate(agreement.template);
            if (!template.validate(newTemplateData)) {
                revert InvalidTemplate();
            }
        }

        // Create pending change
        PendingChangeStorage storage change = pendingChanges[agreementId];
        change.agreementId = agreementId;
        change.newPatchUris = newPatchUris;
        change.proposedTemplateData = newTemplateData;
        change.proposer = msg.sender;
        change.proposedAt = block.timestamp;
        change.active = true;

        // Clear all signatures
        _clearSignatures(agreement);

        // Set status to PendingChanges
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.PendingChanges;

        emit AmendmentProposed(agreementId, msg.sender, newPatchUris);
        emit SignaturesCleared(agreementId);
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Accepts a proposed amendment
     * @dev Once all parties accept, the amendment is applied automatically
     */
    function acceptAmendment(bytes32 agreementId) external {
        Agreement storage agreement = agreements[agreementId];
        PendingChangeStorage storage change = pendingChanges[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check there is a pending amendment
        if (!change.active) {
            revert NoPendingAmendment();
        }

        // Check sender is a party
        bool isParty = false;
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (agreement.parties[i] == msg.sender) {
                isParty = true;
                break;
            }
        }
        if (!isParty) {
            revert NotAParty();
        }

        // Check not already accepted
        if (change.acceptedBy[msg.sender]) {
            revert AlreadyAccepted();
        }

        // Record acceptance
        change.acceptedBy[msg.sender] = true;
        change.acceptances++;

        emit AmendmentAccepted(agreementId, msg.sender);

        // If all parties have accepted, apply the amendment
        if (change.acceptances == agreement.parties.length) {
            _applyAmendment(agreement, change, agreementId);
        }
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Rejects a proposed amendment
     * @dev Discards the pending change and returns agreement to Draft status
     */
    function rejectAmendment(bytes32 agreementId) external {
        Agreement storage agreement = agreements[agreementId];
        PendingChangeStorage storage change = pendingChanges[agreementId];

        // Check agreement exists
        if (agreement.parties.length == 0) {
            revert AgreementDoesNotExist();
        }

        // Check there is a pending amendment
        if (!change.active) {
            revert NoPendingAmendment();
        }

        // Check sender is a party
        bool isParty = false;
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            if (agreement.parties[i] == msg.sender) {
                isParty = true;
                break;
            }
        }
        if (!isParty) {
            revert NotAParty();
        }

        // Clear all acceptances before deleting (mappings are not cleared by delete)
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            change.acceptedBy[agreement.parties[i]] = false;
        }

        // Delete the pending change
        delete pendingChanges[agreementId];

        // Return agreement to Draft status
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Draft;

        emit AmendmentRejected(agreementId, msg.sender);
    }

    /**
     * @notice Internal function to apply an amendment
     * @param agreement The agreement storage
     * @param change The pending change storage
     * @param agreementId The agreement identifier
     */
    function _applyAmendment(
        Agreement storage agreement,
        PendingChangeStorage storage change,
        bytes32 agreementId
    ) internal {
        // Apply template data changes if provided
        if (change.proposedTemplateData.length > 0) {
            agreement.templateData = change.proposedTemplateData;
        }

        // Apply patch URI changes
        for (uint256 i = 0; i < change.newPatchUris.length; i++) {
            agreement.agreementPatchUris.push(change.newPatchUris[i]);
        }

        // Clear all acceptances before deleting (mappings are not cleared by delete)
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            change.acceptedBy[agreement.parties[i]] = false;
        }

        // Delete the pending change
        delete pendingChanges[agreementId];

        // Return agreement to Draft status (signatures already cleared)
        agreement.status = ICyberAgreementRegistryV2.AgreementStatus.Draft;

        emit AmendmentApplied(agreementId);
    }

    /**
     * @notice Internal function to clear all signatures from an agreement
     * @param agreement The agreement storage
     */
    function _clearSignatures(Agreement storage agreement) internal {
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            address party = agreement.parties[i];
            agreement.signedAt[party] = 0;
            delete agreement.signatureInfo[party];
        }
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Returns the current status of an agreement
     */
    function getAgreementStatus(bytes32 agreementId) external view returns (ICyberAgreementRegistryV2.AgreementStatus) {
        return agreements[agreementId].status;
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Returns the pending change for an agreement
     */
    function getPendingChange(bytes32 agreementId) external view returns (
        string[] memory patchUris,
        bytes memory templateData,
        address proposer,
        uint256 proposedAt,
        uint256 acceptances,
        bool hasAccepted
    ) {
        PendingChangeStorage storage change = pendingChanges[agreementId];

        if (!change.active) {
            return (new string[](0), "", address(0), 0, 0, false);
        }

        return (
            change.newPatchUris,
            change.proposedTemplateData,
            change.proposer,
            change.proposedAt,
            change.acceptances,
            change.acceptedBy[msg.sender]
        );
    }

    /**
     * @inheritdoc ICyberAgreementRegistryV2
     * @notice Returns the agreement patch URIs
     */
    function getAgreementPatchUris(bytes32 agreementId) external view returns (string[] memory) {
        return agreements[agreementId].agreementPatchUris;
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable by owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Authorization handled by onlyOwner modifier
    }
}
