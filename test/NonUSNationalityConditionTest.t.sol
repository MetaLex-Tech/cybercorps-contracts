// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
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

contract MockZKPassportHelper is IZKPassportHelper {
    function verifyScopes(
        bytes32[] calldata publicInputs,
        string calldata domain,
        string calldata scope
    ) external pure returns (bool) {
        if (publicInputs.length < 2) return false;
        return
            publicInputs[0] == keccak256(bytes(domain)) &&
            publicInputs[1] == keccak256(bytes(scope));
    }

    function getDisclosedData(
        bytes calldata committedInputs,
        bool
    ) external pure returns (DisclosedData memory disclosedData) {
        (, disclosedData) = abi.decode(committedInputs, (BoundData, DisclosedData));
    }

    function getBoundData(
        bytes calldata committedInputs
    ) external pure returns (BoundData memory boundData) {
        (boundData, ) = abi.decode(committedInputs, (BoundData, DisclosedData));
    }

    function getProofTimestamp(
        bytes32[] calldata publicInputs
    ) external pure returns (uint256) {
        if (publicInputs.length < 3) return 0;
        return uint256(publicInputs[2]);
    }

    function isNationalityOut(
        string[] memory countryList,
        bytes calldata committedInputs
    ) external pure returns (bool) {
        // TODO WIP: do not use. review needed
        return true;
    }

    function enforceSanctionsRoot(
        uint256 currentTimestamp,
        bool isStrict,
        bytes calldata committedInputs
    ) external view {
        // TODO WIP: no-op for now
    }
}

contract MockZKPassportVerifier is IZKPassportVerifier {
    bool public shouldVerify = true;
    IZKPassportHelper public helper;

    constructor(address _helper) {
        helper = IZKPassportHelper(_helper);
    }

    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }

    function verify(
        ProofVerificationParams calldata params
    ) external view returns (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper zkHelper) {
        // Simulate different IDs for different params so they don't conflict upon submissions
        uniqueIdentifier = keccak256(abi.encode(params.proofVerificationData.publicInputs, params.committedInputs));
        return (shouldVerify, uniqueIdentifier, helper);
    }
}

