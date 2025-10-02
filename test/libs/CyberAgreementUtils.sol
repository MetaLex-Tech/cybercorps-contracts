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

library CyberAgreementUtils {
    function signAgreementTypedData(
        Vm vm,
        bytes32 _domainSeparator,
        bytes32 _typeHash,
        bytes32 contractId,
        string memory contractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        // Hash string arrays the same way as the contract
        bytes32 contractUriHash = keccak256(bytes(contractUri));
        bytes32 globalFieldsHash = _hashStringArray(globalFields);
        bytes32 partyFieldsHash = _hashStringArray(partyFields);
        bytes32 globalValuesHash = _hashStringArray(globalValues);
        bytes32 partyValuesHash = _hashStringArray(partyValues);

        // Create the message hash using the same approach as the contract
        bytes32 structHash = keccak256(
            abi.encode(
                _typeHash,
                contractId,
                contractUriHash,
                globalFieldsHash,
                partyFieldsHash,
                globalValuesHash,
                partyValuesHash
            )
        );

        return _signTypedData(vm, _domainSeparator, structHash, privKey);
    }

    function signVoidAgreementTypedData(
        Vm vm,
        bytes32 _domainSeparator,
        bytes32 _typeHash,
        bytes32 contractId,
        address party,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        // Create the message hash using the same approach as the contract
        bytes32 structHash = keccak256(
            abi.encode(_typeHash, contractId, party)
        );

        return _signTypedData(vm, _domainSeparator, structHash, privKey);
    }

    function _signTypedData(
        Vm vm,
        bytes32 _domainSeparator,
        bytes32 structHash,
        uint256 privKey
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }

    // Add this helper function to your test contract
    function _hashStringArray(
        string[] memory array
    ) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            hashes[i] = keccak256(bytes(array[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
