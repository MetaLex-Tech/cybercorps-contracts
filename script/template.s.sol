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

        string[] memory globalFieldsSafeT = new string[](17);
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

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(30)), "MetaLeX cyberSAFE jx-neutral-style Reg D raise", "ipfs://bafybeiazn4jdtlu4yz7lqbfhzaxsfhsfuwaq55m4x5mhjdeddbwwrhfufe", globalFieldsSafe, partyFieldsSafe);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(31)), "MetaLeX cyberTokenWarrant a16z jx-neutral-style-issuer Reg D raise", "ipfs://bafybeibojsh6f4wxj3gvwjbv7uvvurony7jumyqqi5i6rqsv7wcywdsi44", globalFieldsSafeT, partyFieldsSafeT);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(32)), "MetaLeX cyberSAFE jx-neutral-style Reg S raise", "ipfs://bafybeib5pqnqwbfdsnv4lqdkdglz2e4xqz2qklwdzzpbftydopzuqnri2a", globalFieldsSafe, partyFieldsSafe);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(34)), "MetaLeX cyberTokenWarrant a16z-jx-neutral-style-issuer Reg S raise", "ipfs://bafybeihi77o6kxeien3kbg2tquhmyg4bbxvbf2kjejjswk7akfzdfprwle", globalFieldsSafeT, partyFieldsSafeT);
        
        // BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);
         
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

      /*["purchaseAmount", "protocolValuationCap", "governingJurisdiction", "disputeResolution", "unlockStartTimeType", "agreementExecutionTime", "unlockingPeriod", "unlockingCliffPeriod", "unlockingCliffPercentage", "unlockingIntervalType"]*/
        string[] memory globalFieldsSafTt = new string[](10);
        globalFieldsSafTt[0] = "purchaseAmount";
        globalFieldsSafTt[1] = "protocolValuationCap";
        globalFieldsSafTt[2] = "governingJurisdiction";
        globalFieldsSafTt[3] = "disputeResolution";
        globalFieldsSafTt[4] = "unlockStartTimeType";
      globalFieldsSafTt[5] = "agreementExecutionTime";
        globalFieldsSafTt[6] = "unlockingPeriod";
        globalFieldsSafTt[7] = "unlockingCliffPeriod";
        globalFieldsSafTt[8] = "unlockingCliffPercentage";
        globalFieldsSafTt[9] = "unlockingIntervalType";

        string[] memory partyFieldsSaftt = new string[](5);
        partyFieldsSaftt[0] = "name";
        partyFieldsSaftt[1] = "evmAddress";
        partyFieldsSaftt[2] = "contactDetails";
        partyFieldsSaftt[3] = "investorType";
        partyFieldsSaftt[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(35)), "MetaLeX cyberSAFT Reg S raise", "ipfs://bafybeidquzma24o53tiys7kvspvx5izc7iru5n5dfgfwmxefi3qd67ou2y", globalFieldsSafTt, partyFieldsSaftt);
     }
}