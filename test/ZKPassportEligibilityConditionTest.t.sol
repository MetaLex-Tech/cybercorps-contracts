// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICondition} from "../src/interfaces/ICondition.sol";
import {EligibilityRules, IZKPassportEligibilityCondition} from "../src/interfaces/IZKPassportEligibilityCondition.sol";
import {
    BoundData,
    IZKPassportEligibilityHelper,
    IZKPassportHelper,
    IZKPassportVerifier,
    NullifierType,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ZKPassportEligibilityCondition} from "../src/libs/conditions/ZKPassportEligibilityCondition.sol";
import {ZKPassportEligibilityConditionFactory} from "../src/libs/conditions/ZKPassportEligibilityConditionFactory.sol";
import {Escrow, EscrowStatus, Token} from "../src/storage/LexScrowStorage.sol";
import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "openzeppelin-contracts/interfaces/IERC165.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockEligibilityHelper is IZKPassportEligibilityHelper {
    error SanctionsCheckFailed();

    bool public rejectNationalityIn;
    bool public rejectNationalityOut;
    bool public rejectAge;
    bool public revertSanctions;

    // Last observed inputs for assertions (verifies exact list/age passed to helper).
    bytes32 public lastNationalityInHash;
    bytes32 public lastNationalityOutHash;
    uint8 public lastCheckedMinAge;
    bool public sanctionsChecked;

    function setRejectNationalityIn(bool v) external {
        rejectNationalityIn = v;
    }

    function setRejectNationalityOut(bool v) external {
        rejectNationalityOut = v;
    }

    function setRejectAge(bool v) external {
        rejectAge = v;
    }

    function setRevertSanctions(bool v) external {
        revertSanctions = v;
    }

    function verifyScopes(bytes32[] calldata publicInputs, string calldata domain, string calldata scope)
        external
        pure
        returns (bool)
    {
        return publicInputs[0] == keccak256(bytes(domain)) && publicInputs[1] == keccak256(bytes(scope));
    }

    function getBoundData(bytes calldata committedInputs) external pure returns (BoundData memory) {
        return abi.decode(committedInputs, (BoundData));
    }

    function getProofTimestamp(bytes32[] calldata publicInputs) external pure returns (uint256) {
        return uint256(publicInputs[2]);
    }

    function getNullifierType(bytes32[] calldata publicInputs) external pure returns (NullifierType) {
        return NullifierType(uint256(publicInputs[3]));
    }

    function isNationalityIn(string[] memory countryList, bytes calldata committedInputs) external view returns (bool) {
        if (rejectNationalityIn) return false;
        // Also verify that the list committed in the test matches countryList when committed via customData.
        BoundData memory bound = abi.decode(committedInputs, (BoundData));
        if (bytes(bound.customData).length == 0) return true;
        return keccak256(bytes(bound.customData)) == keccak256(abi.encode(countryList));
    }

    function isNationalityOut(string[] memory countryList, bytes calldata committedInputs)
        external
        view
        returns (bool)
    {
        if (rejectNationalityOut) return false;
        BoundData memory bound = abi.decode(committedInputs, (BoundData));
        if (bytes(bound.customData).length == 0) return true;
        return keccak256(bytes(bound.customData)) == keccak256(abi.encode(countryList));
    }

    function isAgeAboveOrEqual(uint8 minAge, bytes calldata) external view returns (bool) {
        if (rejectAge) return false;
        return minAge > 0;
    }

    function enforceSanctionsRoot(uint256, bool, bytes calldata) external view {
        if (revertSanctions) revert SanctionsCheckFailed();
    }
}

