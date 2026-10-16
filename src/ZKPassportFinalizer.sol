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

import {ICyberAgreementRegistry} from "./interfaces/ICyberAgreementRegistry.sol";
import "./interfaces/IZKPassportVerifier.sol";
import "./libs/auth.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @title ZKPassportFinalizer
/// @notice The finalizer of an agreement that needs a passport proof from each party.
/// - Each party sends one transaction. It records the party's passport and signs.
/// - The creator can pin a passport to a party. That party can sign only with that passport.
/// - In one agreement, a passport can fill one party only.
/// - The agreement finalizes when all parties have signed and have a passport record.
/// - Only the passport id goes on-chain. No PII.
/// - Dev mode lets a mock passport sign. Use it on a testnet only.
contract ZKPassportFinalizer is Initializable, UUPSUpgradeable, BorgAuthACL {
    error InvalidRegistry();
    error InvalidVerifier();
    error PassportIdsLengthMismatch();
    error OpenSlotNotSupported();
    error DuplicatePin();
    error AgreementNotRegistered();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidBoundContractId();
    error DevModeProof();
    error NotAParty();
    error NotSigned();
    error AlreadyRecorded();
    error PassportPinMismatch();
    error PassportAlreadyUsed();

    struct ZKPassportFinalizerStorage {
        ICyberAgreementRegistry registry;
        IZKPassportVerifier verifier;
        string expectedDomain;
        string expectedScope;
        bool devMode; // accept dev-mode proofs
        mapping(bytes32 => bool) registered; // contractId => created here
        mapping(bytes32 => mapping(address => bytes32)) pinOf; // contractId => party => pinned passport id
        mapping(bytes32 => mapping(address => bytes32)) passportOf; // contractId => party => recorded passport id
        mapping(bytes32 => mapping(bytes32 => address)) partyOfPassport; // contractId => passport id => party
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.agreements.zkpassport-finalizer.storage.v1");

    event VerifierUpdated(address verifier);
    event PassportsPinned(bytes32 indexed contractId, address[] parties, bytes32[] passportIds);
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
        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        $.registry = ICyberAgreementRegistry(_registry);
        $.expectedDomain = _expectedDomain;
        $.expectedScope = _expectedScope;
        $.devMode = _devMode;
        _setVerifier(_verifier);
    }

    function updateVerifier(address _verifier) external onlyAdmin {
        _setVerifier(_verifier);
    }

    /// @notice Create an agreement on the registry with this contract as its finalizer.
    /// @param passportIds One entry for each party. `bytes32(0)` lets the party use any passport.
    /// @dev The registry gets `keccak256(abi.encode(salt, passportIds))` as its salt. Thus the
    /// agreement id binds the pins, and a front-run with other pins makes a different agreement.
    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        bytes32[] memory passportIds
    ) external returns (bytes32 contractId) {
        if (passportIds.length != parties.length) revert PassportIdsLengthMismatch();
        for (uint256 i = 0; i < parties.length; i++) {
            // A pin and a passport record belong to a party address. An open slot has none yet.
            if (parties[i] == address(0)) revert OpenSlotNotSupported();
            if (passportIds[i] == bytes32(0)) continue;
            for (uint256 j = i + 1; j < passportIds.length; j++) {
                if (passportIds[i] == passportIds[j]) revert DuplicatePin();
            }
        }

        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        contractId = $.registry
            .createContract(
                templateId,
                uint256(keccak256(abi.encode(salt, passportIds))),
                globalValues,
                parties,
                partyValues,
                bytes32(0), // secretHash
                address(this), // finalizer
                expiry
            );

        $.registered[contractId] = true;
        for (uint256 i = 0; i < parties.length; i++) {
            $.pinOf[contractId][parties[i]] = passportIds[i];
            // A pinned passport is taken from the start. No other party can use it.
            if (passportIds[i] != bytes32(0)) $.partyOfPassport[contractId][passportIds[i]] = parties[i];
        }
        emit PassportsPinned(contractId, parties, passportIds);
    }

    /// @notice Record the party's passport and sign for the party. The party is the proof's bound
    /// sender, so anyone can relay this call.
    function signWithProof(
        bytes32 contractId,
        ProofVerificationParams calldata params,
        string[] memory partyValues,
        bytes calldata signature
    ) external {
        address party = _record(contractId, params);
        _zkpassportFinalizerStorage().registry.signContractFor(party, contractId, partyValues, signature, false, "");
        _finalizeIfReady(contractId);
    }

    /// @notice Record the passport of a party that signed on the registry directly.
    function attest(bytes32 contractId, ProofVerificationParams calldata params) external {
        address party = _record(contractId, params);
        if (!_zkpassportFinalizerStorage().registry.hasSigned(contractId, party)) revert NotSigned();
        _finalizeIfReady(contractId);
    }

    function registry() external view returns (ICyberAgreementRegistry) {
        return _zkpassportFinalizerStorage().registry;
    }

    function verifier() external view returns (IZKPassportVerifier) {
        return _zkpassportFinalizerStorage().verifier;
    }

    function expectedDomain() external view returns (string memory) {
        return _zkpassportFinalizerStorage().expectedDomain;
    }

    function expectedScope() external view returns (string memory) {
        return _zkpassportFinalizerStorage().expectedScope;
    }

    function devMode() external view returns (bool) {
        return _zkpassportFinalizerStorage().devMode;
    }

    function isRegistered(bytes32 contractId) external view returns (bool) {
        return _zkpassportFinalizerStorage().registered[contractId];
    }

    function pinOf(bytes32 contractId, address party) external view returns (bytes32) {
        return _zkpassportFinalizerStorage().pinOf[contractId][party];
    }

    function passportOf(bytes32 contractId, address party) external view returns (bytes32) {
        return _zkpassportFinalizerStorage().passportOf[contractId][party];
    }

    /// @dev Verify the proof and store the passport id for its bound sender. Returns that party.
    function _record(bytes32 contractId, ProofVerificationParams calldata params) internal returns (address party) {
        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        if (!$.registered[contractId]) revert AgreementNotRegistered();
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

        party = boundData.senderAddress;
        if (!_isParty($.registry.getParties(contractId), party)) revert NotAParty();
        if ($.passportOf[contractId][party] != bytes32(0)) revert AlreadyRecorded();
        bytes32 pin = $.pinOf[contractId][party];
        if (pin != bytes32(0) && pin != passportId) revert PassportPinMismatch();
        address holder = $.partyOfPassport[contractId][passportId];
        if (holder != address(0) && holder != party) revert PassportAlreadyUsed();

        $.passportOf[contractId][party] = passportId;
        $.partyOfPassport[contractId][passportId] = party;
        emit PassportRecorded(contractId, party, passportId);
    }

    /// @dev Finalize when all parties have signed and have a passport record. Otherwise do nothing.
    function _finalizeIfReady(bytes32 contractId) internal {
        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        if (!$.registry.allPartiesSigned(contractId)) return;
        address[] memory parties = $.registry.getParties(contractId);
        for (uint256 i = 0; i < parties.length; i++) {
            if ($.passportOf[contractId][parties[i]] == bytes32(0)) return;
        }
        $.registry.finalizeContract(contractId);
    }

    function _isParty(address[] memory parties, address account) internal pure returns (bool) {
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == account) return true;
        }
        return false;
    }

    function _setVerifier(address _verifier) internal {
        if (_verifier == address(0)) revert InvalidVerifier();
        _zkpassportFinalizerStorage().verifier = IZKPassportVerifier(_verifier);
        emit VerifierUpdated(_verifier);
    }

    function _zkpassportFinalizerStorage() private pure returns (ZKPassportFinalizerStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
