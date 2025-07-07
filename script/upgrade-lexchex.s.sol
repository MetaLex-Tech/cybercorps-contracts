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
import {LeXcheX} from "../src/creds/lexchex.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
/* Lexchex:  0x123E895e0e1a4e39b2E0488DB904AD37C7A62EeD
  LexchexMinter:  0x2e46c601062f01f0eD098E0b252211b5d54C496a*/


        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));
      address deployedLexChexAddr = 0x123E895e0e1a4e39b2E0488DB904AD37C7A62EeD;
      address deployedLexChexMinterAddr = 0x2e46c601062f01f0eD098E0b252211b5d54C496a;
      LeXcheX deployedLexChex = LeXcheX(deployedLexChexAddr);
      LeXcheXMinter deployedLexChexMinter = LeXcheXMinter(deployedLexChexMinterAddr);

        address newLexChexImplementation = address(new LeXcheX{salt: salt}());
        console.log("New implementation deployed at:", newLexChexImplementation);

        address newLexChexMinterImplementation = address(new LeXcheXMinter{salt: salt}());
        console.log("New Minter implementation deployed at:", newLexChexMinterImplementation);

        LeXcheX(deployedLexChexAddr).upgradeToAndCall(newLexChexImplementation, "");
        LeXcheXMinter(deployedLexChexMinterAddr).upgradeToAndCall(newLexChexMinterImplementation, "");
     }
}