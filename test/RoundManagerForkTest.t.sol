// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RoundManager.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberCertPrinter.sol";
import "../src/storage/RoundManagerStorage.sol";
import "../src/CyberCorpConstants.sol";
import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../dependencies/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC1967} from "../dependencies/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {RoundLib, Round} from "../src/libs/RoundLib.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {LexChexDetails} from "../src/storage/RoundManagerStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {ILexChex} from "../src/interfaces/ILexChex.sol";
import {RoundManagerUpgradeHelper} from "../src/helpers/RoundManagerUpgradeHelper.sol";

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";

using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

contract RoundManagerForkTest is Test {
    address private helper;

    function setUp() public {
        vm.createSelectFork("base_sepolia", 33921622); // must pin to an old block before `exampleCorp` is upgraded
        address me = address(this);
        (,,,,,,,helper) = CyberCorpHelper.deployRegistryAndFactories(me);
    }

    function test_helperUpgrade() public {
        address deployer = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
        vm.startPrank(deployer);
        address cyberCorpSingleFactory = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        ILegacyFactory(cyberCorpSingleFactory).upgradeImplementation(address(new CyberCorp()));
        vm.stopPrank();
        address officer = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
        address exampleCorp = 0xf18393487c6AE9cB75B6AD1715B72d75dEc4F669;
        bytes32 salt = keccak256("test_helperUpgrade");
        vm.startPrank(officer);
        BorgAuth(CyberCorp(exampleCorp).AUTH()).updateRole(helper, BorgAuth(CyberCorp(exampleCorp).AUTH()).OWNER_ROLE());
        RoundManagerUpgradeHelper(helper).upgradeCorp(exampleCorp, salt);
        vm.stopPrank();
    }
}

