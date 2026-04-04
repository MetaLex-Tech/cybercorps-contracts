// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Test.sol";
import {PumpCorpFactory, PumpCorpFactoryLib} from "../src/PumpCorpFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {EIP712Lib} from "../src/libs/EIP712Lib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {CompanyOfficer, SecuritySeries, SecurityClass} from "../src/CyberCorpConstants.sol";
import {RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {MockERC20} from "../test/mock/MockERC20.sol";

contract DeployPumpCorpFactoryScript is Script {

    function run() public returns (
        PumpCorpFactory pumpCorpFactory,
        RoundManagerFactory rmFactory,
        IssuanceManagerFactory imFactory,
        CertificateUriBuilder uriBuilder,
        BorgAuth pumpAuth
    ) {
        return
            runWithArgs(
                // Production
                DeploymentConstants.BASE,
                "PumpCorp.V1.0.0",
                vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

//                // Staging
//                DeploymentConstants.BASE,
//                "PumpCorp.V1.0.0.staging",
//                vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            );
    }

    function runWithArgs(
        uint256 chainId,
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (
        PumpCorpFactory pumpCorpFactory,
        RoundManagerFactory rmFactory,
        IssuanceManagerFactory imFactory,
        CertificateUriBuilder uriBuilder,
        BorgAuth pumpAuth
    ) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(chainId);

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log(
            "CyberAgreementRegistry:",
            deployment.cyberAgreementRegistry
        );
        console2.log("CyberCorpSingleFactory:", deployment.cyberCorpSingleFactory);
        console2.log("DealManagerFactory:", deployment.dealManagerFactory);
        console2.log("RoundManagerFactory:", deployment.roundManagerFactory);
        console2.log("CertificateUriBuilder:", deployment.uriBuilder);
        console2.log("");

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            deployment.cyberAgreementRegistry
        );

        vm.startBroadcast(deployerPrivateKey);

//        // (1) Deploy factory contracts
//
//        pumpAuth = new BorgAuth{salt: salt}(deployerAddress);
//
//        // TODO WIP: as of 2026/03/16 we haven't deployed the new RoundManagerFactory with restrictEndTimeReduction yet,
//        //  so we deploy a dev one here for now
//        rmFactory = RoundManagerFactory(address(
//            new ERC1967Proxy{salt: salt}(
//                address(new RoundManagerFactory{salt: salt}()),
//                abi.encodeWithSelector(
//                    RoundManagerFactory.initialize.selector,
//                    address(pumpAuth),
//                    address(new RoundManager())
//                )
//            )
//        ));
//
//        // TODO WIP: as of 2026/03/16 the on-chain IssuanceManager and CyberCertPrinter lack addOfficerSignature/addIssuerSignature,
//        //  so we deploy a new factory pointing to locally compiled implementations
//        imFactory = IssuanceManagerFactory(address(
//            new ERC1967Proxy{salt: salt}(
//                address(new IssuanceManagerFactory{salt: salt}()),
//                abi.encodeWithSelector(
//                    IssuanceManagerFactory.initialize.selector,
//                    address(pumpAuth),
//                    address(new IssuanceManager()),
//                    address(new CyberCertPrinter()),
//                    address(new CyberScrip())
//                )
//            )
//        ));
//
//        // TODO WIP: as of 2026/03/16 the on-chain CertificateUriBuilder lack ACE securitySeries
//        //  so we deploy a new one pointing to locally compiled implementations
//        uriBuilder = CertificateUriBuilder(address(
//            new ERC1967Proxy{salt: salt}(
//                address(new CertificateUriBuilder{salt: salt}()),
//                abi.encodeWithSelector(
//                    CertificateUriBuilder.initialize.selector,
//                    address(pumpAuth)
//                )
//            )
//        ));
//        uriBuilder.setImageBuilder(address(new CertificateImageBuilderContract()));
//
//        console2.log("==== Deployed (for dev purposes) ====");
//        console2.log("PumpAuth:", address(pumpAuth));
//        console2.log("IssuanceManagerFactory:", address(imFactory));
//        console2.log("RoundManagerFactory:", address(rmFactory));
//        console2.log("CertificateUriBuilder:", address(uriBuilder));
//        console2.log("");

        // In production, the IssuanceManagerFactory and RoundManagerFactory should be upgraded by now so we will just use it
        rmFactory = RoundManagerFactory(deployment.roundManagerFactory);
        imFactory = IssuanceManagerFactory(deployment.issuanceManagerFactory);
        uriBuilder = CertificateUriBuilder(deployment.uriBuilder);
        pumpAuth = BorgAuth(deployment.auth);

        pumpCorpFactory = PumpCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new PumpCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        PumpCorpFactory.initialize.selector,
                        pumpAuth,
                        deployment.cyberAgreementRegistry,
                        address(imFactory),
                        deployment.cyberCorpSingleFactory,
                        deployment.dealManagerFactory,
                        rmFactory,
                        uriBuilder
                    )
                )
            )
        );

        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log("PumpCorpFactory (proxy):", address(pumpCorpFactory));
        console2.log("");
    }
}
