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

import {Vm} from "forge-std/Test.sol";

/**
 * @title CyberAgreementV2Utils
 * @notice Utility library for CyberAgreementRegistryV2 EIP-712 signing
 */
library CyberAgreementV2Utils {
    /**
     * @notice Signs agreement data using EIP-712
     * @param vm The VM instance from forge-std
     * @param domainSeparator The EIP-712 domain separator
     * @param agreementTypehash The agreement signature typehash
     * @param agreementId The agreement identifier
     * @param template The template contract address
     * @param templateData The encoded template data
     * @param parties Array of party addresses
     * @param partyData The signer's encoded party data (not all parties)
     * @param privKey The private key to sign with
     * @return signature The EIP-712 signature
     */
    function signAgreement(
        Vm vm,
        bytes32 domainSeparator,
        bytes32 agreementTypehash,
        bytes32 agreementId,
        address template,
        bytes memory templateData,
        address[] memory parties,
        bytes memory partyData,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        // Hash template data
        bytes32 templateDataHash = keccak256(templateData);

        // Hash parties array
        bytes32 partiesHash = keccak256(abi.encodePacked(parties));

        // Hash signer's party data only
        bytes32 partyDataHash = keccak256(partyData);

        // Create struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                agreementTypehash,
                agreementId,
                template,
                templateDataHash,
                partiesHash,
                partyDataHash
            )
        );

        return _signTypedData(vm, domainSeparator, structHash, privKey);
    }

    /**
     * @notice Signs void agreement data using EIP-712
     * @param vm The VM instance from forge-std
     * @param domainSeparator The EIP-712 domain separator
     * @param voidTypehash The void signature typehash
     * @param agreementId The agreement identifier
     * @param party The party requesting void
     * @param privKey The private key to sign with
     * @return signature The EIP-712 signature
     */
    function signVoid(
        Vm vm,
        bytes32 domainSeparator,
        bytes32 voidTypehash,
        bytes32 agreementId,
        address party,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        bytes32 structHash = keccak256(
            abi.encode(voidTypehash, agreementId, party)
        );

        return _signTypedData(vm, domainSeparator, structHash, privKey);
    }

    /**
     * @notice Internal function to sign typed data
     */
    function _signTypedData(
        Vm vm,
        bytes32 domainSeparator,
        bytes32 structHash,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