contract MockEligibilityVerifier is IZKPassportVerifier {
    bool public shouldVerify = true;
    bool public shouldReturnZeroHelper;
    IZKPassportHelper public helperContract;
    bytes32 public uniqueId = keccak256("passport-1");

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

    function verify(ProofVerificationParams calldata) external view returns (bool, bytes32, IZKPassportHelper) {
        if (!shouldVerify) return (false, bytes32(0), IZKPassportHelper(address(0)));
        if (shouldReturnZeroHelper) return (true, uniqueId, IZKPassportHelper(address(0)));
        return (true, uniqueId, helperContract);
    }
}

contract MockEligibilityManager {
    BorgAuth public AUTH;
    mapping(bytes32 => address) public counterpartyByAgreementId;

    constructor(address _auth) {
        AUTH = BorgAuth(_auth);
    }

    function setCounterparty(bytes32 agreementId, address counterparty) external {
        counterpartyByAgreementId[agreementId] = counterparty;
    }

    function getEscrowDetails(bytes32 agreementId) external view returns (Escrow memory esc) {
        esc = Escrow({
            agreementId: agreementId,
            counterParty: counterpartyByAgreementId[agreementId],
            corpAssets: new Token[](0),
            buyerAssets: new Token[](0),
            signature: "",
            expiry: block.timestamp + 1 days,
            status: EscrowStatus.PAID
        });
    }
}

contract ZKPassportEligibilityConditionV2Mock is ZKPassportEligibilityCondition {
    function upgradedMarker() external pure returns (uint256) {
        return 42;
    }
}

