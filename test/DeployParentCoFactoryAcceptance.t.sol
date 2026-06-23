// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {DeployParentCoFactoryScript} from "../script/deploy-parentco-factory.s.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract DeployParentCoFactoryAcceptanceForkTest is Test {
    DeploymentConstants.CoreDeployment coreDeployment;
    DeploymentConstants.UmiaDeployment umiaDeployment;
    DeploymentConstants.Deps deps;

    CyberAgreementRegistry registry;

    ParentCoFactory parentCoFactory;
    CompanyOfficer[] parentCoOfficers;

    address parentCorpTestOfficer;
    uint256 parentCorpTestOfficerPrivKey;

    address subCorpPayable;
    address subCorpOfficer;
    uint256 subCorpOfficerPrivKey;

    /// @notice Assumes all contracts are deployed
    function setUp() public {
        vm.createSelectFork("ethereum");
        coreDeployment = DeploymentConstants.coreV2(block.chainid);
        umiaDeployment = DeploymentConstants.umia(block.chainid);
        deps = DeploymentConstants.deps(block.chainid);

        (parentCorpTestOfficer, parentCorpTestOfficerPrivKey) = makeAddrAndKey("parentCorpTestOfficer");

        (subCorpPayable, ) = makeAddrAndKey("subCorpPayable");
        (subCorpOfficer, subCorpOfficerPrivKey) = makeAddrAndKey("subCorpOfficer");

        registry = CyberAgreementRegistry(coreDeployment.cyberAgreementRegistry);

        parentCoFactory = ParentCoFactory(umiaDeployment.parentCoFactory);

//        // Simulate MetaLeX creating the templates
//
//        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);
//        safeTxs[0] = GnosisTransaction({
//            to: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
//            value: 0,
//            data: hex"55f0c0c6d9e0fbb89f8e4e973f05d6b40b6a41e3a9af845b604e9acc7aa4f2a0c37009d800000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000004800000000000000000000000000000000000000000000000000000000000000020554d494120464f554e4445522f4f50455241544f52204c4547414c205041434b0000000000000000000000000000000000000000000000000000000000000042697066733a2f2f626166796265696371676e7a6161347a6d376e6c6b726e757566377864796875676869736e6f756765726a6c696577796e6a746461696f69763565000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000000000000000000000000000000000000b666f756e6465724e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e656e74657270726973654e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b636f6d70616e794e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b636f6d70616e79547970650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013636f6d70616e794a7572697364696374696f6e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015636f6d70616e79436f6e7461637444657461696c730000000000000000000000000000000000000000000000000000000000000000000000000000000000000b746f6b656e53796d626f6c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009746f6b656e4e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000046e616d6500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e636f6e7461637444657461696c73000000000000000000000000000000000000"
//        });
//        safeTxs[1] = GnosisTransaction({
//            to: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
//            value: 0,
//            data: hex"55f0c0c693ac1365e39b1d8237c84cf969b752ffbb717f7d8144eb47562b4060bcd91c3000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004c00000000000000000000000000000000000000000000000000000000000000052414354494f4e20425920554e414e494d4f5553205752495454454e20434f4e53454e54204f462054484520424f415244204f46204449524543544f5253204f4620554d4941204c41554e434845522053504300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042697066733a2f2f6261666b7265696372363571626966347670726e74356c326f767a716a62797777676d6e706c7933737a376e656236717a6a6262326e6a63727734000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000028000000000000000000000000000000000000000000000000000000000000002c0000000000000000000000000000000000000000000000000000000000000000b666f756e6465724e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e656e74657270726973654e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b636f6d70616e794e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b636f6d70616e79547970650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013636f6d70616e794a7572697364696374696f6e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015636f6d70616e79436f6e7461637444657461696c730000000000000000000000000000000000000000000000000000000000000000000000000000000000000b746f6b656e53796d626f6c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009746f6b656e4e616d65000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000046e616d6500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e636f6e7461637444657461696c73000000000000000000000000000000000000"
//        });
//
//        for (uint256 i = 0; i < safeTxs.length; i++) {
//            vm.prank(coreDeployment.metalexSafe);
//            (bool success,) = safeTxs[i].to.call{value: safeTxs[i].value}(safeTxs[i].data);
//            vm.assertTrue(success);
//        }

//        // Simulate adding a test parent corp officer
//        parentCoOfficers.push(CompanyOfficer({
//            eoa: parentCorpTestOfficer,
//            name: "Test ParentCo Officer",
//            contact: "test@parent.com",
//            title: "Director"
//        }));

        for(uint256 i = 0; true ; i++) {
            try parentCoFactory.parentCoOfficers(i) returns (address eoa, string memory name, string memory contact, string memory title) {
                parentCoOfficers.push(CompanyOfficer({
                    eoa: eoa,
                    name: name,
                    contact: contact,
                    title: title
                }));
            } catch {
                break;
            }
        }

//        // Simulate adding the test parent corp officer and have him sign the escrowed signature
//
//        vm.prank(parentCoOfficers[1].eoa);
//        parentCoFactory.setParentCoOfficers(parentCoOfficers);
//
//        bytes memory escrowSig = _createParentCoSignatureHash(
//            parentCorpTestOfficerPrivKey,
//            parentCoOfficers[0].name,
//            parentCoOfficers[0].contact
//        );
//
//        vm.prank(parentCoOfficers[1].eoa);
//        parentCoFactory.setParentCoSignatureHash(escrowSig);
    }

    function test_deploySubCorp() public {
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

        // With officer2 as escrow signer, party[0] = parentCoOfficer2
        address[] memory segCoParties = new address[](2);
        segCoParties[0] = parentCoOfficers[0].eoa;
        segCoParties[1] = subCorpOfficer;
        bytes32 agreementId = keccak256(abi.encode(umiaDeployment.segCoTemplateId, subCorpSalt, globalValues, segCoParties));

        (
            string memory legalContractUri,
            ,
            string[] memory templateGlobalFields,
            string[] memory templatePartyFields
        ) = registry.getTemplateDetails(umiaDeployment.segCoTemplateId);

        bytes memory agreementSig = CyberAgreementUtils.signAgreementTypedData(
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

        (address subCorp,,,,,,,) = parentCoFactory.deployCorpContractFor(
            subCorpSalt,
            subCompanyName,
            subCompanyType,
            subCompanyJurisdiction,
            subCompanyContact,
            subDisputeResolution,
            subCorpPayable,
            subOfficer,
            umiaDeployment.segCoTemplateId,
            umiaDeployment.boardConsentTemplateId,
            globalValues,
            partyValues,
            agreementSig,
            subCorpOfficer
        );

        assertTrue(subCorp != address(0));
        assertTrue(registry.hasSigned(agreementId, parentCoOfficers[0].eoa));
        assertTrue(registry.hasSigned(agreementId, subCorpOfficer));
    }

    function test_realCalldata() public {
        // https://sepolia.basescan.org/tx/0xd479c8e723bd1999945477fdb7fe9345f488c248b3e02731c050e442aba5d827
        vm.createSelectFork("base_sepolia");
        vm.rollFork(40820661); // one block before the real tx

        ParentCoFactory realParentCoFactory = ParentCoFactory(0x478ee34c618E9339Ae2DD8100Df7ec535eb24D29);

        string[] memory globalValues = new string[](8);
        globalValues[0] = "alice";
        globalValues[1] = "TestCorp";
        globalValues[2] = "TestCorp S.P.";
        globalValues[3] = "Segregated Portfolio of Segregated Portfolio Company";
        globalValues[4] = "Cayman Islands";

        string[] memory partyValues = new string[](2);
        partyValues[0] = "alice";
        partyValues[1] = "123";

        (address subCorp,,,,,,,) = realParentCoFactory.deployCorpContractFor({
            salt: 1777409598760,
            companyName: "TestCorp S.P.",
            companyType: "Segregated Portfolio of Segregated Portfolio Company",
            companyJurisdiction: "Cayman Islands",
            companyContactDetails: "",
            defaultDisputeResolution: "",
            _companyPayable: 0x0000000000000000000000000000000000000000,
            _officer: CompanyOfficer({
                eoa: 0xd0c3D2b2D19854036a22aFB386920854A67DFC10,
                name: "alice",
                contact: "123",
                title: "Operator"
            }),
            _segCoTemplateId: 0xb6da5c8e53767592c0eeb4c5c0d77eae7e1e2e795190e7237d837b3fbc98ed75,
            _boardConsentTempateId: 0xc02175e98621a996529fb751b30e0b7a8344ece3b00f46a29c1e904c9da87a46,
            _globalValues: globalValues,
            _partyValues: partyValues,
            signature: hex"cf3cd32652fc7998ac55b7c2f457a39519093d28bd0a42c8773f2755ea0ace7831eeb19883a81d501889402f28924a526212155922498b71ae5a109590705b7d1b",
            deployer: 0xd0c3D2b2D19854036a22aFB386920854A67DFC10
        });

        assertTrue(subCorp != address(0));
    }

    function _createParentCoSignatureHash(uint256 privKey, string memory name, string memory contact) internal returns (bytes memory) {
        bytes32 escrowDigest = parentCoFactory.escrowAuthorizationHash(name, contact);
        (uint8 v, bytes32 r_, bytes32 s) = vm.sign(privKey, escrowDigest);
        return abi.encodePacked(r_, s, v);
    }
}
