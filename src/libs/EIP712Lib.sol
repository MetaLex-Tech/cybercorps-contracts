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
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

/// @title EIP712Lib
/// @notice Shared EIP-712 signature verification. A single helper builds the domain separator, wraps the
/// caller's `structHash` into the typed-data digest (via OZ MessageHashUtils), recovers the signer and
/// compares it. Each consumer only computes its own `structHash` and picks its domain name/version. The
/// domain separator is built here (not via OZ's `EIP712`) because OZ's builder is private and bound to
/// constructor immutables — unusable from the delegatecalled linked libraries (with per-consumer domain
/// name and proxy verifyingContract) that verify signatures in this codebase.
library EIP712Lib {
    using ECDSA for bytes32;

    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    /// @notice Verifies `signature` over the EIP-712 typed data for the given domain and `structHash`.
    /// @param name Domain name (per consumer, e.g. "RoundManager" / "DealManager")
    /// @param version Domain version
    /// @param verifyingContract Domain verifyingContract (pass `address(this)` from a delegatecalled lib)
    /// @param signer Expected signer address
    /// @param structHash EIP-712 hashStruct of the message the consumer built
    /// @param signature Signature bytes to recover
    /// @return success True if the recovered signer matches `signer`
    function verifySignature(
        string memory name,
        string memory version,
        address verifyingContract,
        address signer,
        bytes32 structHash,
        bytes memory signature
    ) internal view returns (bool success) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        return digest.recover(signature) == signer;
    }
}
