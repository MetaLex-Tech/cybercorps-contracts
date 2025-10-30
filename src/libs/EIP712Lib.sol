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

pragma solidity ^0.8.28;

import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

library EIP712Lib {
    using ECDSA for bytes32;

    // EIP-712 domain constants
    string constant EIP712_NAME = "RoundManager";
    string constant EIP712_VERSION = "1";
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    struct EscrowedSignatureData {
        bytes32 roundId;
        uint8 seriesType;
        uint256 raiseCap;
        uint256 minTicket;
        uint256 maxTicket;
        uint8 roundType;
        uint256 startTime;
        uint256 endTime;
        bytes32 templateId;
        address paymentToken;
        uint256 pricePerUnit;
        uint256 valuation;
        address companyAddress;
    }

    /// @notice Computes the EIP-712 typed data hash for escrowed round parameters
    /// @param data Escrowed round parameters to be hashed
    /// @return digest EIP-712 typed data digest used for signature verification
    function hashEscrowedTypedDataV4(
        address _this,
        EscrowedSignatureData memory data
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(EIP712_NAME)),
                keccak256(bytes(EIP712_VERSION)),
                block.chainid,
                _this
            )
        );
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        ESCROWEDSIGNATUREDATA_TYPEHASH,
                        data.roundId,
                        data.seriesType,
                        data.raiseCap,
                        data.minTicket,
                        data.maxTicket,
                        data.roundType,
                        data.startTime,
                        data.endTime,
                        data.templateId,
                        data.paymentToken,
                        data.pricePerUnit,
                        data.valuation,
                        data.companyAddress
                    )
                )
            )
        );
    }

    /// @notice Verifies an escrowed signature against expected signer using EIP-712
    /// @param signer Expected signer address (e.g., authority officer EOA)
    /// @param data Escrowed round parameters used to build the typed data
    /// @param signature Signature bytes produced over the typed data
    /// @return isValid True if the recovered signer matches the expected signer
    function verifyEscrowedSignature(
        address _this,
        address signer,
        EscrowedSignatureData memory data,
        bytes memory signature
    ) external view returns (bool) {
        bytes32 digest = hashEscrowedTypedDataV4(_this, data);
        address recoveredSigner = digest.recover(signature);
        return recoveredSigner == signer;
    }
}
