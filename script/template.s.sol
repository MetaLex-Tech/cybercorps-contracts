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
import {SAFTEExtension} from "../src/storage/extensions/SAFTEExtension.sol";

contract BaseScript is Script {
     function run() public {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2"));
        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));

 /*string[] memory globalFieldsSafeT = new string[](17);
 /*string[] memory globalFieldsSafeT = new string[](17);
        globalFieldsSafeT[0] = "purchaseAmount";
        globalFieldsSafeT[1] = "postMoneyValuationCap";
        globalFieldsSafeT[2] = "expirationTime";
        globalFieldsSafeT[3] = "governingJurisdiction";
        globalFieldsSafeT[4] = "disputeResolution";
        globalFieldsSafeT[5] = "exercisePriceMethod";
        globalFieldsSafeT[6] = "exercisePrice";
        globalFieldsSafeT[7] = "unlockStartTimeType";
        globalFieldsSafeT[8] = "unlockStartTime";
        globalFieldsSafeT[9] = "unlockingPeriod";
        globalFieldsSafeT[10] = "latestExpirationTime";
        globalFieldsSafeT[11] = "unlockingCliffPeriod";
        globalFieldsSafeT[12] = "unlockingCliffPercentage";
        globalFieldsSafeT[13] = "unlockingIntervalType";
        globalFieldsSafeT[14] = "tokenCalculationMethod";
        globalFieldsSafeT[15] = "minCompanyReserve";
        globalFieldsSafeT[16] = "tokenPremiumMultiplier";


        string[] memory partyFieldsSafeT = new string[](5);
        partyFieldsSafeT[0] = "name";
        partyFieldsSafeT[1] = "evmAddress";
        partyFieldsSafeT[2] = "contactDetails";
        partyFieldsSafeT[3] = "investorType";
        partyFieldsSafeT[4] = "investorJurisdiction";



        string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";


        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "name";
        partyFieldsSafe[1] = "evmAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "investorType";
        partyFieldsSafe[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(20)), "MetaLeX cyberSAFE US style Reg D v 1.0", "ipfs://bafybeic242ypthamyr3kxnwk4x7sxj7s6svck4xfu3dzgttvic73lihy6m", globalFieldsSafe, partyFieldsSafe);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(21)), "MetaLeX cyberSAFE + cyberTokenWarrant a16z US style reg D v 1.0", "ipfs://bafybeieozn5ur3gocmmleoph57oznz6acgzrclwkibyijjxv7nobt5tbxa", globalFieldsSafeT, partyFieldsSafeT);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(22)), "MetaLeX cyberSAFE UK Cayman style Reg S v 1.0", "ipfs://bafybeigm77lgbd5wptji7hoeeqxedippdlvj4eaykgz5eb2bsw2ncboxcu", globalFieldsSafe, partyFieldsSafe);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(23)), "MetaLeX cyberSAFE + cyberTokenWarrant a16z non-US Reg S v 1.0", "ipfs://bafybeieoahzrvqk3vggrv6zyljlgkrqn2ls5wgpbgp4w4ylenr2r2ftugm", globalFieldsSafeT, partyFieldsSafeT);
        */
         BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);
         
        //deploy saft data extension with create2
  /*      address safteExtension = address(new ERC1967Proxy{salt: salt}(
           address(new SAFTEExtension{salt: salt}()),
           abi.encodeWithSelector(SAFTEExtension.initialize.selector, address(auth))
        ));

         console.log("SAFTEExtension: ", address(safteExtension));*/

/*| **globalFieldName** | **description**                    |
|:--------------------|:-----------------------------------|
| purchaseAmount      |       e.g. "1000.00"              |
| postMoneyValuationCap  |     postmoney equity valuation of the company  |
| protocolUSDValuationAtTimeofInvestment    |  valuation of the 'network' or 'protocol' (i.e., FDV of all tokens)  |
| expirationTime      |    time at which offer to sign agreement (purchasing the SAFTE) expires     |
| governingJurisdiction       |     jurisdiction of incorporation and also jurisdiction of governing law for the agreement     |
| disputeResolution   |       method of dispute resolution   |
| unlockStartTimeType |"agreementExecutionTime" \|"tgeTime" \| "setTime"        |
| unlockStartTime       | only set if using `setTime` for `unlockStartTimeType` |
| unlockingPeriod       | Duration in `unlockingInvervalType` units  |
| unlockingCliffPeriod       | Duration in `unlockingIntervalType`, first tokens unlocked at `unlockingStartTime` + `unlockingCliffPeriod`  |
| unlockingCliffPercentage       | e.g. "10.5%" |
| unlockingIntervalType       |  "secondly", "hourly", "daily", "monthly", "blockly". Note that this affects both `unlockingPeriod` and `unlockingCliffPeriod`   |
| tokenCalculationMethod       |  `equityProRataToTokenSupply` or `equityProRataToCompanyReserve` or 'dollarProRataToProtocolVal' |
| minCompanyReserve       | This is a number of tokens   |
| tokenPremiumMultiplier  | */

        string[] memory globalFieldsSafT = new string[](15);
        globalFieldsSafT[0] = "purchaseAmount";
        globalFieldsSafT[1] = "postMoneyValuationCap";
        globalFieldsSafT[2] = "protocolUSDValuationAtTimeofInvestment";
        globalFieldsSafT[3] = "expirationTime";
        globalFieldsSafT[4] = "governingJurisdiction";
         globalFieldsSafT[5] = "disputeResolution";
        globalFieldsSafT[6] = "unlockStartTimeType";
        globalFieldsSafT[7] = "unlockStartTime";
        globalFieldsSafT[8] = "unlockingPeriod";
        globalFieldsSafT[9] = "unlockingCliffPeriod";
        globalFieldsSafT[10] = "unlockingCliffPercentage";
        globalFieldsSafT[11] = "unlockingIntervalType";
        globalFieldsSafT[12] = "tokenCalculationMethod";
        globalFieldsSafT[13] = "minCompanyReserve";
        globalFieldsSafT[14] = "tokenPremiumMultiplier";


        string[] memory partyFieldsSaft = new string[](5);
        partyFieldsSaft[0] = "name";
        partyFieldsSaft[1] = "evmAddress";
        partyFieldsSaft[2] = "contactDetails";
        partyFieldsSaft[3] = "investorType";
        partyFieldsSaft[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(27)), "MetaLeX cyberSAFTE reg D v.1.1", "ipfs://bafybeidephecyo4ovg2xtik6kiuuhejri4owu5qi6s6qft5j2uj2sf2t3q", globalFieldsSafT, partyFieldsSaft);
     }
}