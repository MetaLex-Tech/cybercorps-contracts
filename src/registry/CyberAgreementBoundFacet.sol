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
import {ISignerConditions, SignerCondition} from "../interfaces/ISignerConditions.sol";
import {CyberAgreementRegistryLib} from "../libs/CyberAgreementRegistryLib.sol";
import {SignerConditionLib} from "../libs/SignerConditionLib.sol";
import {BorgAuth} from "../libs/auth.sol";
import {CyberAgreementRegistryStorage} from "../storage/CyberAgreementRegistryStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title CyberAgreementBoundFacet
/// @notice Registry facet for creator-bound agreements, signer conditions, and signing with evidence.
/// The router delegatecalls it, so it writes the registry's storage and emits the registry's events.
contract CyberAgreementBoundFacet {
    /// @dev The router holds BorgAuthACL. This facet reads AUTH through the router, so it does not
    /// depend on the router's storage layout.
    modifier onlyAdmin() {
        BorgAuth auth = CyberAgreementRegistry(address(this)).AUTH();
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
        _;
    }

    /// @notice Create a template and an unsigned agreement whose ids are bound to
    /// `msg.sender` and every stored term. Exact parties only; no secret or finalizer.
    function createBoundContract(
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry
    ) external returns (bytes32 templateId, bytes32 contractId) {
        return _create(
            msg.sender, template, salt, globalValues, parties, partyValues, expiry, new SignerCondition[][](0)
        );
    }

    /// @notice See `createBoundContract()`. Each party must also pass its conditions to sign.
    /// @param conditions `conditions[i]` lists the conditions of `parties[i]`. They are part of the
    /// agreement id. An empty list gives the same agreement as `createBoundContract()` without conditions.
    function createBoundContract(
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions
    ) external returns (bytes32 templateId, bytes32 contractId) {
        return _create(msg.sender, template, salt, globalValues, parties, partyValues, expiry, conditions);
    }

    /// @notice See `createBoundContract()`. Bound to `parties[0]` and records their signature.
    function createBoundContractAndSignFor(
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        bytes calldata creatorSignature
    ) external returns (bytes32 templateId, bytes32 contractId) {
        return _createAndSignFor(
            template,
            salt,
            globalValues,
            parties,
            partyValues,
            expiry,
            new SignerCondition[][](0),
            new bytes[](0),
            creatorSignature
        );
    }

    /// @notice See `createBoundContractAndSignFor()` and the `createBoundContract()` with conditions.
    /// @param creatorEvidence Empty when `parties[0]` has no conditions. Otherwise see
    /// `signContractWithEvidenceFor()`.
    function createBoundContractAndSignFor(
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions,
        bytes[] memory creatorEvidence,
        bytes calldata creatorSignature
    ) external returns (bytes32 templateId, bytes32 contractId) {
        return _createAndSignFor(
            template, salt, globalValues, parties, partyValues, expiry, conditions, creatorEvidence, creatorSignature
        );
    }

    /// @notice The ids that a bound creation by `creator` gives. Clients use it to know the
    /// agreement id before creation, for example to put it in a proof.
    /// @dev With no conditions, the ids are the same as before conditions existed.
    function boundIdsOf(
        address creator,
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions
    ) public pure returns (bytes32 templateId, bytes32 contractId) {
        templateId = keccak256(
            abi.encode(
                CyberAgreementRegistryLib.BOUND_TEMPLATE_DOMAIN,
                creator,
                salt,
                template.title,
                template.legalContractUri,
                template.globalFields,
                template.partyFields
            )
        );
        bytes32 terms = keccak256(
            abi.encode(creator, templateId, salt, globalValues, parties, keccak256(abi.encode(partyValues)), expiry)
        );
        if (conditions.length == 0) {
            contractId = keccak256(abi.encode(CyberAgreementRegistryLib.BOUND_AGREEMENT_DOMAIN, terms));
        } else {
            contractId = keccak256(
                abi.encode(
                    CyberAgreementRegistryLib.CONDITIONED_BOUND_AGREEMENT_DOMAIN,
                    terms,
                    keccak256(abi.encode(conditions))
                )
            );
        }
    }

    /// @notice Sign for a party with signer conditions. The party passes each condition with its evidence
    /// in this call. The signature uses `SIGNATUREWITHEVIDENCEDATA_TYPEHASH`, so it covers the evidence.
    /// A bound agreement has no finalizer, open slot or secret.
    /// @param evidence `evidence[j]` is for the party's condition `j`, as the struct that its kind defines.
    function signContractWithEvidenceFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes[] memory evidence,
        bytes calldata signature
    ) public {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        if (agreementData.parties.length == 0) revert CyberAgreementRegistry.ContractDoesNotExist();
        if (agreementData.signedAt[signer] != 0) revert CyberAgreementRegistry.AlreadySigned();
        if (agreementData.voided) revert CyberAgreementRegistry.ContractAlreadyVoided();
        if (agreementData.finalized) revert CyberAgreementRegistry.ContractAlreadyFinalized();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp) {
            revert CyberAgreementRegistry.ContractExpired();
        }

        // Only the named parties of a bound agreement have conditions.
        uint256 conditionCount = SignerConditionLib.conditionsOf(contractId, signer).length;
        if (conditionCount == 0) revert ISignerConditions.NoSignerConditions();
        if (evidence.length != conditionCount) revert ISignerConditions.EvidenceLengthMismatch();

        // A bound agreement stores the values of every party at creation.
        if (keccak256(abi.encode(agreementData.partyValues[signer])) != keccak256(abi.encode(partyValues))) {
            revert CyberAgreementRegistry.ClosedAgreementPartyValueMismatch();
        }

        ICyberAgreementRegistry.Template memory template = s.templates[agreementData.templateId];
        bytes32 digest = CyberAgreementRegistryLib.hashTypedData(
            keccak256(
                abi.encode(
                    CyberAgreementRegistryLib.SIGNATUREWITHEVIDENCEDATA_TYPEHASH,
                    contractId,
                    signer,
                    keccak256(bytes(template.legalContractUri)),
                    CyberAgreementRegistryLib.hashStringArray(template.globalFields),
                    CyberAgreementRegistryLib.hashStringArray(template.partyFields),
                    CyberAgreementRegistryLib.hashStringArray(agreementData.globalValues),
                    CyberAgreementRegistryLib.hashStringArray(partyValues),
                    _hashBytesArray(evidence)
                )
            )
        );
        if (!CyberAgreementRegistryLib.isSignerOrDelegate(signer, ECDSA.recover(digest, signature))) {
            revert CyberAgreementRegistry.SignatureVerificationFailed();
        }

        SignerConditionLib.verifyAll(contractId, signer, evidence);

        uint256 timestamp = block.timestamp;
        agreementData.signedAt[signer] = timestamp;
        uint256 totalSignatures = ++agreementData.numSignatures;
        emit ICyberAgreementRegistry.AgreementSigned(contractId, signer, timestamp);

        if (totalSignatures == agreementData.parties.length) {
            agreementData.finalized = true;
            emit CyberAgreementRegistry.ContractFinalized(contractId, msg.sender, timestamp);
            emit ICyberAgreementRegistry.ContractFullySigned(contractId, timestamp);
        }
    }

    /// @notice Set the config of a condition kind, as the struct that the kind defines. It applies to all
    /// agreements.
    function setSignerConditionConfig(bytes32 kind, bytes calldata config) external onlyAdmin {
        SignerConditionLib.setConfig(kind, config);
    }

    function getSignerConditionConfig(bytes32 kind) external view returns (bytes memory) {
        return SignerConditionLib.getConfig(kind);
    }

    /// @notice Create a template and an unsigned agreement whose ids bind `creator`, every
    /// stored term and the conditions. Exact parties only; no secret or finalizer.
    function _create(
        address creator,
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions
    ) private returns (bytes32 templateId, bytes32 contractId) {
        if (bytes(template.legalContractUri).length == 0) {
            revert CyberAgreementRegistry.TemplateDoesNotExist();
        }
        if (parties.length == 0) revert CyberAgreementRegistry.InvalidPartyCount();
        if (partyValues.length != parties.length) revert CyberAgreementRegistry.MismatchedPartyValuesLength();
        if (globalValues.length != template.globalFields.length) {
            revert CyberAgreementRegistry.MismatchedFieldsLength();
        }
        if (expiry != 0 && expiry <= block.timestamp) revert CyberAgreementRegistry.ExpiryNotInFuture();
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == address(0)) revert CyberAgreementRegistry.FirstPartyZeroAddress();
            if (partyValues[i].length != template.partyFields.length) {
                revert CyberAgreementRegistry.MismatchedFieldsLength();
            }
            for (uint256 j = 0; j < i; j++) {
                if (parties[i] == parties[j]) revert CyberAgreementRegistry.DuplicateParty();
            }
        }
        SignerConditionLib.checkLength(conditions, parties.length);

        (templateId, contractId) =
            boundIdsOf(creator, template, salt, globalValues, parties, partyValues, expiry, conditions);

        CyberAgreementRegistryLib.createTemplate(
            templateId, template.title, template.legalContractUri, template.globalFields, template.partyFields
        );

        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        if (agreementData.parties.length > 0) revert CyberAgreementRegistry.ContractAlreadyExists();
        agreementData.templateId = templateId;
        agreementData.globalValues = globalValues;
        agreementData.parties = parties;
        agreementData.expiry = expiry;
        for (uint256 i = 0; i < parties.length; i++) {
            agreementData.partyValues[parties[i]] = partyValues[i];
        }

        emit ICyberAgreementRegistry.ContractCreated(contractId, templateId, parties);

        SignerConditionLib.set(contractId, parties, conditions);

        for (uint256 i = 0; i < parties.length; i++) {
            s.agreementsForParty[parties[i]].push(contractId);
        }
    }

    function _createAndSignFor(
        ICyberAgreementRegistry.Template memory template,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        SignerCondition[][] memory conditions,
        bytes[] memory creatorEvidence,
        bytes calldata creatorSignature
    ) private returns (bytes32 templateId, bytes32 contractId) {
        if (parties.length == 0) revert CyberAgreementRegistry.InvalidPartyCount();
        (templateId, contractId) =
            _create(parties[0], template, salt, globalValues, parties, partyValues, expiry, conditions);
        if (creatorEvidence.length == 0) {
            CyberAgreementRegistryLib.signContractFor(
                parties[0], contractId, partyValues[0], creatorSignature, false, ""
            );
        } else {
            signContractWithEvidenceFor(parties[0], contractId, partyValues[0], creatorEvidence, creatorSignature);
        }
    }

    function _hashBytesArray(bytes[] memory array) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            hashes[i] = keccak256(array[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
