// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

contract DeployParentCoFactoryScript is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() public returns (ParentCoFactory parentCoFactory) {
        return
            runWithArgs(
                vm.envUint("PRIVATE_KEY_MAIN"),
                0x42069BaBe92462393FaFdc653A88F958B64EC9A3, // test corp payable
                0x42069BaBe92462393FaFdc653A88F958B64EC9A3 // test officer EOA
            );
    }

    function runWithArgs(
        uint256 deployerPrivateKey,
        address corpPayable,
        address officerAddress
    ) public returns (ParentCoFactory parentCoFactory) {
        string memory parentCoOfficerName = "Test ParentCo Officer";
        string memory parentCoOfficerContact = "test@parentco.example";
        string memory parentCoOfficerTitle = "Director";

        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(BASE_SEPOLIA_CHAIN_ID);

        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256("ParentCoFactory.deploy.v2"));

        vm.startBroadcast(deployerPrivateKey);

        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        parentCoFactory = ParentCoFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new ParentCoFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        ParentCoFactory.initialize.selector,
                        address(auth),
                        deployment.cyberAgreementRegistry,
                        deployment.issuanceManagerFactory,
                        deployment.cyberCorpSingleFactory,
                        deployment.dealManagerFactory,
                        deployment.roundManagerFactory,
                        deployment.uriBuilder,
                        BASE_USDC
                    )
                )
            )
        );

        parentCoFactory.setParentCoOfficerEOA(officerAddress);
        parentCoFactory.setParentCoOfficerName(parentCoOfficerName);
        parentCoFactory.setParentCoOfficerContact(parentCoOfficerContact);
        parentCoFactory.setParentCoOfficerTitle(parentCoOfficerTitle);

        (
            address parentCorp,
            address parentAuth,
            address parentIssuance,
            address parentDealMgr,
            address parentRoundMgr
        ) = parentCoFactory.createParentCorp(
                bytes32(keccak256("Test2 ParentCo LLC")),
                "Test ParentCo LLC",
                "limited liability company",
                "Delaware",
                "test@parentco.example",
                "binding arbitration",
                corpPayable
            );

        // Escrow signature bytes for parent signing path (placeholder/test value).
        bytes memory parentEscrowSig = hex"73f62ac9b08c813401a02a16a920a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1a";
        parentCoFactory.setParentCoSignatureHash(parentEscrowSig);

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        // Create (or no-op if already present) templates used by deployCorpContractFor.
        bytes32 segCoTemplateId = keccak256("ParentCo.Test2.SegCo.v1");
        bytes32 boardConsentTemplateId = keccak256(
            "ParentCo.Test2.BoardConsent.v1"
        );

        string[] memory globalFields = new string[](8);
        globalFields[0] = "founderName";
        globalFields[1] = "enterpriseName";
        globalFields[2] = "companyName";
        globalFields[3] = "companyType";
        globalFields[4] = "companyJurisdiction";
        globalFields[5] = "companyContactDetails";
        globalFields[6] = "tokenSymbol";
        globalFields[7] = "tokenName";

        string[] memory partyFields = new string[](2);
        partyFields[0] = "name";
        partyFields[1] = "contactDetails";

        try
            registry.createTemplate(
                segCoTemplateId,
                "ParentCo Test SegCo Agreement",
                "ipfs://parentco-test-segco-template",
                globalFields,
                partyFields
            )
        {} catch {}

        try
            registry.createTemplate(
                boardConsentTemplateId,
                "ParentCo Test Board Consent",
                "ipfs://parentco-test-board-consent-template",
                globalFields,
                partyFields
            )
        {} catch {}

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
            eoa: deployerAddress,
            name: partyValues[0],
            contact: partyValues[1],
            title: "Founder"
        });

        // Pre-compute agreement id and signer signature expected by signContractFor.
        address[] memory agreementParties = new address[](2);
        agreementParties[0] = officerAddress;
        agreementParties[1] = deployerAddress;
        bytes32 agreementId = keccak256(
            abi.encode(segCoTemplateId, subCorpSalt, globalValues, agreementParties)
        );

        (
            string memory legalContractUri,
            ,
            string[] memory templateGlobalFields,
            string[] memory templatePartyFields
        ) = registry.getTemplateDetails(segCoTemplateId);

        bytes memory deployerSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            legalContractUri,
            templateGlobalFields,
            templatePartyFields,
            globalValues,
            partyValues,
            deployerPrivateKey
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
                corpPayable,
                subOfficer,
                segCoTemplateId,
                boardConsentTemplateId,
                globalValues,
                partyValues,
                deployerSignature,
                deployerAddress
            );

        auth.updateRole(officerAddress, auth.OWNER_ROLE());
        auth.updateRole(corpPayable, auth.OWNER_ROLE());

        console2.log("Auth:", address(auth));
        console2.log(
            "CyberAgreementRegistry:",
            deployment.cyberAgreementRegistry
        );
        console2.log("IssuanceManagerFactory:", deployment.issuanceManagerFactory);
        console2.log("CyberCorpSingleFactory:", deployment.cyberCorpSingleFactory);
        console2.log("DealManagerFactory:", deployment.dealManagerFactory);
        console2.log("RoundManagerFactory:", deployment.roundManagerFactory);
        console2.log("CertificateUriBuilder:", deployment.uriBuilder);
        console2.log("ParentCoFactory (proxy):", address(parentCoFactory));
        console2.log("ParentCorp:", parentCorp);
        console2.log("ParentAuth:", parentAuth);
        console2.log("ParentIssuance:", parentIssuance);
        console2.log("ParentDealMgr:", parentDealMgr);
        console2.log("ParentRoundMgr:", parentRoundMgr);
        console2.log("SubCorp:", subCorp);
        console2.log("SubAuth:", subAuth);
        console2.log("SubIssuance:", subIssuance);
        console2.log("SubDealMgr:", subDealMgr);
        console2.log("SubRoundMgr:", subRoundMgr);
        console2.log("SubAgreementId:");
        console2.logBytes32(subAgreementId);
        console2.log("SubCertPrinters count:", subCertPrinters.length);
        console2.log("SubCertIds count:", subCertIds.length);

        vm.stopBroadcast();
    }
}
