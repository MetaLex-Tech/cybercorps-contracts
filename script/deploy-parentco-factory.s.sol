// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

contract DeployParentCoFactoryScript is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() public returns (ParentCoFactory parentCoFactory, GnosisTransaction[] memory safeTxs) {
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
                    parentCoPayable: 0x42069BaBe92462393FaFdc653A88F958B64EC9A3,
                    parentCoOfficerAddress: 0x42069BaBe92462393FaFdc653A88F958B64EC9A3,
                    parentCoName: "Test ParentCo LLC",
                    parentCoType: "limited liability company",
                    parentCoJurisdiction: "Delaware",
                    parentCoContactDetails: "test@parentco.example",
                    parentCoDefaultDisputeResolution: "binding arbitration",
                    parentCoOfficerName: "Test ParentCo Officer",
                    parentCoOfficerContact: "test@parentco.example",
                    parentCoOfficerTitle: "Director",
                    parentEscrowSig: hex"73f62ac9b08c813401a02a16a920a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1a"
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
        bytes memory parentEscrowSig
    ) public returns (ParentCoFactory parentCoFactory, GnosisTransaction[] memory safeTxs) {
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(chainId);

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

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
                bytes32(keccak256(bytes(parentCoName))), // use parent corp name as the salt str
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

        console2.log("Safe Txs for creating templates:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console2.log("  #", i);
            console2.log("    to:", safeTxs[i].to);
            console2.log("    value:", safeTxs[i].value);
            console2.log("    data:");
            console2.logBytes(safeTxs[i].data);
            console2.log("");
        }

        vm.stopBroadcast();
    }
}
