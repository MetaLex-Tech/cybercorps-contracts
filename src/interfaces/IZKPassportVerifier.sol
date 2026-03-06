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

    function getDisclosedData(
        bytes calldata committedInputs,
        bool isIDCard
    ) external pure returns (DisclosedData memory);

    function getBoundData(
        bytes calldata committedInputs
    ) external pure returns (BoundData memory);

    function getProofTimestamp(
        bytes32[] calldata publicInputs
    ) external pure returns (uint256);

    function isNationalityOut(
        string[] memory countryList,
        bytes calldata committedInputs
    ) external pure returns (bool);
}
