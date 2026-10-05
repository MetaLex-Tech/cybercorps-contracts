// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

struct BoundData {
    address senderAddress;
    uint256 chainId;
    string customData;
}

struct DisclosedData {
    string name;
    string issuingCountry;
    string nationality;
    string gender;
    string birthDate;
    string expiryDate;
    string documentNumber;
    string documentType;
}

struct ProofVerificationParams {
    bytes32 version;
    ProofVerificationData proofVerificationData;
    bytes committedInputs;
    ServiceConfig serviceConfig;
}

struct ProofVerificationData {
    bytes32 vkeyHash;
    bytes proof;
    bytes32[] publicInputs;
}

struct ServiceConfig {
    uint256 validityPeriodInSeconds;
    string domain;
    string scope;
    bool devMode;
}

// The enums below must keep ZKPassport's member order. The helper reads them as numbers.
enum NullifierType {
    NON_SALTED_NULLIFIER,
    SALTED_NULLIFIER,
    NON_SALTED_MOCK_NULLIFIER,
    SALTED_MOCK_NULLIFIER,
    NONE_NULLIFIER
}

enum FaceMatchMode {
    NONE,
    REGULAR,
    STRICT
}

enum OS {
    ANY,
    IOS,
    ANDROID
}

interface IZKPassportVerifier {
    function verify(ProofVerificationParams calldata params)
        external
        returns (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper);
}

interface IZKPassportHelper {
    function verifyScopes(
        bytes32[] calldata publicInputs,
        string calldata domain,
        string calldata scope
    ) external pure returns (bool);

    function getBoundData(
        bytes calldata committedInputs
    ) external pure returns (BoundData memory);

    function getProofTimestamp(
        bytes32[] calldata publicInputs
    ) external pure returns (uint256);

    function isNationalityOut(
        string[] memory countryList,
        bytes calldata committedInputs
    ) external view returns (bool);

    function enforceSanctionsRoot(
        uint256 currentTimestamp,
        bool isStrict,
        bytes calldata committedInputs
    ) external view;

    // Reverts unless the proof has this nullifier type. A mock type counts as its real type.
    function enforceNullifierType(
        NullifierType expectedNullifierType,
        bytes32[] calldata publicInputs
    ) external view;

    function isFaceMatchVerified(
        FaceMatchMode faceMatchMode,
        OS os,
        bytes calldata committedInputs
    ) external view returns (bool);
}
