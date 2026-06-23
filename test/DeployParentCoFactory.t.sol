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

contract DeployParentCoFactoryForkTest is Test {
    DeploymentConstants.CoreDeployment coreDeployment;
    DeploymentConstants.Deps deps;

    CyberAgreementRegistry registry;

    address deployer;
    uint256 deployerPrivKey;

    ParentCoFactory parentCoFactory;
    address parentCoMultisig;
    address parentCoOfficer1;
    uint256 parentCoOfficer1PrivKey;
    address parentCoOfficer2;
    uint256 parentCoOfficer2PrivKey;

    CompanyOfficer[] parentCoOfficers;

    bytes32 segCoTemplateId = keccak256("ParentCo.SegCo.v1");
    bytes32 boardConsentTemplateId = keccak256("ParentCo.BoardConsent.v1");

    address subCorpPayable;
    address subCorpOfficer;
    uint256 subCorpOfficerPrivKey;

    struct SubCorpResult {
        address subCorp;
        address subAuth;
        address subIssuance;
        address subDealMgr;
        bytes32 expectedSegCoId;
        bytes32 expectedBoardConsentId;
    }

    function setUp() public {
        vm.createSelectFork("base_sepolia", 40732512); // pinned to an old block before ParentCoFactory is deployed
        coreDeployment = DeploymentConstants.coreV2(block.chainid);
        deps = DeploymentConstants.deps(block.chainid);

        registry = CyberAgreementRegistry(coreDeployment.cyberAgreementRegistry);

        (deployer, deployerPrivKey) = makeAddrAndKey("deployer");

        (parentCoMultisig, ) = makeAddrAndKey("parentCoMultisig");
        (parentCoOfficer1, parentCoOfficer1PrivKey) = makeAddrAndKey("parentCoOfficer1");
        (parentCoOfficer2, parentCoOfficer2PrivKey) = makeAddrAndKey("parentCoOfficer2");
        (subCorpPayable, ) = makeAddrAndKey("subCorpPayable");
        (subCorpOfficer, subCorpOfficerPrivKey) = makeAddrAndKey("subCorpOfficer");

        parentCoOfficers.push(CompanyOfficer({
            eoa: parentCoOfficer1,
            name: "Test ParentCo Officer 1",
            contact: "test1@parentco.example",
            title: "Director"
        }));
        parentCoOfficers.push(CompanyOfficer({
            eoa: parentCoOfficer2,
            name: "Test ParentCo Officer 2",
            contact: "test2@parentco.example",
            title: "Director"
        }));

        GnosisTransaction[] memory safeTxs;
        (parentCoFactory, safeTxs) = (new DeployParentCoFactoryScript()).runWithArgs({
            chainId: block.chainid,
            deployerPrivateKey: deployerPrivKey,
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
        bytes memory escrowSig = _createParentCoSignatureHash(
            parentCoOfficer1PrivKey,
            parentCoOfficers[0].name,
            parentCoOfficers[0].contact
        );
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(escrowSig);
    }

    function _deploySubCorp() internal returns (SubCorpResult memory r) {
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

        // Pre-compute expected agreement IDs (registry: keccak256(abi.encode(templateId, salt, globalValues, parties)))
        // parentCoOfficer1 is the escrow signer set in setUp
        address[] memory segCoParties = new address[](2);
        segCoParties[0] = parentCoOfficer1;
        segCoParties[1] = subCorpOfficer;
        r.expectedSegCoId = keccak256(abi.encode(segCoTemplateId, subCorpSalt, globalValues, segCoParties));

        address[] memory boardConsentParties = new address[](1);
        boardConsentParties[0] = parentCoOfficer1;
        r.expectedBoardConsentId = keccak256(abi.encode(boardConsentTemplateId, subCorpSalt, globalValues, boardConsentParties));

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
            r.expectedSegCoId,
            legalContractUri,
            templateGlobalFields,
            templatePartyFields,
            globalValues,
            partyValues,
            subCorpOfficerPrivKey
        );

        (
            r.subCorp,
            r.subAuth,
            r.subIssuance,
            r.subDealMgr,
            ,
            ,
            ,

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

    function test_deployerHasSelfRevokedOwnerOfParentCoFactory() public {
        assertEq(parentCoFactory.userRoles(deployer), 0);
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
        bytes memory nonOfficerSig = _createParentCoSignatureHash(
            nonOfficerKey,
            parentCoOfficers[0].name,
            parentCoOfficers[0].contact
        );
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(nonOfficerSig);

        CompanyOfficer memory dummyOfficer = CompanyOfficer({eoa: address(0), name: "", contact: "", title: ""});
        string[] memory empty = new string[](0);
        vm.expectRevert(ParentCoFactory.UnauthorizedEscrowSigner.selector);
        parentCoFactory.deployCorpContractFor(
            0, "", "", "", "", "", address(0), dummyOfficer,
            bytes32(0), bytes32(0), empty, empty, hex"", address(0)
        );
    }

    function test_deploySubCorp_revertIfOfficerSignsWithAnotherOfficersIdentity() public {
        // officer2 signs using officer1's name+contact — should not authenticate as officer1
        bytes memory spoofedSig = _createParentCoSignatureHash(
            parentCoOfficer2PrivKey,
            parentCoOfficers[0].name,
            parentCoOfficers[0].contact
        );
        vm.prank(parentCoOfficer1);
        parentCoFactory.setParentCoSignatureHash(spoofedSig);

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

    function test_deploySubCorp_returnsNonZeroAddresses() public {
        SubCorpResult memory r = _deploySubCorp();
        assertTrue(r.subCorp != address(0));
        assertTrue(r.subAuth != address(0));
        assertTrue(r.subIssuance != address(0));
        assertTrue(r.subDealMgr != address(0));
        assertTrue(r.subCorp != r.subAuth);
        assertTrue(r.subCorp != r.subIssuance);
        assertTrue(r.subCorp != r.subDealMgr);
    }

    function test_deploySubCorp_subCorpOfficerCorrect() public {
        SubCorpResult memory r = _deploySubCorp();
        CyberCorp corp = CyberCorp(r.subCorp);

        (address eoa, string memory name, string memory contact, string memory title) = corp.companyOfficers(0);
        assertEq(eoa, subCorpOfficer);
        assertEq(name, "Test Deployer Officer");
        assertEq(contact, "deployer@parentco.example");
        assertEq(title, "Founder");
        assertTrue(corp.isCyberCORPOfficer(subCorpOfficer));
    }

    function test_deploySubCorp_subCorpPayableCorrect() public {
        SubCorpResult memory r = _deploySubCorp();
        assertEq(CyberCorp(r.subCorp).companyPayable(), subCorpPayable);
    }

    function test_deploySubCorp_subCorpAuthRoles() public {
        SubCorpResult memory r = _deploySubCorp();
        BorgAuth subAuth = BorgAuth(r.subAuth);
        uint256 ownerRole = subAuth.OWNER_ROLE();
        assertGe(subAuth.userRoles(subCorpOfficer), ownerRole);
    }

    function test_deploySubCorp_agreementSignedByBothParties() public {
        SubCorpResult memory r = _deploySubCorp();
        assertTrue(registry.hasSigned(r.expectedSegCoId, parentCoOfficer1));
        assertTrue(registry.hasSigned(r.expectedSegCoId, subCorpOfficer));
        assertTrue(registry.allPartiesSigned(r.expectedSegCoId));
    }

    function test_deploySubCorp_boardConsentSigned() public {
        SubCorpResult memory r = _deploySubCorp();
        assertTrue(registry.hasSigned(r.expectedBoardConsentId, parentCoOfficer1));
        address[] memory parties = registry.getParties(r.expectedBoardConsentId);
        assertEq(parties.length, 1);
        assertEq(parties[0], parentCoOfficer1);
    }

    function test_deploySubCorp_officer2CanSetEscrowAndDeploy() public {
        bytes memory sig = _createParentCoSignatureHash(
            parentCoOfficer2PrivKey,
            parentCoOfficers[1].name,
            parentCoOfficers[1].contact
        );
        vm.prank(parentCoOfficer2);
        parentCoFactory.setParentCoSignatureHash(sig);

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
        segCoParties[0] = parentCoOfficer2;
        segCoParties[1] = subCorpOfficer;
        bytes32 agreementId = keccak256(abi.encode(segCoTemplateId, subCorpSalt, globalValues, segCoParties));

        (
            string memory legalContractUri,
            ,
            string[] memory templateGlobalFields,
            string[] memory templatePartyFields
        ) = registry.getTemplateDetails(segCoTemplateId);

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

        (address subCorp,,,,,, bytes32 retId,) = parentCoFactory.deployCorpContractFor(
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
            agreementSig,
            subCorpOfficer
        );

        assertTrue(subCorp != address(0));
        assertTrue(registry.hasSigned(agreementId, parentCoOfficer2));
        assertTrue(registry.hasSigned(agreementId, subCorpOfficer));
    }

    function test_deploySubCorp_revertIfPartyValuesTooShort() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory shortPartyValues = new string[](1);
        shortPartyValues[0] = "Test Deployer Officer";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, shortPartyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfOfficerNameMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "WRONG NAME"; // != officer.name
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfOfficerContactMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "wrong@email.com"; // != officer.contact

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfCompanyNameMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "WRONG COMPANY NAME"; // != companyName arg below
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfCompanyTypeMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "WRONG TYPE"; // != companyType arg below
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfJurisdictionMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Nevada"; // != companyJurisdiction arg below
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfContactDetailsMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: subCorpOfficer,
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "wrong@contact.com"; // != companyContactDetails arg below
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.GlobalOrPartyValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function test_deploySubCorp_revertIfOfficerEoaMismatch() public {
        uint256 subCorpSalt = uint256(keccak256("ParentCo.Test2.SubCorp.v1"));
        CompanyOfficer memory subOfficer = CompanyOfficer({
            eoa: address(1), // != deployer arg below
            name: "Test Deployer Officer",
            contact: "deployer@parentco.example",
            title: "Founder"
        });
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Test Founder";
        globalValues[1] = "Test ParentCo Enterprise";
        globalValues[2] = "Test SubCo SPV 1";
        globalValues[3] = "series limited liability company";
        globalValues[4] = "Delaware";
        globalValues[5] = "subco@parentco.example";
        globalValues[6] = "TSC1";
        globalValues[7] = "Test SubCo One";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Test Deployer Officer";
        partyValues[1] = "deployer@parentco.example";

        vm.expectRevert(ParentCoFactory.OfficerValuesMismatch.selector);
        parentCoFactory.deployCorpContractFor(
            subCorpSalt, "Test SubCo SPV 1", "series limited liability company",
            "Delaware", "subco@parentco.example", "binding arbitration",
            subCorpPayable, subOfficer, segCoTemplateId, boardConsentTemplateId,
            globalValues, partyValues, hex"", subCorpOfficer
        );
    }

    function _createParentCoSignatureHash(uint256 privKey, string memory name, string memory contact) internal returns (bytes memory) {
        bytes32 escrowDigest = parentCoFactory.escrowAuthorizationHash(name, contact);
        (uint8 v, bytes32 r_, bytes32 s) = vm.sign(privKey, escrowDigest);
        return abi.encodePacked(r_, s, v);
    }
}
