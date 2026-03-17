// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PumpCorpFactory, PumpCorpFactoryLib} from "../src/PumpCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {EIP712Lib} from "../src/libs/EIP712Lib.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Round, RoundType} from "../src/libs/RoundLib.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCertData} from "../src/interfaces/IRoundManager.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";

/// @dev Always-failing condition: any allocation attempt on its escrow is blocked.
contract AlwaysFalseCondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return false;
    }
}

/// @title PumpCorpFactory Escrow Signature Security Tests
/// @notice Focused on whether an attacker who hijacks an escrowed signature can
///         swap in a different officer or alter key corp/round parameters.
///
/// Run with (timeout = 5m):
///   forge test --use solc:0.8.28 --via-ir --fork-url $END_PT_BASE_SEPOLIA -vvv --mp PumpCorpFactory.t.sol
contract PumpCorpFactoryTest is Test {
    using Strings for address;

    // ── Actors ────────────────────────────────────────────────────────────────
    uint256 internal officerPk  = 0xB0B;
    uint256 internal attackerPk = 0xDEAD;

    address internal officer  = vm.addr(officerPk);
    address internal attacker = vm.addr(attackerPk);

    // ── Base Sepolia live deployments (DeploymentConstants.coreV2) ────────────
    address internal metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    DeploymentConstants.CoreDeployment internal net =
        DeploymentConstants.coreV2(DeploymentConstants.BASE_SEPOLIA);

    // Convenience aliases
    address internal REGISTRY                 = net.cyberAgreementRegistry;
    address internal ISSUANCE_MANAGER_FACTORY = net.issuanceManagerFactory;
    address internal CYBERCORP_SINGLE_FACTORY = net.cyberCorpSingleFactory;
    address internal DEAL_MANAGER_FACTORY     = net.dealManagerFactory;
    address internal ROUND_MANAGER_FACTORY    = net.roundManagerFactory;
    address internal URI_BUILDER              = net.uriBuilder;

    // ── Fresh PumpCorpFactory deployed in setUp ───────────────────────────────
    PumpCorpFactory internal pumpFactory;

    // ── Shared round constants ────────────────────────────────────────────────
    uint256 internal constant RAISE_CAP      = 1_000_000e6;
    uint256 internal constant MIN_TICKET     =    10_000e6;
    uint256 internal constant MAX_TICKET     =   100_000e6;
    uint256 internal constant PRICE_PER_UNIT =         1e6;
    uint256 internal constant VALUATION      = 20_000_000e6;

    // Any bytes32 template ID works for createRound (registry not consulted there)
    bytes32 internal constant TEMPLATE_ID = bytes32(uint256(1));

    // ── Shared cert / legal arrays (1 cert → legalDetails & extensionData length 1) ─
    CyberCertData[] internal certDataArr;
    string[]        internal legalDetails;
    bytes[]         internal extensionData;

    /// As of 2026/03/16, we haven't deployed the dependent `RoundManager` with `restrictEndTimeReduction`
    /// to Base Sepolia yet, so we will simulate the upgrade here
    function setUp() public {
        assertEq(block.chainid, DeploymentConstants.BASE_SEPOLIA, "Fork test: Base Sepolia only @ block 38956871");
        vm.rollFork(38956871);
        // Deploy a fresh BorgAuth + PumpCorpFactory pointing at the Sepolia infra,
        // exactly as the deploy script does (minus the broadcast).
        address deployer = address(this);
        BorgAuth auth = new BorgAuth(deployer);

        pumpFactory = PumpCorpFactory(
            address(
                new ERC1967Proxy(
                    address(new PumpCorpFactory()),
                    abi.encodeWithSelector(
                        PumpCorpFactory.initialize.selector,
                        address(auth),
                        REGISTRY,
                        ISSUANCE_MANAGER_FACTORY,
                        CYBERCORP_SINGLE_FACTORY,
                        DEAL_MANAGER_FACTORY,
                        ROUND_MANAGER_FACTORY,
                        URI_BUILDER
                    )
                )
            )
        );

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

        // Upgrade the Sepolia RoundManagerFactory to use the locally compiled RoundManager
        // (which includes the `restrictEndTimeReduction` field) so that createRound calls
        // encode/decode correctly against the new struct layout.
        RoundManagerFactory rmFactory = RoundManagerFactory(ROUND_MANAGER_FACTORY);
        vm.startPrank(metalexSafe);
        rmFactory.setRefImplementation(address(new RoundManager()));
        vm.stopPrank();
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
        rm   = RoundManagerFactory(ROUND_MANAGER_FACTORY)
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

    /// roundPartyValues expected by PumpCorpFactory: [0]=name, [1]=EOA hex string.
    function _partyValues(address eoa, string memory name)
        internal
        pure
        returns (string[] memory pv)
    {
        pv    = new string[](2);
        pv[0] = name;
        pv[1] = eoa.toHexString();
    }

    /// Compute the EIP-712 escrowed signature for `createRound`.
    /// Mirrors CyberCorpHelper.computeEscrowSignature and the deploy script.
    function _escrowSig(
        address rm,
        address corp,
        uint256 signerPk,
        uint256 startTime,
        uint256 endTime
    ) internal view returns (bytes memory sig) {
        bytes32 roundId = keccak256(abi.encodePacked(
            SecuritySeries.SeriesSeed,
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            uint8(RoundType.FCFS),
            startTime, endTime,
            TEMPLATE_ID,
            address(0),       // paymentToken
            PRICE_PER_UNIT,
            VALUATION,
            corp
        ));
        bytes32 domainSep = keccak256(abi.encode(
            EIP712Lib.EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("RoundManager")),
            keccak256(bytes("1")),
            block.chainid,
            rm
        ));
        bytes32 structHash = keccak256(abi.encode(
            EIP712Lib.ESCROWEDSIGNATUREDATA_TYPEHASH,
            roundId,
            uint8(SecuritySeries.SeriesSeed),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            uint8(RoundType.FCFS),
            startTime, endTime,
            TEMPLATE_ID,
            address(0),
            PRICE_PER_UNIT,
            VALUATION,
            corp
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        sig = abi.encodePacked(r, s, v);
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
            _partyValues(officer, "Alice Officer"),
            legalDetails,
            certDataArr,
            new address[](0),
            signerPk
        );
    }

    /// Full happy-path deploy (officer is the signer).
    function _deployHappyPath(uint256 salt)
        internal
        returns (address corp, address rm, bytes32 roundId)
    {
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        (corp, , , , rm, roundId) = pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),        // companyPayable
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"),
            _escrowSig(predRM, predCorp, officerPk, start, end),
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  HAPPY PATH
    // ═══════════════════════════════════════════════════════════════════════════

    function test_HappyPath_DeployCorpAndRound() public {
        (address corp, address rm, bytes32 roundId) = _deployHappyPath(12345);

        assertTrue(corp != address(0), "corp must be deployed");
        assertTrue(RoundManager(rm).roundExists(roundId), "round must exist");

        // The corp and its RoundManager share the same BorgAuth instance
        BorgAuth corpAuth = RoundManager(rm).AUTH();
        assertTrue(
            corpAuth.userRoles(officer) >= corpAuth.OWNER_ROLE(),
            "officer must be owner"
        );
    }

    function test_HappyPath_RoundParamsMatchSigned() public {
        (,address rm, bytes32 roundId) = _deployHappyPath(99999);

        Round memory r = RoundManager(rm).getRound(roundId);
        assertEq(r.raiseCap,      RAISE_CAP,      "raiseCap");
        assertEq(r.minTicket,     MIN_TICKET,      "minTicket");
        assertEq(r.maxTicket,     MAX_TICKET,      "maxTicket");
        assertEq(r.pricePerUnit,  PRICE_PER_UNIT,  "pricePerUnit");
        assertEq(r.valuation,     VALUATION,       "valuation");
        assertEq(r.authorityOfficer, officer,      "authorityOfficer");
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

        bytes memory officerEscrowSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker's officer struct + matching partyValues pointing to attacker
        CompanyOfficer memory fakeOff = _officer(attacker, "Attacker");
        string[] memory fakePv = _partyValues(attacker, fakeOff.name);

        // Attacker provides their own valid supplemental sig — the escrow sig still traps them
        bytes memory attackerMetaSig = _metaSig(salt, attacker, true, true, true, fakeOff, "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, fakePv, legalDetails, certDataArr, new address[](0), attackerPk);

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
                _partyValues(officer, "Alice Officer"),
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

        bytes memory attackerSig = _escrowSig(predRM, predCorp, attackerPk, start, end);

        CompanyOfficer memory claimedOff = _officer(officer, "Alice Officer");
        string[] memory pv = _partyValues(officer, claimedOff.name);

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
        string[] memory pv = _partyValues(officer, claimedOff.name);

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
            _escrowSig(predRM, predCorp, officerPk, start, end),
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"),
            _escrowSig(predRMA, predCorpA, officerPk, start, end), // signed with saltA
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
            _partyValues(officer, "Alice Officer"),
            _escrowSig(predRMB, predCorpB, officerPk, start, end),
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"),
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

        bytes memory officerEscrowedSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker forges a meta sig with their own key, redirecting payment to themselves.
        // The factory checks that the meta sig signer == officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, attacker, true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, certDataArr, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), officerEscrowedSig,
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
            _partyValues(officer, "Alice Officer"), officerEscrowedSig,
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

        bytes memory officerSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        string[] memory altLegal = new string[](1);
        altLegal[0] = "Attacker-substituted legal details";

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), altLegal, certDataArr, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), officerSig,
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
            _partyValues(officer, "Alice Officer"), officerSig,
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
        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, altCert, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, altCert, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Use a different name in the officer struct while keeping the same EOA.
        // roundPartyValues[0] must also match the (fake) name to pass the factory guard.
        CompanyOfficer memory fakeNameOfficer = CompanyOfficer({
            eoa:     officer,
            name:    "Dr. Impostor",   // ← not what officer intended
            contact: "officer@corp.com",
            title:   "CEO"
        });
        string[] memory pv = _partyValues(officer, "Dr. Impostor");

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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        CompanyOfficer memory altTitleOfficer = CompanyOfficer({
            eoa:     officer,
            name:    "Alice Officer",
            contact: "officer@corp.com",
            title:   "Supreme Overlord"
        });

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, true, altTitleOfficer, "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, certDataArr, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker cannot use his own signatures
        bytes memory attackerMetaSig = _metaSig(salt, address(this), false, true, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, certDataArr, new address[](0), attackerPk);
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
            _partyValues(officer, "Alice Officer"), sig,
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
        (, , , , address rm, bytes32 roundId) = pumpFactory.deployCyberCorpAndCreateRoundFor(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, false, true, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, certDataArr, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker forges meta sig with their own key → signer != officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, false, _officer(officer, "Alice Officer"), "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration", extensionData, _partyValues(officer, "Alice Officer"), legalDetails, certDataArr, new address[](0), attackerPk);

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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
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

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

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
            _partyValues(officer, "Alice Officer"),
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
            _partyValues(officer, "Alice Officer"), sig,
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
            _partyValues(officer, "Alice Officer"), sig,
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS,
            conditions,   // ← malicious condition injected
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true, true
        );
    }
}
