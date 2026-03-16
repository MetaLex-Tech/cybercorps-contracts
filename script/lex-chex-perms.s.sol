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
import {LeXcheX} from "../src/creds/lexchex.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LexChexCondition} from "../src/libs/conditions/lexchexCondition.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.lexchex.2"));
        bytes32 secondSalt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2.lexchex.2"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address testAdmin = 0x42069BaBe92462393FaFdc653A88F958B64EC9A3;
        vm.startBroadcast(deployerPrivateKey);
        address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
         uint256 currentChainId = block.chainid;
        address stable;
        address minter = 0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf;

        BorgAuth lexchexAuth = BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2);
        lexchexAuth.updateRole(address(minter), lexchexAuth.OWNER_ROLE());


        //CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(25)), "MetaLeX cyberSAFT reg D v.1.0", "ipfs://bafybeif6fqgexescp4g2hbb6fjkk3ifrqpopc2lv2oue5tiq6h3t2pmgc4", globalFieldsSafT, partyFieldsSaft);
     }
}