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

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(50)), "cySPA + Reg D SAFE", "IPFS://bafybeics3btqftkfnzchtisazgvlvtq3xok6rrdvhjyhdvr7lhoa6snjxe", globalFieldsSafe, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(51)), "cySPA + REG S SAFE", "IPFS://bafybeidwqou5x4amvsidepwbuqpwarowv3vce473jpqcgejvbf4g2xxdee", globalFieldsSafe, partyFields);

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


        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(52)), "cySPA + REG D SAFE + REG D TOKEN WARRANT", "IPFS://bafybeiapw7thrkzymtnhilmr5sjl7sm55yc42d2zxl66u6tdutfvm55t2y", globalFieldsSafeTokenWarrant, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(53)), "cySPA + REG S SAFE + REG S TOKEN WARRANT", "IPFS://bafybeianosjn74ldjexzmwcji6nl3l24ikwazd64uei625nszysqfwla2i", globalFieldsSafeTokenWarrant, partyFields);

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

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(54)), "cySPA + REG D SAFTE ", "IPFS://bafybeidb2ebvu7uxt6m2ukrdnytzpwrb4ihcncbx2v4qohe5xao3xr3m7e", globalFieldsSafte, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(55)), "cySPA + REG S SAFTE ", "IPFS://bafybeideutuq3r3v66rdcvzar5heefyark24urc3ix44tvvjpo2ntvkc7i", globalFieldsSafte, partyFields);

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

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(56)), "cySPA + REG D SAFT", "IPFS://bafybeidfbgwv35cu22ouwdpmho35gicfnkno2em7ngjn4mbhbiogvvaf7i", globalFieldsSaft, partyFields);
        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(57)), "cySPA + REG S SAFT", "IPFS://bafybeibjm2mss4ctfsyajehtwnmje3aa2agif5n47i575pxdejrk7dee5m", globalFieldsSaft, partyFields);


     }
}