contract RoundManagerFCFSForkTest is Test {
    using RoundLib for Round;
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

    function setUp() public {
        vm.createSelectFork("base_sepolia");
    }

    function test_RevertIf_FCFS_SubmitEOI_FailLexChexCondition() public {
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp B",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        uint256 officerPrivKey = 0xAA04;
        address officerEOA = vm.addr(officerPrivKey);

        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            true
        );

        uint256 salt = 1;
        uint256 privKey = 0xA11CE;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 20_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        uint256 meUsdcBalanceBefore = usdc.balanceOf(me);

        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 5_000 * (10 ** usdc.decimals()),
            maxAmount: 10_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officerEOA,
            privKey,
            address(rm),
            block.timestamp + 7 days,
            bytes32(0));

        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function test_FCFS_PublicRound_IndividualOver200k_LexChexRequired() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            address rmFactoryAddr,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, , , , address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();

        // Prepare officer identity for the round
        uint256 officerPrivKey = 0xBEEF01;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a public FCFS round with maxTicket above 200k
        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
        );

        // Investor setup: natural person investing > 200k
        uint256 salt = 7;
        uint256 investorPrivKey = 0xC0FFEE;
        address investor = vm.addr(investorPrivKey);
        usdc.transfer(investor, 300_000 * (10 ** usdc.decimals()));

        //white list the mock payment token MockPaymentToken: [0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da]
        RoundManagerFactory(rmFactoryAddr).setWhitelistedToken(address(usdc), true);

        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 200_000 * (10 ** usdc.decimals()),
            maxAmount: 250_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
         // Attach a valid LeXcheX mint payload aligned to template 400 so auto-mint can succeed
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor;

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties, bytes32(0), address(minter), block.timestamp + 30 days));
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
                investorPrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Minimal agreement signature for EOI
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            glValues,
            pv,
            officerEOA,
            investorPrivKey,
            address(rm),
            block.timestamp + 30 days,
            bytes32(0));

        rm.submitEOI(
            roundId,
            eoi,
            glValues,
            pv,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(investor), 1, "LexChex should be minted for the investor");
    }

      function test_FCFS_PublicRound_UnderIndividualOver200k_LexChexRequired() public {
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, , , , address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();

        // Prepare officer identity for the round
        uint256 officerPrivKey = 0xBEEF01;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a public FCFS round with maxTicket above 200k
        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            true
        );

        // Investor setup: natural person investing > 200k
        uint256 salt = 7;
        uint256 investorPrivKey = 0xC0FFEE2;
        address investor = vm.addr(investorPrivKey);
        usdc.transfer(investor, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 10_000 * (10 ** usdc.decimals()),
            maxAmount: 15_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        // Attach a valid LeXcheX mint payload aligned to template 400 to avoid MismatchedFieldsLength if auto-mint is ever triggered
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor;

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties, bytes32(0), address(minter), block.timestamp + 30 days));
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
                investorPrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Prepare a valid LeXcheX MintRequest (templateId = bytes32(uint256(400))) for use if auto-mint is triggered later
        {
            // Resolve LexChexMinter and its registry on the fork
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            // Template and values
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor; // owner signs

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;           // investorName
            lxPartyValues[0][1] = eoi.investorType;   // investorType
            lxPartyValues[0][2] = eoi.jurisdiction;   // investorJurisdiction
            lxPartyValues[0][3] = eoi.contact;        // investorContact

            // Compute agreementId and signature for the LeXcheX agreement
            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties, bytes32(0), address(minter), block.timestamp + 30 days));
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
                investorPrivKey
            );

            // Populate lexchexDetails
            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Minimal agreement signature for EOI
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            glValues,
            pv,
            officerEOA,
            investorPrivKey,
            address(rm),
            block.timestamp + 30 days,
            bytes32(0));

        //make sure lexchex is not valid
        assert(!ILexChex(0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62).hasValidLexCheX(investor));

        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        rm.submitEOI(
            roundId,
            eoi,
            glValues,
            pv,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function test_FCFS_PublicRound_LexChexMinting_Whitelist() public {
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            address rmFactoryAddr,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        MockPaymentToken usdc = new MockPaymentToken();

        // Prepare officer
        uint256 officerPrivKey = 0xBEEF02;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a separate Corp and RoundManager for this test
        (address corpPub, , , , address rmAddrPub) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public Whitelist",
            me,
            me
        );
        RoundManager rmPub = RoundManager(rmAddrPub);

        // Allow RoundManager to transfer certs
        vm.prank(address(corpFactory));
        CyberCorp(corpPub).setDealManager(address(rmPub));

        // Create Public FCFS Round
        bytes32 pubRoundId = CyberCorpHelper.CreateLexChexRound(
            rmPub,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corpPub,
            true // publicRound
        );

        // Investor 1: Non-whitelisted token
        uint256 inv1PrivKey = 0x11111;
        address inv1 = vm.addr(inv1PrivKey);
        usdc.mint(inv1, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv1);
        usdc.approve(address(rmPub), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 200_000 * (10 ** usdc.decimals()),
            maxAmount: 250_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        // LexChex Details setup (boilerplate to pass validation if minting were attempted)
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);
            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";
            address[] memory lxParties = new address[](1);
            lxParties[0] = inv1;
            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties, bytes32(0), address(minter), block.timestamp + 30 days));
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
                inv1PrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: inv1,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // EOI Signature
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            123,
            glValues,
            pv,
            officerEOA,
            inv1PrivKey,
            address(rmPub),
            block.timestamp + 30 days,
            bytes32(0));

        // SUBMIT EOI - Should succeed but NOT mint LexChex because token is not whitelisted
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        rmPub.submitEOI(
            pubRoundId,
            eoi,
            glValues,
            pv,
            sig,
            123,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Check LexChex balance
        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(inv1), 0, "LexChex should not be minted for non-whitelisted token");

        // PART 2: Whitelist Token
        vm.prank(me);
        RoundManagerFactory(rmFactoryAddr).setWhitelistedToken(address(usdc), true);


        // Investor 2: Whitelisted token
        uint256 inv2PrivKey = 0x22222;
        address inv2 = vm.addr(inv2PrivKey);
        usdc.mint(inv2, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv2);
        usdc.approve(address(rmPub), type(uint256).max);

        // Reuse EOI struct but update signer info
        eoi.name = "High Roller 2";

        // Update LexChex details for Investor 2
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp + 1;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);
            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";
            address[] memory lxParties = new address[](1);
            lxParties[0] = inv2;
            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties, bytes32(0), address(minter), block.timestamp + 30 days));
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
                inv2PrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 2,
                    owner: inv2,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Compute EOI Signature for Investor 2
        sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            124,
            glValues,
            pv,
            officerEOA,
            inv2PrivKey,
            address(rmPub),
            block.timestamp + 30 days,
            bytes32(0));

        // SUBMIT EOI - Should succeed AND mint LexChex
        rmPub.submitEOI(
            pubRoundId,
            eoi,
            glValues,
            pv,
            sig,
            124,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(inv2), 1, "LexChex SHOULD be minted for whitelisted token");
    }

    // migrated from BaseSepoliaFactoryFcfsForkTest.t.sol
    function test_CyberCorpFactory_CreatesFcfsRound_AndInvestorFundsIt() public {
        DeploymentConstants.CoreDeployment memory net = DeploymentConstants.coreV2(block.chainid);
        ERC20 stable = ERC20(DeploymentConstants.deps(block.chainid).usdc);

        uint256 RAISE_CAP      = 1_000_000e6;
        uint256 TICKET         =    25_000e6;
        uint256 PRICE_PER_UNIT = 10e18;
        uint256 VALUATION      = 20_000_000e18;

        uint256 FOUNDER_PK  = 0xA11CE;
        uint256 OFFICER_PK  = 0xB0B;
        uint256 INVESTOR_PK = 0xC0DE;

        address founder  = vm.addr(FOUNDER_PK);
        address officer  = vm.addr(OFFICER_PK);
        address investor = vm.addr(INVESTOR_PK);

        CyberAgreementRegistry registry = CyberAgreementRegistry(net.cyberAgreementRegistry);
        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(net.cyberCorpFactory);
        CyberCorpSingleFactory cyberCorpSingleFactory = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory());
        RoundManagerFactory roundManagerFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        bytes32 templateId = bytes32(uint256(5535));
        _createFcfsTemplate(registry, net.metalexSafe, templateId);

        uint256 salt = uint256(keccak256("BaseSepoliaFactoryFcfsForkTest.corp"));
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        address predictedCorp = cyberCorpSingleFactory.computeCyberCorpSingleAddress(corpSalt);
        address predictedRoundManager = roundManagerFactory.computeRoundManagerAddress(corpSalt);

        CompanyOfficer memory companyOfficer = CompanyOfficer({
            eoa: officer,
            name: "Fork Officer",
            contact: "officer@cybercorp.test",
            title: "CEO"
        });

        string[] memory legalDetails = new string[](1);
        legalDetails[0] = "Base Sepolia FCFS SAFE";

        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = "";

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";

        CyberCertData[] memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "SEED SAFE",
            symbol: "SEEDSAFE",
            uri: "ipfs://base-sepolia-fcfs-safe",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = companyOfficer.name;
        roundPartyValues[1] = companyOfficer.title;

        uint256 startTime = block.timestamp - 1;
        uint256 endTime = block.timestamp + 30 days;

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            predictedRoundManager,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            TICKET,
            TICKET,
            RoundType.FCFS,
            startTime,
            endTime,
            templateId,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            OFFICER_PK,
            predictedCorp
        );

        (
            address corp,
            ,
            ,
            ,
            address roundManagerAddr,
            bytes32 roundId
        ) = cyberCorpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Base Sepolia FCFS Corp",
            "Delaware C-Corp",
            "DE",
            "founder@cybercorp.test",
            "Arbitration",
            founder,
            companyOfficer,
            legalDetails,
            extensionData,
            certData,
            templateId,
            address(stable),
            PRICE_PER_UNIT,
            VALUATION,
            roundPartyValues,
            escrowedSig,
            RoundType.FCFS,
            new address[](0),
            RAISE_CAP,
            TICKET,
            TICKET,
            startTime,
            endTime,
            true,
            true,
            false
        );

        assertEq(corp, predictedCorp, "unexpected corp address");
        assertEq(roundManagerAddr, predictedRoundManager, "unexpected round manager address");

        RoundManager roundManager = RoundManager(roundManagerAddr);
        Round memory createdRound = roundManager.getRound(roundId);
        assertEq(createdRound.paymentToken, address(stable), "wrong payment token");
        assertEq(uint256(createdRound.roundType), uint256(RoundType.FCFS), "wrong round type");
        assertEq(createdRound.raiseCap, RAISE_CAP, "wrong raise cap");
        assertEq(createdRound.raised, 0, "new round should start empty");

        deal(address(stable), investor, TICKET * 4);

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Base Sepolia";

        string[] memory eoiPartyValues = new string[](2);
        eoiPartyValues[0] = "Fork Investor";
        eoiPartyValues[1] = "Individual";

        uint256 eoiSalt = 777;
        bytes memory eoiSignature = CyberCorpHelper.computeEOISignature(
            registry,
            templateId,
            eoiSalt,
            globalValues,
            eoiPartyValues,
            companyOfficer.eoa,
            INVESTOR_PK,
            address(roundManager),
            block.timestamp + 7 days,
            bytes32(0));

        EOI memory eoi = EOI({
            name: "Fork Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor@cybercorp.test",
            minAmount: TICKET,
            maxAmount: TICKET,
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        uint256 investorBalanceBefore = stable.balanceOf(investor);

        vm.startPrank(investor);
        stable.approve(roundManagerAddr, TICKET);
        (bytes32 agreementId, ) = roundManager.submitEOI(
            roundId,
            eoi,
            globalValues,
            eoiPartyValues,
            eoiSignature,
            eoiSalt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Round memory fundedRound = roundManager.getRound(roundId);
        Escrow memory escrow = roundManager.getEscrowDetails(agreementId);

        assertEq(fundedRound.raised, TICKET, "fcfs submission should raise funds immediately");
        assertEq(investorBalanceBefore - stable.balanceOf(investor), TICKET, "investor should spend the ticket");
        assertEq(uint256(escrow.status), uint256(EscrowStatus.FINALIZED), "escrow should finalize");
        assertGt(escrow.corpAssets.length, 0, "allocation should mint corp-side assets");
    }

    function _createFcfsTemplate(CyberAgreementRegistry registry, address metalexSafe, bytes32 templateId) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Jurisdiction";

        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";

        vm.prank(metalexSafe);
        registry.createTemplate(
            templateId,
            "Base Sepolia FCFS Template",
            "ipfs://base-sepolia-fcfs-template",
            globalFields,
            partyFields
        );
    }
}
