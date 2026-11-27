// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import {EligibilityRules} from "../src/interfaces/IZKPassportEligibilityCondition.sol";
import {
    BoundData,
    NullifierType,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ZKPassportEligibilityCondition} from "../src/libs/conditions/ZKPassportEligibilityCondition.sol";
import {ZKPassportEligibilityConditionFactory} from "../src/libs/conditions/ZKPassportEligibilityConditionFactory.sol";
import {EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {MockEligibilityHelper, MockEligibilityVerifier} from "./ZKPassportEligibilityConditionTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice End-to-end integration tests proving ZKPassportEligibilityCondition enforces nationality,
///         age, optional sanctions, and one-passport-one-wallet rules on unmodified RoundManager 5.1
///         for BOTH FCFS rounds (atomic settle/revert inside submitEOI) and FounderApproved rounds.
contract ZKPassportEligibilityRoundIntegrationTest is Test {
    using RoundLib for Round;

    MockPaymentToken internal paymentToken;
    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;

    address internal corp;
    address internal roundManager;
    address internal corp2;
    address internal roundManager2;
    address internal rmFactory;

    address internal protocolOwner;
    address internal corpOwner;
    uint256 internal corpOwnerKey;
    address internal corp2Owner;
    uint256 internal corp2OwnerKey;

    address internal investor1;
    uint256 internal investor1Key;
    address internal investor2;
    uint256 internal investor2Key;
    address internal corporateInvestor;
    uint256 internal corporateInvestorKey;

    MockEligibilityHelper internal helper;
    MockEligibilityVerifier internal verifier;
    ZKPassportEligibilityConditionFactory internal conditionFactory;

    uint256 internal constant MIN_TICKET = 1_000 * 10 ** 6;
    uint256 internal constant MAX_TICKET = 50_000 * 10 ** 6;
    uint256 internal constant RAISE_CAP = 500_000 * 10 ** 6;
    uint256 internal constant PRICE_PER_UNIT = 10 * 10 ** 18;
    uint256 internal constant VALUATION = 10_000_000 * 10 ** 18;
    uint256 internal constant ROUND_DURATION = 30 days;
    string internal constant DOMAIN = "cyberraise.metalex.tech";

    function setUp() public {
        vm.warp(1_760_000_000);

        (protocolOwner,) = makeAddrAndKey("protocolOwner");
        (corpOwner, corpOwnerKey) = makeAddrAndKey("corpOwner");
        (corp2Owner, corp2OwnerKey) = makeAddrAndKey("corp2Owner");
        (investor1, investor1Key) = makeAddrAndKey("investor1");
        (investor2, investor2Key) = makeAddrAndKey("investor2");
        (corporateInvestor, corporateInvestorKey) = makeAddrAndKey("corporateInvestor");

        paymentToken = new MockPaymentToken();
        (registry, corpFactory,,,, rmFactory,,) = CyberCorpHelper.deployRegistryAndFactories(protocolOwner);

        vm.startPrank(protocolOwner);
        CyberCorpHelper.createTemplate(registry);
        RoundManagerFactory(rmFactory).setPlatformPayable(protocolOwner);
        RoundManagerFactory(rmFactory).setDefaultFeeRatio(25);
        vm.stopPrank();

        (corp,,,, roundManager) = CyberCorpHelper.deployCorp(corpFactory, "Alpha Corp", corpOwner, corpOwner);
        (corp2,,,, roundManager2) = CyberCorpHelper.deployCorp(corpFactory, "Beta Corp", corp2Owner, corp2Owner);

        address[3] memory allInvestors = [investor1, investor2, corporateInvestor];
        for (uint256 i = 0; i < allInvestors.length; i++) {
            paymentToken.transfer(allInvestors[i], MAX_TICKET * 4);
            vm.startPrank(allInvestors[i]);
            paymentToken.approve(roundManager, type(uint256).max);
            paymentToken.approve(roundManager2, type(uint256).max);
            vm.stopPrank();
        }

        helper = new MockEligibilityHelper();
        verifier = new MockEligibilityVerifier();
        verifier.setHelper(address(helper));

        vm.startPrank(protocolOwner);
        BorgAuth conditionAuth = new BorgAuth(protocolOwner);
        ZKPassportEligibilityCondition condImpl = new ZKPassportEligibilityCondition();
        ZKPassportEligibilityConditionFactory factoryImpl = new ZKPassportEligibilityConditionFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(
                ZKPassportEligibilityConditionFactory.initialize,
                (address(conditionAuth), address(condImpl), DOMAIN, address(verifier), 30 days, false)
            )
        );
        conditionFactory = ZKPassportEligibilityConditionFactory(address(factoryProxy));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                helpers
    //////////////////////////////////////////////////////////////*/

    function _createRound(
        address targetCorp,
        address targetRM,
        address targetOwner,
        uint256 targetOwnerKey,
        RoundType roundType,
        uint256 valuation,
        address conditionAddr
    ) internal returns (bytes32 roundId) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Founder";
        roundPartyValues[1] = "CEO";

        address[] memory roundConditions = new address[](1);
        roundConditions[0] = conditionAddr;

        (bytes memory escrowedSig,) = CyberCorpHelper.computeEscrowSignature(
            targetRM,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            roundType,
            block.timestamp,
            block.timestamp + ROUND_DURATION,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            valuation,
            targetOwnerKey,
            targetCorp
        );

        Round memory draft = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                roundType,
                false,
                false,
                false,
                RAISE_CAP,
                MIN_TICKET,
                MAX_TICKET,
                address(paymentToken),
                PRICE_PER_UNIT,
                valuation,
                block.timestamp,
                block.timestamp + ROUND_DURATION
            )
            .setAgreement(
                CyberCorpHelper.TEMPLATE_ID,
                targetOwner,
                "Founder",
                "CEO",
                new string[](1),
                roundPartyValues,
                new bytes[](1),
                roundConditions,
                escrowedSig
            );

        vm.prank(targetOwner);
        roundId = RoundManager(targetRM).createRound(draft, certData);
    }

    function _buildEOI(address targetRM, address targetOwner, uint256 investorKey, uint256 salt, uint256 amount)
        internal
        view
        returns (EOI memory eoi, bytes memory sig)
    {
        eoi = EOI({
            name: "Investor",
            investorType: "Individual",
            jurisdiction: "GBR",
            contact: "inv@example.com",
            minAmount: amount,
            maxAmount: amount,
            expiry: 0,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            new string[](1),
            new string[](2),
            targetOwner,
            investorKey,
            targetRM,
            0,
            bytes32(0)
        );
    }

    function _proofParams(address sender, ZKPassportEligibilityCondition cond, uint256 validity)
        internal
        view
        returns (ProofVerificationParams memory)
    {
        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = keccak256(bytes(DOMAIN));
        publicInputs[1] = keccak256(bytes(cond.expectedScope()));
        publicInputs[2] = bytes32(block.timestamp);
        publicInputs[3] = bytes32(uint256(NullifierType.NON_SALTED_NULLIFIER));

        return ProofVerificationParams({
            version: bytes32(uint256(1)),
            proofVerificationData: ProofVerificationData({
                vkeyHash: bytes32(uint256(2)), proof: hex"abcd", publicInputs: publicInputs
            }),
            committedInputs: abi.encode(BoundData({senderAddress: sender, chainId: block.chainid, customData: ""})),
            serviceConfig: ServiceConfig({
                validityPeriodInSeconds: validity, domain: DOMAIN, scope: cond.expectedScope(), devMode: false
            })
        });
    }

    /*//////////////////////////////////////////////////////////////
                    FCFS end-to-end integration tests
    //////////////////////////////////////////////////////////////*/

    function test_FCFS_BlocksUnverifiedInvestorAndPullsZeroFunds() public {
        string[] memory allowed = new string[](2);
        allowed[0] = "GBR";
        allowed[1] = "USA";

        address condAddr = conditionFactory.deployCondition(
            EligibilityRules({
                allowedNationalities: allowed,
                excludedNationalities: new string[](0),
                minimumAge: 21,
                enforceSanctions: false
            }),
            bytes32(0)
        );

        bytes32 roundId = _createRound(corp, roundManager, corpOwner, corpOwnerKey, RoundType.FCFS, VALUATION, condAddr);

        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        (EOI memory eoi, bytes memory sig) = _buildEOI(roundManager, corpOwner, investor1Key, 1, 10_000 * 10 ** 6);

        // Without proof, FCFS submitEOI atomically reverts during auto-allocation.
        vm.prank(investor1);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager)
            .submitEOI(roundId, eoi, new string[](1), new string[](2), sig, 1, new address[](0), bytes32(0));

        assertEq(paymentToken.balanceOf(investor1), balanceBefore);
        assertEq(RoundManager(roundManager).getRound(roundId).raised, 0);
    }

    function test_FCFS_VerifiedInvestorSettles_SybilWalletBlocked_ExpiredProofBlocked() public {
        string[] memory allowed = new string[](2);
        allowed[0] = "GBR";
        allowed[1] = "USA";

        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            conditionFactory.deployCondition(
                EligibilityRules({
                    allowedNationalities: allowed,
                    excludedNationalities: new string[](0),
                    minimumAge: 21,
                    enforceSanctions: false
                }),
                bytes32(0)
            )
        );

        bytes32 roundId =
            _createRound(corp, roundManager, corpOwner, corpOwnerKey, RoundType.FCFS, VALUATION, address(cond));

        // 1. Investor1 proves UK/US nationality + 21+ age in zero knowledge.
        bytes32 sharedPassport = keccak256("investor1-passport");
        verifier.setUniqueId(sharedPassport);
        ProofVerificationParams memory p1 = _proofParams(investor1, cond, 7 days);
        vm.prank(investor1);
        cond.submitProof(p1);

        // 2. Investor1's FCFS submitEOI auto-allocates and finalizes cleanly.
        uint256 ticket = 10_000 * 10 ** 6;
        (EOI memory eoi1, bytes memory sig1) = _buildEOI(roundManager, corpOwner, investor1Key, 10, ticket);
        vm.prank(investor1);
        (bytes32 agreementId1,) = RoundManager(roundManager)
            .submitEOI(roundId, eoi1, new string[](1), new string[](2), sig1, 10, new address[](0), bytes32(0));

        assertEq(uint8(RoundManager(roundManager).getEscrowDetails(agreementId1).status), uint8(EscrowStatus.FINALIZED));
        assertEq(RoundManager(roundManager).getRound(roundId).raised, ticket);

        // 3. Investor2 tries to reuse investor1's passport: proof rejected, FCFS submitEOI reverts.
        ProofVerificationParams memory p2 = _proofParams(investor2, cond, 7 days);
        vm.prank(investor2);
        vm.expectRevert(ZKPassportEligibilityCondition.ProofAlreadyUsed.selector);
        cond.submitProof(p2);

        (EOI memory eoi2, bytes memory sig2) = _buildEOI(roundManager, corpOwner, investor2Key, 11, ticket);
        vm.prank(investor2);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager)
            .submitEOI(roundId, eoi2, new string[](1), new string[](2), sig2, 11, new address[](0), bytes32(0));

        // 4. After investor1's proof expires, a new FCFS investment reverts until renewed.
        vm.warp(block.timestamp + 7 days + 1);
        (EOI memory eoi3, bytes memory sig3) = _buildEOI(roundManager, corpOwner, investor1Key, 12, ticket);
        vm.prank(investor1);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager)
            .submitEOI(roundId, eoi3, new string[](1), new string[](2), sig3, 12, new address[](0), bytes32(0));
    }

    function test_FCFS_FounderOverrideScopedToOneCompany() public {
        string[] memory allowed = new string[](1);
        allowed[0] = "USA";

        ZKPassportEligibilityCondition cond = ZKPassportEligibilityCondition(
            conditionFactory.deployCondition(
                EligibilityRules({
                    allowedNationalities: allowed,
                    excludedNationalities: new string[](0),
                    minimumAge: 18,
                    enforceSanctions: false
                }),
                bytes32(0)
            )
        );

        bytes32 round1 =
            _createRound(corp, roundManager, corpOwner, corpOwnerKey, RoundType.FCFS, VALUATION, address(cond));
        bytes32 round2 =
            _createRound(corp2, roundManager2, corp2Owner, corp2OwnerKey, RoundType.FCFS, VALUATION, address(cond));

        // Alpha Corp grants founder override to corporateInvestor (entity without passport).
        vm.prank(corpOwner);
        cond.setFounderOverride(roundManager, corporateInvestor, true);

        // Succeeds on Alpha Corp's FCFS round.
        (EOI memory eoiA, bytes memory sigA) =
            _buildEOI(roundManager, corpOwner, corporateInvestorKey, 20, 5_000 * 10 ** 6);
        vm.prank(corporateInvestor);
        (bytes32 aggA,) = RoundManager(roundManager)
            .submitEOI(round1, eoiA, new string[](1), new string[](2), sigA, 20, new address[](0), bytes32(0));
        assertEq(uint8(RoundManager(roundManager).getEscrowDetails(aggA).status), uint8(EscrowStatus.FINALIZED));

        // Still blocked on Beta Corp's FCFS round sharing the exact same condition instance.
        (EOI memory eoiB, bytes memory sigB) =
            _buildEOI(roundManager2, corp2Owner, corporateInvestorKey, 21, 5_000 * 10 ** 6);
        vm.prank(corporateInvestor);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager2)
            .submitEOI(round2, eoiB, new string[](1), new string[](2), sigB, 21, new address[](0), bytes32(0));
    }

    function test_PerRoundDistinctRulesOnSameCompany_WithoutModifyingRoundManager() public {
        string[] memory r1Allowed = new string[](2);
        r1Allowed[0] = "GBR";
        r1Allowed[1] = "USA";
        ZKPassportEligibilityCondition cond1 = ZKPassportEligibilityCondition(
            conditionFactory.deployCondition(
                EligibilityRules({
                    allowedNationalities: r1Allowed,
                    excludedNationalities: new string[](0),
                    minimumAge: 18,
                    enforceSanctions: false
                }),
                keccak256("alpha-round-1")
            )
        );

        string[] memory r2Allowed = new string[](2);
        r2Allowed[0] = "DEU";
        r2Allowed[1] = "FRA";
        ZKPassportEligibilityCondition cond2 = ZKPassportEligibilityCondition(
            conditionFactory.deployCondition(
                EligibilityRules({
                    allowedNationalities: r2Allowed,
                    excludedNationalities: new string[](0),
                    minimumAge: 21,
                    enforceSanctions: true
                }),
                keccak256("alpha-round-2")
            )
        );

        bytes32 round1 = _createRound(
            corp, roundManager, corpOwner, corpOwnerKey, RoundType.FounderApproved, VALUATION, address(cond1)
        );
        bytes32 round2 = _createRound(
            corp, roundManager, corpOwner, corpOwnerKey, RoundType.FounderApproved, VALUATION + 1, address(cond2)
        );

        // Investor1 submits EOIs to both rounds, then proves ONLY cond1.
        (EOI memory eoi1, bytes memory sig1) = _buildEOI(roundManager, corpOwner, investor1Key, 30, 5_000 * 10 ** 6);
        vm.prank(investor1);
        (bytes32 agg1,) = RoundManager(roundManager)
            .submitEOI(round1, eoi1, new string[](1), new string[](2), sig1, 30, new address[](0), bytes32(0));

        (EOI memory eoi2, bytes memory sig2) = _buildEOI(roundManager, corpOwner, investor1Key, 31, 5_000 * 10 ** 6);
        vm.prank(investor1);
        (bytes32 agg2,) = RoundManager(roundManager)
            .submitEOI(round2, eoi2, new string[](1), new string[](2), sig2, 31, new address[](0), bytes32(0));

        ProofVerificationParams memory pCond1 = _proofParams(investor1, cond1, 7 days);
        vm.prank(investor1);
        cond1.submitProof(pCond1);

        // Founder can allocate round 1, while round 2 still reverts because its condition is unmet.
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agg1, 5_000 * 10 ** 6);
        assertEq(uint8(RoundManager(roundManager).getEscrowDetails(agg1).status), uint8(EscrowStatus.FINALIZED));

        vm.prank(corpOwner);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager).allocate(agg2, 5_000 * 10 ** 6);
    }
}
