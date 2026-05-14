// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployPumpCorpFactoryScript} from "../script/deploy-pump-factory.s.sol";
import {PumpCorpFactory, PumpCorpFactoryLib} from "../src/PumpCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {FeeOverride} from "../src/interfaces/IRoundManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {EIP712Lib} from "../src/libs/EIP712Lib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Round, RoundType} from "../src/libs/RoundLib.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCertData} from "../src/interfaces/IRoundManager.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {LexChexCondition} from "../src/libs/conditions/lexchexCondition.sol";
import {OrCondition} from "../src/libs/conditions/OrCondition.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @dev Always-failing condition: any allocation attempt on its escrow is blocked.
contract AlwaysFalseCondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return false;
    }
}

/// @dev Togglable mock: call setApproved(true) to simulate a valid zkPassport proof.
contract MockZkPassportCondition {
    bool public shouldPass;

    function setApproved(bool _approved) external {
        shouldPass = _approved;
    }

    function checkCondition(address, bytes4, bytes memory) external view returns (bool) {
        return shouldPass;
    }
}

/// @title PumpCorpFactory Escrow Signature Security Tests
/// @notice Focused on whether an attacker who hijacks an escrowed signature can
///         swap in a different officer or alter key corp/round parameters.
///
/// Run with (timeout = 5m):
///   forge test --use solc:0.8.28 --via-ir --fork-url $END_PT_BASE -vvv --mp PumpCorpFactory.t.sol
contract PumpCorpFactoryTest is Test {
    using Strings for address;

    string saltStrPump = "PumpCorpFactoryTest.pump";

    // ── Actors ────────────────────────────────────────────────────────────────
    uint256 internal deployerPk;
    uint256 internal officerPk;
    uint256 internal attackerPk;
    uint256 internal investorPk;

    address internal deployer;
    address internal officer;
    address internal attacker;
    address internal investor;

    // ── Live deployments (DeploymentConstants.coreV2) ────────────
    DeploymentConstants.CoreDeployment internal net =
        DeploymentConstants.coreV2(block.chainid);
    address internal metalexSafe = net.metalexSafe;

    // Convenience aliases
    address internal REGISTRY                 = net.cyberAgreementRegistry;
    address internal CYBERCORP_SINGLE_FACTORY = net.cyberCorpSingleFactory;
    address internal DEAL_MANAGER_FACTORY     = net.dealManagerFactory;
    address internal URI_BUILDER              = net.uriBuilder;

    // ── Live LexChex addresses on Base ───────────────────────────────────────
    address internal LEXCHEX                  = net.lexchex;
    address internal LEXCHEX_CONDITION        = net.lexchexCondition;
    address internal LEXCHEX_AUTH             = net.lexchexAuth;

    // ── Mock zkPassport condition deployed in setUp ───────────────────────────────
    MockZkPassportCondition internal zkpassportCondition;

    // ── OrCondition: zkpassportCondition || LEXCHEX_CONDITION ────────────────
    OrCondition internal orCondition;

    // ── Fresh PumpCorpFactory deployed in setUp ───────────────────────────────
    PumpCorpFactory internal pumpFactory;
    RoundManagerFactory internal rmFactory;

    // ── Shared round constants ────────────────────────────────────────────────
    uint256 internal constant RAISE_CAP      = 1_000_000e6;
    uint256 internal constant MIN_TICKET     =    10_000e6;
    uint256 internal constant MAX_TICKET     =   100_000e6;
    uint256 internal constant PRICE_PER_UNIT =         1e6;
    uint256 internal constant VALUATION      = 20_000_000e6;

    // Any bytes32 template ID works for createRound (registry not consulted there)
    bytes32 internal constant TEMPLATE_ID = bytes32(uint256(1));

    // ── Lifecycle test additions ──────────────────────────────────────────────
    MockERC20 internal payToken;      // deployed in setUp

    // ── Shared cert / legal arrays (1 cert → legalDetails & extensionData length 1) ─
    CyberCertData[] internal certDataArr;
    string[]        internal legalDetails;
    bytes[]         internal extensionData;
    string[]        internal officerPartyValues;

    function setUp() public {
        assertEq(block.chainid, DeploymentConstants.BASE, "Fork test: Base only @ block 45993317");
        vm.rollFork(45993317);
//        assertEq(block.chainid, DeploymentConstants.BASE_SEPOLIA, "For test: Base Sepolia only");

        (deployer, deployerPk) = makeAddrAndKey("deployer");
        (officer, officerPk) = makeAddrAndKey("officer");
        (attacker, attackerPk) = makeAddrAndKey("attacker");
        (investor, investorPk) = makeAddrAndKey("investor");

        // Deploy mock zkPassport condition
        zkpassportCondition = new MockZkPassportCondition();

        // Deploy OrCondition (zkPassport || LexChex)
        address[] memory orAddrs = new address[](2);
        orAddrs[0] = address(zkpassportCondition);
        orAddrs[1] = LEXCHEX_CONDITION;
        orCondition = new OrCondition(orAddrs);

        // Deploy PumpCorpFactory
        BorgAuth pumpAuth;
        (pumpFactory, rmFactory, , , pumpAuth) = (new DeployPumpCorpFactoryScript()).runWithArgs(
            block.chainid,
            saltStrPump,
            deployerPk
        );

        // Simulate granting PumpCorpFactory owner access to LeXcheX and to RoundManagerFactory auth
        vm.startPrank(metalexSafe);
        BorgAuth(pumpFactory.lexchexAuth()).updateRole(address(pumpFactory), 99);
        BorgAuth(pumpAuth).updateRole(address(pumpFactory), 99);
        vm.stopPrank();

        string[] memory legend = new string[](1);
        legend[0] = "SEED SAFE";
        certDataArr.push(CyberCertData({
            name:           "SEED SAFE",
            symbol:         "SEEDSAFE",
            uri:            "ipfs://seed-safe",
            securityClass:  SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension:      address(0),
            defaultLegend:  legend
        }));

        legalDetails    = new string[](1);
        legalDetails[0] = "SEED SAFE legal details";
        extensionData   = new bytes[](1);
        extensionData[0] = "";

        // ── Lifecycle setup ──────────────────────────────────────────────────
        payToken = new MockERC20("Test Token", "TT", 9);
        officerPartyValues = _lifecyclePartyValues("Alice Officer", officer);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Predict the CREATE2 addresses that PumpCorpFactory will deploy to for a given salt.
    function _predict(uint256 salt)
        internal
        view
        returns (address corp, address rm)
    {
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        corp = CyberCorpSingleFactory(CYBERCORP_SINGLE_FACTORY)
            .computeCyberCorpSingleAddress(corpSalt);
        rm   = rmFactory
            .computeRoundManagerAddress(corpSalt);
    }

    /// Build a CompanyOfficer for the given EOA.
    function _officer(address eoa, string memory name)
        internal
        pure
        returns (CompanyOfficer memory)
    {
        return CompanyOfficer({eoa: eoa, name: name, contact: "officer@corp.com", title: "CEO"});
    }

    /// Build party-values sized to TEMPLATE_ID's partyFields.
    /// Slot 0 = name, slot 1 = eoa hex string, remaining slots = "".
    function _lifecyclePartyValues(string memory name_, address eoa_)
    internal view returns (string[] memory pv)
    {
        (, , , string[] memory pFields) = CyberAgreementRegistry(REGISTRY)
            .getTemplateDetails(TEMPLATE_ID);
        pv = new string[](pFields.length);
        if (pFields.length > 0) pv[0] = name_;
        if (pFields.length > 1) pv[1] = eoa_.toHexString();
    }

    /// Build global-values sized to TEMPLATE_ID's globalFields.
    /// Slot 0 = "Seed Round", remaining slots = "".
    function _lifecycleGlobalValues()
    internal view returns (string[] memory gv)
    {
        (, , string[] memory gFields, ) = CyberAgreementRegistry(REGISTRY)
            .getTemplateDetails(TEMPLATE_ID);
        gv = new string[](gFields.length);
        if (gFields.length > 0) gv[0] = "Seed Round";
    }

    /// Compute the EIP-712 supplemental metadata signature for PumpCorpFactory.
    function _metaSig(
        uint256 salt,
        address companyPayable,
        bool publicRound,
        bool allowTimedOffers,
        bool restrictEndTimeReduction,
        CompanyOfficer memory off,
        string memory companyName_,
        string memory companyType_,
        string memory companyJurisdiction_,
        string memory companyContactDetails_,
        string memory defaultDisputeResolution_,
        bytes[] memory extensionData_,
        string[] memory roundPartyValues_,
        string[] memory legal,
        CyberCertData[] memory certs,
        address[] memory conditions,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        bytes32 domainSep = keccak256(abi.encode(
            PumpCorpFactoryLib.FACTORY_DOMAIN_TYPEHASH,
            keccak256(bytes("PumpCorpFactory")),
            keccak256(bytes("1")),
            block.chainid,
            address(pumpFactory)
        ));
        bytes32 officerHash = keccak256(abi.encode(
            PumpCorpFactoryLib.OFFICER_TYPEHASH,
            off.eoa,
            keccak256(bytes(off.name)),
            keccak256(bytes(off.contact)),
            keccak256(bytes(off.title))
        ));
        bytes32 structHash = keccak256(abi.encode(
            PumpCorpFactoryLib.ROUND_SUPPLEMENTAL_TYPEHASH,
            corpSalt,
            companyPayable,
            publicRound,
            allowTimedOffers,
            restrictEndTimeReduction,
            officerHash,
            keccak256(bytes(companyName_)),
            keccak256(bytes(companyType_)),
            keccak256(bytes(companyJurisdiction_)),
            keccak256(bytes(companyContactDetails_)),
            keccak256(bytes(defaultDisputeResolution_)),
            PumpCorpFactoryLib.hashBytesArray(extensionData_),
            PumpCorpFactoryLib.hashStringArray(roundPartyValues_),
            PumpCorpFactoryLib.hashStringArray(legal),
            PumpCorpFactoryLib.hashCertDataArray(certs),
            PumpCorpFactoryLib.hashAddresses(conditions)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// Convenience wrapper using standard happy-path values.
    function _metaSigDefault(uint256 salt, uint256 signerPk) internal view returns (bytes memory) {
        return _metaSig(
            salt,
            address(this),
            true,
            true,
            true,
            _officer(officer, "Alice Officer"),
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            extensionData,
            officerPartyValues,
            legalDetails,
            certDataArr,
            new address[](0),
            signerPk
        );
    }

    /// Escrow signature parameterised for a specific paymentToken, templateId, and roundType.
    function _escrowSigFull(
        address rm_,
        address corp_,
        uint256 signerPk_,
        uint256 startTime_,
        uint256 endTime_,
        address paymentToken_,
        bytes32 templateId_,
        RoundType roundType_
    ) internal view returns (bytes memory sig) {
        bytes32 roundId_ = keccak256(abi.encodePacked(
            SecuritySeries.SeriesSeed,
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            uint8(roundType_),
            startTime_, endTime_,
            templateId_,
            paymentToken_,
            PRICE_PER_UNIT, VALUATION, corp_
        ));
        bytes32 domainSep = keccak256(abi.encode(
            EIP712Lib.EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("RoundManager")),
            keccak256(bytes("1")),
            block.chainid, rm_
        ));
        bytes32 structHash = keccak256(abi.encode(
            EIP712Lib.ESCROWEDSIGNATUREDATA_TYPEHASH,
            roundId_,
            uint8(SecuritySeries.SeriesSeed),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            uint8(roundType_),
            startTime_, endTime_,
            templateId_,
            paymentToken_,
            PRICE_PER_UNIT, VALUATION, corp_
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk_, digest);
        sig = abi.encodePacked(r, s, v);
    }

    /// Compute the investor's EIP-712 EOI signature for TEMPLATE_ID.
    function _eoiSig(
        uint256 eoiSalt_,
        string[] memory globalValues_,
        string[] memory investorPv_
    ) internal view returns (bytes memory) {
        CyberAgreementRegistry reg = CyberAgreementRegistry(REGISTRY);
        (
            string memory legalUri,
            ,
            string[] memory gFields,
            string[] memory pFields
        ) = reg.getTemplateDetails(TEMPLATE_ID);
        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        bytes32 contractId = keccak256(
            abi.encode(TEMPLATE_ID, eoiSalt_, globalValues_, parties)
        );
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            reg.DOMAIN_SEPARATOR(),
            reg.SIGNATUREDATA_TYPEHASH(),
            contractId,
            legalUri,
            gFields,
            pFields,
            globalValues_,
            investorPv_,
            investorPk
        );
    }

    function _emptyLex() internal pure returns (LexChexDetails memory) {
        return LexChexDetails({
            request: MintRequest({
            uuid: 0, owner: address(0),
            investorName: "", investorType: "",
            investorJurisdiction: "", investorContact: "",
            mintPrice: 0, expiry: 0, paymentToken: address(0)
        }),
            templateId: bytes32(0),
            salt: 0,
            globalValues: new string[](0),
            parties: new address[](0),
            partyValues: new string[][](0),
            agreementSignature: ""
        });
    }

    /// Deploy a corp + round using payToken and TEMPLATE_ID.
    function _deployLifecycle(
        uint256 salt_,
        RoundType roundType_,
        address[] memory conditions
    ) internal returns (address corp_, address rm_, bytes32 roundId_)
    {
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory escrowSig;
        {
            (address predCorp, address predRM) = _predict(salt_);
            escrowSig = _escrowSigFull(
                predRM, predCorp, officerPk,
                start, end,
                address(payToken), TEMPLATE_ID, roundType_
            );
        }

        (corp_, , , , rm_, roundId_) = pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt_,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(payToken), PRICE_PER_UNIT, VALUATION,
            officerPartyValues,
            escrowSig,
            _metaSig(
                salt_, address(this), true, true, true,
                _officer(officer, "Alice Officer"),
                "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
                extensionData,
                officerPartyValues,
                legalDetails, certDataArr, conditions,
                officerPk
            ),
            roundType_,
            conditions,
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  DEFAULT FEE
    // ═══════════════════════════════════════════════════════════════════════════

    function test_NoRoundManagerFeeOverride() public {
        (, address rm, ) = _deployLifecycle(299999, RoundType.FCFS, new address[](0));

        FeeOverride memory fo = rmFactory.getInstanceFeeOverride(rm);
        assertFalse(fo.enabled, "there should be no fee overrides");
        assertEq(RoundManager(rm).computeFee(1 ether), 0.003 ether, "expect fee ratio of 0.3%");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  HAPPY PATH
    // ═══════════════════════════════════════════════════════════════════════════

    /// FCFS round: submitEOI auto-triggers allocate — full life cycle in one tx.
    function test_HappyPath_SubmitEOI_FCFS() public {
        (, address rm, bytes32 roundId) = _deployLifecycle(300001, RoundType.FCFS, new address[](0));

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 eoiSalt      = 1;
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        (bytes32 agreementId, ) = RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(eoiSalt, globalValues, investorPv),
            eoiSalt, new address[](0), bytes32(0)
        );
        vm.stopPrank();

        assertTrue(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "agreement must be finalized after FCFS submitEOI"
        );
        assertEq(
            RoundManager(rm).getRound(roundId).raised,
            investAmount,
            "raised must equal investAmount"
        );
        // No fees: companyPayable receives full investAmount, fee recipient receives nothing
        assertEq(
            payToken.balanceOf(address(this)),
            investAmount - RoundManager(rm).computeFee(investAmount),
            "companyPayable must receive investAmount less fee"
        );
        assertEq(
            payToken.balanceOf(rmFactory.getPlatformPayable()),
            RoundManager(rm).computeFee(investAmount),
            "fee recipient must receive fees"
        );
    }

    /// FCFS round: submitEOI auto-triggers allocate — full life cycle in one tx, with zkPassport
    function test_HappyPath_SubmitEOI_FCFS_zkpassportCondition() public {
        address[] memory zkConds = new address[](1);
        zkConds[0] = address(zkpassportCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(300003, RoundType.FCFS, zkConds);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 eoiSalt      = 1;
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);

        zkpassportCondition.setApproved(true); // simulate passing zkpassport condition

        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(eoiSalt, globalValues, investorPv),
            eoiSalt, new address[](0), bytes32(0)
        );
        vm.stopPrank();
    }

    /// FCFS round with zkPassport condition: EOI fails when condition not approved.
    function test_RevertIf_ZkPassportCondition_Blocks_When_Not_Approved() public {
        address[] memory zkConds = new address[](1);
        zkConds[0] = address(zkpassportCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(300005, RoundType.FCFS, zkConds);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);

        zkpassportCondition.setApproved(false); // simulate failing zkpassport condition

        // Pre-compute sig before vm.expectRevert — _eoiSig makes an external call
        bytes memory eoiSig = _eoiSig(1, globalValues, investorPv);

        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        vm.expectRevert(RoundManager.AgreementConditionsNotMet.selector);
        RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            eoiSig,
            1, new address[](0), bytes32(0)
        );
        vm.stopPrank();
    }

    /// FounderApproved round: submitEOI parks the EOI, then officer calls allocate.
    function test_HappyPath_SubmitEOI_FounderApproved_Allocate() public {
        (, address rm, bytes32 roundId) = _deployLifecycle(300002, RoundType.FounderApproved, new address[](0));

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 eoiSalt      = 2;
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        (bytes32 agreementId, ) = RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(eoiSalt, globalValues, investorPv),
            eoiSalt, new address[](0), bytes32(0)
        );
        vm.stopPrank();

        // EOI is parked (escrow PAID) but agreement not yet finalized
        assertFalse(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "must not be finalized before allocate"
        );

        // Officer approves and allocates
        vm.prank(officer);
        RoundManager(rm).allocate(agreementId, investAmount);

        assertTrue(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "agreement must be finalized after allocate"
        );
        assertEq(
            RoundManager(rm).getRound(roundId).raised,
            investAmount,
            "raised must equal investAmount"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ATTACKER CANNOT SUBSTITUTE A DIFFERENT OFFICER EOA
    // ═══════════════════════════════════════════════════════════════════════════

    /// Attacker intercepts the officer's escrow signature but plugs in their own
    /// officer info. Should be prevented by the officer's meta signature.
    function test_RevertIf_AttackerSwapsOfficer() public {
        uint256 salt = 11111;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory officerEscrowSig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker's officer struct + matching partyValues pointing to attacker
        CompanyOfficer memory fakeOff = _officer(attacker, "Attacker");
        string[] memory fakePv = _lifecyclePartyValues(fakeOff.name, attacker);

        // Attacker cannot use his own signatures
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),        // companyPayable
            fakeOff, // ← faked by attacker
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            fakePv, // ← faked by attacker
            _metaSig(
                salt,
                address(this),
                true,
                true,
                true,
                _officer(officer, "Alice Officer"),
                "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
                extensionData,
                officerPartyValues,
                legalDetails,
                certDataArr,
                new address[](0),
                attackerPk
            ),       // ← signed by attacker
            _metaSigDefault(salt, officerPk), // ← signed by officer, not attacker
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),        // companyPayable
            fakeOff, // ← faked by attacker
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            fakePv, // ← faked by attacker
            officerEscrowSig,       // ← signed by officer, not attacker
            _metaSigDefault(salt, officerPk), // ← signed by officer, not attacker
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    /// Attacker signs the escrow data with their own key but claims the victim
    /// officer's EOA.  RoundManager recovers attacker ≠ claimed officer → revert.
    function test_RevertIf_AttackerSignsEscrowForVictimOfficer() public {
        uint256 salt = 22222;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory attackerSig = _escrowSigFull(predRM, predCorp, attackerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        CompanyOfficer memory claimedOff = _officer(officer, "Alice Officer");
        string[] memory pv = _lifecyclePartyValues(claimedOff.name, officer);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            claimedOff,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv,
            attackerSig,      // ← signed by attacker, not officer
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    /// Attacker should not be able to sign the metadata with their own key but claims
    /// the victim officer's EOA.
    function test_RevertIf_AttackerSignsMetadataForVictimOfficer() public {
        uint256 salt = 33333;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory attackerSig = _metaSigDefault(salt, attackerPk);

        CompanyOfficer memory claimedOff = _officer(officer, "Alice Officer");
        string[] memory pv = _lifecyclePartyValues(claimedOff.name, officer);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            claimedOff,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv,
            _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS),
            attackerSig,      // ← signed by attacker, not officer
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  PARTY VALUES GUARD (factory-level, before signature check)
    // ═══════════════════════════════════════════════════════════════════════════

    /// roundPartyValues[1] does not parse to officer.eoa → GlobalOrPartyValuesMismatch.
    function test_RevertIf_PartyValues_EOA_Mismatch() public {
        uint256 salt = 33333;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        string[] memory pv = new string[](2);
        pv[0] = "Alice Officer";
        pv[1] = attacker.toHexString(); // wrong EOA

        vm.expectRevert(PumpCorpFactory.GlobalOrPartyValuesMismatch.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// roundPartyValues[0] does not match officer.name → GlobalOrPartyValuesMismatch.
    function test_RevertIf_PartyValues_Name_Mismatch() public {
        uint256 salt = 44444;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        string[] memory pv = new string[](2);
        pv[0] = "Bob Attacker";        // wrong name
        pv[1] = officer.toHexString();

        vm.expectRevert(PumpCorpFactory.GlobalOrPartyValuesMismatch.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// roundPartyValues.length == 1 → GlobalOrPartyValuesMismatch.
    function test_RevertIf_PartyValues_TooShort() public {
        uint256 salt = 55555;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        string[] memory pv = new string[](1);
        pv[0] = "Alice Officer";

        vm.expectRevert(PumpCorpFactory.GlobalOrPartyValuesMismatch.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Empty roundPartyValues → GlobalOrPartyValuesMismatch.
    function test_RevertIf_PartyValues_Empty() public {
        uint256 salt = 66666;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        vm.expectRevert(PumpCorpFactory.GlobalOrPartyValuesMismatch.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            new string[](0), sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  CROSS-CORP REPLAY: signature bound to a specific corp address via CREATE2
    // ═══════════════════════════════════════════════════════════════════════════

    /// Escrowed signature for salt A is bound to corpA/rmA.  Replaying it for salt B
    /// (different corp/rm) must fail because the signed companyAddress mismatches.
    function test_RevertIf_EscrowedSignatureReplayedForDifferentSalt() public {
        uint256 saltA = 77777;
        uint256 saltB = 88888;

        (address predCorpA, address predRMA) = _predict(saltA);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            saltB,            // different salt → different corp address in RoundManager
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues,
            _escrowSigFull(predRMA, predCorpA, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS), // signed with saltA
            _metaSigDefault(saltB, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Metadata signature for salt A is bound to corpA/rmA.  Replaying it for salt B
    /// (different corp/rm) must fail because the signed companyAddress mismatches.
    function test_RevertIf_MetadataSignatureReplayedForDifferentSalt() public {
        uint256 saltA = 77777;
        uint256 saltB = 88888;

        (address predCorpB, address predRMB) = _predict(saltA);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            saltB,            // different salt → different corp address in RoundManager
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues,
            _escrowSigFull(predRMB, predCorpB, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS),
            _metaSigDefault(saltA, officerPk), // signed with saltA
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  ROUND PARAMETER TAMPERING
    // ═══════════════════════════════════════════════════════════════════════════

    /// Attacker inflates raiseCap after intercepting a valid signature.
    function test_RevertIf_TamperedRaiseCap() public {
        uint256 salt = 11112;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP * 100, // ← tampered: 100× raise cap
            MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Attacker deflates valuation to give investors a larger equity slice.
    function test_RevertIf_TamperedValuation() public {
        uint256 salt = 11113;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT,
            VALUATION / 10, // ← tampered: 10× lower valuation
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Attacker swaps the payment token to drain a different ERC-20.
    function test_RevertIf_TamperedPaymentToken() public {
        uint256 salt = 11114;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0xCAFEBABE), // ← tampered payment token
            PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Attacker changes RoundType from FCFS to FounderApproved to gain
    /// discretionary allocation control.
    function test_RevertIf_TamperedRoundType() public {
        uint256 salt = 11115;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);
        // sig was produced for FCFS

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FounderApproved, // ← tampered
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Attacker extends the end time to keep a round open beyond the signed window.
    function test_RevertIf_TamperedEndTime() public {
        uint256 salt = 11116;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start,
            end + 365 days, // ← tampered: extend by 1 year
            true, true, true
        );
    }

    /// Zero-length signature is explicitly rejected before EIP-712 recovery.
    function test_RevertIf_EmptyEscrowedSignature() public {
        uint256 salt = 22222;

        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues,
            "",  // empty escrowed sig
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  PARAMETERS NOT IN ESCROW SIGNATURE
    // ═══════════════════════════════════════════════════════════════════════════

    /// `_companyPayable` is protected by the meta signature.
    /// An attacker who intercepts the officer's escrow signature cannot redirect
    /// the company payment address without the officer's meta signature.
    function test_RevertIf_MetaSigRequired_CompanyPayableProtected() public {
        uint256 salt = 55551;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory officerEscrowedSig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker forges a meta sig with their own key, redirecting payment to themselves.
        // The factory checks that the meta sig signer == officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, attacker, true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            attacker,             // ← redirected payment address
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, officerEscrowedSig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            attacker,             // ← redirected payment address
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, officerEscrowedSig,
            _metaSigDefault(salt, officerPk), // ← signed by officer, not attacker
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    /// Demonstrates that legalDetails are not covered by the escrow signature,
    /// but ARE covered by the meta signature — an attacker who cannot forge the
    /// meta sig is blocked from substituting legal text.
    function test_RevertIf_MetaSigRequired_LegalDetailsProtected() public {
        uint256 salt = 55552;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory officerSig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        string[] memory altLegal = new string[](1);
        altLegal[0] = "Attacker-substituted legal details";

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, altLegal, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            altLegal,             // ← substituted legal details
            extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, officerSig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            altLegal,             // ← substituted legal details
            extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, officerSig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  CERTIFICATE DATA PROTECTED BY META SIGNATURE
    //  certData is NOT covered by the escrow signature, but IS covered by the
    //  meta signature.  An attacker without the officer's key cannot substitute it.
    // ═══════════════════════════════════════════════════════════════════════════

    /// Attacker tries to substitute CommonStock / SeriesA cert while the officer
    /// signed for SeriesSeed / SAFE.  Without the officer's key the forged meta
    /// sig is rejected.
    function test_RevertIf_MetaSigRequired_CertSecurityClassAndSeriesProtected() public {
        uint256 salt = 60001;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        // Signature was produced for SeriesSeed (as usual)
        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker substitutes CommonStock / SeriesA cert
        CyberCertData[] memory altCert = new CyberCertData[](1);
        string[] memory legend = new string[](1);
        legend[0] = "SERIES A";
        altCert[0] = CyberCertData({
            name:           "SERIES A COMMON",
            symbol:         "SERIESA",
            uri:            "ipfs://series-a",
            securityClass:  SecurityClass.CommonStock,  // ← different from signed
            securitySeries: SecuritySeries.SeriesA,     // ← different from signed
            extension:      address(0),
            defaultLegend:  legend
        });

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, altCert, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData,
            altCert,                    // ← substituted cert
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData,
            altCert,                    // ← substituted cert
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Cert name/symbol are not covered by the escrow signature but ARE covered
    /// by the meta signature.  An attacker without the officer's key is blocked.
    function test_RevertIf_MetaSigRequired_CertNameAndSymbolProtected() public {
        uint256 salt = 60002;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        CyberCertData[] memory altCert = new CyberCertData[](1);
        string[] memory legend = new string[](1);
        legend[0] = "FAKE SAFE";
        altCert[0] = CyberCertData({
            name:           "FAKE SAFE",           // ← not what officer approved
            symbol:         "FAKESAFE",
            uri:            "ipfs://fake-uri",
            securityClass:  SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension:      address(0),
            defaultLegend:  legend
        });

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, altCert, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData,
            altCert, // ← substituted cert
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData,
            altCert, // ← substituted cert
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  OFFICER METADATA PROTECTED BY META SIGNATURE
    //  The full officer struct (eoa, name, contact, title) is NOT covered by the
    //  escrow signature, but IS covered by the meta signature.  An attacker without
    //  the officer's key cannot substitute any of these fields.
    // ═══════════════════════════════════════════════════════════════════════════

    /// Attacker tries to display "Dr. Impostor" on certificates by supplying
    /// a forged meta sig.  Without the officer's key the call reverts.
    function test_RevertIf_MetaSigRequired_OfficerNameProtected() public {
        uint256 salt = 61001;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Use a different name in the officer struct while keeping the same EOA.
        // roundPartyValues[0] must also match the (fake) name to pass the factory guard.
        CompanyOfficer memory fakeNameOfficer = CompanyOfficer({
            eoa:     officer,
            name:    "Dr. Impostor",   // ← not what officer intended
            contact: "officer@corp.com",
            title:   "CEO"
        });
        string[] memory pv = _lifecyclePartyValues("Dr. Impostor", officer);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, fakeNameOfficer, "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, pv, legalDetails, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            fakeNameOfficer,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            fakeNameOfficer,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    /// Attacker tries to use "Supreme Overlord" as officer title on certificates.
    /// Without the officer's key the forged meta sig is rejected.
    function test_RevertIf_MetaSigRequired_OfficerTitleProtected() public {
        uint256 salt = 61002;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        CompanyOfficer memory altTitleOfficer = CompanyOfficer({
            eoa:     officer,
            name:    "Alice Officer",
            contact: "officer@corp.com",
            title:   "Supreme Overlord"
        });

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, altTitleOfficer, "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            altTitleOfficer,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            altTitleOfficer,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  UNSIGNED ROUND FLAGS
    //  publicRound and allowTimedOffers are NOT committed to by the escrow
    //  signature — they can be flipped without the officer's consent.
    // ═══════════════════════════════════════════════════════════════════════════

    /// Officer signs for a private round (publicRound=false) but deployer
    /// flips it to public — investors not on any allowlist can still submit EOIs.
    function test_RevertIf_MetaSigRequired_PublicRoundFlagProtected() public {
        uint256 salt = 62001;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker cannot use his own signatures
        bytes memory attackerMetaSig = _metaSig(salt, address(this), false, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, certDataArr, new address[](0), attackerPk);
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            false,   // ← publicRound flipped
            true, true
        );

        // Test against signature malleability
        // Deploy with publicRound=false even though the officer signed for true
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            false,   // ← publicRound flipped
            true, true
        );
    }

    /// allowTimedOffers is not covered by the escrow signature but IS covered by
    /// the meta signature.  An attacker who cannot forge the meta sig is blocked.
    function test_RevertIf_MetaSigRequired_AllowTimedOffersFlagProtected() public {
        uint256 salt = 62002;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, false, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true,
            false, true  // ← allowTimedOffers flipped
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true,
            false, true  // ← allowTimedOffers flipped
        );
    }

    /// restrictEndTimeReduction is covered by the meta signature.
    /// An attacker who cannot forge the meta sig is blocked from flipping it.
    function test_RevertIf_MetaSigRequired_RestrictEndTimeReductionFlagProtected() public {
        uint256 salt = 62003;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, false, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, officerPartyValues, legalDetails, certDataArr, new address[](0), attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true,
            false  // ← restrictEndTimeReduction flipped
        );

        // Test against signature malleability: officer's sig commits to true,
        // but the call passes false → digest mismatch → revert.
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true,
            false  // ← restrictEndTimeReduction flipped
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  MALICIOUS CONDITION INJECTION (round-level DoS griefing)
    //  roundConditions are NOT signed.  An attacker who submits the transaction
    //  can inject a condition contract that always returns false, permanently
    //  blocking every allocation in the round.
    // ═══════════════════════════════════════════════════════════════════════════

    /// Attacker tries to inject a malicious condition contract that always returns false.
    /// Without the officer's meta signature, the deployment reverts.
    function test_RevertIf_MetaSigRequired_ConditionsProtected() public {
        uint256 salt = 63001;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSigFull(predRM, predCorp, officerPk, start, end, address(0), TEMPLATE_ID, RoundType.FCFS);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        address badCondition = address(new AlwaysFalseCondition());
        address[] memory conditions = new address[](1);
        conditions[0] = badCondition;
        bytes memory attackerMetaSig = _metaSig(
            salt,
            address(this),
            true,
            true,
            true,
            _officer(officer, "Alice Officer"),
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            extensionData,
            officerPartyValues,
            legalDetails,
            certDataArr,
            new address[](0),
            attackerPk
        );

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            attackerMetaSig,
            RoundType.FCFS,
            conditions,   // ← malicious condition injected
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );

        // Test against signature malleability
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            officerPartyValues, sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS,
            conditions,   // ← malicious condition injected
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  OR CONDITION — zkPassport || LexChex
    // ═══════════════════════════════════════════════════════════════════════════

    /// Grant this test contract admin rights on LEXCHEX and mint a valid LexChex to `to`.
    function _mintLexChex(address to) internal {
        uint256 adminRole = BorgAuth(LEXCHEX_AUTH).ADMIN_ROLE();
        vm.prank(metalexSafe);
        BorgAuth(LEXCHEX_AUTH).updateRole(address(this), adminRole);

        LeXcheX(LEXCHEX).mint(to, Accreditation({
            uuid: 0,
            agreementId: bytes32(0),
            registryAddress: address(0),
            investorName: "Test Investor",
            investorType: "Individual",
            investorJurisdiction: "XX",
            investorContact: "investor@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: ""
        }));
    }

    /// Neither credential present → AgreementConditionsNotMet.
    function test_OrCondition_BlocksWhenNeitherCredentialPresent() public {
        address[] memory conds = new address[](1);
        conds[0] = address(orCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(400001, RoundType.FCFS, conds);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        bytes memory eoiSig = _eoiSig(1, globalValues, investorPv);
        vm.expectRevert(RoundManager.AgreementConditionsNotMet.selector);
        RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            eoiSig,
            1, new address[](0), bytes32(0)
        );
        vm.stopPrank();
    }

    /// LexChex only (no zkPassport) → EOI succeeds.
    function test_OrCondition_PassesWithLexChexOnly() public {
        address[] memory conds = new address[](1);
        conds[0] = address(orCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(400002, RoundType.FCFS, conds);

        _mintLexChex(investor);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        (bytes32 agreementId, ) = RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(1, globalValues, investorPv),
            1, new address[](0), bytes32(0)
        );
        vm.stopPrank();

        assertTrue(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "agreement must be finalized after FCFS submitEOI with LexChex"
        );
    }

    /// zkPassport only (no LexChex) → EOI succeeds.
    function test_OrCondition_PassesWithZkPassportOnly() public {
        address[] memory conds = new address[](1);
        conds[0] = address(orCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(400003, RoundType.FCFS, conds);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        zkpassportCondition.setApproved(true); // simulate passing zkpassport condition

        (bytes32 agreementId, ) = RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(1, globalValues, investorPv),
            1, new address[](0), bytes32(0)
        );
        vm.stopPrank();

        assertTrue(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "agreement must be finalized after FCFS submitEOI with zkPassport"
        );
    }

    /// Both credentials present → EOI succeeds.
    function test_OrCondition_PassesWithBoth() public {
        address[] memory conds = new address[](1);
        conds[0] = address(orCondition);
        (, address rm, bytes32 roundId) = _deployLifecycle(400004, RoundType.FCFS, conds);

        _mintLexChex(investor);

        string[] memory globalValues = _lifecycleGlobalValues();
        string[] memory investorPv   = _lifecyclePartyValues("Test Investor", investor);
        uint256 investAmount = MIN_TICKET;

        payToken.mint(investor, investAmount);
        vm.startPrank(investor);
        payToken.approve(rm, investAmount);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@test.com",
            minAmount: investAmount,
            maxAmount: investAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: _emptyLex()
        });

        zkpassportCondition.setApproved(true); // simulate passing zkpassport condition

        (bytes32 agreementId, ) = RoundManager(rm).submitEOI(
            roundId, eoi,
            globalValues, investorPv,
            _eoiSig(1, globalValues, investorPv),
            1, new address[](0), bytes32(0)
        );
        vm.stopPrank();

        assertTrue(
            CyberAgreementRegistry(REGISTRY).isFinalized(agreementId),
            "agreement must be finalized after FCFS submitEOI with both credentials"
        );
    }
}
