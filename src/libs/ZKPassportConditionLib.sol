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

import "../interfaces/IZKPassportVerifier.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @notice `params` of a ZKPassport condition.
/// @param uniqueIdentifier The only passport the party can use. `bytes32(0)` lets the party use any passport.
struct ZKPassportCondition {
    bytes32 uniqueIdentifier;
}

/// @notice Evidence of a ZKPassport condition. The proof commits to the agreement id, the chain and the signer.
struct ZKPassportEvidence {
    ProofVerificationParams proof;
}

/// @notice `result` of a ZKPassport condition, in `SignerConditionMet`.
struct ZKPassportResult {
    bytes32 uniqueIdentifier;
}

/// @notice `config` of the ZKPassport kind. One config applies to all agreements.
/// @param devMode Accept dev-mode proofs. Use it on a testnet only.
struct ZKPassportConfig {
    address verifier;
    string domain;
    string scope;
    bool devMode;
}

/// @title ZKPassportConditionLib
/// @notice The party must sign with a passport proof.
/// - The creator can pin a passport for a party.
/// - In one agreement, a passport can fill one party only.
/// - Only the passport's unique identifier goes on-chain. No PII.
/// It runs inside the registry, so its state is in the registry's storage.
library ZKPassportConditionLib {
    bytes32 internal constant KIND = keccak256("MetaLeX.SignerCondition.ZKPassport.v1");

    error ZKPassportNotConfigured();
    error InvalidZKPassportConditionParams();
    error InvalidVerifier();
    error DevModeProof();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidBoundSender();
    error InvalidBoundContractId();
    error UniqueIdentifierMismatch();
    error UniqueIdentifierAlreadyUsed();

    struct ZKPassportConditionStorage {
        ZKPassportConfig config;
        mapping(bytes32 => mapping(bytes32 => address)) partyOfIdentifier; // contractId => unique identifier => party
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.agreements.signer-conditions.zkpassport.storage.v1");

    /// @dev `params` must be exactly one `ZKPassportCondition`, so each condition has one encoding.
    function validateParams(bytes memory params) internal view {
        if (params.length != 32) revert InvalidZKPassportConditionParams();
        if (_storage().config.verifier == address(0)) revert ZKPassportNotConfigured();
    }

    function setConfig(bytes memory config) internal {
        ZKPassportConfig memory decoded = abi.decode(config, (ZKPassportConfig));
        if (decoded.verifier == address(0)) revert InvalidVerifier();
        _storage().config = decoded;
    }

    function getConfig() internal view returns (bytes memory) {
        return abi.encode(_storage().config);
    }

    /// @notice Verify the party's proof for `contractId` and reserve its passport in this agreement.
    /// @return result `abi.encode(ZKPassportResult)`.
    function verify(bytes32 contractId, address party, bytes memory params, bytes memory evidence)
        internal
        returns (bytes memory result)
    {
        ZKPassportConditionStorage storage $ = _storage();
        ZKPassportConfig memory config = $.config;
        ProofVerificationParams memory proof = abi.decode(evidence, (ZKPassportEvidence)).proof;
        // A dev-mode proof can come from a mock passport. Only a dev-mode config accepts it.
        if (proof.serviceConfig.devMode && !config.devMode) revert DevModeProof();

        (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper) =
            IZKPassportVerifier(config.verifier).verify(proof);
        if (!verified || address(helper) == address(0)) revert InvalidProof();
        if (!helper.verifyScopes(proof.proofVerificationData.publicInputs, config.domain, config.scope)) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(proof.committedInputs);
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();
        if (boundData.senderAddress != party) revert InvalidBoundSender();
        // The passport holder approves this agreement, not only this wallet.
        if (keccak256(bytes(boundData.customData)) != keccak256(bytes(Strings.toHexString(uint256(contractId), 32)))) {
            revert InvalidBoundContractId();
        }

        bytes32 pinned = abi.decode(params, (ZKPassportCondition)).uniqueIdentifier;
        if (pinned != bytes32(0) && pinned != uniqueIdentifier) revert UniqueIdentifierMismatch();
        address holder = $.partyOfIdentifier[contractId][uniqueIdentifier];
        if (holder != address(0) && holder != party) revert UniqueIdentifierAlreadyUsed();
        $.partyOfIdentifier[contractId][uniqueIdentifier] = party;

        return abi.encode(ZKPassportResult(uniqueIdentifier));
    }

    function _storage() private pure returns (ZKPassportConditionStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }
}
