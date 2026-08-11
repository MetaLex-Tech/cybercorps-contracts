// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));

         BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);
        //deploy saft data extension with create2
       /* address saftExtension = address(new ERC1967Proxy{salt: salt}(
           address(new SAFTExtension{salt: salt}()),
           abi.encodeWithSelector(SAFTExtension.initialize.selector, address(auth))
        ));

        console.log("SAFTExtension: ", address(saftExtension));*/

        string[] memory globalFieldsLexchex = new string[](1);
        globalFieldsLexchex[0] = "expiryDate";


        string[] memory partyFieldsLexchex = new string[](4);
        partyFieldsLexchex[0] = "investorName";
        partyFieldsLexchex[1] = "investorType";
        partyFieldsLexchex[2] = "investorJurisdiction";
        partyFieldsLexchex[3] = "investorContact";

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(404)), "MetaLeX LeXCheX agreement v.1.0 DRAFT", "ipfs://bafybeighlffqicblntl7shsqhsku4h54dtpitlrsvwkd3quofxkix77wt4", globalFieldsLexchex, partyFieldsLexchex);
     }
}