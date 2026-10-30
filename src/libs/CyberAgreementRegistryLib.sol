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
import {ISignerConditions} from "../interfaces/ISignerConditions.sol";
import {CyberAgreementRegistryStorage} from "../storage/CyberAgreementRegistryStorage.sol";
import {SignerConditionLib} from "./SignerConditionLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title CyberAgreementRegistryLib
/// @notice Logic that more than one registry facet uses. All functions are internal, so each facet
/// gets its own copy and runs it on the registry's storage.
library CyberAgreementRegistryLib {
    // The EIP-712 domain name
    string internal constant NAME = "CyberAgreementRegistry";

    // Type hash for AgreementData. It binds the signer, so a delegate signature counts for one
    // party only.
    bytes32 internal constant SIGNATUREDATA_TYPEHASH = keccak256(
        "SignatureData(bytes32 contractId,address signer,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues)"
    );
    bytes32 internal constant VOIDSIGNATUREDATA_TYPEHASH =
        keccak256("VoidSignatureData(bytes32 contractId,address party)");

    bytes32 internal constant BOUND_TEMPLATE_DOMAIN = keccak256("MetaLeX.CyberAgreementRegistry.BoundTemplate.v1");
    bytes32 internal constant BOUND_AGREEMENT_DOMAIN = keccak256("MetaLeX.CyberAgreementRegistry.BoundAgreement.v1");
    bytes32 internal constant CONDITIONED_BOUND_AGREEMENT_DOMAIN =
        keccak256("MetaLeX.CyberAgreementRegistry.ConditionedBoundAgreement.v1");
    // Type hash for a party with signer conditions. It is SignatureData plus the evidence, so the
    // signature covers the evidence too.
    bytes32 internal constant SIGNATUREWITHEVIDENCEDATA_TYPEHASH = keccak256(
        "SignatureWithEvidenceData(bytes32 contractId,address signer,string legalContractUri,string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues,bytes[] evidence)"
    );

    // This data is what is signed by each party
    struct SignatureData {
        bytes32 contractId;
        // The party the signature consents for. A delegate can sign for more than one party, so
        // the payload must say which one, or the same signature counts for all of them.
        address signer;
        string legalContractUri;
        string[] globalFields;
        string[] partyFields;
        string[] globalValues;
        string[] partyValues;
    }

    struct VoidSignatureData {
        bytes32 contractId;
        address party;
    }

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) internal {
        mapping(bytes32 => ICyberAgreementRegistry.Template) storage templates =
            CyberAgreementRegistryStorage.getStorageData().templates;
        if (bytes(templates[templateId].legalContractUri).length > 0) {
            revert CyberAgreementRegistry.TemplateAlreadyExists();
        }

        if (bytes(title).length == 0) {
            revert CyberAgreementRegistry.TitleEmpty();
        }

        templates[templateId] = ICyberAgreementRegistry.Template({
            legalContractUri: legalContractUri, title: title, globalFields: globalFields, partyFields: partyFields
        });

        emit ICyberAgreementRegistry.TemplateCreated(templateId, title, legalContractUri, globalFields, partyFields);
    }

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes memory signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) internal {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        // A party with signer conditions signs with evidence. See `signContractWithEvidenceFor()`.
        if (SignerConditionLib.conditionsOf(contractId, signer).length != 0) {
            revert ISignerConditions.EvidenceRequired();
        }

        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        ICyberAgreementRegistry.Template memory template = s.templates[agreementData.templateId];
        if (agreementData.parties.length == 0) revert CyberAgreementRegistry.ContractDoesNotExist();
        if (agreementData.signedAt[signer] != 0) revert CyberAgreementRegistry.AlreadySigned();
        if (agreementData.voided) revert CyberAgreementRegistry.ContractAlreadyVoided();
        if (agreementData.finalized) revert CyberAgreementRegistry.ContractAlreadyFinalized();
        if (agreementData.expiry > 0 && agreementData.expiry < block.timestamp) {
            revert CyberAgreementRegistry.ContractExpired();
        }

        if (!isParty(contractId, signer)) {
            if (agreementData.secretHash > 0 && keccak256(abi.encode(secret)) != agreementData.secretHash) {
                revert CyberAgreementRegistry.InvalidSecret();
            }
            // Not a named party, so check if there's an open slot
            uint256 firstOpenPartyIndex = getFirstOpenPartyIndex(contractId);
            if (firstOpenPartyIndex == 0 || !fillUnallocated) revert CyberAgreementRegistry.NotAParty();
            // There is a spare slot, assign the sender to this slot.
            agreementData.parties[firstOpenPartyIndex] = signer;
            s.agreementsForParty[agreementData.parties[firstOpenPartyIndex]].push(contractId);
        }

        //verify if the contract is closed
        if (agreementData.partyValues[signer].length > 0) {
            //check that the submitted partyValues match
            if (keccak256(abi.encode(agreementData.partyValues[signer])) != keccak256(abi.encode(partyValues))) {
                revert CyberAgreementRegistry.ClosedAgreementPartyValueMismatch();
            }
        }

        // Verify the signature
        if (!verifySignature(
                signer,
                SignatureData({
                    contractId: contractId,
                    signer: signer,
                    legalContractUri: template.legalContractUri,
                    globalFields: template.globalFields,
                    partyFields: template.partyFields,
                    globalValues: agreementData.globalValues,
                    partyValues: partyValues
                }),
                signature
            )) {
            revert CyberAgreementRegistry.SignatureVerificationFailed();
        }

        if (
            address(0) != agreementData.finalizer // if finalizer is undefined, as long as the signature is valid we still allow it
                && msg.sender != agreementData.finalizer && msg.sender != signer
        ) {
            revert CyberAgreementRegistry.NotFinalizer();
        }

        if (partyValues.length != template.partyFields.length) revert CyberAgreementRegistry.MismatchedFieldsLength();

        uint256 timestamp = block.timestamp;

        agreementData.partyValues[signer] = partyValues;
        agreementData.signedAt[signer] = timestamp;
        uint256 totalSignatures = ++agreementData.numSignatures;

        emit ICyberAgreementRegistry.AgreementSigned(contractId, signer, timestamp);

        if (totalSignatures == agreementData.parties.length) {
            if (agreementData.finalizer == address(0)) {
                agreementData.finalized = true;
                emit CyberAgreementRegistry.ContractFinalized(contractId, msg.sender, timestamp);
            }

            emit ICyberAgreementRegistry.ContractFullySigned(contractId, timestamp);
        }
    }

    function isParty(bytes32 contractId, address user) internal view returns (bool) {
        if (user == address(0)) {
            return false;
        }

        // Check direct party membership
        address[] memory parties = CyberAgreementRegistryStorage.getStorageData().agreements[contractId].parties;
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == user) {
                return true;
            }
        }

        return false;
    }

    function getFirstOpenPartyIndex(bytes32 contractId) internal view returns (uint256) {
        CyberAgreementRegistryStorage.AgreementData storage agreementData =
            CyberAgreementRegistryStorage.getStorageData().agreements[contractId];
        for (uint256 i = 0; i < agreementData.parties.length; i++) {
            if (agreementData.parties[i] == address(0)) {
                return i;
            }
        }
        // NOTE: 0 can never be an open party
        return 0;
    }

    /// @notice True if `recovered` is `signer`, or is a delegate of `signer` that has not expired.
    function isSignerOrDelegate(address signer, address recovered) internal view returns (bool) {
        // Check direct signature
        if (recovered == signer) {
            return true;
        }

        // Check delegation signature
        CyberAgreementRegistryStorage.Delegation storage delegation =
            CyberAgreementRegistryStorage.getStorageData().delegations[signer];
        return delegation.delegate == recovered && (delegation.expiry == 0 || delegation.expiry > block.timestamp);
    }

    function verifySignature(address signer, SignatureData memory data, bytes memory signature)
        internal
        view
        returns (bool)
    {
        // Hash the data (AgreementData) according to EIP-712
        bytes32 digest = hashTypedData(
            keccak256(
                abi.encode(
                    SIGNATUREDATA_TYPEHASH,
                    data.contractId,
                    data.signer,
                    keccak256(bytes(data.legalContractUri)),
                    hashStringArray(data.globalFields),
                    hashStringArray(data.partyFields),
                    hashStringArray(data.globalValues),
                    hashStringArray(data.partyValues)
                )
            )
        );
        return isSignerOrDelegate(signer, ECDSA.recover(digest, signature));
    }

    function verifyVoidSignature(address signer, VoidSignatureData memory data, bytes memory signature)
        internal
        view
        returns (bool)
    {
        // Hash the data (VoidSignatureData) according to EIP-712
        bytes32 digest = hashTypedData(keccak256(abi.encode(VOIDSIGNATUREDATA_TYPEHASH, data.contractId, data.party)));
        return isSignerOrDelegate(signer, ECDSA.recover(digest, signature));
    }

    // Hash a struct hash with the registry's EIP-712 domain
    function hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", CyberAgreementRegistryStorage.getStorageData().domainSeparator, structHash)
        );
    }

    // Helper function to hash string arrays
    function hashStringArray(string[] memory array) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            hashes[i] = keccak256(bytes(array[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
