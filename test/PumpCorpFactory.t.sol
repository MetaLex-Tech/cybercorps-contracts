// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

// Test command:
//   forge test --use solc:0.8.28 --via-ir --fork-url $END_PT_SEPOLIA -vvv --mp PumpCorpFactory.t.sol

import {Test, console} from "forge-std/Test.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
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
///   forge test --use solc:0.8.28 --via-ir --fork-url $END_PT_SEPOLIA -vvv --mp PumpCorpFactory.t.sol
contract PumpCorpFactoryTest is Test {
    using Strings for address;

    // ── EIP-712 constants (mirror EIP712Lib) ─────────────────────────────────
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    // ── EIP-712 constants (mirror PumpCorpFactory supplemental sig) ───────────
    bytes32 constant FACTORY_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ROUND_SUPPLEMENTAL_TYPEHASH = keccak256(
        "RoundSupplementalData(bytes32 corpSalt,address companyPayable,uint8 publicRound,uint8 allowTimedOffers,string officerName,string officerTitle,bytes32 legalDetailsHash,bytes32 certDataHash)"
    );

    // ── Actors ────────────────────────────────────────────────────────────────
    uint256 internal officerPk  = 0xB0B;
    uint256 internal attackerPk = 0xDEAD;

    address internal officer  = vm.addr(officerPk);
    address internal attacker = vm.addr(attackerPk);

    // ── ETH Sepolia live deployments (DeploymentConstants.coreV2) ────────────
    DeploymentConstants.CoreDeployment internal net =
        DeploymentConstants.coreV2(DeploymentConstants.ETH_SEPOLIA);

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

    // ─────────────────────────────────────────────────────────────────────────
    function setUp() public {
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
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("RoundManager")),
            keccak256(bytes("1")),
            block.chainid,
            rm
        ));
        bytes32 structHash = keccak256(abi.encode(
            ESCROWEDSIGNATUREDATA_TYPEHASH,
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
        string memory officerName,
        string memory officerTitle,
        string[] memory legal,
        CyberCertData[] memory certs,
        uint256 signerPk
    ) internal view returns (bytes memory) {
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        bytes32 domainSep = keccak256(abi.encode(
            FACTORY_DOMAIN_TYPEHASH,
            keccak256(bytes("PumpCorpFactory")),
            keccak256(bytes("1")),
            block.chainid,
            address(pumpFactory)
        ));
        bytes32 structHash = keccak256(abi.encode(
            ROUND_SUPPLEMENTAL_TYPEHASH,
            corpSalt,
            companyPayable,
            publicRound ? uint8(1) : uint8(0),
            allowTimedOffers ? uint8(1) : uint8(0),
            keccak256(bytes(officerName)),
            keccak256(bytes(officerTitle)),
            keccak256(abi.encode(legal)),
            keccak256(abi.encode(certs))
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
            "Alice Officer",
            "CEO",
            legalDetails,
            certDataArr,
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

        (corp, , , , rm, roundId) = pumpFactory.deployCyberCorpAndCreateRound(
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
            true, true
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
    /// EOA as officer.  RoundManager recovers the original signer ≠ attacker → revert.
    function test_RevertIf_AttackerSwapsOfficerEOA_WithOfficerSig() public {
        uint256 salt = 11111;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory officerSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker's officer struct + matching partyValues pointing to attacker
        CompanyOfficer memory fakeOff = _officer(attacker, "Attacker");
        string[] memory pv = _partyValues(attacker, fakeOff.name);

        // Attacker provides their own valid supplemental sig — the escrow sig still traps them
        bytes memory attackerMetaSig = _metaSig(salt, attacker, true, true, "Attacker", "CEO", legalDetails, certDataArr, attackerPk);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Attacker Corp", "C-Corp", "DE", "evil@corp.com", "Arbitration",
            attacker,
            fakeOff,
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            pv,
            officerSig,       // ← signed by officer, not attacker
            attackerMetaSig,
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end,
            true, true
        );
    }

    /// Attacker signs the escrow data with their own key but claims the victim
    /// officer's EOA.  RoundManager recovers attacker ≠ claimed officer → revert.
    function test_RevertIf_AttackerSignsForVictimOfficer() public {
        uint256 salt = 22222;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory attackerSig = _escrowSig(predRM, predCorp, attackerPk, start, end);

        CompanyOfficer memory claimedOff = _officer(officer, "Alice Officer");
        string[] memory pv = _partyValues(officer, claimedOff.name);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Fake Corp", "C-Corp", "DE", "fake@corp.com", "Arbitration",
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
            true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  CROSS-CORP REPLAY: signature bound to a specific corp address via CREATE2
    // ═══════════════════════════════════════════════════════════════════════════

    /// Signature for salt A is bound to corpA/rmA.  Replaying it for salt B
    /// (different corp/rm) must fail because the signed companyAddress mismatches.
    function test_RevertIf_SignatureReplayedForDifferentSalt() public {
        uint256 saltA = 77777;
        uint256 saltB = 88888;

        (address predCorpA, address predRMA) = _predict(saltA);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sigA = _escrowSig(predRMA, predCorpA, officerPk, start, end);

        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            saltB,            // different salt → different corp address in RoundManager
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), sigA,
            _metaSigDefault(saltB, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        pumpFactory.deployCyberCorpAndCreateRound(
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
            true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  EIP-712 SIGNATURE MALLEABILITY
    // ═══════════════════════════════════════════════════════════════════════════

    /// OZ ECDSA rejects signatures with s > secp256k1n/2 (high-s malleability).
    /// OZ reverts with ECDSAInvalidSignatureS directly (before the RoundManager
    /// wrapper can emit InvalidEscrowedSignature), so we catch any revert.
    function test_RevertIf_MalleableSignature_FlippedS() public {
        uint256 salt = 22221;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory validSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        bytes32 r;
        bytes32 s;
        uint8   v;
        assembly {
            r := mload(add(validSig, 32))
            s := mload(add(validSig, 64))
            v := byte(0, mload(add(validSig, 96)))
        }

        // s' = secp256k1n - s  (canonical form flip)
        bytes32 secp256k1n =
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 sFlipped;
        assembly { sFlipped := sub(secp256k1n, s) }
        uint8 vFlipped = v == 27 ? 28 : 27;

        // OZ ECDSA throws ECDSAInvalidSignatureS before the RoundManager
        // wrapper can catch it and re-throw InvalidEscrowedSignature.
        vm.expectRevert();
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"),
            abi.encodePacked(r, sFlipped, vFlipped), // malleable sig
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
        );
    }

    /// Zero-length signature is explicitly rejected before EIP-712 recovery.
    function test_RevertIf_EmptySignature() public {
        uint256 salt = 22222;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        // Suppress unused warning
        predCorp; predRM;

        vm.expectRevert(); // InvalidEscrowedSignature (length == 0 guard)
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"),
            "",  // empty sig
            _metaSigDefault(salt, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  CROSS-CONTRACT REPLAY: EIP-712 domain includes verifyingContract
    // ═══════════════════════════════════════════════════════════════════════════

    /// A signature produced for RoundManager A (salt 1) cannot be replayed for
    /// RoundManager B (salt 2) because the EIP-712 domain encodes the contract address.
    function test_RevertIf_CrossContractReplay() public {
        uint256 saltA = 99991;
        uint256 saltB = 99992;

        (address predCorpA, address predRMA) = _predict(saltA);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sigA = _escrowSig(predRMA, predCorpA, officerPk, start, end);

        // Use sigA (for rmA/corpA) in a saltB deployment (rmB/corpB)
        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            saltB,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), sigA,
            _metaSigDefault(saltB, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  PARAMETERS NOT IN ESCROW SIGNATURE (known un-protected fields)
    // ═══════════════════════════════════════════════════════════════════════════

    /// `_companyPayable` is protected by the meta signature.
    /// An attacker who intercepts the officer's escrow signature cannot redirect
    /// the company payment address without the officer's meta signature.
    function test_RevertIf_MetaSigRequired_CompanyPayableProtected() public {
        uint256 salt = 55551;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory officerSig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Attacker forges a meta sig with their own key, redirecting payment to themselves.
        // The factory checks that the meta sig signer == officer.eoa → revert.
        bytes memory attackerMetaSig = _metaSig(salt, attacker, true, true, "Alice Officer", "CEO", legalDetails, certDataArr, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            attacker,             // ← redirected payment address
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), officerSig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, "Alice Officer", "CEO", altLegal, certDataArr, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  MISC GUARDS
    // ═══════════════════════════════════════════════════════════════════════════

    /// salt=0 → corpSalt=keccak256(0)≠bytes32(0) does NOT trigger InvalidSalt?
    /// Actually keccak256(abi.encodePacked(uint256(0))) is non-zero, so this just
    /// deploys.  The InvalidSalt guard in deployCyberCorp requires salt==bytes32(0).
    /// Verify that salt=0 uint input does NOT revert at the salt guard.
    function test_SaltZeroUint_DoesNotRevertAtSaltGuard() public {
        // corpSalt = keccak256(abi.encodePacked(uint256(0))) which is non-zero,
        // so deployCyberCorp salt guard passes.
        (address predCorp, address predRM) = _predict(0);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Should succeed (non-zero corpSalt)
        pumpFactory.deployCyberCorpAndCreateRound(
            0,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData, certDataArr,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), sig,
            _metaSigDefault(0, officerPk),
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, "Alice Officer", "CEO", legalDetails, altCert, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, "Alice Officer", "CEO", legalDetails, altCert, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Test Corp", "C-Corp", "DE", "contact@test.com", "Arbitration",
            address(this),
            _officer(officer, "Alice Officer"),
            legalDetails, extensionData,
            altCert,
            TEMPLATE_ID,
            address(0), PRICE_PER_UNIT, VALUATION,
            _partyValues(officer, "Alice Officer"), sig,
            attackerMetaSig,
            RoundType.FCFS, new address[](0),
            RAISE_CAP, MIN_TICKET, MAX_TICKET,
            start, end, true, true
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  OFFICER METADATA PROTECTED BY META SIGNATURE
    //  officerName and officerTitle are NOT covered by the escrow signature, but
    //  ARE covered by the meta signature.  An attacker without the officer's key
    //  cannot substitute them.
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, "Dr. Impostor", "CEO", legalDetails, certDataArr, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, true, "Alice Officer", "Supreme Overlord", legalDetails, certDataArr, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
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

        // Deploy with publicRound=false even though the officer signed for true
        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        (, , , , address rm, bytes32 roundId) = pumpFactory.deployCyberCorpAndCreateRound(
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
            false,   // ← publicRound flipped; signature was produced without caring about this flag
            true
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
        bytes memory attackerMetaSig = _metaSig(salt, address(this), true, false, "Alice Officer", "CEO", legalDetails, certDataArr, attackerPk);

        vm.expectRevert(PumpCorpFactory.InvalidMetadataSignature.selector);
        pumpFactory.deployCyberCorpAndCreateRound(
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
            false  // ← allowTimedOffers flipped; not covered by escrow signature
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  MALICIOUS CONDITION INJECTION (round-level DoS griefing)
    //  roundConditions are NOT signed.  An attacker who submits the transaction
    //  can inject a condition contract that always returns false, permanently
    //  blocking every allocation in the round.
    // ═══════════════════════════════════════════════════════════════════════════

    /// A condition that always returns false can be injected.
    /// After injection conditionCheck() fails, so no EOI can be allocated.
    // TODO FIXME: should be covered by metaSig as well
    function test_MaliciousConditionCanBeInjected() public {
        uint256 salt = 63001;
        (address predCorp, address predRM) = _predict(salt);
        uint256 start = block.timestamp - 1;
        uint256 end   = block.timestamp + 30 days;

        bytes memory sig = _escrowSig(predRM, predCorp, officerPk, start, end);

        // Deploy the always-false condition and inject it
        address badCondition = address(new AlwaysFalseCondition());
        address[] memory conditions = new address[](1);
        conditions[0] = badCondition;

        (, , , , address rm, bytes32 roundId) = pumpFactory.deployCyberCorpAndCreateRound(
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
            start, end, true, true
        );

        // Round was created successfully with the injected condition
        assertTrue(RoundManager(rm).roundExists(roundId), "round with injected condition was created");

        Round memory r = RoundManager(rm).getRound(roundId);
        assertEq(r.roundConditions.length, 1, "malicious condition stored on round");
        assertEq(r.roundConditions[0], badCondition, "correct condition address stored");
    }
}
