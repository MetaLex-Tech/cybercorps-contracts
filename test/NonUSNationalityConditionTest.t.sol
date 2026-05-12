// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Escrow, EscrowStatus, Token} from "../src/storage/LexScrowStorage.sol";
import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    BoundData,
    DisclosedData,
    IZKPassportHelper,
    IZKPassportVerifier,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";

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

contract MockZKPassportHelper is IZKPassportHelper {
    bool public shouldRevertSanctions;
    bool public shouldRejectNationality;

    error SanctionsCheckFailed();

    function setShouldRevertSanctions(bool _should) external {
        shouldRevertSanctions = _should;
    }

    function setShouldRejectNationality(bool _should) external {
        shouldRejectNationality = _should;
    }

    function verifyScopes(
        bytes32[] calldata publicInputs,
        string calldata domain,
        string calldata scope
    ) external pure returns (bool) {
        return publicInputs[0] == keccak256(bytes(domain)) && publicInputs[1] == keccak256(bytes(scope));
    }

    function getBoundData(bytes calldata committedInputs) external pure returns (BoundData memory) {
        return abi.decode(committedInputs, (BoundData));
    }

    function getProofTimestamp(bytes32[] calldata publicInputs) external pure returns (uint256) {
        return uint256(publicInputs[2]);
    }

    function isNationalityOut(string[] memory, bytes calldata) external view returns (bool) {
        return !shouldRejectNationality;
    }

    function enforceSanctionsRoot(uint256, bool, bytes calldata) external view {
        if (shouldRevertSanctions) revert SanctionsCheckFailed();
    }
}

contract MockZKPassportVerifier is IZKPassportVerifier {
    bool public shouldVerify = true;
    bool public shouldReturnZeroHelper;
    IZKPassportHelper public helperContract;
    bytes32 public uniqueId = keccak256("default-proof-id");

    function setHelper(address _helper) external {
        helperContract = IZKPassportHelper(_helper);
    }

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function setShouldReturnZeroHelper(bool _should) external {
        shouldReturnZeroHelper = _should;
    }

    function setUniqueId(bytes32 _id) external {
        uniqueId = _id;
    }

    function verify(ProofVerificationParams calldata)
        external
        returns (bool, bytes32, IZKPassportHelper)
    {
        if (!shouldVerify) return (false, bytes32(0), IZKPassportHelper(address(0)));
        if (shouldReturnZeroHelper) return (true, uniqueId, IZKPassportHelper(address(0)));
        return (true, uniqueId, helperContract);
    }
}

// TODO rename it
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

