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

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.3"));
        bytes32 secondSalt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2.3"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address testAdmin = 0x42069BaBe92462393FaFdc653A88F958B64EC9A3;
        vm.startBroadcast(deployerPrivateKey);
        address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
         uint256 currentChainId = block.chainid;
        address stable;

        if (currentChainId == 1) {
            stable = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet
        } else if (currentChainId == 42161) {
            stable = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum
        } else if (currentChainId == 8453) {
            stable = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base
        } else if (currentChainId == 84532) {
            stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia
        } else if (currentChainId == 11155111) {
            stable = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia
        } else {
            revert("Unsupported chain ID"); // Handle unsupported chains
        }

        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));

        BorgAuth lexchexAuth = new BorgAuth{salt: secondSalt}(deployerAddress);


         LeXcheX lexchex = LeXcheX(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheX{salt: salt}()),
            abi.encodeWithSelector(LeXcheX.initialize.selector, address(lexchexAuth))
        )));

        LeXcheXMinter lexchexMinter = LeXcheXMinter(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheXMinter{salt: salt}()),
            abi.encodeWithSelector(
                LeXcheXMinter.initialize.selector,
                address(lexchexAuth),
                address(lexchex),
                address(registry),
                multisig
            )
        )));

        // Grant LeXcheXMinter admin access to LeXcheX
        lexchexAuth.updateRole(address(lexchexMinter), lexchexAuth.ADMIN_ROLE());
        lexchexAuth.updateRole(address(multisig), lexchexAuth.OWNER_ROLE());
        lexchexAuth.updateRole(address(testAdmin), lexchexAuth.ADMIN_ROLE());

        console.log("LexchexAuth: ", address(lexchexAuth));
        console.log("Lexchex: ", address(lexchex));
        console.log("LexchexMinter: ", address(lexchexMinter));


        //CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(25)), "MetaLeX cyberSAFT reg D v.1.0", "ipfs://bafybeif6fqgexescp4g2hbb6fjkk3ifrqpopc2lv2oue5tiq6h3t2pmgc4", globalFieldsSafT, partyFieldsSaft);
     }
}