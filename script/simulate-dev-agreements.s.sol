
import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract SimulateDevAgreementsScript is Script {

    // Agreement configs
    string testTitle = "Test agreement";
    string testLegalContractUri = "ipfs://template";
    string[] testGlobalFields;
    string[] testPartyFields;
    string[] testGlobalValues;
    address[] testParties;
    string[][] testPartyValues;

    function run() public {
        runWithArgs(
            CyberAgreementRegistry(0x4bd6B665118dAfdf06Bd4201f0b0b6373f3D02E4),
            uint256(keccak256("SimulateDevAgreementsScript")), // salt
            vm.envUint("PRIVATE_KEY_MAIN"), // proposerPrivateKey
            vm.envUint("PRIVATE_KEY_COUNTER_PARTY_SIGNED"), // counterPartySignedPrivateKey
            vm.envUint("PRIVATE_KEY_COUNTER_PARTY_PENDING") // counterPartyPendingPrivateKey
        );
    }

    function runWithArgs(
        CyberAgreementRegistry registry,
        uint256 salt,
        uint256 proposerPrivateKey,
        uint256 counterPartySignedPrivateKey,
        uint256 counterPartyPendingPrivateKey
    ) public returns (
        bytes32 agreementIdPending,
        bytes32 agreementIdSigned,
        bytes32 agreementIdFinalized,
        bytes32 agreementIdExpired
    ) {
        address proposer = vm.addr(proposerPrivateKey);
        address counterPartySigned = vm.addr(counterPartySignedPrivateKey);
        address counterPartyPending = vm.addr(counterPartyPendingPrivateKey);
        console2.log("proposer: %s", proposer);
        console2.log("counterPartySigned: %s", counterPartySigned);
        console2.log("counterPartyPending: %s", counterPartyPending);

        // Agreement configs

        testGlobalFields = new string[](1);
        testGlobalFields[0] = "Global Field";
        testPartyFields = new string[](2);
        testPartyFields[0] = "Officer Name";
        testPartyFields[1] = "Officer Title";

        testGlobalValues = new string[](1);
        testGlobalValues[0] = "global value 0";

        testParties = new address[](3);
        testParties[0] = proposer;
        testParties[1] = counterPartySigned;
        testParties[2] = counterPartyPending;

        testPartyValues = new string[][](3);
        testPartyValues[0] = new string[](2);
        testPartyValues[0][0] = "Alice";
        testPartyValues[0][1] = "Test title";
        testPartyValues[1] = new string[](2);
        testPartyValues[1][0] = "Bob";
        testPartyValues[1][1] = "Test title 2";
        testPartyValues[2] = new string[](2);
        testPartyValues[2][0] = "Chad";
        testPartyValues[2][1] = "Test title 3";

        // Create a proposed agreement

        agreementIdPending = _createTestContract(
            registry,
            salt + 0,
            block.timestamp + 30 days,
            proposerPrivateKey
        );

        // Create a signed agreement


        agreementIdSigned = _createTestContract(
            registry,
            salt + 1,
            block.timestamp + 30 days,
            proposerPrivateKey
        );

        _signContract(
            registry,
            agreementIdSigned,
            testPartyValues[1],
            counterPartySignedPrivateKey
        );

        // Create a finalized agreement

        agreementIdFinalized = _createTestContract(
            registry,
            salt + 2,
            block.timestamp + 30 days,
            proposerPrivateKey
        );

        _signContract(
            registry,
            agreementIdFinalized,
            testPartyValues[1],
            counterPartySignedPrivateKey
        );

        _signContract(
            registry,
            agreementIdFinalized,
            testPartyValues[2],
            counterPartyPendingPrivateKey
        );

        // Create an expired agreement

        agreementIdExpired = _createTestContract(
            registry,
            salt + 3,
            block.timestamp + 1 minutes, // expired soon
            proposerPrivateKey
        );

        console2.log("agreementIdPending:");
        console2.logBytes32(agreementIdPending);
        console2.log("agreementIdSigned:");
        console2.logBytes32(agreementIdSigned);
        console2.log("agreementIdFinalized:");
        console2.logBytes32(agreementIdFinalized);
        console2.log("agreementIdExpired:");
        console2.logBytes32(agreementIdExpired);
    }

    function _createTestContract(
        CyberAgreementRegistry registry,
        uint256 salt,
        uint256 expiry,
        uint256 proposerPrivateKey
    ) internal returns (bytes32) {
        // Calculate the expected standalone template ID
        bytes32 expectedStandaloneTemplateId = keccak256(abi.encode(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields
        ));

        bytes32 expectedAgreementId = keccak256(abi.encode(
            expectedStandaloneTemplateId,
            salt,
            testGlobalValues,
            testParties
        ));

        vm.startBroadcast(proposerPrivateKey);
        bytes32 agreementId = registry.createStandaloneContractAndSign(
            testTitle,
            testLegalContractUri,
            testGlobalFields,
            testPartyFields,
            salt,
            testGlobalValues,
            testParties,
            testPartyValues,
            expiry,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                testPartyValues[0],
                proposerPrivateKey
            )
        );
        vm.stopBroadcast();
        return agreementId;
    }

    function _signContract(
        CyberAgreementRegistry registry,
        bytes32 agreementId,
        string[] memory partyValues,
        uint256 signerPrivateKey
    ) internal {
        vm.startBroadcast(signerPrivateKey);
        registry.signContract(
            agreementId,
            partyValues,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                testLegalContractUri,
                testGlobalFields,
                testPartyFields,
                testGlobalValues,
                partyValues,
                signerPrivateKey
            ),
            false,
            "" // secret
        );
        vm.stopBroadcast();
        vm.assertTrue(registry.hasSigned(agreementId, vm.addr(signerPrivateKey)), "counter-party should have signed by now");
    }
}
