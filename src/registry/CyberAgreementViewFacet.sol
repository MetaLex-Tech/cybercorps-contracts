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

import {ICyberAgreementRegistry} from "../interfaces/ICyberAgreementRegistry.sol";
import {CyberAgreementRegistryLib} from "../libs/CyberAgreementRegistryLib.sol";
import {JsonLib} from "../libs/JsonLib.sol";
import {CyberAgreementRegistryStorage} from "../storage/CyberAgreementRegistryStorage.sol";

/// @title CyberAgreementViewFacet
/// @notice Registry facet for constants, getters and the agreement JSON.
/// The router delegatecalls it, so it reads the registry's storage.
contract CyberAgreementViewFacet {
    // Domain information
    string public constant name = CyberAgreementRegistryLib.NAME;

    bytes32 public constant SIGNATUREDATA_TYPEHASH = CyberAgreementRegistryLib.SIGNATUREDATA_TYPEHASH;
    bytes32 public constant VOIDSIGNATUREDATA_TYPEHASH = CyberAgreementRegistryLib.VOIDSIGNATUREDATA_TYPEHASH;
    bytes32 public constant BOUND_TEMPLATE_DOMAIN = CyberAgreementRegistryLib.BOUND_TEMPLATE_DOMAIN;
    bytes32 public constant BOUND_AGREEMENT_DOMAIN = CyberAgreementRegistryLib.BOUND_AGREEMENT_DOMAIN;
    bytes32 public constant CONDITIONED_BOUND_AGREEMENT_DOMAIN =
        CyberAgreementRegistryLib.CONDITIONED_BOUND_AGREEMENT_DOMAIN;
    bytes32 public constant SIGNATUREWITHEVIDENCEDATA_TYPEHASH =
        CyberAgreementRegistryLib.SIGNATUREWITHEVIDENCEDATA_TYPEHASH;

    function version() external view returns (string memory) {
        return CyberAgreementRegistryStorage.getStorageData().version;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return CyberAgreementRegistryStorage.getStorageData().domainSeparator;
    }

    function templates(bytes32 templateId) external view returns (string memory legalContractUri, string memory title) {
        ICyberAgreementRegistry.Template storage template =
            CyberAgreementRegistryStorage.getStorageData().templates[templateId];
        return (template.legalContractUri, template.title);
    }

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
        )
    {
        CyberAgreementRegistryStorage.AgreementData storage agreementData =
            CyberAgreementRegistryStorage.getStorageData().agreements[contractId];
        return (
            agreementData.templateId,
            agreementData.numSignatures,
            agreementData.finalizer,
            agreementData.finalized,
            agreementData.voided,
            agreementData.secretHash,
            agreementData.expiry
        );
    }

    function agreementsForParty(address party, uint256 index) external view returns (bytes32) {
        return CyberAgreementRegistryStorage.getStorageData().agreementsForParty[party][index];
    }

    function delegations(address delegator) external view returns (address delegate, uint256 expiry) {
        return getDelegation(delegator);
    }

    /**
     * @dev Get delegation info for a given address
     * @param delegator The address to check for delegation
     * @return delegate The delegate address
     * @return expiry The expiry timestamp (0 if no expiry)
     */
    function getDelegation(address delegator) public view returns (address delegate, uint256 expiry) {
        CyberAgreementRegistryStorage.Delegation storage delegation =
            CyberAgreementRegistryStorage.getStorageData().delegations[delegator];
        return (delegation.delegate, delegation.expiry);
    }

    /**
     * @dev Check if a delegation is valid (not expired)
     * @param delegator The delegator address
     * @return True if delegation exists and is not expired
     */
    function isValidDelegation(address delegator) external view returns (bool) {
        CyberAgreementRegistryStorage.Delegation storage delegation =
            CyberAgreementRegistryStorage.getStorageData().delegations[delegator];
        return delegation.delegate != address(0) && (delegation.expiry == 0 || delegation.expiry > block.timestamp);
    }

    /**
     * @dev Check if an address is a valid delegate for a given delegator
     * @param delegator The delegator address
     * @param delegate The delegate address to check
     * @return True if the delegate is valid and not expired
     */
    function isValidDelegate(address delegator, address delegate) external view returns (bool) {
        CyberAgreementRegistryStorage.Delegation storage delegation =
            CyberAgreementRegistryStorage.getStorageData().delegations[delegator];
        return delegation.delegate == delegate && (delegation.expiry == 0 || delegation.expiry > block.timestamp);
    }

    function getParties(bytes32 contractId) external view returns (address[] memory) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].parties;
    }

    function hasSigned(bytes32 contractId, address signer) external view returns (bool) {
        if (signer == address(0)) revert ICyberAgreementRegistry.NotAParty();
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].signedAt[signer] != 0;
    }

    function getSignatureTimestamp(bytes32 contractId, address signer) external view returns (uint256) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].signedAt[signer];
    }

    function allPartiesSigned(bytes32 contractId) external view returns (bool) {
        CyberAgreementRegistryStorage.AgreementData storage agreementData =
            CyberAgreementRegistryStorage.getStorageData().agreements[contractId];
        return agreementData.numSignatures == agreementData.parties.length;
    }

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
        )
    {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        ICyberAgreementRegistry.Template memory template = s.templates[agreementData.templateId];

        if (agreementData.parties.length == 0) revert ICyberAgreementRegistry.ContractDoesNotExist();

        // Collect all party values and timestamps
        string[][] memory allPartyValues = new string[][](agreementData.parties.length);
        uint256[] memory allSignedAt = new uint256[](agreementData.parties.length);

        for (uint256 i = 0; i < agreementData.parties.length; i++) {
            address party = agreementData.parties[i];
            allPartyValues[i] = agreementData.partyValues[party];
            allSignedAt[i] = agreementData.signedAt[party];
        }

        return (
            agreementData.templateId,
            template.legalContractUri,
            template.globalFields,
            template.partyFields,
            agreementData.globalValues,
            agreementData.parties,
            allPartyValues,
            allSignedAt,
            agreementData.numSignatures,
            agreementData.numSignatures == agreementData.parties.length
        );
    }

    function getTemplateDetails(bytes32 templateId)
        external
        view
        returns (
            string memory legalContractUri,
            string memory title,
            string[] memory globalFields,
            string[] memory signerFields
        )
    {
        ICyberAgreementRegistry.Template storage template =
            CyberAgreementRegistryStorage.getStorageData().templates[templateId];
        if (bytes(template.legalContractUri).length == 0) revert ICyberAgreementRegistry.TemplateDoesNotExist();

        return (template.legalContractUri, template.title, template.globalFields, template.partyFields);
    }

    function getSignerValues(bytes32 contractId, address signer) external view returns (string[] memory signerValues) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].partyValues[signer];
    }

    // This makes fetching all agreements for a party easier from a client, as the
    // default getter requires an index
    function getAgreementsForParty(address party) external view returns (bytes32[] memory) {
        return CyberAgreementRegistryStorage.getStorageData().agreementsForParty[party];
    }

    function getVoidRequestedBy(bytes32 contractId) external view returns (address[] memory) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].voidRequestedBy;
    }

    function isFinalized(bytes32 contractId) external view returns (bool) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].finalized;
    }

    function isVoided(bytes32 contractId) external view returns (bool) {
        return CyberAgreementRegistryStorage.getStorageData().agreements[contractId].voided;
    }

    function _bytes32ToString(bytes32 _bytes32) external pure returns (string memory) {
        return bytes32ToString(_bytes32);
    }

    function getContractJson(bytes32 contractId) external view returns (string memory) {
        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        CyberAgreementRegistryStorage.AgreementData storage agreementData = s.agreements[contractId];
        ICyberAgreementRegistry.Template storage template = s.templates[agreementData.templateId];

        // Start with basic fields
        string memory json = string(
            abi.encodePacked(
                '{"templateId": "',
                bytes32ToString(agreementData.templateId), // Corrected to use agreementData.templateId
                '", "title": "',
                JsonLib.jsonEscape(template.title),
                '", "legalContractUri": "',
                JsonLib.jsonEscape(template.legalContractUri),
                '", "ContractFields": {'
            )
        );

        // Add global fields and values as key-value pairs
        if (template.globalFields.length > 0) {
            for (uint256 i = 0; i < template.globalFields.length; i++) {
                json = string.concat(
                    json,
                    '"',
                    JsonLib.jsonEscape(template.globalFields[i]),
                    '": "',
                    JsonLib.jsonEscape(agreementData.globalValues[i]),
                    '"'
                );
                if (i + 1 < template.globalFields.length) {
                    json = string.concat(json, ",");
                }
            }
        }
        json = string.concat(json, '}, "parties": {');

        // Add parties and their values as key-value pairs
        if (agreementData.parties.length > 0) {
            for (uint256 i = 0; i < agreementData.parties.length; i++) {
                address party = agreementData.parties[i];
                json = string.concat(json, '"', _addressToString(party), '": {');

                // Add party fields and values
                if (template.partyFields.length > 0) {
                    string[] memory values = agreementData.partyValues[party];
                    for (uint256 j = 0; j < template.partyFields.length; j++) {
                        json = string.concat(json, '"', JsonLib.jsonEscape(template.partyFields[j]), '": "');
                        if (values.length > j) {
                            json = string.concat(json, JsonLib.jsonEscape(values[j]));
                        }
                        json = string.concat(json, '"');
                        if (j + 1 < template.partyFields.length) {
                            json = string.concat(json, ",");
                        }
                    }
                }

                // Add signature timestamp
                if (template.partyFields.length > 0) {
                    json = string.concat(json, ",");
                }
                json = string.concat(json, '"signedAt": ', _uint256ToString(agreementData.signedAt[party]));
                json = string.concat(json, "}");

                if (i + 1 < agreementData.parties.length) {
                    json = string.concat(json, ",");
                }
            }
        }

        // Add metadata
        json = string.concat(json, '}, "numSignatures": ', _uint256ToString(agreementData.numSignatures));
        json = string.concat(
            json, ', "isComplete": ', agreementData.numSignatures == agreementData.parties.length ? "true" : "false"
        );
        // Add voided status
        json = string.concat(json, ', "voided": ', agreementData.voided ? "true" : "false");
        // loop and add voidRequestedBy
        json = string.concat(json, ', "voidRequestedBy": [');
        for (uint256 i = 0; i < agreementData.voidRequestedBy.length; i++) {
            json = string.concat(json, '"', _addressToString(agreementData.voidRequestedBy[i]), '"');
            if (i + 1 < agreementData.voidRequestedBy.length) {
                json = string.concat(json, ",");
            }
        }
        json = string.concat(json, "]");
        // add finalized status
        json = string.concat(json, ', "finalized": ', agreementData.finalized ? "true" : "false");
        json = string.concat(json, "}");
        return json;
    }

    function bytes32ToString(bytes32 _bytes32) private pure returns (string memory) {
        bytes memory bytesArray = new bytes(66); // 0x prefix + 64 hex chars
        bytesArray[0] = "0";
        bytesArray[1] = "x";

        for (uint256 i = 0; i < 32; i++) {
            uint8 byteValue = uint8(_bytes32[i]);
            // High nibble (first hex char)
            uint8 highNibble = (byteValue >> 4) & 0x0F;
            bytesArray[2 + i * 2] = bytes1(highNibble < 10 ? 48 + highNibble : 87 + highNibble);
            // Low nibble (second hex char)
            uint8 lowNibble = byteValue & 0x0F;
            bytesArray[3 + i * 2] = bytes1(lowNibble < 10 ? 48 + lowNibble : 87 + lowNibble);
        }
        return string(bytesArray);
    }

    // Helper function to convert address to string
    function _addressToString(address _addr) private pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint160(_addr) >> (8 * (19 - i))));
            uint8 hi = uint8(b) >> 4;
            uint8 lo = uint8(b) & 0x0f;
            s[2 * i] = bytes1(hi + (hi < 10 ? 48 : 87));
            s[2 * i + 1] = bytes1(lo + (lo < 10 ? 48 : 87));
        }
        return string(abi.encodePacked("0x", s));
    }

    // Helper function to convert uint256 to string
    function _uint256ToString(uint256 _i) private pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
