// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./baseCondition.sol";
import "../LexScroWLite.sol";
import "../../interfaces/IZKPassportVerifier.sol";

/// @title NonUSNationalityCondition
/// @notice Round condition requiring a valid, non-US ZKPassport proof for the participant
contract NonUSNationalityCondition is BaseCondition {
    error InvalidVerifier();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundSender();
    error InvalidBoundChainId();
    error USNationalityNotAllowed();
    error ProofExpired();
    error ProofAlreadyUsed();

    event ProofSubmitted(
        address indexed account,
        uint256 expiresAt,
        bytes32 normalizedNationalityHash
    );

    // Deterministic verifier address from ZKPassport docs.
    address public constant DEFAULT_ZKPASSPORT_VERIFIER =
        0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    IZKPassportVerifier public immutable verifier;
    string public expectedDomain;
    string public expectedScope;

    mapping(address => uint256) public nonUSProofExpiry;
    mapping(bytes32 => bool) public usedProofIdentifiers;

    constructor(
        string memory _expectedDomain,
        string memory _expectedScope,
        address _verifier
    ) {
        expectedDomain = _expectedDomain;
        expectedScope = _expectedScope;

        address resolvedVerifier = _verifier == address(0)
            ? DEFAULT_ZKPASSPORT_VERIFIER
            : _verifier;
        if (resolvedVerifier == address(0)) revert InvalidVerifier();
        verifier = IZKPassportVerifier(resolvedVerifier);
    }

    /// @notice Submit and verify ZKPassport proof, then cache non-US eligibility for the caller
    function submitProof(
        ProofVerificationParams calldata params,
        bool isIDCard
    ) external {
        (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper) = verifier.verify(params);
        if (!verified || address(helper) == address(0)) revert InvalidProof();

        if (usedProofIdentifiers[uniqueIdentifier]) revert ProofAlreadyUsed();
        usedProofIdentifiers[uniqueIdentifier] = true;

        if (
            !helper.verifyScopes(
                params.proofVerificationData.publicInputs,
                expectedDomain,
                expectedScope
            )
        ) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(params.committedInputs);
        if (boundData.senderAddress != msg.sender) revert InvalidBoundSender();
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();

        DisclosedData memory disclosed = helper.getDisclosedData(
            params.committedInputs,
            isIDCard
        );
        bytes32 normalizedNationalityHash = _normalizedCountryHash(
            disclosed.nationality
        );
        if (_isUSHash(normalizedNationalityHash)) revert USNationalityNotAllowed();

        uint256 proofTimestamp = helper.getProofTimestamp(
            params.proofVerificationData.publicInputs
        );
        uint256 expiresAt = proofTimestamp +
            params.serviceConfig.validityPeriodInSeconds;
        if (expiresAt < block.timestamp) revert ProofExpired();

        nonUSProofExpiry[msg.sender] = expiresAt;
        emit ProofSubmitted(msg.sender, expiresAt, normalizedNationalityHash);
    }

    /// @notice Condition check used by LexScroWLite.conditionCheck
    function checkCondition(
        address _contract,
        bytes4,
        bytes memory data
    ) public view override returns (bool) {
        LexScroWLite lexScrow = LexScroWLite(_contract);
        bytes32 agreementId = abi.decode(data, (bytes32));
        address counterparty = lexScrow.getEscrowDetails(agreementId).counterParty;
        return nonUSProofExpiry[counterparty] >= block.timestamp;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view override returns (bool) {
        return
            interfaceId == type(ICondition).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function _isUSHash(bytes32 countryHash) internal pure returns (bool) {
        return
            countryHash == keccak256(bytes("USA")) ||
            countryHash == keccak256(bytes("US")) ||
            countryHash == keccak256(bytes("UNITEDSTATES")) ||
            countryHash == keccak256(bytes("UNITEDSTATESOFAMERICA"));
    }

    function _normalizedCountryHash(
        string memory raw
    ) internal pure returns (bytes32) {
        bytes memory source = bytes(raw);
        bytes memory cleaned = new bytes(source.length);
        uint256 count = 0;

        for (uint256 i = 0; i < source.length; i++) {
            uint8 c = uint8(source[i]);
            if (c >= 97 && c <= 122) {
                c -= 32; // to upper
            }
            if (c >= 65 && c <= 90) {
                cleaned[count] = bytes1(c);
                count++;
            }
        }

        bytes memory normalized = new bytes(count);
        for (uint256 i = 0; i < count; i++) {
            normalized[i] = cleaned[i];
        }

        return keccak256(normalized);
    }
}
