// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {DeployParentCoFactoryScript} from "../script/deploy-parentco-factory.s.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

contract DeployParentCoFactoryTest is Test {
    DeploymentConstants.CoreDeployment deployment;

    CyberAgreementRegistry registry;

    ParentCoFactory parentCoFactory;
    address parentCoPayable;

    bytes32 segCoTemplateId = keccak256("ParentCo.SegCo.v1");
    bytes32 boardConsentTemplateId = keccak256("ParentCo.BoardConsent.v1");

    address subCorpOfficer;
    uint256 subCorpOfficerPrivKey;

    function setUp() public {
        deployment = DeploymentConstants
            .coreV2(block.chainid);

        registry = CyberAgreementRegistry(deployment.cyberAgreementRegistry);

        (parentCoPayable, ) = makeAddrAndKey("parentCoPayable");
        (subCorpOfficer, subCorpOfficerPrivKey) = makeAddrAndKey("subCorpOfficer");

        GnosisTransaction[] memory safeTxs;
        (parentCoFactory, safeTxs) = (new DeployParentCoFactoryScript()).runWithArgs({
            chainId: block.chainid,
            deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
            saltStr: "ParentCoFactory.deploy.v1",
            paymentToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // Base Sepolia USDC
            segCoTemplateId: segCoTemplateId,
            segCoDocName: "FOUNDER/OPERATOR LEGAL PACK",
            segCoDocUri: "ipfs://parentco-test-segco-template",
            boardConsentTemplateId: boardConsentTemplateId,
            boardConsentName: "ParentCo Board Consent",
            boardConsentUri: "ipfs://parentco-test-board-consent-template",
            parentCoPayable: parentCoPayable,
            parentCoOfficerAddress: parentCoPayable,
            parentCoName: "Test ParentCo LLC",
            parentCoType: "limited liability company",
            parentCoJurisdiction: "Delaware",
            parentCoContactDetails: "test@parentco.example",
            parentCoDefaultDisputeResolution: "binding arbitration",
            parentCoOfficerName: "Test ParentCo Officer",
            parentCoOfficerContact: "test@parentco.example",
            parentCoOfficerTitle: "Director",
            parentEscrowSig: hex"73f62ac9b08c813401a02a16a920a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1a" // TODO simulate escrow sig
        });

        // simulate MetaLeX safe executing safe txs
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(deployment.metalexSafe);
            (bool success,) = safeTxs[i].to.call{value: safeTxs[i].value}(safeTxs[i].data);
            vm.assertTrue(success);
        }
    }

    // TODO WIP: verify results
    function test_deploySubCorp() public {
        // Build SubCorp inputs matching ParentCoFactory's strict field checks.
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        string memory subCompanyName = "Test SubCo SPV 1";
        string memory subCompanyType = "series limited liability company";
        string memory subCompanyJurisdiction = "Delaware";
        string memory subCompanyContact = "subco@parentco.example";
        string memory subDisputeResolution = "binding arbitration";

        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = subCompanyName;
        globalValues[3] = subCompanyType;
        globalValues[4] = subCompanyJurisdiction;
        globalValues[5] = subCompanyContact;
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";

        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: partyValues[0],
            contact: partyValues[1],
            title: "Founder"
        });

        // Pre-compute agreement id and signer signature expected by signContractFor.
        address[] memory agreementParties = new address[](2);
        agreementParties[0] = parentCoPayable;
        agreementParties[1] = subCorpOfficer;
        bytes32 agreementId = keccak256(
            abi.encode(segCoTemplateId, subCorpSalt, globalValues, agreementParties)
        );

        (
            string memory legalContractUri,
            ,
            string[] memory templateGlobalFields,
            string[] memory templatePartyFields
        ) = registry.getTemplateDetails(segCoTemplateId);

        bytes memory subCorpOwnerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            legalContractUri,
            templateGlobalFields,
            templatePartyFields,
            globalValues,
            partyValues,
            subCorpOfficerPrivKey
        );

        (
            address subCorp,
            address subAuth,
            address subIssuance,
            address subDealMgr,
            address subRoundMgr,
            address[] memory subCertPrinters,
            bytes32 subAgreementId,
            uint256[] memory subCertIds
        ) = parentCoFactory.deployCorpContractFor(
            subCorpSalt,
            subCompanyName,
            subCompanyType,
            subCompanyJurisdiction,
            subCompanyContact,
            subDisputeResolution,
            parentCoPayable,
            subOfficer,
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
            subCorpOwnerSignature,
            subCorpOfficer
        );

        console2.log("SubCorp:", subCorp);
        console2.log("SubAuth:", subAuth);
        console2.log("SubIssuance:", subIssuance);
        console2.log("SubDealMgr:", subDealMgr);
        console2.log("SubRoundMgr:", subRoundMgr);
        console2.log("SubAgreementId:");
        console2.logBytes32(subAgreementId);
        console2.log("SubCertPrinters count:", subCertPrinters.length);
        console2.log("SubCertIds count:", subCertIds.length);
        console2.log("");
    }
}
