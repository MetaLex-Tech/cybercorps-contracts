// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./libs/SafeUtils.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployParentCoFactoryScript is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant BASE_CHAIN_ID = 8453;

    function run() public returns (ParentCoFactory parentCoFactory, GnosisTransaction[] memory safeTxs) {

        // production

        address[] memory eoas = vm.envAddress("PARENT_CO_OFFICER_EOAS", ",");
        string[] memory names = vm.envString("PARENT_CO_OFFICER_NAMES", ",");
        string[] memory contacts = vm.envString("PARENT_CO_OFFICER_CONTACTS", ",");
        string[] memory titles = vm.envString("PARENT_CO_OFFICER_TITLES", ",");
        CompanyOfficer[] memory parentCoOfficers = new CompanyOfficer[](eoas.length);
        for (uint256 i = 0; i < eoas.length ; i++) {
            parentCoOfficers[i] = CompanyOfficer({
                eoa: eoas[i],
                name: names[i],
                contact: contacts[i],
                title: titles[i]
            });
        }

        return runWithArgs({
            chainId: DeploymentConstants.BASE,
            deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
            saltStr: "ParentCoFactory.deploy.v1",
            segCoTemplateId: keccak256("ParentCo.SegCo.v1"),
            segCoDocName: "UMIA FOUNDER/OPERATOR LEGAL PACK",
            segCoDocUri: "ipfs://bafybeicqgnzaa4zm7nlkrnuuf7xdyhughisnougerjliewynjtdaioiv5e",
            boardConsentTemplateId: keccak256("ParentCo.BoardConsent.v1"),
            boardConsentName: "ACTION BY UNANIMOUS WRITTEN CONSENT OF THE BOARD OF DIRECTORS OF UMIA LAUNCHER SPC",
            boardConsentUri: "ipfs://bafkreicr65qbif4vprnt5l2ovzqjbywwgmnply3sz7neb6qzjbb2njcrw4",
            parentCoPayable: 0x299FF70C049c0a6d591319fA7BaD86e24a671436,
            parentCoName: "UMIA LAUNCHER, SPC",
            parentCoType: "Segregated Portfolio Company",
            parentCoJurisdiction: "Cayman Islands",
            parentCoContactDetails: "c/o TTA Corporate Services Limited, Harbour Place, 2nd Floor, North Wing, 103 South Church Street, P.O. Box 472, George Town, Grand Cayman KY1-1106, Cayman Islands",
            parentCoDefaultDisputeResolution: "confidential, binding arbitration",
            parentCoOfficers: parentCoOfficers
        });

//        // testnet
//
//        CompanyOfficer[] memory parentCoOfficers = new CompanyOfficer[](2);
//        parentCoOfficers[0] = CompanyOfficer({
//            eoa: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe,
//            name: "Test Officer 1",
//            contact: "test1@parentco.example",
//            title: "Director"
//        });
//        parentCoOfficers[1] = CompanyOfficer({
//            eoa: 0xE8ABA57F64Db674E35fADBb497c3bea4bD69F787,
//            name: "Test Officer 2",
//            contact: "test2@parentco.example",
//            title: "Director"
//        });
//
//        return runWithArgs({
//            chainId: DeploymentConstants.BASE_SEPOLIA,
//            deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
//            saltStr: "ParentCoFactory.deploy.v2.dev0",
//            segCoTemplateId: keccak256("ParentCo.Test2.SegCo.v1"),
//            segCoDocName: "FOUNDER/OPERATOR LEGAL PACK",
//            segCoDocUri: "ipfs://parentco-test-segco-template",
//            boardConsentTemplateId: keccak256("ParentCo.Test2.BoardConsent.v1"),
//            boardConsentName: "ParentCo Test Board Consent",
//            boardConsentUri: "ipfs://parentco-test-board-consent-template",
//            parentCoPayable: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe,
//            parentCoName: "Test ParentCo LLC dev0",
//            parentCoType: "limited liability company",
//            parentCoJurisdiction: "Delaware",
//            parentCoContactDetails: "test@parentco.example",
//            parentCoDefaultDisputeResolution: "binding arbitration",
//            parentCoOfficers: parentCoOfficers
//        });
    }

    function runWithArgs(
        uint256 chainId,
        uint256 deployerPrivateKey,
        string memory saltStr,
        bytes32 segCoTemplateId,
        string memory segCoDocName,
        string memory segCoDocUri,
        bytes32 boardConsentTemplateId,
        string memory boardConsentName,
        string memory boardConsentUri,
        address parentCoPayable,
        string memory parentCoName,
        string memory parentCoType,
        string memory parentCoJurisdiction,
        string memory parentCoContactDetails,
        string memory parentCoDefaultDisputeResolution,
        CompanyOfficer[] memory parentCoOfficers
    ) public returns (ParentCoFactory parentCoFactory, GnosisTransaction[] memory safeTxs) {
        DeploymentConstants.Deps memory deps = DeploymentConstants.deps(chainId);
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants.coreV2(chainId);

        address paymentToken = deps.usdc;

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        console2.log("==== Configs ====");
        console2.log("deployer: %s", deployerAddress);
        console2.log("saltStr: %s", saltStr);
        for (uint256 i = 0; i < parentCoOfficers.length; i++) {
            console2.log("parentCoOfficers %d:", i);
            console2.log("  EOA: %s", parentCoOfficers[i].eoa);
            console2.log("  name: %s", parentCoOfficers[i].name);
            console2.log("  contact: %s", parentCoOfficers[i].contact);
            console2.log("  title: %s", parentCoOfficers[i].title);
            console2.log("");
        }
        console2.log("UMIA FOUNDER/OPERATOR LEGAL PACK template ID:");
        console2.logBytes32(segCoTemplateId);
        console2.log("ACTION BY UNANIMOUS WRITTEN CONSENT OF THE BOARD OF DIRECTORS OF UMIA LAUNCHER SPC template ID:");
        console2.logBytes32(boardConsentTemplateId);
        console2.log("");

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

        parentCoFactory.setParentCoOfficers(parentCoOfficers);

        (
            address parentCorp,
            address parentAuth,
            address parentIssuance,
            address parentDealMgr,
            address parentRoundMgr
        ) = parentCoFactory.createParentCorp(
                bytes32(keccak256(bytes(parentCoName))), // use parent corp name as the salt str
                parentCoName,
                parentCoType,
                parentCoJurisdiction,
                parentCoContactDetails,
                parentCoDefaultDisputeResolution,
                parentCoPayable
            );

        for (uint256 i = 0; i < parentCoOfficers.length; i++)
            parentCoFactoryAuth.updateRole(parentCoOfficers[i].eoa, parentCoFactoryAuth.OWNER_ROLE());
        parentCoFactoryAuth.updateRole(parentCoPayable, parentCoFactoryAuth.OWNER_ROLE());

        // Deployer to self-revoke ownership
        parentCoFactoryAuth.zeroOwner();

        console2.log("==== Deployed ====");
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

        safeTxs = new GnosisTransaction[](2);
        // create Founder Sig Pack template
        safeTxs[0] = GnosisTransaction({
            to: address(registry),
            value: 0,
            data: abi.encodeWithSelector(
                registry.createTemplate.selector,
                segCoTemplateId,
                segCoDocName,
                segCoDocUri,
                globalFields,
                partyFields
            )
        });
        safeTxs[1] = GnosisTransaction({
            to: address(registry),
            value: 0,
            data: abi.encodeWithSelector(
                registry.createTemplate.selector,
                boardConsentTemplateId,
                boardConsentName,
                boardConsentUri,
                globalFields,
                partyFields
            )
        });

        string memory safeTxJson = SafeUtils.formatSafeTxJson(safeTxs, chainId);

        console2.log("Safe tx JSON (can be imported to Safe Transaction Builder):");
        console2.log("==== JSON data start ====");
        console2.log(safeTxJson);
        console2.log("==== JSON data end ====");

        vm.stopBroadcast();
    }
}
