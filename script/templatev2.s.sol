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

        string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";


        string[] memory partyFields = new string[](5);
        partyFields[0] = "name";
        partyFields[1] = "evmAddress";
        partyFields[2] = "contactDetails";
        partyFields[3] = "investorType";
        partyFields[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safe_reg_d_v1_3")), "metalex cybersafe jx-neutral reg d raise v 1.3", "IPFS://bafybeih7l2kxncjuwrfgv5gnmpcik43dnn4pxpe4it4u7ti2hgfgrlot2a", globalFieldsSafe, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safe_reg_s_v1_3")), "metalex cybersafe jx-neutral reg s raise v 1.3", "IPFS://bafybeieh7jn553jmrjmwee3dsvwf5hkedomey2vhubc3mumlewfpumvlae", globalFieldsSafe, partyFields);

        string[] memory globalFieldsSafeTokenWarrant = new string[](17);
        globalFieldsSafeTokenWarrant[0] = "purchaseAmount";
        globalFieldsSafeTokenWarrant[1] = "postMoneyValuationCap";
        globalFieldsSafeTokenWarrant[2] = "expirationTime";
        globalFieldsSafeTokenWarrant[3] = "governingJurisdiction";
        globalFieldsSafeTokenWarrant[4] = "disputeResolution";
        globalFieldsSafeTokenWarrant[5] = "exercisePriceMethod";
        globalFieldsSafeTokenWarrant[6] = "exercisePrice";
        globalFieldsSafeTokenWarrant[7] = "unlockStartTimeType";
        globalFieldsSafeTokenWarrant[8] = "unlockStartTime";
        globalFieldsSafeTokenWarrant[9] = "unlockingPeriod";
        globalFieldsSafeTokenWarrant[10] = "latestExpirationTime";
        globalFieldsSafeTokenWarrant[11] = "unlockingCliffPeriod";
        globalFieldsSafeTokenWarrant[12] = "unlockingCliffPercentage";
        globalFieldsSafeTokenWarrant[13] = "unlockingIntervalType";
        globalFieldsSafeTokenWarrant[14] = "tokenCalculationMethod";
        globalFieldsSafeTokenWarrant[15] = "minCompanyReserve";
        globalFieldsSafeTokenWarrant[16] = "tokenPremiumMultiplier";


        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safe_tw_reg_d_v1_3")), "metalex cybersafe + cybertokenwarrant jx-neutral reg d raise v 1.3", "IPFS://bafybeiaw3pwov3ahg4bk2hte2hu4pwv34nndoguxyk3umq6f5su3kod6ay", globalFieldsSafeTokenWarrant, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safe_tw_reg_s_v1_3")), "metalex cybersafe + cybertokenwarrant jx-neutral reg s raise v 1.3", "IPFS://bafybeicto2raupsj5ad7snxvhmmll2plwyploqho4fg2cibnn2fuhlm2d4", globalFieldsSafeTokenWarrant, partyFields);

        //make an array for this: ["purchaseAmount", "postMoneyValuationCap", "protocolUSDValuationAtTimeofInvestment", "expirationTime", "governingJurisdiction", "disputeResolution", "unlockStartTimeType", "unlockStartTime", "unlockingPeriod", "unlockingCliffPeriod", "unlockingCliffPercentage", "unlockingIntervalType", "tokenCalculationMethod", "minCompanyReserve", "tokenPremiumMultiplier"]*/
        string[] memory globalFieldsSafte = new string[](15);
        globalFieldsSafte[0] = "purchaseAmount";
        globalFieldsSafte[1] = "postMoneyValuationCap";
        globalFieldsSafte[2] = "protocolUSDValuationAtTimeofInvestment";
        globalFieldsSafte[3] = "expirationTime";
        globalFieldsSafte[4] = "governingJurisdiction";
        globalFieldsSafte[5] = "disputeResolution";
        globalFieldsSafte[6] = "unlockStartTimeType";
        globalFieldsSafte[7] = "unlockStartTime";
        globalFieldsSafte[8] = "unlockingPeriod";
        globalFieldsSafte[9] = "unlockingCliffPeriod";
        globalFieldsSafte[10] = "unlockingCliffPercentage";
        globalFieldsSafte[11] = "unlockingIntervalType";
        globalFieldsSafte[12] = "tokenCalculationMethod";
        globalFieldsSafte[13] = "minCompanyReserve";
        globalFieldsSafte[14] = "tokenPremiumMultiplier";

        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safte_reg_d_v1_3")), "metalex cybersafte jx-neutral reg d raise v 1.3", "IPFS://bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay", globalFieldsSafte, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_safte_reg_s_v1_3")), "metalex cybersafte jx-neutral reg s raise v 1.3", "IPFS://bafybeia43r7e566s2jlq4gtaasmtybutujy7fuizhw3fycxtwnstfbkeia", globalFieldsSafte, partyFields);

        string[] memory globalFieldsSaft = new string[](10);
        globalFieldsSaft[0] = "purchaseAmount";
        globalFieldsSaft[1] = "protocolValuationCap";
        globalFieldsSaft[2] = "governingJurisdiction";
        globalFieldsSaft[3] = "disputeResolution";
        globalFieldsSaft[4] = "unlockStartTimeType";
        globalFieldsSaft[5] = "unlockStartTime";
        globalFieldsSaft[6] = "unlockingPeriod";
        globalFieldsSaft[7] = "unlockingCliffPeriod";
        globalFieldsSaft[8] = "unlockingCliffPercentage";
        globalFieldsSaft[9] = "unlockingIntervalType";

        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_saft_reg_d_v1_3")), "metalex cybersaft jx-neutral reg d raise v 1.3", "IPFS://bafybeieoljri2rwuv35rymjd654sr3u46kbcao7mymseqobfo7x6lxgdcy", globalFieldsSaft, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("mlx_saft_reg_s_v1_3")), "metalex cybersaft jx-neutral reg s raise v 1.3", "IPFS://bafybeibwrz3rttteguo5ccoh5x7ndwdu6hyhy7i3iraii5c5ml4pfv73t4", globalFieldsSaft, partyFields);


     }
}