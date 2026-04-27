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

contract DeployParentCoFactoryTest is Test {
    DeploymentConstants.CoreDeployment coreDeployment;
    DeploymentConstants.Deps deps;

    CyberAgreementRegistry registry;

    ParentCoFactory parentCoFactory;
    address parentCoMultisig;
    address parentCoOfficer1;
    uint256 parentCoOfficer1PrivKey;
    address parentCoOfficer2;
    uint256 parentCoOfficer2PrivKey;

    bytes32 segCoTemplateId = keccak256("ParentCo.SegCo.v1");
    bytes32 boardConsentTemplateId = keccak256("ParentCo.BoardConsent.v1");

    address subCorpPayable;
    address subCorpOfficer;
    uint256 subCorpOfficerPrivKey;

    function setUp() public {
        coreDeployment = DeploymentConstants.coreV2(block.chainid);
        deps = DeploymentConstants.deps(block.chainid);

        registry = CyberAgreementRegistry(coreDeployment.cyberAgreementRegistry);

        (parentCoMultisig, ) = makeAddrAndKey("parentCoMultisig");
        (parentCoOfficer1, parentCoOfficer1PrivKey) = makeAddrAndKey("parentCoOfficer1");
        (parentCoOfficer2, parentCoOfficer2PrivKey) = makeAddrAndKey("parentCoOfficer2");
        (subCorpPayable, ) = makeAddrAndKey("subCorpPayable");
        (subCorpOfficer, subCorpOfficerPrivKey) = makeAddrAndKey("subCorpOfficer");

        CompanyOfficer[] memory parentCoOfficers = new CompanyOfficer[](2);
        parentCoOfficers[0] = CompanyOfficer({
            eoa: parentCoOfficer1,
            name: "Test ParentCo Officer 1",
            contact: "test1@parentco.example",
            title: "Director"
        });
        parentCoOfficers[1] = CompanyOfficer({
            eoa: parentCoOfficer2,
            name: "Test ParentCo Officer 2",
            contact: "test2@parentco.example",
            title: "Director"
        });

        GnosisTransaction[] memory safeTxs;
        (parentCoFactory, safeTxs) = (new DeployParentCoFactoryScript()).runWithArgs({
            chainId: block.chainid,
            deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
            saltStr: "ParentCoFactory.deploy.v1",
            segCoTemplateId: segCoTemplateId,
            segCoDocName: "FOUNDER/OPERATOR LEGAL PACK",
            segCoDocUri: "ipfs://parentco-test-segco-template",
            boardConsentTemplateId: boardConsentTemplateId,
            boardConsentName: "ParentCo Board Consent",
            boardConsentUri: "ipfs://parentco-test-board-consent-template",
            parentCoPayable: parentCoMultisig,
            parentCoName: "Test ParentCo LLC",
            parentCoType: "limited liability company",
            parentCoJurisdiction: "Delaware",
            parentCoContactDetails: "test@parentco.example",
            parentCoDefaultDisputeResolution: "binding arbitration",
            parentCoOfficers: parentCoOfficers
        });

        // simulate MetaLeX safe executing safe txs
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(coreDeployment.metalexSafe);
            (bool success,) = safeTxs[i].to.call{value: safeTxs[i].value}(safeTxs[i].data);
            vm.assertTrue(success);
        }

        // Set escrow sig: parentCoOfficer1 signs the factory-specific EIP-712 authorization
        bytes32 escrowDigest = parentCoFactory.escrowAuthorizationHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(parentCoOfficer1PrivKey, escrowDigest);
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(abi.encodePacked(r, s, v));
    }

    function test_parentCoOfficersInFactory() public {
        (address eoa0, string memory name0, string memory contact0, string memory title0) = parentCoFactory.parentCoOfficers(0);
        assertEq(eoa0, parentCoOfficer1);
        assertEq(name0, "Test ParentCo Officer 1");
        assertEq(contact0, "test1@parentco.example");
        assertEq(title0, "Director");

        (address eoa1, string memory name1, string memory contact1, string memory title1) = parentCoFactory.parentCoOfficers(1);
        assertEq(eoa1, parentCoOfficer2);
        assertEq(name1, "Test ParentCo Officer 2");
        assertEq(contact1, "test2@parentco.example");
        assertEq(title1, "Director");

        vm.expectRevert();
        parentCoFactory.parentCoOfficers(2);
    }

    function test_parentCorpOfficersInCyberCorp() public {
        CyberCorp corp = CyberCorp(parentCoFactory.parentCorp());

        (address eoa0, string memory name0, string memory contact0, string memory title0) = corp.companyOfficers(0);
        assertEq(eoa0, parentCoOfficer1);
        assertEq(name0, "Test ParentCo Officer 1");
        assertEq(contact0, "test1@parentco.example");
        assertEq(title0, "Director");

        (address eoa1, string memory name1, string memory contact1, string memory title1) = corp.companyOfficers(1);
        assertEq(eoa1, parentCoOfficer2);
        assertEq(name1, "Test ParentCo Officer 2");
        assertEq(contact1, "test2@parentco.example");
        assertEq(title1, "Director");

        assertTrue(corp.isCyberCORPOfficer(parentCoOfficer1));
        assertTrue(corp.isCyberCORPOfficer(parentCoOfficer2));
        assertFalse(corp.isCyberCORPOfficer(parentCoMultisig));

        vm.expectRevert();
        corp.companyOfficers(2);
    }

    function test_parentCoMultisigIsCorpPayable() public {
        CyberCorp corp = CyberCorp(parentCoFactory.parentCorp());
        assertEq(corp.companyPayable(), parentCoMultisig);
    }

    function test_corpPayableIsOwnerOfParentCoFactory() public {
        uint256 ownerRole = parentCoFactory.AUTH().OWNER_ROLE();
        assertGe(parentCoFactory.userRoles(parentCoMultisig), ownerRole);
    }

    function test_parentCoOfficersAreOwnersOfParentCoFactory() public {
        uint256 ownerRole = parentCoFactory.AUTH().OWNER_ROLE();
        assertGe(parentCoFactory.userRoles(parentCoOfficer1), ownerRole);
        assertGe(parentCoFactory.userRoles(parentCoOfficer2), ownerRole);
    }

    function test_parentCoOfficersAreOwnersOfParentCyberCorp() public {
        CyberCorp corp = CyberCorp(parentCoFactory.parentCorp());
        uint256 ownerRole = corp.AUTH().OWNER_ROLE();
        assertGe(corp.userRoles(parentCoOfficer1), ownerRole);
        assertGe(corp.userRoles(parentCoOfficer2), ownerRole);
    }

    function test_deploySubCorp_revertIfEscrowSignerNotOfficer() public {
        (, uint256 nonOfficerKey) = makeAddrAndKey("nonOfficer");
        bytes32 escrowDigest = parentCoFactory.escrowAuthorizationHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nonOfficerKey, escrowDigest);
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(abi.encodePacked(r, s, v));

        CompanyOfficer memory dummyOfficer = CompanyOfficer({eoa: address(0), name: "", contact: "", title: ""});
        string[] memory empty = new string[](0);
        vm.expectRevert(ParentCoFactory.UnauthorizedEscrowSigner.selector);
        parentCoFactory.deployCorpContractFor(
            0, "", "", "", "", "", address(0), dummyOfficer,
            bytes32(0), bytes32(0), empty, empty, hex"", address(0)
        );
    }

    function test_deploySubCorp_revertIfEscrowSigForWrongFactory() public {
        // Officer signs a valid EIP-712 sig but with address(0) as the factory field
        bytes32 wrongDigest = keccak256(abi.encodePacked(
            "\x19\x01",
            parentCoFactory.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(parentCoFactory.ESCROW_AUTHORIZATION_TYPEHASH(), address(0)))
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(parentCoOfficer1PrivKey, wrongDigest);
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(abi.encodePacked(r, s, v));

        CompanyOfficer memory dummyOfficer = CompanyOfficer({eoa: address(0), name: "", contact: "", title: ""});
        string[] memory empty = new string[](0);
        vm.expectRevert(ParentCoFactory.UnauthorizedEscrowSigner.selector);
        parentCoFactory.deployCorpContractFor(
            0, "", "", "", "", "", address(0), dummyOfficer,
            bytes32(0), bytes32(0), empty, empty, hex"", address(0)
        );
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
        agreementParties[0] = parentCoOfficer1;
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
            subCorpPayable,
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
