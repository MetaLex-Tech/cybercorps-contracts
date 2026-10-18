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
/// @notice The finalizer of an agreement where the creator can ask some parties for a passport proof.
/// - The creator sets a gate for each party: proof required or not, and an optional pinned passport.
/// - Each party sends one transaction. A gated party records its passport and signs in that transaction.
/// - A pinned party can sign only with that passport.
/// - In one agreement, a passport can fill one party only.
/// - The agreement finalizes when all parties have signed and each gated party has a passport record.
/// - Only the passport id goes on-chain. No PII.
/// - Dev mode lets a mock passport sign. Use it on a testnet only.
contract ZKPassportFinalizer is Initializable, UUPSUpgradeable, BorgAuthACL {
    error InvalidRegistry();
    error InvalidVerifier();
    error GatesLengthMismatch();
    error OpenSlotNotSupported();
    error PinWithoutProofRequired();
    error DuplicatePin();
    error AgreementNotRegistered();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundChainId();
    error InvalidBoundContractId();
    error DevModeProof();
    error NotAParty();
    error NotSigned();
    error ProofRequired();
    error ProofNotRequired();
    error AlreadyRecorded();
    error PassportPinMismatch();
    error PassportAlreadyUsed();
    error NotReadyToFinalize();

    /// @notice The creator's rule for one party.
    /// @param proofRequired The party must record a passport proof before the agreement finalizes.
    /// @param passportId The pinned passport. `bytes32(0)` lets the party use any passport.
    struct PartyGate {
        bool proofRequired;
        bytes32 passportId;
    }

    struct ZKPassportFinalizerStorage {
        ICyberAgreementRegistry registry;
        IZKPassportVerifier verifier;
        string expectedDomain;
        string expectedScope;
        bool devMode; // accept dev-mode proofs
        mapping(bytes32 => bool) registered; // contractId => created here
        mapping(bytes32 => mapping(address => PartyGate)) gateOf; // contractId => party => gate
        mapping(bytes32 => mapping(address => bytes32)) passportOf; // contractId => party => recorded passport id
        mapping(bytes32 => mapping(bytes32 => address)) partyOfPassport; // contractId => passport id => party
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.agreements.zkpassport-finalizer.storage.v1");

    event VerifierUpdated(address verifier);
    event GatesSet(bytes32 indexed contractId, address[] parties, PartyGate[] gates);
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
    /// @param gates One entry for each party.
    /// @dev The registry gets `keccak256(abi.encode(salt, gates))` as its salt. Thus the agreement
    /// id binds the gates, and a front-run with other gates makes a different agreement.
    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        PartyGate[] memory gates
    ) external returns (bytes32 contractId) {
        return _createContract(templateId, salt, globalValues, parties, partyValues, expiry, gates);
    }

    /// @notice Same as the registry's `createStandaloneContractAndSignFor`, for a gated first party.
    /// - Creates the template if it does not exist.
    /// - Creates the agreement as `createContract` does.
    /// - Records the passport and signs for the proof's bound sender, as `signWithProof` does.
    /// The signer uses `partyValues[0]`, so the signer must be the first party.
    /// Anyone can relay this call.
    function createStandaloneContractAndSignWithProof(
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        PartyGate[] memory gates,
        ProofVerificationParams calldata params,
        bytes calldata signature
    ) external returns (bytes32 contractId) {
        bytes32 templateId = _createTemplateIfMissing(title, legalContractUri, globalFields, partyFields);
        contractId = _createContract(templateId, salt, globalValues, parties, partyValues, expiry, gates);
        _signWithProof(contractId, params, partyValues[0], signature);
    }

    /// @notice Same as the registry's `createStandaloneContractAndSignFor`, for a first party with no gate.
    /// The signer is the first party. Anyone can relay this call.
    function createStandaloneContractAndSignWithoutProof(
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        PartyGate[] memory gates,
        bytes calldata signature
    ) external returns (bytes32 contractId) {
        bytes32 templateId = _createTemplateIfMissing(title, legalContractUri, globalFields, partyFields);
        contractId = _createContract(templateId, salt, globalValues, parties, partyValues, expiry, gates);
        _signWithoutProof(contractId, parties[0], partyValues[0], signature);
    }

    /// @notice Record the gated party's passport and sign for the party. The party is the proof's
    /// bound sender, so anyone can relay this call.
    function signWithProof(
        bytes32 contractId,
        ProofVerificationParams calldata params,
        string[] memory partyValues,
        bytes calldata signature
    ) external {
        _signWithProof(contractId, params, partyValues, signature);
    }

    /// @notice Sign for a party with no gate. Anyone can relay this call.
    function signWithoutProof(bytes32 contractId, address party, string[] memory partyValues, bytes calldata signature)
        external
    {
        _signWithoutProof(contractId, party, partyValues, signature);
    }

    /// @notice Record the passport of a gated party that signed on the registry directly.
    function attest(bytes32 contractId, ProofVerificationParams calldata params) external {
        address party = _record(contractId, params);
        if (!_zkpassportFinalizerStorage().registry.hasSigned(contractId, party)) revert NotSigned();
        _finalizeIfReady(contractId);
    }

    /// @notice Finalize an agreement whose last party signed on the registry directly.
    function finalize(bytes32 contractId) external {
        if (!_zkpassportFinalizerStorage().registered[contractId]) revert AgreementNotRegistered();
        if (!_isReady(contractId)) revert NotReadyToFinalize();
        _zkpassportFinalizerStorage().registry.finalizeContract(contractId);
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

    function gateOf(bytes32 contractId, address party) external view returns (PartyGate memory) {
        return _zkpassportFinalizerStorage().gateOf[contractId][party];
    }

    function passportOf(bytes32 contractId, address party) external view returns (bytes32) {
        return _zkpassportFinalizerStorage().passportOf[contractId][party];
    }

    /// @dev Use the same template id as the registry's standalone path.
    function _createTemplateIfMissing(
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) internal returns (bytes32 templateId) {
        templateId = keccak256(abi.encode(title, legalContractUri, globalFields, partyFields));
        ICyberAgreementRegistry registry_ = _zkpassportFinalizerStorage().registry;
        // The registry has no existence check that does not revert. A revert means "no template".
        try registry_.getTemplateDetails(templateId) {}
        catch {
            registry_.createTemplate(templateId, title, legalContractUri, globalFields, partyFields);
        }
    }

    function _createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        uint256 expiry,
        PartyGate[] memory gates
    ) internal returns (bytes32 contractId) {
        if (gates.length != parties.length) revert GatesLengthMismatch();
        for (uint256 i = 0; i < parties.length; i++) {
            // A gate and a passport record belong to a party address. An open slot has none yet.
            if (parties[i] == address(0)) revert OpenSlotNotSupported();
            bytes32 pin = gates[i].passportId;
            if (pin == bytes32(0)) continue;
            if (!gates[i].proofRequired) revert PinWithoutProofRequired();
            for (uint256 j = i + 1; j < gates.length; j++) {
                if (pin == gates[j].passportId) revert DuplicatePin();
            }
        }

        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        contractId = $.registry
            .createContract(
                templateId,
                uint256(keccak256(abi.encode(salt, gates))),
                globalValues,
                parties,
                partyValues,
                bytes32(0), // secretHash
                address(this), // finalizer
                expiry
            );

        $.registered[contractId] = true;
        for (uint256 i = 0; i < parties.length; i++) {
            $.gateOf[contractId][parties[i]] = gates[i];
            // A pinned passport is taken from the start. No other party can use it.
            bytes32 pin = gates[i].passportId;
            if (pin != bytes32(0)) $.partyOfPassport[contractId][pin] = parties[i];
        }
        emit GatesSet(contractId, parties, gates);
    }

    function _signWithProof(
        bytes32 contractId,
        ProofVerificationParams calldata params,
        string[] memory partyValues,
        bytes calldata signature
    ) internal {
        address party = _record(contractId, params);
        _zkpassportFinalizerStorage().registry.signContractFor(party, contractId, partyValues, signature, false, "");
        _finalizeIfReady(contractId);
    }

    function _signWithoutProof(bytes32 contractId, address party, string[] memory partyValues, bytes calldata signature)
        internal
    {
        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        if (!$.registered[contractId]) revert AgreementNotRegistered();
        if ($.gateOf[contractId][party].proofRequired) revert ProofRequired();
        $.registry.signContractFor(party, contractId, partyValues, signature, false, "");
        _finalizeIfReady(contractId);
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
        PartyGate memory gate = $.gateOf[contractId][party];
        // A passport record holds a passport. A party with no gate must not take one.
        if (!gate.proofRequired) revert ProofNotRequired();
        if ($.passportOf[contractId][party] != bytes32(0)) revert AlreadyRecorded();
        if (gate.passportId != bytes32(0) && gate.passportId != passportId) revert PassportPinMismatch();
        address holder = $.partyOfPassport[contractId][passportId];
        if (holder != address(0) && holder != party) revert PassportAlreadyUsed();

        $.passportOf[contractId][party] = passportId;
        $.partyOfPassport[contractId][passportId] = party;
        emit PassportRecorded(contractId, party, passportId);
    }

    /// @dev Finalize when the agreement is ready. Otherwise do nothing.
    function _finalizeIfReady(bytes32 contractId) internal {
        if (_isReady(contractId)) _zkpassportFinalizerStorage().registry.finalizeContract(contractId);
    }

    /// @dev Ready means all parties have signed and each gated party has a passport record.
    function _isReady(bytes32 contractId) internal view returns (bool) {
        ZKPassportFinalizerStorage storage $ = _zkpassportFinalizerStorage();
        if (!$.registry.allPartiesSigned(contractId)) return false;
        address[] memory parties = $.registry.getParties(contractId);
        for (uint256 i = 0; i < parties.length; i++) {
            address party = parties[i];
            if ($.gateOf[contractId][party].proofRequired && $.passportOf[contractId][party] == bytes32(0)) {
                return false;
            }
        }
        return true;
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
