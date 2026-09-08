// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {Errors} from "openzeppelin-contracts/utils/Errors.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {PumpCorpFactory, PumpCorpFactoryLib} from "../src/PumpCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {Round} from "../src/libs/RoundLib.sol";
import {CorpFactoryMetadataLib} from "../src/libs/CorpFactoryMetadataLib.sol";

/// @dev Placeholder eligibility gate. Only its address matters here.
contract PassThroughCondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return true;
    }
}

/// @title MTLX1-26 proof of concept
/// @notice PumpCorpFactory protects the deployment metadata with a second officer signature.
///         CyberCorpFactory does not. Both factories use the same sub-factories, and the
///         sub-factories key CREATE2 on the salt only. One salt therefore gives one CyberCorp
///         address and one RoundManager address on either path. The escrowed signature binds
///         those two addresses, so it verifies on the unprotected path too.
///
/// Run with:
///   forge test --use solc:0.8.28 --via-ir --mp test/FactoryRoundAuthReplayPOC.t.sol -vv
contract FactoryRoundAuthReplayPOCTest is Test {
    uint256 internal constant SALT = 909090;

    uint256 internal ownerPk = 0xA11CE;
    uint256 internal officerPk = 0xB0B;
    uint256 internal attackerPk = 0xBAD;

    address internal owner = vm.addr(ownerPk);
    address internal officer = vm.addr(officerPk);
    address internal attacker = vm.addr(attackerPk);
    address internal honestPayable = makeAddr("companyTreasury");

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    PumpCorpFactory internal pumpFactory;
    address internal cyberCorpSingleFactory;
    address internal rmFactory;
    MockERC20 internal paymentToken;
    PassThroughCondition internal eligibilityGate;

    uint8 internal constant PAYMENT_DECIMALS = 9;
    uint256 internal constant TOKEN_SCALE = 10 ** PAYMENT_DECIMALS;

    // Round economics. These are inside the escrowed signature, so the attacker cannot change them.
    uint256 internal constant RAISE_CAP = 1_000_000 * TOKEN_SCALE;
    uint256 internal constant TICKET = 100_000 * TOKEN_SCALE;
    uint256 internal constant PRICE_PER_UNIT = 1 * TOKEN_SCALE;
    uint256 internal constant VALUATION = 20_000_000 * TOKEN_SCALE;

    uint256 internal startTime;
    uint256 internal endTime;

    // Predicted addresses for SALT. Both factories produce these.
    address internal predictedCorp;
    address internal predictedRM;

    bytes internal escrowedSig;

    // Results of the last _deployThroughCyberCorpFactory call. The 29-argument call plus return
    // slots does not fit the stack, so the wrapper writes here instead of returning.
    address internal lastCorp;
    address internal lastRoundManager;
    bytes32 internal lastRoundId;

    // Inputs for the 29-argument deploy call. Held in storage because the call plus wrapper
    // parameters does not fit the EVM stack.
    CyberCertData[] internal argCertData;
    address internal argPayable;
    address[] internal argConditions;
    bytes internal argMetaSig;

    function setUp() public {
        (registry, corpFactory, , , , , , ) = CyberCorpHelper.deployRegistryAndFactories(owner);

        vm.prank(owner);
        CyberCorpHelper.createTemplate(registry);

        BorgAuth auth = corpFactory.AUTH();

        // Read the sub-factories off CyberCorpFactory so both top-level factories are wired
        // identically, the same as production. See script/deploy-pump-factory.s.sol, which reads
        // them from DeploymentConstants.coreV2.
        cyberCorpSingleFactory = corpFactory.cyberCorpSingleFactory();
        rmFactory = corpFactory.roundManagerFactory();
        pumpFactory = PumpCorpFactory(
            address(
                new ERC1967Proxy(
                    address(new PumpCorpFactory()),
                    abi.encodeWithSelector(
                        PumpCorpFactory.initialize.selector,
                        address(auth),
                        address(registry),
                        corpFactory.issuanceManagerFactory(),
                        cyberCorpSingleFactory,
                        corpFactory.dealManagerFactory(),
                        rmFactory,
                        corpFactory.uriBuilder()
                    )
                )
            )
        );

        vm.startPrank(owner);
        pumpFactory.setLexchexAuth(address(auth));
        auth.updateRole(address(pumpFactory), auth.OWNER_ROLE());
        vm.stopPrank();

        paymentToken = new MockERC20("Mock USD", "mUSD", PAYMENT_DECIMALS);
        eligibilityGate = new PassThroughCondition();

        startTime = block.timestamp - 1;
        endTime = block.timestamp + 30 days;

        bytes32 corpSalt = keccak256(abi.encodePacked(SALT));
        predictedCorp = CyberCorpSingleFactory(cyberCorpSingleFactory)
            .computeCyberCorpSingleAddress(corpSalt);
        predictedRM = RoundManagerFactory(rmFactory).computeRoundManagerAddress(corpSalt);

        // The officer signs the escrowed round parameters. The digest binds the RoundManager
        // address as EIP-712 verifyingContract and the CyberCorp address as companyAddress.
        (escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            predictedRM,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            TICKET,
            TICKET,
            RoundType.FCFS,
            startTime,
            endTime,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            officerPk,
            predictedCorp
        );
    }

    // =========================================================================
    // The attack
    // =========================================================================

    /// @notice MTLX1-26 regression. CyberCorpFactory now requires the officer's signature over
    /// the deployment metadata, so the escrowed signature alone is not enough.
    function test_MTLX1_26_EscrowedSignatureAloneIsRejected() public {
        // The relayer holds the officer's escrowed signature and replays it to CyberCorpFactory
        // with substituted metadata. The supplemental signature is missing.
        vm.prank(attacker);
        vm.expectRevert(CyberCorpFactory.InvalidMetadataSignature.selector);
        _deployThroughCyberCorpFactory(_attackerCertData(), attacker, new address[](0), "");
    }

    /// @notice A PumpCorpFactory metadata signature does not verify on CyberCorpFactory, because
    /// the EIP-712 domain name and verifying contract differ.
    function test_MTLX1_26_PumpMetadataSignatureDoesNotCrossFactories() public {
        bytes memory pumpMetaSig = _honestMetadataSignature();

        vm.prank(attacker);
        vm.expectRevert(CyberCorpFactory.InvalidMetadataSignature.selector);
        _deployThroughCyberCorpFactory(_honestCertData(), honestPayable, _honestConditions(), pumpMetaSig);
    }

    /// @notice The attacker cannot keep the officer's own CyberCorpFactory metadata signature and
    /// change the fields it covers.
    function test_MTLX1_26_MetadataSignatureBindsTheSubstitutedFields() public {
        bytes memory officerMetaSig = _cyberCorpMetadataSignature(
            _honestCertData(),
            honestPayable,
            _honestConditions()
        );

        // Swap the payout address only.
        vm.prank(attacker);
        vm.expectRevert(CyberCorpFactory.InvalidMetadataSignature.selector);
        _deployThroughCyberCorpFactory(_honestCertData(), attacker, _honestConditions(), officerMetaSig);

        // Swap the certificate configuration only.
        vm.prank(attacker);
        vm.expectRevert(CyberCorpFactory.InvalidMetadataSignature.selector);
        _deployThroughCyberCorpFactory(_attackerCertData(), honestPayable, _honestConditions(), officerMetaSig);

        // Drop the eligibility gate only.
        vm.prank(attacker);
        vm.expectRevert(CyberCorpFactory.InvalidMetadataSignature.selector);
        _deployThroughCyberCorpFactory(_honestCertData(), honestPayable, new address[](0), officerMetaSig);
    }

    /// @notice The officer's own package still works on CyberCorpFactory, and the metadata lands.
    function test_MTLX1_26_OfficerPackageStillDeploysOnCyberCorpFactory() public {
        bytes memory officerMetaSig = _cyberCorpMetadataSignature(
            _honestCertData(),
            honestPayable,
            _honestConditions()
        );

        _deployThroughCyberCorpFactory(_honestCertData(), honestPayable, _honestConditions(), officerMetaSig);

        assertEq(lastCorp, predictedCorp, "corp address");
        assertEq(lastRoundManager, predictedRM, "round manager address");
        assertEq(CyberCorp(lastCorp).companyPayable(), honestPayable, "honest payout address");

        Round memory round = RoundManager(lastRoundManager).getRound(lastRoundId);
        assertEq(round.roundConditions.length, 1, "eligibility gate is present");
        assertEq(
            uint256(round.primarySecuritySeries),
            uint256(SecuritySeries.SeriesSeed),
            "issued series matches the signed round series"
        );
        assertEq(
            LedgerEntryToken(round.certPrinter[0]).defaultLegend().length,
            1,
            "restrictive legend is present"
        );
    }

    // =========================================================================
    // Same root cause, cheaper attack: no signature needed at all
    // =========================================================================

    function test_POC_AnyoneCanBurnTheSignedDeploymentIdentity() public {
        bytes memory metadataSig = _honestMetadataSignature();

        // NOTE: still open. The metadata signature closes the replay, not the address squat.
        // The sub-factory deploy functions are public with no access control, and CREATE2 keys
        // on the salt only. Any address can take the CyberCorp address for a known salt.
        vm.prank(attacker);
        address squatted = CyberCorpSingleFactory(cyberCorpSingleFactory)
            .deployCyberCorpSingle(keccak256(abi.encodePacked(SALT)));
        assertEq(squatted, predictedCorp, "attacker took the predicted corp address");

        vm.expectRevert(Errors.FailedDeployment.selector);
        _deployHonestThroughPump(metadataSig);
    }

    /// @dev Control: with an untouched salt the same package deploys and keeps the honest metadata.
    function test_HonestPumpPathSucceedsOnAnUntouchedSalt() public {
        bytes memory metadataSig = _honestMetadataSignature();

        (address corp, , , , address roundManager, bytes32 roundId) = _deployHonestThroughPump(metadataSig);

        assertEq(corp, predictedCorp, "corp address");
        assertEq(roundManager, predictedRM, "round manager address");
        assertEq(CyberCorp(corp).companyPayable(), honestPayable, "honest payout address");

        Round memory round = RoundManager(roundManager).getRound(roundId);
        assertEq(round.roundConditions.length, 1, "eligibility gate is present");
        assertEq(round.roundConditions[0], address(eligibilityGate), "eligibility gate address");
        assertEq(
            uint256(round.primarySecuritySeries),
            uint256(SecuritySeries.SeriesSeed),
            "issued series matches the signed round series"
        );
        assertEq(
            LedgerEntryToken(round.certPrinter[0]).defaultLegend().length,
            1,
            "restrictive legend is present"
        );
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _officer() internal view returns (CompanyOfficer memory) {
        return CompanyOfficer({
            eoa: officer,
            name: "Officer A",
            contact: "officer@corp.com",
            title: "CEO"
        });
    }

    function _legalDetails() internal pure returns (string[] memory legalDetails) {
        legalDetails = new string[](1);
        legalDetails[0] = "SEED SAFE legal details";
    }

    function _extensionData() internal pure returns (bytes[] memory extensionData) {
        extensionData = new bytes[](1);
        extensionData[0] = "";
    }

    /// @dev PumpCorpFactory requires party value 0 to equal the officer name and party value 1
    ///      to parse as the officer address.
    function _roundPartyValues() internal view returns (string[] memory roundPartyValues) {
        roundPartyValues = new string[](2);
        roundPartyValues[0] = "Officer A";
        roundPartyValues[1] = Strings.toHexString(officer);
    }

    function _honestConditions() internal view returns (address[] memory conditions) {
        conditions = new address[](1);
        conditions[0] = address(eligibilityGate);
    }

    /// @dev What the officer signed: a restricted SAFE at the signed SeriesSeed.
    function _honestCertData() internal pure returns (CyberCertData[] memory certData) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "RESTRICTED - NOT TRANSFERABLE WITHOUT ISSUER CONSENT";

        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SEED SAFE",
            symbol: "SEEDSAFE",
            uri: "ipfs://seed-safe",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });
    }

    /// @dev What the attacker substitutes: a different class and series, and no legend.
    function _attackerCertData() internal pure returns (CyberCertData[] memory certData) {
        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "UNRESTRICTED PREFERRED",
            symbol: "PREF",
            uri: "ipfs://attacker",
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: new string[](0)
        });
    }

    /// @dev Officer signature over the CyberCorpFactory deployment metadata.
    function _cyberCorpMetadataSignature(
        CyberCertData[] memory certData,
        address companyPayable,
        address[] memory conditions
    ) internal view returns (bytes memory) {
        return CyberCorpHelper.computeMetadataSignature(
     address(corpFactory),
     CorpFactoryMetadataLib.RoundSupplementalData({
         corpSalt: keccak256(abi.encodePacked(SALT)),
         companyPayable: companyPayable,
         publicRound: true,
         allowTimedOffers: true,
         restrictEndTimeReduction: false,
         officer: _officer(),
         companyName: "Signed Company Name",
         companyType: "C-Corp",
         companyJurisdiction: "DE",
         companyContactDetails: "contact@seedcorp.com",
         defaultDisputeResolution: "Arbitration",
         extensionData: _extensionData(),
         roundPartyValues: _roundPartyValues(),
         legalDetails: _legalDetails(),
         certData: certData,
         conditionAddresses: conditions
     }),
     officerPk
 );
    }

    function _deployThroughCyberCorpFactory(
        CyberCertData[] memory certData,
        address companyPayable,
        address[] memory conditions,
        bytes memory metadataSignature
    ) internal {
        delete argCertData;
        for (uint256 i = 0; i < certData.length; i++) {
            argCertData.push(certData[i]);
        }
        argPayable = companyPayable;
        argConditions = conditions;
        argMetaSig = metadataSignature;
        _deployWithStoredArgs();
    }

    function _deployWithStoredArgs() private {
        (lastCorp, , , , lastRoundManager, lastRoundId) = corpFactory.deployCyberCorpAndCreateRound(
            SALT,
            SecuritySeries.SeriesSeed,
            "Signed Company Name",
            "C-Corp",
            "DE",
            "contact@seedcorp.com",
            "Arbitration",
            argPayable,
            _officer(),
            _legalDetails(),
            _extensionData(),
            argCertData,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            _roundPartyValues(),
            escrowedSig,
            argMetaSig,
            RoundType.FCFS,
            argConditions,
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            true,
            false
        );
    }

    function _honestMetadataSignature() internal view returns (bytes memory) {
        bytes32 domainSep = keccak256(
            abi.encode(
                PumpCorpFactoryLib.FACTORY_DOMAIN_TYPEHASH,
                keccak256(bytes("PumpCorpFactory")),
                keccak256(bytes("1")),
                block.chainid,
                address(pumpFactory)
            )
        );
        CompanyOfficer memory off = _officer();
        bytes32 officerHash = keccak256(
            abi.encode(
                PumpCorpFactoryLib.OFFICER_TYPEHASH,
                off.eoa,
                keccak256(bytes(off.name)),
                keccak256(bytes(off.contact)),
                keccak256(bytes(off.title))
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                PumpCorpFactoryLib.ROUND_SUPPLEMENTAL_TYPEHASH,
                keccak256(abi.encodePacked(SALT)),
                honestPayable,
                true,
                true,
                false,
                officerHash,
                keccak256(bytes("Signed Company Name")),
                keccak256(bytes("C-Corp")),
                keccak256(bytes("DE")),
                keccak256(bytes("contact@seedcorp.com")),
                keccak256(bytes("Arbitration")),
                PumpCorpFactoryLib.hashBytesArray(_extensionData()),
                PumpCorpFactoryLib.hashStringArray(_roundPartyValues()),
                PumpCorpFactoryLib.hashStringArray(_legalDetails()),
                PumpCorpFactoryLib.hashCertDataArray(_honestCertData()),
                PumpCorpFactoryLib.hashAddresses(_honestConditions())
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(officerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _deployHonestThroughPump(bytes memory metadataSig)
        internal
        returns (
            address cyberCorpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress,
            bytes32 roundId
        )
    {
        return pumpFactory.deployCyberCorpAndCreateRoundFor(
            SALT,
            SecuritySeries.SeriesSeed,
            "Signed Company Name",
            "C-Corp",
            "DE",
            "contact@seedcorp.com",
            "Arbitration",
            honestPayable,
            _officer(),
            _legalDetails(),
            _extensionData(),
            _honestCertData(),
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            _roundPartyValues(),
            escrowedSig,
            metadataSig,
            RoundType.FCFS,
            _honestConditions(),
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            true,
            false
        );
    }
}