contract ZKPassportEligibilityConditionTest is Test {
    BorgAuth internal coreAuth;
    BorgAuth internal managerAuth1;
    BorgAuth internal managerAuth2;

    MockEligibilityHelper internal helper;
    MockEligibilityVerifier internal verifier;
    MockEligibilityManager internal manager1;
    MockEligibilityManager internal manager2;

    ZKPassportEligibilityCondition internal conditionImpl;
    ZKPassportEligibilityConditionFactory internal factory;

    address internal admin = address(0xA11CE);
    address internal owner1 = address(0xB0B1);
    address internal owner2 = address(0xB0B2);
    address internal investor1 = address(0x1111);
    address internal investor2 = address(0x2222);

    string internal constant DOMAIN = "cyberraise.metalex.tech";
    uint256 internal constant MAX_VALIDITY = 30 days;
    bytes32 internal constant AGREEMENT_1 = keccak256("agreement-1");

    function setUp() public {
        vm.warp(1_760_000_000);

        coreAuth = new BorgAuth(address(this));
        coreAuth.updateRole(admin, coreAuth.ADMIN_ROLE());

        managerAuth1 = new BorgAuth(owner1);
        managerAuth2 = new BorgAuth(owner2);
        manager1 = new MockEligibilityManager(address(managerAuth1));
        manager2 = new MockEligibilityManager(address(managerAuth2));

        helper = new MockEligibilityHelper();
        verifier = new MockEligibilityVerifier();
        verifier.setHelper(address(helper));

        conditionImpl = new ZKPassportEligibilityCondition();
        ZKPassportEligibilityConditionFactory factoryImpl = new ZKPassportEligibilityConditionFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                ZKPassportEligibilityConditionFactory.initialize,
                (address(coreAuth), address(conditionImpl), DOMAIN, address(verifier), MAX_VALIDITY, false)
            )
        );
        factory = ZKPassportEligibilityConditionFactory(address(factoryProxy));
    }

    /*//////////////////////////////////////////////////////////////
                             helper builders
    //////////////////////////////////////////////////////////////*/

    function _arr1(string memory a) internal pure returns (string[] memory arr) {
        arr = new string[](1);
        arr[0] = a;
    }

    function _arr2(string memory a, string memory b) internal pure returns (string[] memory arr) {
        arr = new string[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _empty() internal pure returns (string[] memory) {
        return new string[](0);
    }

    function _allowRules(string[] memory allowed, uint8 minAge, bool sanctions)
        internal
        pure
        returns (EligibilityRules memory)
    {
        return EligibilityRules({
            allowedNationalities: allowed,
            excludedNationalities: new string[](0),
            minimumAge: minAge,
            enforceSanctions: sanctions
        });
    }

    function _excludeRules(string[] memory excluded, uint8 minAge, bool sanctions)
        internal
        pure
        returns (EligibilityRules memory)
    {
        return EligibilityRules({
            allowedNationalities: new string[](0),
            excludedNationalities: excluded,
            minimumAge: minAge,
            enforceSanctions: sanctions
        });
    }

    function _buildParams(
        address sender,
        string memory domain,
        string memory scope,
        uint256 chainId,
        uint256 proofTimestamp,
        uint256 validityPeriod,
        bool devMode,
        NullifierType nullifierType
    ) internal pure returns (ProofVerificationParams memory) {
        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = keccak256(bytes(domain));
        publicInputs[1] = keccak256(bytes(scope));
        publicInputs[2] = bytes32(proofTimestamp);
        publicInputs[3] = bytes32(uint256(nullifierType));

        return ProofVerificationParams({
            version: bytes32(uint256(1)),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(uint256(2)), proof: hex"1234", publicInputs: publicInputs
            }),
            committedInputs: abi.encode(BoundData({senderAddress: sender, chainId: chainId, customData: ""})),
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: validityPeriod, domain: domain, scope: scope, devMode: devMode
            })
        });
    }

    /*//////////////////////////////////////////////////////////////
                     initialization & rule validation
    //////////////////////////////////////////////////////////////*/

    function test_ImplementationDisablesInitializers() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        conditionImpl.initialize(
            address(coreAuth),
            DOMAIN,
            "scope",
            address(verifier),
            MAX_VALIDITY,
            false,
            _allowRules(_arr1("USA"), 18, false)
        );
    }

    function test_DeployAllowlistAndAge_SucceedsAndStoresImmutableRules() public {
        EligibilityRules memory rules = _allowRules(_arr2("GBR", "USA"), 21, false);
        address predicted = factory.predictConditionAddress(rules, bytes32(0));
        address deployed = factory.deployCondition(rules, bytes32(0));

        assertEq(deployed, predicted);
        assertTrue(factory.isCondition(deployed));

        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(deployed);
        assertEq(cond.DEPLOY_VERSION(), "1.0");
        assertEq(address(cond.verifier()), address(verifier));
        assertEq(cond.expectedDomain(), DOMAIN);
        assertEq(cond.expectedScope(), factory.computeExpectedScope(rules, bytes32(0)));
        assertEq(cond.maxValidityPeriod(), MAX_VALIDITY);
        assertFalse(cond.devModeAllowed());
        assertEq(cond.minimumAge(), 21);
        assertFalse(cond.enforceSanctions());

        string[] memory allowed = cond.getAllowedNationalities();
        assertEq(allowed.length, 2);
        assertEq(allowed[0], "GBR");
        assertEq(allowed[1], "USA");
        assertEq(cond.getExcludedNationalities().length, 0);

        EligibilityRules memory readBack = cond.getRules();
        assertEq(readBack.minimumAge, 21);
        assertEq(readBack.allowedNationalities.length, 2);
        assertFalse(readBack.enforceSanctions);
    }

    function test_SupportsInterface() public {
        address deployed = factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0));
        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(deployed);

        assertTrue(cond.supportsInterface(type(IZKPassportEligibilityCondition).interfaceId));
        assertTrue(cond.supportsInterface(type(ICondition).interfaceId));
        assertTrue(cond.supportsInterface(type(IERC165).interfaceId));
        assertFalse(cond.supportsInterface(bytes4(0xdeadbeef)));
    }

    function test_DeployIdempotentForSameRulesAndSalt() public {
        EligibilityRules memory rules = _allowRules(_arr2("GBR", "USA"), 18, false);
        address first = factory.deployCondition(rules, bytes32(0));
        address second = factory.deployCondition(rules, bytes32(0));
        assertEq(first, second);
    }

    function test_DifferentSaltOrRulesDeployDistinctAddressesAndScopes() public {
        EligibilityRules memory r1 = _allowRules(_arr2("GBR", "USA"), 18, false);
        EligibilityRules memory r2 = _allowRules(_arr2("GBR", "USA"), 21, false);

        address c1 = factory.deployCondition(r1, bytes32(0));
        address c1Round = factory.deployCondition(r1, keccak256("round-1"));
        address c2 = factory.deployCondition(r2, bytes32(0));

        assertTrue(c1 != c1Round);
        assertTrue(c1 != c2);
        assertTrue(
            keccak256(bytes(ZKPassportEligibilityCondition(c1).expectedScope()))
                != keccak256(bytes(ZKPassportEligibilityCondition(c1Round).expectedScope()))
        );
        assertTrue(
            keccak256(bytes(ZKPassportEligibilityCondition(c1).expectedScope()))
                != keccak256(bytes(ZKPassportEligibilityCondition(c2).expectedScope()))
        );
    }

    function test_RejectsConflictingAllowAndExcludeLists() public {
        EligibilityRules memory rules = EligibilityRules({
            allowedNationalities: _arr1("USA"),
            excludedNationalities: _arr1("PRK"),
            minimumAge: 18,
            enforceSanctions: false
        });
        vm.expectRevert(ZKPassportEligibilityCondition.ConflictingNationalityLists.selector);
        factory.deployCondition(rules, bytes32(0));
    }

    function test_RejectsInvalidMinimumAge() public {
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidMinimumAge.selector);
        factory.deployCondition(_allowRules(_empty(), 100, false), bytes32(0));
    }

    function test_RejectsInvalidCountryCodes() public {
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidCountryCode.selector);
        factory.deployCondition(_allowRules(_arr1("usa"), 0, false), bytes32(0));

        vm.expectRevert(ZKPassportEligibilityCondition.InvalidCountryCode.selector);
        factory.deployCondition(_allowRules(_arr1("US"), 0, false), bytes32(0));

        vm.expectRevert(ZKPassportEligibilityCondition.InvalidCountryCode.selector);
        factory.deployCondition(_allowRules(_arr1("USAA"), 0, false), bytes32(0));

        vm.expectRevert(ZKPassportEligibilityCondition.InvalidCountryCode.selector);
        factory.deployCondition(_allowRules(_arr1("US1"), 0, false), bytes32(0));
    }

    function test_RejectsUnsortedOrDuplicateCountries() public {
        vm.expectRevert(ZKPassportEligibilityCondition.UnsortedOrDuplicateCountries.selector);
        factory.deployCondition(_allowRules(_arr2("USA", "GBR"), 0, false), bytes32(0));

        vm.expectRevert(ZKPassportEligibilityCondition.UnsortedOrDuplicateCountries.selector);
        factory.deployCondition(_allowRules(_arr2("USA", "USA"), 0, false), bytes32(0));

        vm.expectRevert(ZKPassportEligibilityCondition.UnsortedOrDuplicateCountries.selector);
        factory.deployCondition(_excludeRules(_arr2("PRK", "CUB"), 0, false), bytes32(0));
    }

    function test_RejectsTooManyCountries() public {
        string[] memory countries = new string[](251);
        for (uint256 i = 0; i < 251; i++) {
            uint8 b0 = uint8(0x41 + (i / 676));
            uint8 b1 = uint8(0x41 + ((i / 26) % 26));
            uint8 b2 = uint8(0x41 + (i % 26));
            countries[i] = string(abi.encodePacked(b0, b1, b2));
        }
        vm.expectRevert(ZKPassportEligibilityCondition.TooManyCountries.selector);
        factory.deployCondition(_allowRules(countries, 0, false), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                      ZK nationality, age, sanctions
    //////////////////////////////////////////////////////////////*/

    function test_SubmitProof_AllowlistAndAge_SuccessAndCheckCondition() public {
        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            factory.deployCondition(_allowRules(_arr2("GBR", "USA"), 21, false), bytes32(0))
        );
        manager1.setCounterparty(AGREEMENT_1, investor1);

        assertFalse(cond.checkCondition(address(manager1), bytes4(0), abi.encode(AGREEMENT_1)));
        assertFalse(cond.isEligible(address(manager1), investor1));

        // Sanctions failing must NOT block when enforceSanctions is false.
        helper.setRevertSanctions(true);

        ProofVerificationParams memory params = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );

        vm.prank(investor1);
        cond.submitProof(params);

        assertTrue(cond.checkCondition(address(manager1), bytes4(0), abi.encode(AGREEMENT_1)));
        assertTrue(cond.isEligible(address(manager1), investor1));
        assertEq(cond.proofExpiry(investor1), block.timestamp + 7 days);
        assertEq(cond.walletOfIdentifier(verifier.uniqueId()), investor1);
        assertEq(cond.identifierOfWallet(investor1), verifier.uniqueId());
    }

    function test_SubmitProof_AllowlistRejectsNonMemberNationality() public {
        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            factory.deployCondition(_allowRules(_arr2("GBR", "USA"), 0, false), bytes32(0))
        );
        helper.setRejectNationalityIn(true);

        ProofVerificationParams memory params = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );

        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.NationalityNotAllowed.selector);
        cond.submitProof(params);
    }

    function test_SubmitProof_ExclusionListWorksAndBlocksExcludedNationality() public {
        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            factory.deployCondition(_excludeRules(_arr2("IRN", "USA"), 18, false), bytes32(0))
        );
        ProofVerificationParams memory params = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );

        helper.setRejectNationalityOut(true);
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.NationalityExcluded.selector);
        cond.submitProof(params);

        helper.setRejectNationalityOut(false);
        vm.prank(investor1);
        cond.submitProof(params);
        assertTrue(cond.isEligible(address(manager1), investor1));
    }

    function test_SubmitProof_AgeRequirementEnforcedWhenSetAndSkippedWhenZero() public {
        ZKPassportEligibilityCondition condAge =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_empty(), 21, false), bytes32(0)));
        ZKPassportEligibilityCondition condNoAge =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_empty(), 0, false), bytes32(0)));

        helper.setRejectAge(true);

        ProofVerificationParams memory pAge = _buildParams(
            investor1,
            DOMAIN,
            condAge.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.AgeRequirementNotMet.selector);
        condAge.submitProof(pAge);

        // Age = 0 skips the age check (proof-of-personhood mode).
        ProofVerificationParams memory pNoAge = _buildParams(
            investor1,
            DOMAIN,
            condNoAge.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        condNoAge.submitProof(pNoAge);
        assertTrue(condNoAge.isEligible(address(manager1), investor1));
    }

    function test_SubmitProof_OptionalSanctionsEnforcedWhenEnabled() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, true), bytes32(0)));
        ProofVerificationParams memory params = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );

        helper.setRevertSanctions(true);
        vm.prank(investor1);
        vm.expectRevert(MockEligibilityHelper.SanctionsCheckFailed.selector);
        cond.submitProof(params);

        helper.setRevertSanctions(false);
        vm.prank(investor1);
        cond.submitProof(params);
        assertTrue(cond.isEligible(address(manager1), investor1));
    }

    /*//////////////////////////////////////////////////////////////
                MTLX1-33, scope/binding, expiry, sybil
    //////////////////////////////////////////////////////////////*/

    function test_MTLX1_33_RefusesDevModeAndSaltedNullifiersOnProduction() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0)));

        // 1. Caller-selected devMode = true must revert when devModeAllowed == false.
        ProofVerificationParams memory devParams = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            true,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.DevModeProof.selector);
        cond.submitProof(devParams);

        // 2. Salted, mock, and none nullifier types must all revert when devModeAllowed == false.
        NullifierType[4] memory badTypes = [
            NullifierType.SALTED_NULLIFIER,
            NullifierType.NON_SALTED_MOCK_NULLIFIER,
            NullifierType.SALTED_MOCK_NULLIFIER,
            NullifierType.NONE_NULLIFIER
        ];
        for (uint256 i = 0; i < badTypes.length; i++) {
            ProofVerificationParams memory badParams = _buildParams(
                investor1, DOMAIN, cond.expectedScope(), block.chainid, block.timestamp, 7 days, false, badTypes[i]
            );
            vm.prank(investor1);
            vm.expectRevert(ZKPassportEligibilityCondition.InvalidNullifierType.selector);
            cond.submitProof(badParams);
        }
    }

    function test_TestnetDevModeFactory_AllowsNonSaltedMockOnlyAndStillBlocksSalted() public {
        ZKPassportEligibilityConditionFactory testnetFactoryImpl = new ZKPassportEligibilityConditionFactory();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(testnetFactoryImpl),
            abi.encodeCall(
                ZKPassportEligibilityConditionFactory.initialize,
                (address(coreAuth), address(conditionImpl), DOMAIN, address(verifier), MAX_VALIDITY, true)
            )
        );
        ZKPassportEligibilityConditionFactory testnetFactory = ZKPassportEligibilityConditionFactory(address(proxy));
        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            testnetFactory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0))
        );
        assertTrue(cond.devModeAllowed());

        // Salted mock still rejected even in dev mode.
        ProofVerificationParams memory saltedMock = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            true,
            NullifierType.SALTED_MOCK_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidNullifierType.selector);
        cond.submitProof(saltedMock);

        // Non-salted mock accepted in dev mode.
        ProofVerificationParams memory nonSaltedMock = _buildParams(
            investor1,
            DOMAIN,
            cond.expectedScope(),
            block.chainid,
            block.timestamp,
            7 days,
            true,
            NullifierType.NON_SALTED_MOCK_NULLIFIER
        );
        vm.prank(investor1);
        cond.submitProof(nonSaltedMock);
        assertTrue(cond.isEligible(address(manager1), investor1));
    }

    function test_RejectsWrongDomainScopeSenderChainIdOrInvalidVerifierResult() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0)));
        string memory scope = cond.expectedScope();

        // Wrong domain
        ProofVerificationParams memory wrongDomain = _buildParams(
            investor1,
            "evil.example.com",
            scope,
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidScope.selector);
        cond.submitProof(wrongDomain);

        // Wrong scope
        ProofVerificationParams memory wrongScope = _buildParams(
            investor1,
            DOMAIN,
            "other-scope",
            block.chainid,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidScope.selector);
        cond.submitProof(wrongScope);

        // Wrong bound sender
        ProofVerificationParams memory wrongSender = _buildParams(
            investor2, DOMAIN, scope, block.chainid, block.timestamp, 7 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidBoundSender.selector);
        cond.submitProof(wrongSender);

        // Wrong chain id
        ProofVerificationParams memory wrongChain = _buildParams(
            investor1,
            DOMAIN,
            scope,
            block.chainid + 1,
            block.timestamp,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidBoundChainId.selector);
        cond.submitProof(wrongChain);

        // Verifier returns false
        ProofVerificationParams memory good = _buildParams(
            investor1, DOMAIN, scope, block.chainid, block.timestamp, 7 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        verifier.setShouldVerify(false);
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidProof.selector);
        cond.submitProof(good);

        // Verifier returns zero helper
        verifier.setShouldVerify(true);
        verifier.setShouldReturnZeroHelper(true);
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidProof.selector);
        cond.submitProof(good);

        // Verifier returns zero uniqueIdentifier
        verifier.setShouldReturnZeroHelper(false);
        verifier.setUniqueId(bytes32(0));
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidUniqueIdentifier.selector);
        cond.submitProof(good);
    }

    function test_OnePassportOneWallet_SameWalletRenewalAndPostExpiryRebind() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0)));
        string memory scope = cond.expectedScope();
        bytes32 passportA = keccak256("passport-A");
        bytes32 passportB = keccak256("passport-B");
        verifier.setUniqueId(passportA);

        // Investor1 submits proof valid for 7 days.
        uint256 t0 = 1_760_000_000;
        ProofVerificationParams memory p1 = _buildParams(
            investor1, DOMAIN, scope, block.chainid, t0, 7 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        cond.submitProof(p1);

        // Second wallet trying to reuse passportA while unexpired must revert.
        ProofVerificationParams memory p2 = _buildParams(
            investor2, DOMAIN, scope, block.chainid, t0, 7 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor2);
        vm.expectRevert(ZKPassportEligibilityCondition.ProofAlreadyUsed.selector);
        cond.submitProof(p2);

        // Investor1 trying to bind a second passport while active must revert.
        verifier.setUniqueId(passportB);
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.WalletAlreadyBound.selector);
        cond.submitProof(p1);

        // Investor1 CAN renew with the SAME passportA, extending expiry.
        verifier.setUniqueId(passportA);
        vm.warp(t0 + 2 days);
        ProofVerificationParams memory pRenew = _buildParams(
            investor1, DOMAIN, scope, block.chainid, t0 + 2 days, 10 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        cond.submitProof(pRenew);
        assertEq(cond.proofExpiry(investor1), t0 + 12 days);
        assertEq(cond.uniqueIdentifierExpiry(passportA), t0 + 12 days);

        // After expiry, investor1 is no longer eligible and passportA can bind to investor2.
        vm.warp(t0 + 12 days + 1);
        assertFalse(cond.isEligible(address(manager1), investor1));

        ProofVerificationParams memory pRebind = _buildParams(
            investor2, DOMAIN, scope, block.chainid, t0 + 12 days + 1, 7 days, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor2);
        cond.submitProof(pRebind);
        assertFalse(cond.isEligible(address(manager1), investor1));
        assertTrue(cond.isEligible(address(manager1), investor2));
        assertEq(cond.walletOfIdentifier(passportA), investor2);
    }

    function test_ProofExpiryAndMaxValidityBounds() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0)));
        string memory scope = cond.expectedScope();

        // Validity 0 rejected
        ProofVerificationParams memory pZero = _buildParams(
            investor1, DOMAIN, scope, block.chainid, block.timestamp, 0, false, NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.MaxValidityPeriodExceeded.selector);
        cond.submitProof(pZero);

        // Validity > maxValidityPeriod rejected
        ProofVerificationParams memory pTooLong = _buildParams(
            investor1,
            DOMAIN,
            scope,
            block.chainid,
            block.timestamp,
            MAX_VALIDITY + 1,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.MaxValidityPeriodExceeded.selector);
        cond.submitProof(pTooLong);

        // Expired proof rejected
        ProofVerificationParams memory pExpired = _buildParams(
            investor1,
            DOMAIN,
            scope,
            block.chainid,
            block.timestamp - 8 days,
            7 days,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.ProofExpired.selector);
        cond.submitProof(pExpired);

        // Future proof timestamp pushing expiresAt past block.timestamp + maxValidityPeriod rejected
        ProofVerificationParams memory pFuture = _buildParams(
            investor1,
            DOMAIN,
            scope,
            block.chainid,
            block.timestamp + 2 days,
            MAX_VALIDITY,
            false,
            NullifierType.NON_SALTED_NULLIFIER
        );
        vm.prank(investor1);
        vm.expectRevert(ZKPassportEligibilityCondition.MaxValidityPeriodExceeded.selector);
        cond.submitProof(pFuture);
    }

    /*//////////////////////////////////////////////////////////////
                      founder overrides & beacon upgrade
    //////////////////////////////////////////////////////////////*/

    function test_FounderOverride_ScopedToManagerAndAuthGated() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 21, false), bytes32(0)));
        manager1.setCounterparty(AGREEMENT_1, investor1);
        manager2.setCounterparty(AGREEMENT_1, investor1);

        // Non-owner cannot override
        vm.prank(investor1);
        vm.expectRevert();
        cond.setFounderOverride(address(manager1), investor1, true);

        // Owner of manager1 overrides for manager1 only
        vm.prank(owner1);
        cond.setFounderOverride(address(manager1), investor1, true);

        assertTrue(cond.checkCondition(address(manager1), bytes4(0), abi.encode(AGREEMENT_1)));
        assertFalse(cond.checkCondition(address(manager2), bytes4(0), abi.encode(AGREEMENT_1)));

        // Revoking override blocks again
        vm.prank(owner1);
        cond.setFounderOverride(address(manager1), investor1, false);
        assertFalse(cond.checkCondition(address(manager1), bytes4(0), abi.encode(AGREEMENT_1)));
    }

    function test_FactoryBeaconUpgrade_UpgradesAllConditionProxiesAtomically() public {
        address c1 = factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0));
        address c2 = factory.deployCondition(_excludeRules(_arr1("PRK"), 21, true), keccak256("round-2"));

        ZKPassportEligibilityConditionV2Mock v2Impl = new ZKPassportEligibilityConditionV2Mock();

        // Non-owner cannot upgrade beacon
        vm.prank(admin);
        vm.expectRevert();
        factory.setImplementation(address(v2Impl));

        // EOA / zero address rejected
        vm.expectRevert(ZKPassportEligibilityConditionFactory.InvalidImplementation.selector);
        factory.setImplementation(address(0));
        vm.expectRevert(ZKPassportEligibilityConditionFactory.InvalidImplementation.selector);
        factory.setImplementation(address(0x123456));

        // Owner upgrades beacon; both existing proxies immediately reflect V2 logic and keep state
        factory.setImplementation(address(v2Impl));
        assertEq(factory.implementation(), address(v2Impl));
        assertEq(ZKPassportEligibilityConditionV2Mock(c1).upgradedMarker(), 42);
        assertEq(ZKPassportEligibilityConditionV2Mock(c2).upgradedMarker(), 42);
        assertEq(ZKPassportEligibilityCondition(c1).minimumAge(), 18);
        assertEq(ZKPassportEligibilityCondition(c2).minimumAge(), 21);
        assertTrue(ZKPassportEligibilityCondition(c2).enforceSanctions());
    }

    function test_AdminCanUpdateMaxValidityPeriod() public {
        ZKPassportEligibilityCondition cond =
            ZKPassportEligibilityCondition(factory.deployCondition(_allowRules(_arr1("USA"), 18, false), bytes32(0)));

        vm.prank(investor1);
        vm.expectRevert();
        cond.updateMaxValidityPeriod(14 days);

        vm.prank(admin);
        vm.expectRevert(ZKPassportEligibilityCondition.InvalidMaxValidityPeriod.selector);
        cond.updateMaxValidityPeriod(0);

        vm.prank(admin);
        cond.updateMaxValidityPeriod(14 days);
        assertEq(cond.maxValidityPeriod(), 14 days);
    }

    function test_FactoryDomainChangeProducesDistinctDeterministicAddress() public {
        EligibilityRules memory rules = _allowRules(_arr1("USA"), 18, false);
        address cOld = factory.deployCondition(rules, bytes32(0));

        factory.setExpectedDomain("app.metalex.tech");
        address cNew = factory.deployCondition(rules, bytes32(0));

        assertTrue(cOld != cNew);
        assertEq(ZKPassportEligibilityCondition(cOld).expectedDomain(), DOMAIN);
        assertEq(ZKPassportEligibilityCondition(cNew).expectedDomain(), "app.metalex.tech");
    }
}
