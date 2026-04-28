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

contract DeployParentCoFactoryAcceptanceTest is Test {
    DeploymentConstants.CoreDeployment coreDeployment;
    DeploymentConstants.UmiaDeployment umiaDeployment;
    DeploymentConstants.Deps deps;

    CyberAgreementRegistry registry;

    ParentCoFactory parentCoFactory;
    CompanyOfficer[] parentCoOfficers;

    address subCorpPayable;
    address subCorpOfficer;
    uint256 subCorpOfficerPrivKey;

    /// @notice Assumes all contracts are deployed and escrow signature has been submitted
    function setUp() public {
        coreDeployment = DeploymentConstants.coreV2(block.chainid);
        umiaDeployment = DeploymentConstants.umia(block.chainid);
        deps = DeploymentConstants.deps(block.chainid);

        (subCorpPayable, ) = makeAddrAndKey("subCorpPayable");
        (subCorpOfficer, subCorpOfficerPrivKey) = makeAddrAndKey("subCorpOfficer");

        registry = CyberAgreementRegistry(coreDeployment.cyberAgreementRegistry);

        parentCoFactory = ParentCoFactory(umiaDeployment.parentCoFactory);

        for(uint256 i = 0; true ; i++) {
            try  parentCoFactory.parentCoOfficers(i) returns (address eoa, string memory name, string memory contact, string memory title) {
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
        // Skip test if not on Base Sepolia
        if(block.chainid != DeploymentConstants.BASE_SEPOLIA) {
            console2.log("skipping unsupported chain ID: %d ...", block.chainid);
            return;
        }

        // https://sepolia.basescan.org/tx/0xd479c8e723bd1999945477fdb7fe9345f488c248b3e02731c050e442aba5d827
        vm.rollFork(40820661); // one block before the real tx

        string[] memory globalValues = new string[](8);
        globalValues[0] = "alice";
        globalValues[1] = "TestCorp";
        globalValues[2] = "TestCorp S.P.";
        globalValues[3] = "Segregated Portfolio of Segregated Portfolio Company";
        globalValues[4] = "Cayman Islands";

        string[] memory partyValues = new string[](2);
        partyValues[0] = "alice";
        partyValues[1] = "123";

        (address subCorp,,,,,,,) = parentCoFactory.deployCorpContractFor({
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
