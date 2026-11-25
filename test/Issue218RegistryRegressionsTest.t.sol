// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {DealManager} from "../src/DealManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {Escrow, EscrowStatus, LexScrowStorage} from "../src/storage/LexScrowStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {UUPSUpgradeable} from "../dependencies/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract FakeUpgradeFactory {
    address public refImplementation;

    function setRefImplementation(address impl) external {
        refImplementation = impl;
    }

    function getRefImplementation() external view returns (address) {
        return refImplementation;
    }
}

contract MaliciousManagerImpl is UUPSUpgradeable {
    function _authorizeUpgrade(address) internal override {}
}

/// @notice Behavioral regressions for Issue #218 against real protocol contracts (no mock registry).
/// @dev Case 3 and Case 4 execute exact `metalex-webapp` `production` (`625bc5fa8c1`) call sequences:
///      both pass on `develop` (`c110827`, prior to `9d2ab44`) and fail on `38e92baa` with `NotFinalizer()`.
///      Case 2 demonstrates why naive dynamic factory-deployment gating is insufficient, while
///      `CyberCorpFactory`-initialized proxies permanently pin their canonical `upgradeFactory`.
contract Issue218RegistryRegressionsTest is Test {
    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    address internal roundManagerFactory;

    address internal admin;
    address internal officer;
    uint256 internal officerKey;
    address internal investor;
    uint256 internal investorKey;
    address internal companyPayable;

    address internal corp;
    address internal corpAuth;
    address internal issuance;
    address internal dealManager;
    address internal roundManager;
    address internal certPrinter;
    MockPaymentToken internal paymentToken;

    bytes32 internal constant DEAL_TEMPLATE_ID = keccak256("Issue218.PrimaryDealTemplate");
    string internal constant DEAL_URI = "ipfs://issue-218-primary-deal";

    function setUp() public {
        admin = makeAddr("issue218-admin");
        (officer, officerKey) = makeAddrAndKey("issue218-officer");
        (investor, investorKey) = makeAddrAndKey("issue218-investor");
        companyPayable = makeAddr("issue218-company-payable");

        (registry, corpFactory,,,, roundManagerFactory,,) = CyberCorpHelper.deployRegistryAndFactories(admin);

        string[] memory globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";
        vm.prank(admin);
        registry.createTemplate(DEAL_TEMPLATE_ID, "Primary SPA", DEAL_URI, globalFields, partyFields);

        (corp, corpAuth, issuance, dealManager, roundManager) =
            CyberCorpHelper.deployCorp(corpFactory, "Issue 218 Corp", companyPayable, officer);

        vm.prank(officer);
        certPrinter = IssuanceManager(issuance).createCertPrinter(
            new string[](0),
            "Common Stock",
            "CS",
            "ipfs://class-terms",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0),
            bytes("")
        );

        paymentToken = new MockPaymentToken();
        paymentToken.transfer(investor, 100_000e6);
    }

    /// @notice Case 3 (Issue #218 Section 2.1): Two-step primary deal escrow (`DealManager.proposeDeal`).
    /// @dev Exact call sequence from `metalex-webapp` `production` (`625bc5fa8c1`, PR #3348):
    ///      1. Company owner proposes unsigned deal via `DealManager.proposeDeal`.
    ///      2. Investor signs `SignatureData` and locks payment via `DealManager.signDealAndPay`
    ///         (`apps/cybercorps-web/src/features/deals/helpers/primaryEscrowState.ts:721`).
    ///      3. Company proposer (`parties[0]`) signs `SignatureData` and calls
    ///         `CyberAgreementRegistry.signContract` directly because `DealManager` has no
    ///         proposer-signing entry point (`primaryEscrowState.ts:848`, `EscrowedDealPanel.tsx`).
    ///      4. `DealManager.finalizeDeal` releases escrowed payment and delivers the LET
    ///         (`primaryEscrowState.ts:767`).
    ///      Passes on `develop`; reverts `NotFinalizer()` at step 3 on `38e92baa`.
    function test_Case3_ProposeDealTwoStepEscrow_ProposerSignAndFinalize() public {
        address[] memory printers = new address[](1);
        printers[0] = certPrinter;

        CertificateDetails[] memory certs = new CertificateDetails[](1);
        certs[0] = CertificateDetails({
            signingOfficerName: "Alice Founder",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 25_000,
            issuerUSDValuationAtTimeOfInvestment: 5_000_000,
            unitsRepresented: 25_000,
            legalDetails: "",
            extensionData: bytes("")
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "25000000000";

        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Issue 218 Corp";
        partyValues[0][1] = "Issuer";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Bob Investor";
        partyValues[1][1] = "Purchaser";

        uint256 price = 25_000e6;
        uint256 expiry = block.timestamp + 7 days;

        // 1. Company proposes unsigned deal (`proposeDeal` creates agreement with `finalizer = dealManager`).
        vm.prank(officer);
        (bytes32 agreementId, uint256[] memory certIds) = DealManager(dealManager).proposeDeal(
            printers,
            address(paymentToken),
            price,
            DEAL_TEMPLATE_ID,
            1,
            globalValues,
            parties,
            certs,
            partyValues,
            new address[](0),
            bytes32(0),
            expiry
        );
        assertFalse(registry.hasSigned(agreementId, officer), "proposeDeal leaves parties[0] unsigned");

        // 2. Investor signs `SignatureData` and locks funds in escrow via `DealManager.signDealAndPay`.
        string[] memory globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";

        bytes memory investorSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            investorKey
        );

        vm.startPrank(investor);
        paymentToken.approve(dealManager, price);
        DealManager(dealManager).signDealAndPay(
            investor,
            agreementId,
            investorSig,
            partyValues[1],
            false,
            "Bob Investor",
            ""
        );
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(dealManager), price, "investor payment is now locked in DealManager escrow");

        // 3. Company (`parties[0]`) signs in `CyberAgreementRegistry` via `buildSignContractCall` (`signContract`).
        bytes memory officerSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            officerKey
        );

        vm.prank(officer);
        registry.signContract(agreementId, partyValues[0], officerSig, false, "");

        // 4. Company finalizes escrow via `DealManager.finalizeDeal`.
        vm.prank(officer);
        DealManager(dealManager).finalizeDeal(agreementId);

        assertTrue(registry.isFinalized(agreementId), "agreement must finalize");
        assertEq(LedgerEntryToken(certPrinter).ownerOf(certIds[0]), investor, "investor must receive LET");
        assertGt(paymentToken.balanceOf(companyPayable), 0, "company payable must receive net proceeds");
    }

    /// @notice Case 4 (Issue #218 Section 2.2): EOA/Safe finalizer service agreement flow.
    /// @dev Exact call sequence from `metalex-webapp` `production` (`625bc5fa8c1`):
    ///      `apps/web/src/app/(frame-layout)/metavest-agreement/[chainId]/sign-service-agreement/[agreementId]/_components/SignPageView.tsx:184-260`.
    ///      Passes on `develop`; reverts `NotFinalizer()` when counterparty calls `signContractFor` on `38e92baa`.
    function test_Case4_EOAFinalizerServiceAgreement_CounterpartySignAndFinalize() public {
        (address guardianSafe, uint256 guardianKey) = makeAddrAndKey("issue218-guardian-finalizer");
        (address contractor, uint256 contractorKey) = makeAddrAndKey("issue218-contractor");

        string[] memory globalFields = new string[](1);
        globalFields[0] = "PurchaseAmount";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Name";
        partyFields[1] = "Capacity";

        string[] memory globalValues = new string[](1);
        globalValues[0] = "5000000000";

        address[] memory parties = new address[](2);
        parties[0] = guardianSafe;
        parties[1] = contractor;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "BORG Guardian";
        partyValues[0][1] = "Client";
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Jane Contractor";
        partyValues[1][1] = "Service Provider";

        bytes32 agreementId = registry.createContract(
            DEAL_TEMPLATE_ID,
            42,
            globalValues,
            parties,
            partyValues,
            bytes32(0),
            guardianSafe,
            block.timestamp + 14 days
        );

        bytes memory guardianSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            guardianKey
        );
        vm.prank(guardianSafe);
        registry.signContractFor(guardianSafe, agreementId, partyValues[0], guardianSig, false, "");

        bytes memory contractorSig = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            DEAL_URI,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            contractorKey
        );
        vm.prank(contractor);
        registry.signContractFor(contractor, agreementId, partyValues[1], contractorSig, false, "");

        vm.prank(guardianSafe);
        registry.finalizeContract(agreementId);

        assertTrue(registry.isFinalized(agreementId), "service agreement must finalize");
    }

    /// @notice Case 2 (Issue #218 Section 1): Direct `deployRoundManager` allows attacker-chosen `upgradeFactory`,
    ///         whereas `CyberCorpFactory`-deployed managers permanently lock `upgradeFactory` to the canonical factory.
    /// @dev Confirms Detoo's point that a dynamic factory-deployment gate is unsafe, while proving that a static
    ///      pre-upgrade allowlist of existing `CyberCorpFactory`-initialized proxies cannot be upgraded to arbitrary code.
    function test_Case2_DirectFactoryDeployCanHijackImpl_WhileCyberCorpFactoryProxyCannot() public {
        address attacker = makeAddr("issue218-attacker");
        FakeUpgradeFactory fakeFactory = new FakeUpgradeFactory();
        MaliciousManagerImpl maliciousImpl = new MaliciousManagerImpl();
        fakeFactory.setRefImplementation(address(maliciousImpl));

        // 1. Direct permissionless `RoundManagerFactory.deployRoundManager` leaves `initialize` open to attacker:
        //    attacker supplies `fakeFactory` and upgrades the proxy to arbitrary bytecode.
        vm.startPrank(attacker);
        BorgAuth attackerAuth = new BorgAuth(attacker);
        address attackerProxy = RoundManagerFactory(roundManagerFactory).deployRoundManager(keccak256("attacker-rm"));
        RoundManager(attackerProxy).initialize(
            address(attackerAuth),
            corp,
            address(registry),
            issuance,
            address(fakeFactory)
        );
        RoundManager(attackerProxy).upgradeToAndCall(address(maliciousImpl), "");
        vm.stopPrank();

        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(
            address(uint160(uint256(vm.load(attackerProxy, implSlot)))),
            address(maliciousImpl),
            "direct factory deploy lets attacker swap implementation"
        );

        // 2. By contrast, an existing `CyberCorpFactory`-deployed `RoundManager` initialized `upgradeFactory`
        //    atomically to the canonical MetaLeX `roundManagerFactory`, so even its `OWNER_ROLE` reverts
        //    with `NotRefImplementation()` if it attempts to upgrade to `maliciousImpl`.
        vm.prank(officer);
        vm.expectRevert(RoundManager.NotRefImplementation.selector);
        RoundManager(roundManager).upgradeToAndCall(address(maliciousImpl), "");
    }
}
