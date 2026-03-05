// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Escrow, EscrowStatus, Token} from "../src/storage/LexScrowStorage.sol";
import {
    BoundData,
    DisclosedData,
    IZKPassportHelper,
    IZKPassportVerifier,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @notice Assume Sepolia testnet
contract NonUSNationalityConditionForkTest is Test {
    using stdJson for string;

    NonUSNationalityCondition internal condition;

    uint256 internal constant MAX_VALIDITY_PERIOD = 365 days;
    address public constant REAL_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    // These must match the proof or what the condition expects
    string domain = "localhost";
    string scope = "hello-world";

    function setUp() public {
        condition = new NonUSNationalityCondition(
            domain,
            scope,
            REAL_VERIFIER,
            MAX_VALIDITY_PERIOD
        );
    }

    function test_SubmitRealProof() public {
        // Assume the sample data is signed for Sepolia (included in committedInputs)
        // at timestamp: 1772702435 (included in publicInputs)
        // with validityPeriodInSeconds =
        uint256 signedTimestamp = 1772702435;

        string memory path = "test/res/sample-non-us-proof-call.json";
        string memory json = vm.readFile(path);

        bytes32 vkeyHash = json.readBytes32(".args[0].proofVerificationData.vkeyHash");
        bytes memory proof = json.readBytes(".args[0].proofVerificationData.proof");
        bytes32 version = json.readBytes32(".args[0].version");
        bytes memory committedInputs = json.readBytes(".args[0].committedInputs"); // = abi.encode(boundData, disclosedData)
        bytes32[] memory publicInputs = json.readBytes32Array(".args[0].proofVerificationData.publicInputs");

        ProofVerificationData memory proofData = ProofVerificationData({
            vkeyHash: vkeyHash,
            proof: proof,
            publicInputs: publicInputs
        });

        ServiceConfig memory serviceConfig = ServiceConfig({
            validityPeriodInSeconds: json.readUint(".args[0].serviceConfig.validityPeriodInSeconds"),
            domain: json.readString(".args[0].serviceConfig.domain"),
            scope: json.readString(".args[0].serviceConfig.scope"),
            devMode: json.readBool(".args[0].serviceConfig.devMode")
        });

        ProofVerificationParams memory params = ProofVerificationParams({
            version: version,
            proofVerificationData: proofData,
            committedInputs: committedInputs,
            serviceConfig: serviceConfig
        });

        address account = json.readAddress(".account");
        vm.warp(signedTimestamp);
        vm.prank(account);
        condition.submitProof(params, false);
        assertEq(condition.nonUSProofExpiry(account), signedTimestamp + serviceConfig.validityPeriodInSeconds, "unexpected proof expiry");
    }
}
