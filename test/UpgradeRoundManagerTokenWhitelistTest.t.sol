// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {UpgradeRoundManagerTokenWhitelistScript} from "../script/upgrade-round-manager-token-whitelist.s.sol";
import {KnownAddressesLoader} from "../script/libs/KnownAddressesLoader.sol";
import {SecuritySeries, SecurityClass} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheXMinter, LeXcheX} from "../src/creds/lexchexMinter.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {RoundLib, Round, RoundType} from "../src/libs/RoundLib.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

/// @notice This is for testing upgrading base-sepolia, which has been upgraded to a dev version of v3 before, to the current version of v3
contract UpgradeRoundManagerTokenWhitelistTest is Test {
    using RoundLib for Round;
    using ERC1967ProxyLib for address;
    
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Known addresses
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    BorgAuth deployedLexChexAddrAuth = BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2);
    address lexchexConditionAddress = 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42;
    LeXcheXMinter leXcheXMinter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
    ERC20 stable = ERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e); // Base Sepolia

    RoundManagerFactory rmFactory;

    address paymentToken = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC @ Base Sepolia

    uint256 legacyAddressesCount = 3; // Limit the number of legacy addresses we migrate during tests so it won't stress the RPC endpoints too much

    address[] knownLegacyCorps;

    address deployer;
    uint256 deployerPrivateKey;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        // Lock in specific chain ID and fork block (after previous dev public-round migration and after LexCheX Minter is setup)
        assertEq(block.chainid, 84532, "This test is meant for only Base Sepolia @ 34732511");
        vm.rollFork(34732511);

        rmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        // Load a limit number of known legacy cyber corps for tests
        knownLegacyCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", legacyAddressesCount);

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        registry.AUTH().updateRole(deployer, registry.AUTH().OWNER_ROLE());
        vm.stopPrank();

        // Run scripts to upgrade RoundManager and its factory
        (new UpgradeRoundManagerTokenWhitelistScript()).runWithArgs(deployerPrivateKey);

        // Sanity check
        assertTrue(rmFactory.isWhitelistedToken(address(stable)), "stable should have been whitelisted");

        // Run scripts to accept the new RoundManager for the legacy corps (assuming they have all been migrated by now)
        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(corp.roundManager());
            assertNotEq(
                address(rm),
                address(0),
                string(abi.encodePacked("legacy CyberCorp: ", vm.toString(address(corp)), " should have RoundManager by now"))
            );

            address refRmImpl = rmFactory.getRefImplementation();
            if (address(rm).getErc1967Implementation() != refRmImpl) {
                vm.prank(address(corp));
                rm.upgradeToAndCall(refRmImpl, "");
                console2.log("CyberCorp: %s, RoundManager: %s accepted upgrade to implementation: %s", address(corp), address(rm), refRmImpl);
            }

            // Simulate admin to retro-authorize legacy corp's RoundManager to LexCheX minter
            vm.startPrank(metalexSafe); // In practice, SAFE can temporarily grant the deployer owner-role to do the followings
            deployedLexChexAddrAuth.updateRole(
                address(rm),
                deployedLexChexAddrAuth.OWNER_ROLE()
            );
            console2.log("CyberCorp: %s, RoundManager: %s is assigned owner role for LexCheX Minter", address(corp), address(rm));
            vm.stopPrank();
        }
    }

    function test_SanityCheck() public {
        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(corp.roundManager());
            // RoundManager should be at current implementation
            assertEq(address(rm).getErc1967Implementation(), rmFactory.getRefImplementation(), string(abi.encodePacked("CyberCorp: ", vm.toString(address(corp)), " should have up-to-date implementation for its roundManager")));
        }
    }

    /// @notice Now that legacy corps have the most current RoundManager, it should be able to create a LeXCheX round
    function test_CreateLexchexRound() public {
        // Create template for tests

        bytes32 templateId = keccak256("test_CreateLexchexRound");
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        vm.prank(metalexSafe);
        registry.createTemplate(
            templateId,
            "Test",
            "ipfs://template",
            globalFields,
            partyFields
        );

        // Test data for agreement

        SecuritySeries series = SecuritySeries.SeriesSeed;
        RoundType roundType = RoundType.FCFS;
        uint256 raiseCap = 1_000_000 * (10 ** stable.decimals());
        uint256 minTicket = 2_000 * (10 ** stable.decimals());
        uint256 maxTicket = 300_000 * (10 ** stable.decimals());
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;
        uint256 pricePerUnit = 10 * (10 ** stable.decimals());
        uint256 valuation = 10_000_000;

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

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
            defaultLegend: defaultLegend
        });

        address[] memory conditions = new address[](1);
        conditions[0] = lexchexConditionAddress;

        // Test each known corp

        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(corp.roundManager());

            // Create round

            (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
                address(rm),
                series,
                raiseCap,
                minTicket,
                maxTicket,
                roundType,
                startTime,
                endTime,
                templateId,
                paymentToken,
                pricePerUnit,
                valuation,
                alicePrivateKey,
                address(corp)
            );

            vm.startPrank(address(corp));
            bytes32 roundId = rm.createRound(
                RoundLib.draft()
                .setTickets(
                    series,
                    roundType,
                    true, // publicRound
                    true, // allowTimedOffers
                    false, // restrictEndTimeReduction
                    raiseCap,
                    minTicket,
                    maxTicket,
                    address(stable),
                    pricePerUnit,
                    valuation,
                    startTime,
                    endTime
                )
                .setAgreement(
                    templateId,
                    alice,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    roundPartyValues,
                    new bytes[](certData.length),
                    conditions,
                    escrowedSig
                ),
                certData
            );
            vm.stopPrank();

            // Submit EOI

            uint256 salt = uint256(keccak256("test_CreateLexchexRound.EOI")) + i;

            EOI memory eoi = EOI({
                name: "High Roller",
                investorType: "Individual",
                jurisdiction: "US",
                contact: "email",
                minAmount: 200_000 * (10 ** stable.decimals()),
                maxAmount: 250_000 * (10 ** stable.decimals()),
                expiry: block.timestamp + 7 days,
                naturalPerson: true,
                lexchexDetails: CyberCorpHelper.emptyLex()
            });

            // Attach a valid LeXcheX mint payload aligned to template 400 so auto-mint can succeed
            {
                CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(leXcheXMinter.dealRegistry());

                bytes32 lxTemplateId = bytes32(uint256(400));
                uint256 lxSalt = block.timestamp;
                (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

                string[] memory lxGlobalValues = new string[](1);
                lxGlobalValues[0] = "2029-01-01";

                address[] memory lxParties = new address[](1);
                lxParties[0] = bob;

                string[][] memory lxPartyValues = new string[][](1);
                lxPartyValues[0] = new string[](4);
                lxPartyValues[0][0] = eoi.name;
                lxPartyValues[0][1] = eoi.investorType;
                lxPartyValues[0][2] = eoi.jurisdiction;
                lxPartyValues[0][3] = eoi.contact;

                bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
                bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                    vm,
                    lxRegistry.DOMAIN_SEPARATOR(),
                    lxRegistry.SIGNATUREDATA_TYPEHASH(),
                    lxContractId,
                    legalUri,
                    lxGlFields,
                    lxPartyFields,
                    lxGlobalValues,
                    lxPartyValues[0],
                    bobPrivateKey
                );

                eoi.lexchexDetails = LexChexDetails({
                    request: MintRequest({
                        uuid: 1,
                        owner: bob,
                        investorName: eoi.name,
                        investorType: eoi.investorType,
                        investorJurisdiction: eoi.jurisdiction,
                        investorContact: eoi.contact,
                        mintPrice: 0,
                        expiry: block.timestamp + 30 days,
                        paymentToken: address(stable)
                    }),
                    templateId: lxTemplateId,
                    salt: uint256(lxSalt),
                    globalValues: lxGlobalValues,
                    parties: lxParties,
                    partyValues: lxPartyValues,
                    agreementSignature: lxSig
                });
            }

            string[] memory globalValues = new string[](1);
            globalValues[0] = "g";
            string[] memory partyValues = new string[](2);
            partyValues[0] = "Officer";
            partyValues[1] = "CEO";

            deal(address(stable), bob, 300_000 * (10 ** stable.decimals()));

            vm.startPrank(bob);
            stable.approve(address(rm), 300_000 * (10 ** stable.decimals()));
            rm.submitEOI(
                roundId,
                eoi,
                globalValues,
                partyValues,
                CyberCorpHelper.computeEOISignature(
                    registry,
                    templateId,
                    salt,
                    globalValues,
                    partyValues,
                    alice,
                    bobPrivateKey
                ),
                salt,
                new address[](0),
                bytes32(0)
            );
            vm.stopPrank();

            assertEq(LeXcheX(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(bob), 1, "LexChex should be minted for bob");
        }
    }
}
