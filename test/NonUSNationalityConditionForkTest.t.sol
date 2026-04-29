// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm, console2} from "forge-std/Test.sol";
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
import {BorgAuth} from "../src/libs/auth.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract MockManager {
    BorgAuth public AUTH;
    mapping(bytes32 => address) public counterpartyByAgreementId;

    constructor(address auth) { AUTH = BorgAuth(auth); }

    function setCounterparty(bytes32 agreementId, address counterparty) external {
        counterpartyByAgreementId[agreementId] = counterparty;
    }

    function getEscrowDetails(bytes32 agreementId) external view returns (Escrow memory esc) {
        Token[] memory corpAssets = new Token[](0);
        Token[] memory buyerAssets = new Token[](0);
        esc = Escrow({
            agreementId: agreementId,
            counterParty: counterpartyByAgreementId[agreementId],
            corpAssets: corpAssets,
            buyerAssets: buyerAssets,
            signature: "",
            expiry: block.timestamp + 1 days,
            status: EscrowStatus.PAID
        });
    }
}

library NonUSNationalityConditionHelper {
    using stdJson for string;

    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function parseProofFromJson(string memory path) internal returns (ProofVerificationParams memory params, address account) {
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

        params = ProofVerificationParams({
            version: version,
            proofVerificationData: proofData,
            committedInputs: committedInputs,
            serviceConfig: serviceConfig
        });

        account = json.readAddress(".account");

        return (params, account);
    }
}

/// @notice Assume Sepolia testnet
contract NonUSNationalityConditionForkTest is Test {
    BorgAuth internal zkpassportAuth;

    NonUSNationalityCondition internal condition;

    uint256 internal constant MAX_VALIDITY_PERIOD = 365 days;
    address public constant REAL_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    // These must match the proof or what the condition expects
    string domain = "localhost";
    string scope = "hello-world";
    
    string[] excludedCountries;

    function setUp() public {
        excludedCountries = new string[](9);
        excludedCountries[0] = "IRN";
        excludedCountries[1] = "IRQ";
        excludedCountries[2] = "LBY";
        excludedCountries[3] = "PRK";
        excludedCountries[4] = "SDN";
        excludedCountries[5] = "SOM";
        excludedCountries[6] = "SYR";
        excludedCountries[7] = "USA";
        excludedCountries[8] = "YEM";

        zkpassportAuth = new BorgAuth(address(this));

        condition = new NonUSNationalityCondition(
            address(zkpassportAuth),
            domain,
            scope,
            REAL_VERIFIER,
            MAX_VALIDITY_PERIOD,
            excludedCountries
        );
    }

    function test_SubmitRealProofValid() public {
        // Assume the sample data is signed for Sepolia (included in committedInputs)
        // at timestamp: 1772783327 (included in publicInputs)
        uint256 signedTimestamp = 1772783327;
        (ProofVerificationParams memory params, address account) = NonUSNationalityConditionHelper.parseProofFromJson("test/res/sample-non-us-sanctioned-countries-sanctioned-list-proof-call.json");

        vm.warp(signedTimestamp);
        vm.prank(account);
        condition.submitProof(params, false);
        assertEq(condition.proofExpiry(account), signedTimestamp + params.serviceConfig.validityPeriodInSeconds, "unexpected proof expiry");
    }

    function test_FounderOverride_HappyPath() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);
        bytes32 agreementId = keccak256("agreement-fork-override");
        manager.setCounterparty(agreementId, investor);

        condition.setFounderOverride(address(manager), investor, true);

        assertTrue(condition.isFounderOverrideApproved(address(manager), investor));
        assertTrue(condition.checkCondition(address(manager), bytes4(0), abi.encode(agreementId)));
    }

    /// @notice Real proof of non-FRA nationality should not pass since we want non-US + non-sanctioned proof
    function test_RevertIf_RealProofInvalid() public {
        // Assume the sample data is signed for Sepolia (included in committedInputs)
        // at timestamp: 1772768315 (included in publicInputs)
        uint256 signedTimestamp = 1772768315;
        (ProofVerificationParams memory params, address account) = NonUSNationalityConditionHelper.parseProofFromJson("test/res/sample-non-fr-proof-call.json");

        vm.warp(signedTimestamp);
        vm.prank(account);
        vm.expectRevert(NonUSNationalityCondition.USAOrSanctionedCountriesNotAllowed.selector);
        condition.submitProof(params, false);
    }
}