contract MockEscrowSource {
    mapping(bytes32 => address) public counterpartyByAgreementId;

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

contract NonUSNationalityConditionTest is Test {
    string internal constant EXPECTED_DOMAIN = "app.example";
    string internal constant EXPECTED_SCOPE = "non-us-round";

    MockZKPassportHelper internal helper;
    MockZKPassportVerifier internal verifier;
    NonUSNationalityCondition internal condition;
    MockEscrowSource internal escrowSource;
    BorgAuth internal zkpassportAuth;

    uint256 internal constant MAX_VALIDITY_PERIOD = 30 days;

    string[] excludedCountries;

    function setUp() public {
        zkpassportAuth = new BorgAuth(address(this));

        helper = new MockZKPassportHelper();
        verifier = new MockZKPassportVerifier(address(helper));

        excludedCountries = new string[](1);
        excludedCountries[0] = "USA";

        condition = new NonUSNationalityCondition();
        condition.initialize(
            address(zkpassportAuth),
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE,
            address(verifier),
            MAX_VALIDITY_PERIOD,
            excludedCountries
        );
        escrowSource = new MockEscrowSource();
    }

    function test_RevertWhen_InvalidScope() public {
        vm.expectRevert(NonUSNationalityCondition.InvalidScope.selector);
        condition.submitProof(_buildParams(msg.sender, "FRA", EXPECTED_DOMAIN, "wrong-scope"), false);
    }

    function test_RevertWhen_BoundSenderMismatch() public {
        vm.expectRevert(NonUSNationalityCondition.InvalidBoundSender.selector);
        condition.submitProof(_buildParams(address(0xBEEF), "FRA", EXPECTED_DOMAIN, EXPECTED_SCOPE), false);
    }

    function test_ConditionCheck_RevertsWithoutSubmittedProof() public {
        bytes32 agreementId = keccak256("agreement-no-proof");
        address investor = address(0xA11CE);
        escrowSource.setCounterparty(agreementId, investor);

        bool allowed = condition.checkCondition(
            address(escrowSource),
            bytes4(0),
            abi.encode(agreementId)
        );
        assertFalse(allowed);
    }

    function test_ConditionCheck_PassesWithValidNonUSProof() public {
        bytes32 agreementId = keccak256("agreement-valid-proof");
        address investor = address(0xB0B);
        escrowSource.setCounterparty(agreementId, investor);

        vm.startPrank(investor);
        condition.submitProof(
            _buildParams(investor, "FRA", EXPECTED_DOMAIN, EXPECTED_SCOPE),
            false
        );
        vm.stopPrank();

        bool allowed = condition.checkCondition(
            address(escrowSource),
            bytes4(0),
            abi.encode(agreementId)
        );
        assertTrue(allowed);
    }

    /// @dev User should not be able to resubmit an old proof (same proof/public inputs)
    ///      but with a larger validity period in ServiceConfig, effectively extending eligibility without a new proof.
    function test_RevertIf_ExtendEligibilityByReplayAttack() public {
        bytes32 agreementId = keccak256("agreement-valid-proof");
        address investor = address(0xB0B);
        escrowSource.setCounterparty(agreementId, investor);

        ProofVerificationParams memory params = _buildParams(
            investor,
            "FRA",
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE
        );

        vm.startPrank(investor);

        // Initial submit uses 1 day validity (as built by _buildParams)
        condition.submitProof(params, false);
        uint256 expiry1 = condition.proofExpiry(investor);

        // Simulate expiry
        vm.warp(expiry1 + 1);

        {
            bool allowed = condition.checkCondition(
                address(escrowSource),
                bytes4(0),
                abi.encode(agreementId)
            );
            assertFalse(allowed);
        }

        // "Replay" the same proof package but claim a longer validity period.
        params.serviceConfig.validityPeriodInSeconds = 365 days;
        vm.expectRevert(NonUSNationalityCondition.ProofAlreadyUsed.selector);
        condition.submitProof(params, false);

        vm.stopPrank();
    }

    /// @dev A different address should not be able to replay someone else's proof package
    function test_RevertIf_ReplaySomeoneElsesProof() public {
        address victim = address(0xA11CE);
        address attacker = address(0xB0B);

        ProofVerificationParams memory victimsParams = _buildParams(
            victim,
            "FRA",
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE
        );

        vm.startPrank(attacker);
        vm.expectRevert(NonUSNationalityCondition.InvalidBoundSender.selector);
        condition.submitProof(victimsParams, false);
        vm.stopPrank();
    }

    function test_RevertIf_ValidityPeriodExceedsMax() public {
        address investor = address(0x123);
        ProofVerificationParams memory params = _buildParams(
            investor,
            "FRA",
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE
        );

        // Request 100 days, but max is 30 days
        params.serviceConfig.validityPeriodInSeconds = 100 days;

        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.MaxValidityPeriodExceeded.selector);
        condition.submitProof(params, false);
    }

    function test_UpdateMaxValidityPeriod() public {
        condition.updateMaxValidityPeriod(1 days);
        assertEq(condition.maxValidityPeriod(), 1 days);
    }

    function test_UpdateSanctionedCountries() public {
        string[] memory sanctioned = new string[](2);
        sanctioned[0] = "FRA";
        sanctioned[1] = "NK";
        condition.updateExcludedCountries(sanctioned);

        assertEq(condition.excludedCountries(0), "FRA");
        assertEq(condition.excludedCountries(1), "NK");
    }

    function _buildParams(
        address senderAddress,
        string memory nationality,
        string memory domain,
        string memory scope
    ) internal view returns (ProofVerificationParams memory params) {
        BoundData memory boundData = BoundData({
            senderAddress: senderAddress,
            chainId: block.chainid,
            customData: ""
        });
        DisclosedData memory disclosedData = DisclosedData({
            name: "",
            issuingCountry: "",
            nationality: nationality,
            gender: "",
            birthDate: "",
            expiryDate: "",
            documentNumber: "",
            documentType: "passport"
        });
        bytes memory committedInputs = abi.encode(boundData, disclosedData);

        bytes32[] memory publicInputs = new bytes32[](3);
        publicInputs[0] = keccak256(bytes(domain));
        publicInputs[1] = keccak256(bytes(scope));
        publicInputs[2] = bytes32(block.timestamp);

        params = ProofVerificationParams({
            version: bytes32(uint256(1)),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(0),
                proof: "",
                publicInputs: publicInputs
            }),
            committedInputs: committedInputs,
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: 1 days,
                domain: domain,
                scope: scope,
                devMode: false
            })
        });
    }
}
