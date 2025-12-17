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
import "../src/creds/lexchexMinter.sol";


contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("LexChexMinterAdminUpgrade"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
/* Lexchex:  0x123E895e0e1a4e39b2E0488DB904AD37C7A62EeD
  LexchexMinter:  0x2e46c601062f01f0eD098E0b252211b5d54C496a*/


      address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));
      address deployedLexChexAddr = 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62;
      address deployedLexChexMinterAddr = 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960;
      address deployedLexChexAddrAuth = 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2;
      address lexnode = 0x3B12Bfc36931155A8Dc26c6636D0C888E9a3F55C;
      LeXcheX deployedLexChex = LeXcheX(deployedLexChexAddr);
      LeXcheXMinter deployedLexChexMinter = LeXcheXMinter(deployedLexChexMinterAddr);


      address newLexChexMinterImplementation = address(new LeXcheXMinter{salt: salt}());
      console.log("New Minter implementation deployed at:", newLexChexMinterImplementation);

      LeXcheXMinter(deployedLexChexMinterAddr).upgradeToAndCall(newLexChexMinterImplementation, "");

      BorgAuth(deployedLexChexAddrAuth).updateRole(lexnode, BorgAuth(deployedLexChexAddrAuth).ADMIN_ROLE());

      /* LeXcheXMinter.MintRequest memory request = LeXcheXMinter.MintRequest({
            uuid: 1,
            owner: deployerAddress,
            investorName: "Test Entity",
            investorType: "LLC",
            investorJurisdiction: "Delaware",
            investorContact: "test@test.com",
            mintPrice: 0,
            expiry: block.timestamp + 365 days,
            paymentToken: address(0)
        });

       LeXcheXMinter(deployedLexChexMinterAddr).adminMintFor(request);*/
        vm.stopBroadcast();
     }
}