contract NonUSNationalityConditionTest is Test {
    string internal constant EXPECTED_DOMAIN = "app.example";
    string internal constant EXPECTED_SCOPE = "non-us-round";

    NonUSNationalityCondition internal condition;
    MockEscrowSource internal escrowSource;
    BorgAuth internal zkpassportAuth;
    MockZKPassportHelper internal mockHelper;
    MockZKPassportVerifier internal mockVerifier;

    uint256 internal constant MAX_VALIDITY_PERIOD = 30 days;

    function setUp() public {
        zkpassportAuth = new BorgAuth(address(this));
        mockHelper = new MockZKPassportHelper();
        mockVerifier = new MockZKPassportVerifier();
        mockVerifier.setHelper(address(mockHelper));

        string[] memory excludedCountries = new string[](1);
        excludedCountries[0] = "USA";

        condition = new NonUSNationalityCondition(
            address(zkpassportAuth),
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE,
            address(mockVerifier),
            MAX_VALIDITY_PERIOD,
            excludedCountries
        );
        escrowSource = new MockEscrowSource();
    }

    // --- existing tests ---

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

    function test_UpdateExcludedCountries_EmptyArray() public {
        string[] memory empty = new string[](0);
        vm.expectEmit(false, false, false, true);
        emit NonUSNationalityCondition.ExcludedCountriesUpdated(empty);
        condition.updateExcludedCountries(empty);
    }

    // --- submitProof tests ---

    function test_RevertWhen_InvalidProof_VerificationFailed() public {
        mockVerifier.setShouldVerify(false);
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.InvalidProof.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_InvalidProof_ZeroHelper() public {
        mockVerifier.setShouldReturnZeroHelper(true);
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.InvalidProof.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_ProofAlreadyUsed() public {
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        condition.submitProof(params, false);

        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.ProofAlreadyUsed.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_InvalidScope() public {
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        params.proofVerificationData.publicInputs[1] = keccak256(bytes("wrong-scope"));
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.InvalidScope.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_BoundSenderMismatch() public {
        address investor = address(0xA11CE);
        address attacker = address(0xDEAD);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(attacker);
        vm.expectRevert(NonUSNationalityCondition.InvalidBoundSender.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_BoundChainIdMismatch() public {
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        params.committedInputs = _buildCommittedInputs(investor, block.chainid + 1);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.InvalidBoundChainId.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_NationalityRejected() public {
        mockHelper.setShouldRejectNationality(true);
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.USAOrSanctionedCountriesNotAllowed.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_SanctionsFail() public {
        mockHelper.setShouldRevertSanctions(true);
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        vm.expectRevert(MockZKPassportHelper.SanctionsCheckFailed.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_MaxValidityPeriodExceeded() public {
        address investor = address(0xA11CE);
        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 100 days);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.MaxValidityPeriodExceeded.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_ProofExpired() public {
        vm.warp(3 days);
        address investor = address(0xA11CE);
        uint256 proofTimestamp = block.timestamp - 2 days;
        ProofVerificationParams memory params = _buildParams(investor, proofTimestamp, 1 days);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.ProofExpired.selector);
        condition.submitProof(params, false);
    }

    function test_UniqueIdentifier_CanBeReusedAfterProofExpired() public {
        address investor = address(0xA11CE);
        uint256 validityPeriod = 1 days;

        uint256 firstTimestamp = 1000;
        uint256 firstExpiry = firstTimestamp + validityPeriod;

        vm.warp(firstTimestamp);
        ProofVerificationParams memory params = _buildParams(investor, firstTimestamp, validityPeriod);
        vm.prank(investor);
        condition.submitProof(params, false);

        uint256 secondTimestamp = firstExpiry + 1;
        vm.warp(secondTimestamp);

        ProofVerificationParams memory renewalParams = _buildParams(investor, secondTimestamp, validityPeriod);
        vm.prank(investor);
        condition.submitProof(renewalParams, false);

        assertEq(condition.proofExpiry(investor), secondTimestamp + validityPeriod);
    }

    function test_RevertWhen_ProofAlreadyUsed_AtExpiryBlock() public {
        address investor = address(0xA11CE);
        uint256 firstTimestamp = 1000;
        uint256 validityPeriod = 1 days;
        uint256 firstExpiry = firstTimestamp + validityPeriod;

        vm.warp(firstTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, firstTimestamp, validityPeriod), false);

        vm.warp(firstExpiry);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.ProofAlreadyUsed.selector);
        condition.submitProof(_buildParams(investor, firstExpiry, validityPeriod), false);
    }

    function test_RevertWhen_FutureTimestamp_ExceedsMaxValidityWindow() public {
        address investor = address(0xA11CE);
        uint256 futureTimestamp = block.timestamp + 1;
        ProofVerificationParams memory params = _buildParams(investor, futureTimestamp, MAX_VALIDITY_PERIOD);
        vm.prank(investor);
        vm.expectRevert(NonUSNationalityCondition.MaxValidityPeriodExceeded.selector);
        condition.submitProof(params, false);
    }

    function test_RevertWhen_SybilAttempt_SameUniqueId_DifferentWallet() public {
        address investor = address(0xA11CE);
        address attacker = address(0xDEAD);
        uint256 firstTimestamp = 1000;
        uint256 validityPeriod = 1 days;

        vm.warp(firstTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, firstTimestamp, validityPeriod), false);

        vm.prank(attacker);
        vm.expectRevert(NonUSNationalityCondition.ProofAlreadyUsed.selector);
        condition.submitProof(_buildParams(attacker, firstTimestamp, validityPeriod), false);
    }

    function test_UniqueIdentifier_AllowedForDifferentWalletAfterExpiry() public {
        address investor = address(0xA11CE);
        address newWallet = address(0xBEEF);
        uint256 firstTimestamp = 1000;
        uint256 validityPeriod = 1 days;
        uint256 firstExpiry = firstTimestamp + validityPeriod;

        vm.warp(firstTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, firstTimestamp, validityPeriod), false);

        uint256 secondTimestamp = firstExpiry + 1;
        vm.warp(secondTimestamp);
        vm.prank(newWallet);
        condition.submitProof(_buildParams(newWallet, secondTimestamp, validityPeriod), false);

        assertEq(condition.proofExpiry(newWallet), secondTimestamp + validityPeriod);
    }

    function test_SubmitProof_UniqueIdentifierExpiryIsWritten() public {
        address investor = address(0xA11CE);
        uint256 proofTimestamp = 1000;
        uint256 validityPeriod = 1 days;

        vm.warp(proofTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, proofTimestamp, validityPeriod), false);

        assertEq(condition.uniqueIdentifierExpiry(mockVerifier.uniqueId()), proofTimestamp + validityPeriod);
    }

    function test_SubmitProof_EarlyRenewal_DifferentUniqueId_OverwritesExpiry() public {
        address investor = address(0xA11CE);
        uint256 firstTimestamp = 1000;
        uint256 validityPeriod = 1 days;

        vm.warp(firstTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, firstTimestamp, validityPeriod), false);
        assertEq(condition.proofExpiry(investor), firstTimestamp + validityPeriod);

        uint256 secondTimestamp = firstTimestamp + 12 hours;
        vm.warp(secondTimestamp);
        mockVerifier.setUniqueId(keccak256("second-proof-id"));
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, secondTimestamp, validityPeriod), false);

        assertEq(condition.proofExpiry(investor), secondTimestamp + validityPeriod);
    }

    function test_SubmitProof_ValidityPeriodAtMaxBoundary() public {
        address investor = address(0xA11CE);
        uint256 proofTimestamp = 1000;
        vm.warp(proofTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, proofTimestamp, MAX_VALIDITY_PERIOD), false);
        assertEq(condition.proofExpiry(investor), proofTimestamp + MAX_VALIDITY_PERIOD);
    }

    function test_SubmitProof_HappyPath() public {
        address investor = address(0xA11CE);
        uint256 proofTimestamp = block.timestamp;
        uint256 validityPeriod = 1 days;
        ProofVerificationParams memory params = _buildParams(investor, proofTimestamp, validityPeriod);
        vm.expectEmit(true, false, false, true);
        emit NonUSNationalityCondition.ProofSubmitted(investor, proofTimestamp + validityPeriod);
        vm.prank(investor);
        condition.submitProof(params, false);
        assertEq(condition.proofExpiry(investor), proofTimestamp + validityPeriod);
    }

    // --- checkCondition tests ---

    function test_CheckCondition_ReturnsTrueWithValidProof() public {
        bytes32 agreementId = keccak256("agreement-1");
        address investor = address(0xA11CE);
        escrowSource.setCounterparty(agreementId, investor);

        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        condition.submitProof(params, false);

        bool result = condition.checkCondition(address(escrowSource), bytes4(0), abi.encode(agreementId));
        assertTrue(result);
    }

    function test_CheckCondition_ReturnsFalseAfterExpiry() public {
        bytes32 agreementId = keccak256("agreement-2");
        address investor = address(0xA11CE);
        escrowSource.setCounterparty(agreementId, investor);

        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        condition.submitProof(params, false);

        vm.warp(block.timestamp + 2 days);
        bool result = condition.checkCondition(address(escrowSource), bytes4(0), abi.encode(agreementId));
        assertFalse(result);
    }

    function test_CheckCondition_TrueAtExactExpiry() public {
        bytes32 agreementId = keccak256("agreement-exact");
        address investor = address(0xA11CE);
        escrowSource.setCounterparty(agreementId, investor);

        uint256 proofTimestamp = 1000;
        uint256 validityPeriod = 1 days;
        uint256 expiresAt = proofTimestamp + validityPeriod;

        vm.warp(proofTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, proofTimestamp, validityPeriod), false);

        vm.warp(expiresAt);
        assertTrue(condition.checkCondition(address(escrowSource), bytes4(0), abi.encode(agreementId)));
    }

    function test_CheckCondition_FalseOneSecondAfterExpiry() public {
        bytes32 agreementId = keccak256("agreement-past");
        address investor = address(0xA11CE);
        escrowSource.setCounterparty(agreementId, investor);

        uint256 proofTimestamp = 1000;
        uint256 validityPeriod = 1 days;
        uint256 expiresAt = proofTimestamp + validityPeriod;

        vm.warp(proofTimestamp);
        vm.prank(investor);
        condition.submitProof(_buildParams(investor, proofTimestamp, validityPeriod), false);

        vm.warp(expiresAt + 1);
        assertFalse(condition.checkCondition(address(escrowSource), bytes4(0), abi.encode(agreementId)));
    }

    function test_CheckCondition_ZeroAddressCounterparty() public {
        bytes32 agreementId = keccak256("agreement-zero-cp");
        // counterparty not set — escrowSource returns address(0) by default
        assertFalse(condition.checkCondition(address(escrowSource), bytes4(0), abi.encode(agreementId)));
    }

    // --- founder override tests ---

    function test_SetFounderOverride_HappyPath() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);
        bytes32 agreementId = keccak256("agreement-override");
        manager.setCounterparty(agreementId, investor);

        condition.setFounderOverride(address(manager), investor, true);

        assertTrue(condition.founderOverrides(address(manager), investor));
        assertTrue(condition.checkCondition(address(manager), bytes4(0), abi.encode(agreementId)));
    }

    function test_SetFounderOverride_PublicMappingGetter() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);

        assertFalse(condition.founderOverrides(address(manager), investor));
        condition.setFounderOverride(address(manager), investor, true);
        assertTrue(condition.founderOverrides(address(manager), investor));
    }

    function test_SetFounderOverride_EmitsFounderOverrideUpdated() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);

        vm.expectEmit(true, true, true, true);
        emit NonUSNationalityCondition.FounderOverrideUpdated(address(manager), investor, true, address(this));
        condition.setFounderOverride(address(manager), investor, true);
    }

    function test_SetFounderOverride_RevokeOverride() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);
        bytes32 agreementId = keccak256("agreement-revoke");
        manager.setCounterparty(agreementId, investor);

        condition.setFounderOverride(address(manager), investor, true);
        condition.setFounderOverride(address(manager), investor, false);

        assertFalse(condition.founderOverrides(address(manager), investor));
        assertFalse(condition.checkCondition(address(manager), bytes4(0), abi.encode(agreementId)));
    }

    function test_CheckCondition_FounderOverrideTakesPrecedence() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address investor = address(0xA11CE);
        bytes32 agreementId = keccak256("agreement-expired");
        manager.setCounterparty(agreementId, investor);

        ProofVerificationParams memory params = _buildParams(investor, block.timestamp, 1 days);
        vm.prank(investor);
        condition.submitProof(params, false);

        vm.warp(block.timestamp + 2 days);
        assertFalse(condition.checkCondition(address(manager), bytes4(0), abi.encode(agreementId)));

        condition.setFounderOverride(address(manager), investor, true);
        assertTrue(condition.checkCondition(address(manager), bytes4(0), abi.encode(agreementId)));
    }

    function test_CheckCondition_OverrideScopedToManager() public {
        BorgAuth managerAuthA = new BorgAuth(address(this));
        MockManager managerA = new MockManager(address(managerAuthA));
        BorgAuth managerAuthB = new BorgAuth(address(this));
        MockManager managerB = new MockManager(address(managerAuthB));
        address investor = address(0xA11CE);
        bytes32 agreementId = keccak256("agreement-scoped");
        managerA.setCounterparty(agreementId, investor);
        managerB.setCounterparty(agreementId, investor);

        condition.setFounderOverride(address(managerA), investor, true);

        assertTrue(condition.checkCondition(address(managerA), bytes4(0), abi.encode(agreementId)));
        assertFalse(condition.checkCondition(address(managerB), bytes4(0), abi.encode(agreementId)));
    }

    function test_RevertWhen_SetFounderOverride_Unauthorized() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));
        address attacker = address(0xDEAD);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(99), attacker)
        );
        condition.setFounderOverride(address(manager), address(0xA11CE), true);
    }

    function test_RevertWhen_SetFounderOverride_InvalidManager() public {
        vm.expectRevert(NonUSNationalityCondition.InvalidManager.selector);
        condition.setFounderOverride(address(0), address(0xA11CE), true);
    }

    function test_RevertWhen_SetFounderOverride_InvalidInvestor() public {
        BorgAuth managerAuth = new BorgAuth(address(this));
        MockManager manager = new MockManager(address(managerAuth));

        vm.expectRevert(NonUSNationalityCondition.InvalidInvestor.selector);
        condition.setFounderOverride(address(manager), address(0), true);
    }

    // --- access control tests ---

    function test_RevertWhen_UpdateMaxValidityPeriod_Unauthorized() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(98), address(0xBEEF))
        );
        condition.updateMaxValidityPeriod(1 days);
    }

    function test_RevertWhen_UpdateExcludedCountries_Unauthorized() public {
        string[] memory countries = new string[](1);
        countries[0] = "FRA";
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(98), address(0xBEEF))
        );
        condition.updateExcludedCountries(countries);
    }

    // --- initialize validation tests ---

    function test_RevertWhen_Initialize_ZeroMaxValidityPeriod() public {
        string[] memory excludedCountries = new string[](1);
        excludedCountries[0] = "USA";

        vm.expectRevert(NonUSNationalityCondition.InvalidMaxValidityPeriod.selector);
        NonUSNationalityCondition fresh = new NonUSNationalityCondition(
            address(zkpassportAuth),
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE,
            address(mockVerifier),
            0,
            excludedCountries
        );
    }

    function test_RevertWhen_UpdateMaxValidityPeriod_Zero() public {
        vm.expectRevert(NonUSNationalityCondition.InvalidMaxValidityPeriod.selector);
        condition.updateMaxValidityPeriod(0);
    }

    function test_RevertWhen_Initialize_CalledTwice() public {
        string[] memory excludedCountries = new string[](1);
        excludedCountries[0] = "USA";
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        condition.initialize(
            address(zkpassportAuth),
            EXPECTED_DOMAIN,
            EXPECTED_SCOPE,
            address(mockVerifier),
            MAX_VALIDITY_PERIOD,
            excludedCountries
        );
    }

    // --- supportsInterface tests ---

    function test_SupportsInterface_ICondition() public view {
        assertTrue(condition.supportsInterface(type(ICondition).interfaceId));
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(condition.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_Unknown() public view {
        assertFalse(condition.supportsInterface(bytes4(0xDEADBEEF)));
    }

    // --- internal helpers ---
    //
    // NOTE: The encoding conventions used here (committedInputs, publicInputs, BoundData)
    // are simplified mock conventions chosen for testability. They do NOT necessarily
    // reflect the actual production encoding used by the ZKPassport protocol. Specifically:
    //   - committedInputs: abi.encode(BoundData) — mock only; nationality is controlled via flag
    //   - publicInputs[0]: keccak256(domain), [1]: keccak256(scope), [2]: timestamp — mock only
    //   - BoundData fields are populated with synthetic test values

    function _buildCommittedInputs(address sender, uint256 chainId) internal pure returns (bytes memory) {
        return abi.encode(BoundData({senderAddress: sender, chainId: chainId, customData: ""}));
    }

    function _buildPublicInputs(uint256 proofTimestamp) internal pure returns (bytes32[] memory) {
        bytes32[] memory pubs = new bytes32[](3);
        pubs[0] = keccak256(bytes(EXPECTED_DOMAIN));
        pubs[1] = keccak256(bytes(EXPECTED_SCOPE));
        pubs[2] = bytes32(proofTimestamp);
        return pubs;
    }

    function _buildParams(
        address sender,
        uint256 proofTimestamp,
        uint256 validityPeriod
    ) internal view returns (ProofVerificationParams memory) {
        return ProofVerificationParams({
            version: bytes32(0),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(0),
                proof: "",
                publicInputs: _buildPublicInputs(proofTimestamp)
            }),
            committedInputs: _buildCommittedInputs(sender, block.chainid),
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: validityPeriod,
                domain: EXPECTED_DOMAIN,
                scope: EXPECTED_SCOPE,
                devMode: false
            })
        });
    }
}
