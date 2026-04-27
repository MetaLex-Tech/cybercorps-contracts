// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
                // TODO need production arguments
//                {
//                    stable: 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913, // Base USDC
//                }

                // Base sepolia
                {
                    chainId: BASE_SEPOLIA_CHAIN_ID,
                    deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
                    saltStr: "ParentCoFactory.deploy.v2",
                    paymentToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // Base Sepolia USDC
                    segCoTemplateId: keccak256("ParentCo.Test2.SegCo.v1"),
                    segCoDocName: "FOUNDER/OPERATOR LEGAL PACK",
                    segCoDocUri: "ipfs://parentco-test-segco-template",
                    boardConsentTemplateId: keccak256("ParentCo.Test2.BoardConsent.v1"),
                    boardConsentName: "ParentCo Test Board Consent",
                    boardConsentUri: "ipfs://parentco-test-board-consent-template",
                    parentCorpPayable: 0x42069BaBe92462393FaFdc653A88F958B64EC9A3,
                    parentCorpOfficerAddress: 0x42069BaBe92462393FaFdc653A88F958B64EC9A3,
                    parentCoName: "Test ParentCo LLC",
                    parentCoType: "limited liability company",
                    parentCoJurisdiction: "Delaware",
                    parentCoContactDetails: "test@parentco.example",
                    parentCoDefaultDisputeResolution: "binding arbitration",
                    parentCoOfficerName: "Test ParentCo Officer",
                    parentCoOfficerContact: "test@parentco.example",
                    parentCoOfficerTitle: "Director",
                    parentEscrowSig: hex"73f62ac9b08c813401a02a16a920a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1a",
                    deployTestSubCorp: true
                }
            );
    }

    function runWithArgs(
        uint256 chainId,
        uint256 deployerPrivateKey,
        string memory saltStr,
        address paymentToken,
        bytes32 segCoTemplateId,
        string memory segCoDocName,
        string memory segCoDocUri,
        bytes32 boardConsentTemplateId,
        string memory boardConsentName,
        string memory boardConsentUri,
        address parentCoPayable,
        address parentCoOfficerAddress,
        string memory parentCoName,
        string memory parentCoType,
        string memory parentCoJurisdiction,
        string memory parentCoContactDetails,
        string memory parentCoDefaultDisputeResolution,
        string memory parentCoOfficerName,
        string memory parentCoOfficerContact,
        string memory parentCoOfficerTitle,
        bytes memory parentEscrowSig,
        bool deployTestSubCorp
    ) public returns (ParentCoFactory parentCoFactory) {
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(chainId);

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        BorgAuth parentCoFactoryAuth = new BorgAuth{salt: salt}(deployerAddress);

        parentCoFactory = ParentCoFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new ParentCoFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        ParentCoFactory.initialize.selector,
                        address(parentCoFactoryAuth),
                        deployment.cyberAgreementRegistry,
                        deployment.issuanceManagerFactory,
                        deployment.cyberCorpSingleFactory,
                        deployment.dealManagerFactory,
                        deployment.roundManagerFactory,
                        deployment.uriBuilder,
                        paymentToken
                    )
                )
            )
        );

        // Configure ParentCo officer and escrowed signature BEFORE revoking deployer ownership

        parentCoFactory.setParentCoOfficerEOA(parentCoOfficerAddress);
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
                bytes32(keccak256(parentCoName)), // use parent corp name as the salt str
                parentCoName,
                parentCoType,
                parentCoJurisdiction,
                parentCoContactDetails,
                parentCoDefaultDisputeResolution,
                parentCoPayable
            );

        parentCoFactory.setParentCoSignatureHash(parentEscrowSig);

        parentCoFactoryAuth.updateRole(parentCoOfficerAddress, parentCoFactoryAuth.OWNER_ROLE());
        parentCoFactoryAuth.updateRole(parentCoPayable, parentCoFactoryAuth.OWNER_ROLE());

        console2.log("ParentCoFactory Auth:", address(parentCoFactoryAuth));
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
        console2.log("");

        // TODO create multisig txs instead
        // Create (or no-op if already present) templates used by deployCorpContractFor.

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
                segCoDocName,
                segCoDocUri,
                globalFields,
                partyFields
            )
        {
            console2.log("Founder Sig Pack template created:");
            console2.log(segCoTemplateId);
            console2.log("  name: %s", segCoDocName);
            console2.log("  URI: %s", segCoDocUri);
        } catch {
            console2.log("Founder Sig Pack template already exists, skipped");
        }

        try
            registry.createTemplate(
                boardConsentTemplateId,
                boardConsentName,
                boardConsentUri,
                globalFields,
                partyFields
            )
        {
            console2.log("Board Consent template created:");
            console2.log(boardConsentTemplateId);
            console2.log("  name: %s", boardConsentName);
            console2.log("  URI: %s", boardConsentUri);
        } catch {
            console2.log("Board Consent template already exists, skipped");
        }

        console2.log("");

        if (deployTestSubCorp) {

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
            agreementParties[0] = parentCoOfficerAddress;
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
                    parentCoPayable,
                    subOfficer,
                segCoTemplateId,
                    boardConsentTemplateId,
                    globalValues,
                    partyValues,
                    deployerSignature,
                    deployerAddress
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

        vm.stopBroadcast();
    }
}
