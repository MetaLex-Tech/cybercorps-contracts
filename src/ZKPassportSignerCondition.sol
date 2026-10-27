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

import {ISignerCondition} from "./interfaces/ISignerCondition.sol";
import "./interfaces/IZKPassportVerifier.sol";
import "./libs/auth.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IERC165} from "openzeppelin-contracts/utils/introspection/IERC165.sol";

/// @title ZKPassportSignerCondition
/// @notice A signer check for creator-bound agreements: the party must show a passport proof.
/// - The proof commits to the agreement id and the party's address. Anyone can relay it, also
///   before the agreement exists.
/// - The creator can pin a passport for a party with `data = abi.encode(passportId)`. Empty
///   `data` lets the party use any passport.
/// - In one agreement, a passport can fill one party only.
/// - Only the passport id goes on-chain. No PII.
/// - Dev mode lets a mock passport sign. Use it on a testnet only.
contract ZKPassportSignerCondition is Initializable, UUPSUpgradeable, BorgAuthACL, ISignerCondition {
    error InvalidRegistry();
    error InvalidVerifier();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidBoundContractId();
    error DevModeProof();
    error AlreadyRecorded();
    error PassportAlreadyUsed();

    struct ZKPassportSignerConditionStorage {
        address registry;
        IZKPassportVerifier verifier;
        string expectedDomain;
        string expectedScope;
        bool devMode; // accept dev-mode proofs
        mapping(bytes32 => mapping(address => bytes32)) passportOf; // contractId => party => recorded passport id
        mapping(bytes32 => mapping(bytes32 => address)) partyOfPassport; // contractId => passport id => party
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.agreements.zkpassport-signer-condition.storage.v1");

    event VerifierUpdated(address verifier);
    event PassportRecorded(bytes32 indexed contractId, address indexed party, bytes32 indexed passportId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _registry,
        address _verifier,
        string memory _expectedDomain,
        string memory _expectedScope,
        bool _devMode
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        if (_registry == address(0)) revert InvalidRegistry();
        ZKPassportSignerConditionStorage storage $ = _zkpassportSignerConditionStorage();
        $.registry = _registry;
        $.expectedDomain = _expectedDomain;
        $.expectedScope = _expectedScope;
        $.devMode = _devMode;
        _setVerifier(_verifier);
    }

    function updateVerifier(address _verifier) external onlyAdmin {
        _setVerifier(_verifier);
    }

    /// @notice Verify the proof and record the passport for the proof's bound sender in `contractId`.
    /// Anyone can relay this call.
    function submitProof(bytes32 contractId, ProofVerificationParams calldata params) external {
        ZKPassportSignerConditionStorage storage $ = _zkpassportSignerConditionStorage();
        // A dev-mode proof can come from a mock passport. Only a dev-mode deployment accepts it.
        if (params.serviceConfig.devMode && !$.devMode) revert DevModeProof();

        (bool verified, bytes32 passportId, IZKPassportHelper helper) = $.verifier.verify(params);
        if (!verified || address(helper) == address(0)) revert InvalidProof();
        if (!helper.verifyScopes(params.proofVerificationData.publicInputs, $.expectedDomain, $.expectedScope)) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(params.committedInputs);
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();
        // The proof holder approves this agreement, not only this wallet.
        if (keccak256(bytes(boundData.customData)) != keccak256(bytes(Strings.toHexString(uint256(contractId), 32)))) {
            revert InvalidBoundContractId();
        }

        address party = boundData.senderAddress;
        if ($.passportOf[contractId][party] != bytes32(0)) revert AlreadyRecorded();
        if ($.partyOfPassport[contractId][passportId] != address(0)) revert PassportAlreadyUsed();

        $.passportOf[contractId][party] = passportId;
        $.partyOfPassport[contractId][passportId] = party;
        emit PassportRecorded(contractId, party, passportId);
    }

    /// @inheritdoc ISignerCondition
    /// @dev `data` is empty, or `abi.encode(bytes32 passportId)` for a pinned party.
    function checkSigner(address registry_, bytes32 contractId, address party, bytes calldata data)
        external
        view
        returns (bool)
    {
        ZKPassportSignerConditionStorage storage $ = _zkpassportSignerConditionStorage();
        if (registry_ != $.registry) return false;
        bytes32 passportId = $.passportOf[contractId][party];
        if (passportId == bytes32(0)) return false;
        if (data.length == 0) return true;
        return passportId == abi.decode(data, (bytes32));
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISignerCondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function registry() external view returns (address) {
        return _zkpassportSignerConditionStorage().registry;
    }

    function verifier() external view returns (IZKPassportVerifier) {
        return _zkpassportSignerConditionStorage().verifier;
    }

    function expectedDomain() external view returns (string memory) {
        return _zkpassportSignerConditionStorage().expectedDomain;
    }

    function expectedScope() external view returns (string memory) {
        return _zkpassportSignerConditionStorage().expectedScope;
    }

    function devMode() external view returns (bool) {
        return _zkpassportSignerConditionStorage().devMode;
    }

    function passportOf(bytes32 contractId, address party) external view returns (bytes32) {
        return _zkpassportSignerConditionStorage().passportOf[contractId][party];
    }

    function _setVerifier(address _verifier) internal {
        if (_verifier == address(0)) revert InvalidVerifier();
        _zkpassportSignerConditionStorage().verifier = IZKPassportVerifier(_verifier);
        emit VerifierUpdated(_verifier);
    }

    function _zkpassportSignerConditionStorage() private pure returns (ZKPassportSignerConditionStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
