// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {CorpFactoryMetadataLib} from "../src/libs/CorpFactoryMetadataLib.sol";

/// @title Factory BorgAuth zeroOwner and renounceAuthOwnership Regressions
/// @notice Verifies that none of the four company deployment factories retains OWNER_ROLE
///         on newly deployed company BorgAuth contracts, and that renounceAuthOwnership
///         clears legacy company auths while refusing protected auth contracts.
contract FactoryZeroOwnerTest is Test {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OFFICER_PK = 0xB0B;
    uint256 internal constant OFFICER2_PK = 0xC0C;
    uint256 internal constant ATTACKER_PK = 0xBAD;

    address internal owner = vm.addr(OWNER_PK);
    address internal officer = vm.addr(OFFICER_PK);
    address internal officer2 = vm.addr(OFFICER2_PK);
    address internal attacker = vm.addr(ATTACKER_PK);
    address internal companyPayable = makeAddr("companyTreasury");

    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;
    PumpCorpFactory internal pumpFactory;
    ParentCoFactory internal parentCoFactory;
    MetaDAOFactory internal metaDAOFactory;
    BorgAuth internal factoryAuth;
    BorgAuth internal lexchexAuth;
    MockERC20 internal paymentToken;

    uint256 internal constant RAISE_CAP = 1_000_000e6;
    uint256 internal constant TICKET = 100_000e6;
    uint256 internal constant PRICE_PER_UNIT = 1e6;
    uint256 internal constant VALUATION = 20_000_000e6;

    function setUp() public {
        (registry, corpFactory, , , , , , ) = CyberCorpHelper.deployRegistryAndFactories(owner);
        factoryAuth = corpFactory.AUTH();

        vm.startPrank(owner);
        CyberCorpHelper.createTemplate(registry);

        // Separate lexchexAuth so tests prove factoryAuth and lexchexAuth are independently protected.
        lexchexAuth = new BorgAuth(owner);
        corpFactory.setLexchexAuth(address(lexchexAuth));
        lexchexAuth.updateRole(address(corpFactory), lexchexAuth.OWNER_ROLE());

        paymentToken = new MockERC20("Mock USD", "mUSD", 6);

        pumpFactory = PumpCorpFactory(
            address(
                new ERC1967Proxy(
                    address(new PumpCorpFactory()),
                    abi.encodeWithSelector(
                        PumpCorpFactory.initialize.selector,
                        address(factoryAuth),
                        address(registry),
                        corpFactory.issuanceManagerFactory(),
                        corpFactory.cyberCorpSingleFactory(),
                        corpFactory.dealManagerFactory(),
                        corpFactory.roundManagerFactory(),
                        corpFactory.uriBuilder()
                    )
                )
            )
        );
        pumpFactory.setLexchexAuth(address(lexchexAuth));
        lexchexAuth.updateRole(address(pumpFactory), lexchexAuth.OWNER_ROLE());

        parentCoFactory = ParentCoFactory(
            address(
                new ERC1967Proxy(
                    address(new ParentCoFactory()),
                    abi.encodeWithSelector(
                        ParentCoFactory.initialize.selector,
                        address(factoryAuth),
                        address(registry),
                        corpFactory.issuanceManagerFactory(),
                        corpFactory.cyberCorpSingleFactory(),
                        corpFactory.dealManagerFactory(),
                        corpFactory.roundManagerFactory(),
                        corpFactory.uriBuilder(),
                        address(paymentToken)
                    )
                )
            )
        );

        metaDAOFactory = MetaDAOFactory(
            address(
                new ERC1967Proxy(
                    address(new MetaDAOFactory()),
                    abi.encodeWithSelector(
                        MetaDAOFactory.initialize.selector,
                        address(factoryAuth),
                        address(registry),
                        corpFactory.issuanceManagerFactory(),
                        corpFactory.cyberCorpSingleFactory(),
                        corpFactory.dealManagerFactory(),
                        corpFactory.roundManagerFactory(),
                        corpFactory.uriBuilder(),
                        address(paymentToken)
                    )
                )
            )
        );
        vm.stopPrank();
    }

    function _officer(address eoa, string memory name) internal pure returns (CompanyOfficer memory) {
        return CompanyOfficer({
            eoa: eoa,
            name: name,
            contact: "officer@example.com",
            title: "CEO"
        });
    }

    function _roundFixtures()
        internal
        view
        returns (
            string[] memory legalDetails,
            bytes[] memory extensionData,
            CyberCertData[] memory certData,
            string[] memory roundPartyValues,
            address[] memory conditions
        )
    {
        legalDetails = new string[](1);
        legalDetails[0] = "Standard Seed Terms";
        extensionData = new bytes[](1);
        extensionData[0] = "";

        string[] memory legend = new string[](1);
        legend[0] = "RESTRICTED";

        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            defaultLegend: legend,
            name: "Series Seed",
            symbol: "SEED",
            uri: "ipfs://seed",
            securityClass: SecurityClass.PreferredStock,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            seriesData: ""
        });

        roundPartyValues = new string[](2);
        roundPartyValues[0] = "Founder One";
        roundPartyValues[1] = Strings.toHexString(officer);

        conditions = new address[](0);
    }

    // -------------------------------------------------------------------------
    // CyberCorpFactory
    // -------------------------------------------------------------------------

    function test_CyberCorpFactory_deployCyberCorp_dropsFactoryOwnerRole() public {
        (
            address corp,
            address authAddr,
            address issuanceMgr,
            address dealMgr,
            address roundMgr
        ) = corpFactory.deployCyberCorp(
            keccak256("cybercorp.standalone.v1"),
            "Acme Corp",
            "C-Corp",
            "DE",
            "contact@acme.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One")
        );

        BorgAuth corpAuth = BorgAuth(authAddr);
        assertEq(corpAuth.userRoles(address(corpFactory)), 0, "factory must drop OWNER_ROLE");
        assertEq(corpAuth.userRoles(officer), 200, "officer keeps role 200");
        assertEq(corpAuth.userRoles(corp), 200, "corp keeps role 200");
        assertEq(corpAuth.userRoles(issuanceMgr), 99, "issuanceManager keeps role 99");
        assertEq(corpAuth.userRoles(dealMgr), 99, "dealManager keeps role 99");
        assertEq(corpAuth.userRoles(roundMgr), 99, "roundManager keeps role 99");
        assertEq(lexchexAuth.userRoles(roundMgr), lexchexAuth.OWNER_ROLE(), "roundManager granted lexchexAuth");

        uint256 ownerRole = corpAuth.OWNER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                ownerRole,
                address(corpFactory)
            )
        );
        vm.prank(address(corpFactory));
        corpAuth.updateRole(attacker, 200);
    }

    function test_CyberCorpFactory_deployCyberCorpAndCreateRound_dropsFactoryOwnerRole() public {
        uint256 rawSalt = 424242;
        bytes32 corpSalt = corpFactory.computeDeploymentSalt(
            keccak256(abi.encodePacked(rawSalt)),
            "Round Corp",
            "C-Corp",
            "DE",
            "contact@round.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One")
        );
        address predictedCorp = CyberCorpSingleFactory(corpFactory.cyberCorpSingleFactory())
            .computeCyberCorpSingleAddress(corpSalt, address(corpFactory));
        address predictedRM = RoundManagerFactory(corpFactory.roundManagerFactory())
            .computeRoundManagerAddress(corpSalt, address(corpFactory));

        (
            string[] memory legalDetails,
            bytes[] memory extensionData,
            CyberCertData[] memory certData,
            string[] memory roundPartyValues,
            address[] memory conditions
        ) = _roundFixtures();

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
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
            OFFICER_PK,
            predictedCorp
        );

        bytes32 metaDigest = CorpFactoryMetadataLib.digest(
            "CyberCorpFactory",
            address(corpFactory),
            CorpFactoryMetadataLib.RoundSupplementalData({
                corpSalt: keccak256(abi.encodePacked(rawSalt)),
                companyPayable: companyPayable,
                publicRound: true,
                allowTimedOffers: false,
                restrictEndTimeReduction: false,
                officer: _officer(officer, "Founder One"),
                companyName: "Round Corp",
                companyType: "C-Corp",
                companyJurisdiction: "DE",
                companyContactDetails: "contact@round.example",
                defaultDisputeResolution: "Arbitration",
                extensionData: extensionData,
                roundPartyValues: roundPartyValues,
                legalDetails: legalDetails,
                certData: certData,
                conditionAddresses: conditions
            })
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OFFICER_PK, metaDigest);
        bytes memory metaSig = abi.encodePacked(r, s, v);

        (
            address corp,
            address authAddr,
            ,
            ,
            address roundMgr,
            bytes32 roundId
        ) = corpFactory.deployCyberCorpAndCreateRound(
            rawSalt,
            SecuritySeries.SeriesSeed,
            "Round Corp",
            "C-Corp",
            "DE",
            "contact@round.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One"),
            legalDetails,
            extensionData,
            certData,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            roundPartyValues,
            escrowedSig,
            metaSig,
            RoundType.FCFS,
            conditions,
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            false,
            false
        );

        assertTrue(roundId != bytes32(0), "round created");
        assertEq(corp, predictedCorp, "predicted corp matches");
        assertEq(roundMgr, predictedRM, "predicted roundManager matches");
        assertEq(BorgAuth(authAddr).userRoles(address(corpFactory)), 0, "factory must drop OWNER_ROLE after round launch");
        assertEq(BorgAuth(authAddr).userRoles(officer), 200, "officer keeps role 200");
        assertEq(lexchexAuth.userRoles(roundMgr), lexchexAuth.OWNER_ROLE(), "roundManager authorized on lexchexAuth");
    }

    function test_CyberCorpFactory_renounceAuthOwnership_clearsLegacyAndRefusesProtected() public {
        // Simulate two legacy company BorgAuth contracts deployed before this fix.
        BorgAuth legacyAuth1 = new BorgAuth(address(corpFactory));
        BorgAuth legacyAuth2 = new BorgAuth(address(corpFactory));
        vm.startPrank(address(corpFactory));
        legacyAuth1.updateRole(officer, 200);
        legacyAuth2.updateRole(officer2, 200);
        vm.stopPrank();

        address[] memory batch = new address[](2);
        batch[0] = address(legacyAuth1);
        batch[1] = address(legacyAuth2);

        // Non-owner caller is refused.
        uint256 ownerRole = factoryAuth.OWNER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                ownerRole,
                attacker
            )
        );
        vm.prank(attacker);
        corpFactory.renounceAuthOwnership(batch);

        // Protected auth contracts are refused even for the factory owner.
        address[] memory zeroBatch = new address[](1);
        zeroBatch[0] = address(0);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CyberCorpFactory.CannotRenounceProtectedAuth.selector, address(0)));
        corpFactory.renounceAuthOwnership(zeroBatch);

        address[] memory ownAuthBatch = new address[](1);
        ownAuthBatch[0] = address(factoryAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(CyberCorpFactory.CannotRenounceProtectedAuth.selector, address(factoryAuth))
        );
        corpFactory.renounceAuthOwnership(ownAuthBatch);

        address[] memory lexchexBatch = new address[](1);
        lexchexBatch[0] = address(lexchexAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(CyberCorpFactory.CannotRenounceProtectedAuth.selector, address(lexchexAuth))
        );
        corpFactory.renounceAuthOwnership(lexchexBatch);
        assertEq(lexchexAuth.userRoles(address(corpFactory)), lexchexAuth.OWNER_ROLE(), "lexchexAuth preserved");

        // Owner clears both legacy company auths in one batch.
        vm.prank(owner);
        corpFactory.renounceAuthOwnership(batch);

        assertEq(legacyAuth1.userRoles(address(corpFactory)), 0, "legacyAuth1 cleared");
        assertEq(legacyAuth2.userRoles(address(corpFactory)), 0, "legacyAuth2 cleared");
        assertEq(legacyAuth1.userRoles(officer), 200, "legacyAuth1 officer preserved");
        assertEq(legacyAuth2.userRoles(officer2), 200, "legacyAuth2 officer preserved");

        // Re-running the same batch is idempotent.
        vm.prank(owner);
        corpFactory.renounceAuthOwnership(batch);
    }

    // -------------------------------------------------------------------------
    // PumpCorpFactory
    // -------------------------------------------------------------------------

    function test_PumpCorpFactory_deployCyberCorp_dropsFactoryOwnerRole() public {
        (
            address corp,
            address authAddr,
            address issuanceMgr,
            address dealMgr,
            address roundMgr
        ) = pumpFactory.deployCyberCorp(
            keccak256("pump.standalone.v1"),
            "Pump Corp",
            "C-Corp",
            "DE",
            "contact@pump.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One")
        );

        BorgAuth corpAuth = BorgAuth(authAddr);
        assertEq(corpAuth.userRoles(address(pumpFactory)), 0, "pumpFactory must drop OWNER_ROLE");
        assertEq(corpAuth.userRoles(officer), 200);
        assertEq(corpAuth.userRoles(corp), 200);
        assertEq(corpAuth.userRoles(issuanceMgr), 99);
        assertEq(corpAuth.userRoles(dealMgr), 99);
        assertEq(corpAuth.userRoles(roundMgr), 99);
    }

    function test_PumpCorpFactory_deployCyberCorpAndCreateRoundFor_dropsFactoryOwnerRole() public {
        uint256 rawSalt = 515151;
        bytes32 corpSalt = pumpFactory.computeDeploymentSalt(
            keccak256(abi.encodePacked(rawSalt)),
            "Pump Round Corp",
            "C-Corp",
            "DE",
            "contact@pumpround.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One")
        );
        address predictedCorp = CyberCorpSingleFactory(pumpFactory.cyberCorpSingleFactory())
            .computeCyberCorpSingleAddress(corpSalt, address(pumpFactory));
        address predictedRM = RoundManagerFactory(pumpFactory.roundManagerFactory())
            .computeRoundManagerAddress(corpSalt, address(pumpFactory));

        (
            string[] memory legalDetails,
            bytes[] memory extensionData,
            CyberCertData[] memory certData,
            string[] memory roundPartyValues,
            address[] memory conditions
        ) = _roundFixtures();

        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
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
            OFFICER_PK,
            predictedCorp
        );

        bytes32 metaDigest = CorpFactoryMetadataLib.digest(
            "PumpCorpFactory",
            address(pumpFactory),
            CorpFactoryMetadataLib.RoundSupplementalData({
                corpSalt: keccak256(abi.encodePacked(rawSalt)),
                companyPayable: companyPayable,
                publicRound: true,
                allowTimedOffers: false,
                restrictEndTimeReduction: false,
                officer: _officer(officer, "Founder One"),
                companyName: "Pump Round Corp",
                companyType: "C-Corp",
                companyJurisdiction: "DE",
                companyContactDetails: "contact@pumpround.example",
                defaultDisputeResolution: "Arbitration",
                extensionData: extensionData,
                roundPartyValues: roundPartyValues,
                legalDetails: legalDetails,
                certData: certData,
                conditionAddresses: conditions
            })
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OFFICER_PK, metaDigest);
        bytes memory metaSig = abi.encodePacked(r, s, v);

        (
            address corp,
            address authAddr,
            ,
            ,
            address roundMgr,
            bytes32 roundId
        ) = pumpFactory.deployCyberCorpAndCreateRoundFor(
            rawSalt,
            SecuritySeries.SeriesSeed,
            "Pump Round Corp",
            "C-Corp",
            "DE",
            "contact@pumpround.example",
            "Arbitration",
            companyPayable,
            _officer(officer, "Founder One"),
            legalDetails,
            extensionData,
            certData,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            roundPartyValues,
            escrowedSig,
            metaSig,
            RoundType.FCFS,
            conditions,
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            false,
            false
        );

        assertTrue(roundId != bytes32(0));
        assertEq(corp, predictedCorp);
        assertEq(roundMgr, predictedRM);
        assertEq(BorgAuth(authAddr).userRoles(address(pumpFactory)), 0, "pumpFactory must drop OWNER_ROLE after round launch");
        assertEq(BorgAuth(authAddr).userRoles(officer), 200);
    }

    function test_PumpCorpFactory_renounceAuthOwnership_clearsLegacyAndRefusesProtected() public {
        BorgAuth legacyAuth = new BorgAuth(address(pumpFactory));
        vm.prank(address(pumpFactory));
        legacyAuth.updateRole(officer, 200);

        address[] memory batch = new address[](1);
        batch[0] = address(legacyAuth);

        uint256 ownerRole = factoryAuth.OWNER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                ownerRole,
                attacker
            )
        );
        vm.prank(attacker);
        pumpFactory.renounceAuthOwnership(batch);

        address[] memory protectedBatch = new address[](1);
        protectedBatch[0] = address(lexchexAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PumpCorpFactory.CannotRenounceProtectedAuth.selector, address(lexchexAuth))
        );
        pumpFactory.renounceAuthOwnership(protectedBatch);

        protectedBatch[0] = address(factoryAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PumpCorpFactory.CannotRenounceProtectedAuth.selector, address(factoryAuth))
        );
        pumpFactory.renounceAuthOwnership(protectedBatch);

        vm.prank(owner);
        pumpFactory.renounceAuthOwnership(batch);
        assertEq(legacyAuth.userRoles(address(pumpFactory)), 0);
        assertEq(legacyAuth.userRoles(officer), 200);

        // Idempotent retry
        vm.prank(owner);
        pumpFactory.renounceAuthOwnership(batch);
    }

    // -------------------------------------------------------------------------
    // ParentCoFactory
    // -------------------------------------------------------------------------

    function test_ParentCoFactory_deployCorp_and_createParentCorp_dropFactoryOwnerRole() public {
        // Standalone deployCorp
        (
            address standaloneCorp,
            address standaloneAuth,
            address standaloneIssuance,
            address standaloneDealMgr,
            address standaloneRoundMgr
        ) = parentCoFactory.deployCorp(
            keccak256("parentco.standalone.v1"),
            "SubCo Standalone",
            "Series LLC",
            "DE",
            "sub@example.com",
            "Arbitration",
            companyPayable,
            _officer(officer, "Sub Officer")
        );

        assertEq(BorgAuth(standaloneAuth).userRoles(address(parentCoFactory)), 0, "standalone deployCorp must drop role");
        assertEq(BorgAuth(standaloneAuth).userRoles(officer), 200);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneCorp), 200);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneIssuance), 99);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneDealMgr), 99);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneRoundMgr), 99);

        // createParentCorp with 2 officers: must add officer2 BEFORE calling zeroOwner()
        CompanyOfficer[] memory parentOfficers = new CompanyOfficer[](2);
        parentOfficers[0] = _officer(officer, "Parent Officer 1");
        parentOfficers[1] = _officer(officer2, "Parent Officer 2");

        vm.startPrank(owner);
        parentCoFactory.setParentCoOfficers(parentOfficers);
        (
            address parentCorp,
            address parentAuth,
            ,
            ,
        ) = parentCoFactory.createParentCorp(
            keccak256("parentco.parent.v1"),
            "ParentCo LLC",
            "LLC",
            "DE",
            "parent@example.com",
            "Arbitration",
            companyPayable
        );
        vm.stopPrank();

        assertEq(BorgAuth(parentAuth).userRoles(address(parentCoFactory)), 0, "createParentCorp must drop role");
        assertEq(BorgAuth(parentAuth).userRoles(officer), 200, "parent officer 1 keeps role 200");
        assertEq(BorgAuth(parentAuth).userRoles(officer2), 200, "parent officer 2 added with role 200");
        assertEq(BorgAuth(parentAuth).userRoles(parentCorp), 200, "parent corp keeps role 200");
    }

    function test_ParentCoFactory_renounceAuthOwnership_clearsLegacyAndRefusesProtected() public {
        BorgAuth legacyAuth = new BorgAuth(address(parentCoFactory));
        vm.prank(address(parentCoFactory));
        legacyAuth.updateRole(officer, 200);

        address[] memory batch = new address[](1);
        batch[0] = address(legacyAuth);

        uint256 ownerRole = factoryAuth.OWNER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                ownerRole,
                attacker
            )
        );
        vm.prank(attacker);
        parentCoFactory.renounceAuthOwnership(batch);

        address[] memory protectedBatch = new address[](1);
        protectedBatch[0] = address(factoryAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ParentCoFactory.CannotRenounceProtectedAuth.selector, address(factoryAuth))
        );
        parentCoFactory.renounceAuthOwnership(protectedBatch);

        protectedBatch[0] = address(0);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ParentCoFactory.CannotRenounceProtectedAuth.selector, address(0))
        );
        parentCoFactory.renounceAuthOwnership(protectedBatch);

        vm.prank(owner);
        parentCoFactory.renounceAuthOwnership(batch);
        assertEq(legacyAuth.userRoles(address(parentCoFactory)), 0);
        assertEq(legacyAuth.userRoles(officer), 200);

        vm.prank(owner);
        parentCoFactory.renounceAuthOwnership(batch);
    }

    // -------------------------------------------------------------------------
    // MetaDAOFactory
    // -------------------------------------------------------------------------

    function test_MetaDAOFactory_deployMetaCorp_and_createParentCorp_dropFactoryOwnerRole() public {
        (
            address standaloneCorp,
            address standaloneAuth,
            address standaloneIssuance,
            address standaloneDealMgr,
        ) = metaDAOFactory.deployMetaCorp(
            keccak256("metadao.standalone.v1"),
            "MetaSub Corp",
            "LLC",
            "DE",
            "metasub@example.com",
            "Arbitration",
            companyPayable,
            _officer(officer, "Meta Officer")
        );

        assertEq(BorgAuth(standaloneAuth).userRoles(address(metaDAOFactory)), 0, "deployMetaCorp must drop role");
        assertEq(BorgAuth(standaloneAuth).userRoles(officer), 200);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneCorp), 200);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneIssuance), 99);
        assertEq(BorgAuth(standaloneAuth).userRoles(standaloneDealMgr), 99);

        vm.startPrank(owner);
        metaDAOFactory.setMetaDAOOfficer(_officer(officer, "MetaDAO Parent Officer"));
        (
            address parentCorp,
            address parentAuth,
            ,
            ,
        ) = metaDAOFactory.createParentCorp(
            keccak256("metadao.parent.v1"),
            "MetaDAO Parent LLC",
            "LLC",
            "DE",
            "metaparent@example.com",
            "Arbitration",
            companyPayable
        );
        vm.stopPrank();

        assertEq(BorgAuth(parentAuth).userRoles(address(metaDAOFactory)), 0, "createParentCorp must drop role");
        assertEq(BorgAuth(parentAuth).userRoles(officer), 200);
        assertEq(BorgAuth(parentAuth).userRoles(parentCorp), 200);
    }

    function test_MetaDAOFactory_renounceAuthOwnership_clearsLegacyAndRefusesProtected() public {
        BorgAuth legacyAuth = new BorgAuth(address(metaDAOFactory));
        vm.prank(address(metaDAOFactory));
        legacyAuth.updateRole(officer, 200);

        address[] memory batch = new address[](1);
        batch[0] = address(legacyAuth);

        uint256 ownerRole = factoryAuth.OWNER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                BorgAuth.BorgAuth_NotAuthorized.selector,
                ownerRole,
                attacker
            )
        );
        vm.prank(attacker);
        metaDAOFactory.renounceAuthOwnership(batch);

        address[] memory protectedBatch = new address[](1);
        protectedBatch[0] = address(factoryAuth);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MetaDAOFactory.CannotRenounceProtectedAuth.selector, address(factoryAuth))
        );
        metaDAOFactory.renounceAuthOwnership(protectedBatch);

        protectedBatch[0] = address(0);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(MetaDAOFactory.CannotRenounceProtectedAuth.selector, address(0))
        );
        metaDAOFactory.renounceAuthOwnership(protectedBatch);

        vm.prank(owner);
        metaDAOFactory.renounceAuthOwnership(batch);
        assertEq(legacyAuth.userRoles(address(metaDAOFactory)), 0);
        assertEq(legacyAuth.userRoles(officer), 200);

        vm.prank(owner);
        metaDAOFactory.renounceAuthOwnership(batch);
    }
}
