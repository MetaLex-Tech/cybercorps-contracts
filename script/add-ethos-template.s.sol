// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
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
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TokenWarrantExtension} from "../src/storage/extensions/TokenWarrantExtension.sol";
import {SAFTEExtension} from "../src/storage/extensions/SAFTEExtension.sol";

contract BaseScript is Script {
     function run() public {

        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
        
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2"));
        address stableMainNetEth = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address stableArbitrum = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address stableBase = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address stableBaseSepolia = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        address stableSepolia = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        //address registry = 0x9d4EFe86964eb038848D7aD4d208AAdEA7282516;

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
        //ethos_safte_template
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;

        string[] memory globalFieldsSafeT = new string[](14);
        globalFieldsSafeT[0] = "purchaseAmount";
        globalFieldsSafeT[1] = "postMoneyValuationCap";
        globalFieldsSafeT[2] = "expirationTime";
        globalFieldsSafeT[3] = "governingJurisdiction";
        globalFieldsSafeT[4] = "disputeResolution";
        globalFieldsSafeT[5] = "unlockStartTimeType";
        globalFieldsSafeT[6] = "unlockStartTime";
        globalFieldsSafeT[7] = "unlockingPeriod";
        globalFieldsSafeT[8] = "unlockingCliffPeriod";
        globalFieldsSafeT[9] = "unlockingCliffPercentage";
        globalFieldsSafeT[10] = "unlockingIntervalType";
        globalFieldsSafeT[11] = "tokenCalculationMethod";
        globalFieldsSafeT[12] = "minCompanyReserve";
        globalFieldsSafeT[13] = "tokenPremiumMultiplier";


        string[] memory partyFieldsSafeT = new string[](5);
        partyFieldsSafeT[0] = "name";
        partyFieldsSafeT[1] = "evmAddress";
        partyFieldsSafeT[2] = "contactDetails";
        partyFieldsSafeT[3] = "investorType";
        partyFieldsSafeT[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(bytes("ethos_safte_test2")), "SAFTE", "ipfs://bafybeiby3ikipxaxafsqyow4jfchofw4wb2jr2x4nfximmwc6cnszca7ge", globalFieldsSafeT, partyFieldsSafeT);

        console.log("Template created successfully");


     }
}