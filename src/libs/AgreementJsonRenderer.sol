// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from '../CyberAgreementRegistry.sol';
import {ICyberAgreementRegistry} from '../interfaces/ICyberAgreementRegistry.sol';
import {JsonLib} from './JsonLib.sol';

/// @dev Linked, read-only renderer. Keeps the registry within EIP-170 without changing JSON bytes.
library AgreementJsonRenderer {
    function render(CyberAgreementRegistry.AgreementData storage agreementData, ICyberAgreementRegistry.Template storage template) external view returns (string memory) {
        // Start with basic fields
        string memory json = string(
            abi.encodePacked(
                '{"templateId": "',
                _bytes32ToString(agreementData.templateId), // Corrected to use agreementData.templateId
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
                json = string.concat(
                    json,
                    '"',
                    _addressToString(party),
                    '": {'
                );

                // Add party fields and values
                if (template.partyFields.length > 0) {
                    string[] memory values = agreementData.partyValues[party];
                    for (uint256 j = 0; j < template.partyFields.length; j++) {
                        json = string.concat(
                            json,
                            '"',
                            JsonLib.jsonEscape(template.partyFields[j]),
                            '": "'
                        );
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
                json = string.concat(
                    json,
                    '"signedAt": ',
                    _uint256ToString(agreementData.signedAt[party])
                );
                json = string.concat(json, "}");

                if (i + 1 < agreementData.parties.length) {
                    json = string.concat(json, ",");
                }
            }
        }

        // Add metadata
        json = string.concat(
            json,
            '}, "numSignatures": ',
            _uint256ToString(agreementData.numSignatures)
        );
        json = string.concat(
            json,
            ', "isComplete": ',
            agreementData.numSignatures == agreementData.parties.length
                ? "true"
                : "false"
        );
        // Add voided status
        json = string.concat(
            json,
            ', "voided": ',
            agreementData.voided ? "true" : "false"
        );
        // loop and add voidRequestedBy
        json = string.concat(json, ', "voidRequestedBy": [');
        for (uint256 i = 0; i < agreementData.voidRequestedBy.length; i++) {
            json = string.concat(
                json,
                '"',
                _addressToString(agreementData.voidRequestedBy[i]),
                '"'
            );
            if (i + 1 < agreementData.voidRequestedBy.length) {
                json = string.concat(json, ",");
            }
        }
        json = string.concat(json, "]");
        // add finalized status
        json = string.concat(
            json,
            ', "finalized": ',
            agreementData.finalized ? "true" : "false"
        );
        json = string.concat(json, "}");
        return json;
    }

function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
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
    function _addressToString(
        address _addr
    ) internal pure returns (string memory) {
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
    function _uint256ToString(
        uint256 _i
    ) internal pure returns (string memory) {
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
