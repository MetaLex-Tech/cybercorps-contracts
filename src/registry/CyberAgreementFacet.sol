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

import {CyberAgreementRegistry} from "../CyberAgreementRegistry.sol";
import {ICyberAgreementRegistry} from "../interfaces/ICyberAgreementRegistry.sol";
import {CyberAgreementRegistryLib} from "../libs/CyberAgreementRegistryLib.sol";
import {CyberAgreementRegistryStorage} from "../storage/CyberAgreementRegistryStorage.sol";

/// @title CyberAgreementFacet
/// @notice Registry facet for templates, agreements, signatures, void, finalize and delegation.
/// The router delegatecalls it, so it writes the registry's storage and emits the registry's events.
contract CyberAgreementFacet {
    /// @notice allows only when finalizer is not defined, or msg.sender is the finalizer
    modifier onlyFinalizerIfSet(bytes32 contractId) {
        address finalizer = CyberAgreementRegistryStorage.getStorageData().agreements[contractId].finalizer;
        if (finalizer != msg.sender && finalizer != address(0)) revert CyberAgreementRegistry.NotFinalizer();
        _;
    }

    /// @notice allows only when finalizer is defined, and msg.sender is the finalizer
    modifier onlyDefinedFinalizer(bytes32 contractId) {
        address finalizer = CyberAgreementRegistryStorage.getStorageData().agreements[contractId].finalizer;
        if (finalizer == address(0)) revert CyberAgreementRegistry.FinalizerNotDefined();
        if (finalizer != msg.sender) revert CyberAgreementRegistry.NotFinalizer();
        _;
    }

    /// @notice Create a new agreement template. Only the owner can do it externally; however, the registry itself can
    /// do it as well for just-in-time operations.
    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external {
        CyberAgreementRegistryLib.createTemplate(templateId, title, legalContractUri, globalFields, partyFields);
    }

    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes32 secretHash,
        address finalizer,
        uint256 expiry
    ) public returns (bytes32 contractId) {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        // It is critical to bind `secretHash` and `finalizer` into the id: the finalizer
        // controls settlement and the secretHash gates who may sign, so omitting them would
        // let a front-runner seize the same id with hostile terms and bind signers to an
        // agreement they never authorized.
        // `expiry` is deliberately NOT bound: callers derive it from block.timestamp at
        // creation time, which a party signing off-chain cannot predict, so including it
        // would make every presigned signature unverifiable.
        // TODO: an off-chain indexer that derives contractId (rather than reading the
        // ContractCreated event) must include these two fields.
        contractId = keccak256(abi.encode(templateId, salt, globalValues, parties, secretHash, finalizer));
        if (s.agreements[contractId].parties.length > 0) {
            revert CyberAgreementRegistry.ContractAlreadyExists();
        }

        ICyberAgreementRegistry.Template storage template = s.templates[templateId];
        if (bytes(template.legalContractUri).length == 0) {
            revert CyberAgreementRegistry.TemplateDoesNotExist();
        }

        if (globalValues.length != template.globalFields.length) {
            revert CyberAgreementRegistry.MismatchedFieldsLength();
        }

        if (parties[0] == address(0)) {
            revert CyberAgreementRegistry.FirstPartyZeroAddress();
        }

        /*for (uint256 i = 0; i < parties.length; i++) {
            for (uint256 j = i + 1; j < parties.length; j++) {
                if (parties[i] == parties[j]) {
                    revert DuplicateParty();
                }
            }
        }*/

        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        agreementData.templateId = templateId;
        agreementData.globalValues = globalValues;
        agreementData.parties = parties;
        agreementData.finalizer = finalizer;
        agreementData.expiry = expiry;
        agreementData.secretHash = secretHash;

        //check all arrays inside partyValues are the same length
        for (uint256 i = 0; i < partyValues.length; i++) {
            if (partyValues[i].length != template.partyFields.length) {
                revert CyberAgreementRegistry.MismatchedFieldsLength();
            }
            //matching address cannot be 0
            if (parties[i] == address(0)) {
                revert CyberAgreementRegistry.FirstPartyZeroAddress();
            }
            //set agreement partyValues
            agreementData.partyValues[parties[i]] = partyValues[i];
        }

        emit ICyberAgreementRegistry.ContractCreated(contractId, templateId, parties);

        // Add to the party's list of agreements
        for (uint256 i = 0; i < parties.length; i++) {
            s.agreementsForParty[parties[i]].push(contractId);
        }
    }

    /// @notice See `createStandaloneContractAndSignFor()`
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
    ) external returns (bytes32 contractId) {
        return createStandaloneContractAndSignFor(
            title,
            legalContractUri,
            globalFields,
            partyFields,
            salt,
            globalValues,
            parties,
            partyValues,
            expiry,
            msg.sender, // signer
            signature
        );
    }

    /// @notice Create a standalone agreement that:
    /// - Proposer can prepare & sign an agreement in one tx. For single-party agreements that means one tx and done
    /// - Standalone means it creates its own template just-in-time if needed. No more waiting for admin to create the template for you
    /// - Takes `salt` so agreement IDs are deterministic. You can also create identical agreements with distinct IDs if needed
    ///
    /// Note `finalizer` is intentionally fixed at `address(0)` because other values require
    /// tighter integration with vetted smart contracts, which does not fit our use cases here
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
    ) public returns (bytes32 contractId) {
        // Derive template ID
        bytes32 templateId = keccak256(abi.encode(title, legalContractUri, globalFields, partyFields));

        // Create the template if needed
        if (bytes(CyberAgreementRegistryStorage.getStorageData().templates[templateId].legalContractUri).length == 0) {
            CyberAgreementRegistryLib.createTemplate(templateId, title, legalContractUri, globalFields, partyFields);
        }

        contractId = createContract(
            templateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "", // secretHash
            address(0), // fixed finalizer, see notice above
            expiry
        );

        CyberAgreementRegistryLib.signContractFor(
            signer,
            contractId,
            partyValues[0], // proposer
            signature,
            false, // proposer should explicitly add himself to the parties
            "" // secret
        );
    }

    function signContract(
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external {
        CyberAgreementRegistryLib.signContractFor(
            msg.sender, contractId, partyValues, signature, fillUnallocated, secret
        );
    }

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external {
        CyberAgreementRegistryLib.signContractFor(signer, contractId, partyValues, signature, fillUnallocated, secret);
    }

    /// @notice Sign a contract with escrow signatures. It relies on the finalizer to enforce proper access control.
    /// As a result, the finalizer is required to be a predefined smart contract.
    /// @dev See `test_RevertIf_signContractWithEscrowUndefinedFinalizer` for how it prevent exploits
    function signContractWithEscrow(
        address escrowSigner,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external onlyDefinedFinalizer(contractId) {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        ICyberAgreementRegistry.Template memory template = s.templates[agreementData.templateId];
        if (agreementData.parties.length == 0) revert CyberAgreementRegistry.ContractDoesNotExist();
        if (agreementData.signedAt[escrowSigner] != 0) revert CyberAgreementRegistry.AlreadySigned();
        if (agreementData.voided) revert CyberAgreementRegistry.ContractAlreadyVoided();
        if (agreementData.finalized) revert CyberAgreementRegistry.ContractAlreadyFinalized();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp) {
            revert CyberAgreementRegistry.ContractExpired();
        }

        if (!CyberAgreementRegistryLib.isParty(contractId, escrowSigner)) {
            if (agreementData.secretHash > 0 && keccak256(abi.encode(secret)) != agreementData.secretHash) {
                revert CyberAgreementRegistry.InvalidSecret();
            }
            // Not a named party, so check if there's an open slot
            uint256 firstOpenPartyIndex = CyberAgreementRegistryLib.getFirstOpenPartyIndex(contractId);
            if (firstOpenPartyIndex == 0 || !fillUnallocated) revert CyberAgreementRegistry.NotAParty();
            // There is a spare slot, assign the sender to this slot.
            agreementData.parties[firstOpenPartyIndex] = escrowSigner;
            s.agreementsForParty[agreementData.parties[firstOpenPartyIndex]].push(contractId);
        }

        //verify if the contract is closed
        if (agreementData.partyValues[escrowSigner].length > 0) {
            //check that the submitted partyValues match
            if (keccak256(abi.encode(agreementData.partyValues[escrowSigner])) != keccak256(abi.encode(partyValues))) {
                revert CyberAgreementRegistry.ClosedAgreementPartyValueMismatch();
            }
        }

        if (partyValues.length != template.partyFields.length) revert CyberAgreementRegistry.MismatchedFieldsLength();

        uint256 timestamp = block.timestamp;

        agreementData.partyValues[escrowSigner] = partyValues;
        agreementData.signedAt[escrowSigner] = timestamp;
        uint256 totalSignatures = ++agreementData.numSignatures;

        emit ICyberAgreementRegistry.AgreementSigned(contractId, escrowSigner, timestamp);

        if (totalSignatures == agreementData.parties.length) {
            emit ICyberAgreementRegistry.ContractFullySigned(contractId, timestamp);
        }
    }

    function voidContractFor(bytes32 contractId, address party, bytes calldata signature) external {
        //make sure the party is a party to the contract
        if (!CyberAgreementRegistryLib.isParty(contractId, party)) revert CyberAgreementRegistry.NotAParty();

        CyberAgreementRegistryStorage.AgreementData storage agreementData =
            CyberAgreementRegistryStorage.getStorageData().agreements[contractId];
        if (agreementData.finalized) revert CyberAgreementRegistry.ContractAlreadyFinalized();

        //verify the signature
        if (msg.sender != agreementData.finalizer) {
            if (!CyberAgreementRegistryLib.verifyVoidSignature(
                    party,
                    CyberAgreementRegistryLib.VoidSignatureData({contractId: contractId, party: party}),
                    signature
                )) {
                revert CyberAgreementRegistry.SignatureVerificationFailed();
            }
        }

        for (uint256 i = 0; i < agreementData.voidRequestedBy.length; i++) {
            if (agreementData.voidRequestedBy[i] == party) revert CyberAgreementRegistry.ContractAlreadyVoided();
        }

        agreementData.voidRequestedBy.push(party);
        emit CyberAgreementRegistry.VoidRequested(contractId, party);

        // Unanimity is measured against allocated (nonzero) party slots: unfilled address(0)
        // slots in open agreements can never submit a void request (isParty rejects them), so
        // requiring raw parties.length would leave a no-deadline open agreement un-voidable
        // even with every actual party's consent. parties[0] is enforced nonzero at creation,
        // so allocatedParties >= 1 and equality implies at least one request.
        uint256 allocatedParties = 0;
        for (uint256 i = 0; i < agreementData.parties.length; i++) {
            if (agreementData.parties[i] != address(0)) allocatedParties++;
        }

        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp) {
            agreementData.voided = true;
        } else if (agreementData.voidRequestedBy.length == allocatedParties) {
            agreementData.voided = true;
        } else if (agreementData.parties[0] == party && agreementData.numSignatures == 1) {
            agreementData.voided = true;
        }

        if (agreementData.voided) {
            emit CyberAgreementRegistry.ContractVoided(contractId, agreementData.voidRequestedBy, block.timestamp);
        }
    }

    function finalizeContract(bytes32 contractId) external onlyFinalizerIfSet(contractId) {
        CyberAgreementRegistryStorage.AgreementData storage agreementData =
            CyberAgreementRegistryStorage.getStorageData().agreements[contractId];
        if (agreementData.finalized) revert CyberAgreementRegistry.ContractAlreadyFinalized();
        if (agreementData.parties.length == 0) revert CyberAgreementRegistry.ContractDoesNotExist();
        if (agreementData.numSignatures != agreementData.parties.length) {
            revert CyberAgreementRegistry.ContractNotFullySigned();
        }
        if (agreementData.voided) revert CyberAgreementRegistry.ContractAlreadyVoided();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp) {
            revert CyberAgreementRegistry.ContractExpired();
        }

        agreementData.finalized = true;
        emit CyberAgreementRegistry.ContractFinalized(contractId, msg.sender, block.timestamp);
    }

    function setDelegation(address delegate, uint256 expiry) external {
        if (delegate == address(0)) revert CyberAgreementRegistry.DelegateZeroAddress();
        if (delegate == msg.sender) revert CyberAgreementRegistry.DelegateIsSelf();
        if (expiry != 0 && expiry <= block.timestamp) revert CyberAgreementRegistry.ExpiryNotInFuture();

        CyberAgreementRegistryStorage.getStorageData().delegations[msg.sender] =
            CyberAgreementRegistryStorage.Delegation({delegate: delegate, expiry: expiry});
        emit CyberAgreementRegistry.DelegationSet(msg.sender, delegate, expiry);
    }

    /**
     * @dev Revoke delegation for the caller
     */
    function revokeDelegation() external {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        address delegate = s.delegations[msg.sender].delegate;
        delete s.delegations[msg.sender];
        emit CyberAgreementRegistry.DelegationRevoked(msg.sender, delegate);
    }
}
