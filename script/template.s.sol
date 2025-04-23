// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberAgreementFactory} from "../src/CyberAgreementFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        address registry = CyberAgreementRegistry(0x5c3a3f82Dd9713b25656176053e38Af140804bd6);

        string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "Purchase Amount";
        globalFieldsSafe[1] = "Post-Money Valuation Cap";
        globalFieldsSafe[2] = "Expiration Time";
        globalFieldsSafe[3] = "Governing Jurisdiction";
        globalFieldsSafe[4] = "Dispute Resolution";

        string[] memory partyFieldsSafe = new string[](3);
        partyFieldsSafe[0] = "Name";
        partyFieldsSafe[1] = "EVM Address";
        partyFieldsSafe[2] = "Contact";
        
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(1)), "SAFE", "ipfs.io/ipfs/[cid]", globalFieldsSafe, partyFieldsSafe);

        
     }
}