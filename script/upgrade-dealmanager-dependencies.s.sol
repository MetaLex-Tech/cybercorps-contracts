// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {ILegacyDealManagerFactory} from "./interfaces/ILegacyDealManagerFactory.sol";
import {GnosisTransaction} from "./libs/safe.sol";

/// @notice Deploy and upgrade all dependencies for testing DealManager upgrades
contract UpgradeDealManagerDependenciesScript is Script {

    function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.3.Upgrade")); // TODO TBD
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        address deployerAddress = vm.addr(deployerPrivateKey);

        // Universal registry address
        address cyberCorpFactory = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        BorgAuth auth = CyberAgreementRegistry(registry).AUTH();
        vm.assertEq(address(auth), 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01, "should match universal AUTH address");

        vm.startBroadcast(deployerPrivateKey);

        // Upgrade CyberCorpSingleFactory
        address newCyberCorpSingleFactoryImpl = address(new CyberCorpSingleFactory(address(auth)));
        console.log("new CyberCorpSingleFactory implementation deployed at: %s", newCyberCorpSingleFactoryImpl);

        // Upgrade IssuanceManagerFactory
        address newIssuanceManagerFactoryImpl = address(new IssuanceManagerFactory(address(auth)));
        console.log("new IssuanceManagerFactory implementation deployed at: %s", newIssuanceManagerFactoryImpl);

        // Deploy RoundManagerFactory
        address roundManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        );

        // Deploy CyberScrip implementation
        address cyberCert20Implementation = address(new CyberScrip());

        //
        // Upgrade CybercorpFactory
        //

        address newCyberCorpFactoryImpl = address(new CyberCorpFactory());
        CyberCorpFactory(cyberCorpFactory).upgradeToAndCall(newCyberCorpFactoryImpl, "");
        console.log("CyberCorpFactory upgraded to implementation: %s", newCyberCorpFactoryImpl);

        CyberCorpFactory(cyberCorpFactory).setCyberCorpSingleFactory(newCyberCorpSingleFactoryImpl);
        CyberCorpFactory(cyberCorpFactory).setIssuanceManagerFactory(newIssuanceManagerFactoryImpl);
        CyberCorpFactory(cyberCorpFactory).setRoundManagerFactory(roundManagerFactory);
        CyberCorpFactory(cyberCorpFactory).setCyberCert20Implementation(cyberCert20Implementation);

        vm.stopBroadcast();
    }
}
