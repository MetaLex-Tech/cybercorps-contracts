// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
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
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TokenWarrantExtension} from "../src/storage/extensions/TokenWarrantExtension.sol";

contract BaseScript is Script {
     function run() public {

        address deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_MAIN"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);
        
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpWarrantTest"));
        address stableMainNetEth = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address stableArbitrum = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address stableBase = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address stableBaseSepolia = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        address stableSepolia = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        //address registry = 0x9d4EFe86964eb038848D7aD4d208AAdEA7282516;

         address stable = stableBaseSepolia;//0x036CbD53842c5426634e7929541eC2318f3dCF7e;// 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;//0x036CbD53842c5426634e7929541eC2318f3dCF7e; //sepolia base
         address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
        //use salt to deploy BorgAuth
        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        address issuanceManagerFactory = address(new IssuanceManagerFactory{salt: salt}(address(auth)));

        address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
        CyberCertPrinter cyberCertPrinter = CyberCertPrinter(cyberCertPrinterImplementation);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "";
        //cyberCertPrinter.initialize(defaultLegend, "", "", "ipfs.io/ipfs/[cid]", address(0), SecurityClass.SAFE, SecuritySeries.SeriesPreSeed);

        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory{salt: salt}(address(auth)));

        address dealManagerFactory = address(new DealManagerFactory{salt: salt}(address(auth)));

       // address registry = address(new CyberAgreementRegistry{salt: salt}(address(auth)));
                // Deploy CyberAgreementRegistry implementation and proxy
        address registryImplementation = address(new CyberAgreementRegistry{salt: salt}());
        bytes memory initData = abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth));
        address registry = address(new ERC1967Proxy{salt: salt}(registryImplementation, initData));

        address tokenWarrantExtension = address(new TokenWarrantExtension{salt: salt}());


        address uriBuilder = address(new CertificateUriBuilder{salt: salt}());
        CyberCorpFactory cyberCorpFactory = new CyberCorpFactory{salt: salt}(address(auth), address(registry), cyberCertPrinterImplementation, issuanceManagerFactory, cyberCorpSingleFactory, dealManagerFactory, uriBuilder);
        cyberCorpFactory.setStable(stable);


        string[] memory globalFieldsSafe = new string[](17);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";
        globalFieldsSafe[5] = "exercisePriceMethod";
        globalFieldsSafe[6] = "exercisePrice";
        globalFieldsSafe[7] = "unlockStartTimeType";
        globalFieldsSafe[8] = "unlockStartTime";
        globalFieldsSafe[9] = "unlockingPeriod";
        globalFieldsSafe[10] = "latestExpirationTime";
        globalFieldsSafe[11] = "unlockingCliffPeriod";
        globalFieldsSafe[12] = "unlockingCliffPercentage";
        globalFieldsSafe[13] = "unlockingIntervalType";
        globalFieldsSafe[14] = "tokenCalculationMethod";
        globalFieldsSafe[15] = "minCompanyReserve";
        globalFieldsSafe[16] = "tokenPremiumMultiplier";


        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "name";
        partyFieldsSafe[1] = "evmAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "investorType";
        partyFieldsSafe[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(bytes32(uint256(3)), "SAFE+T", "https://ipfs.io/ipfs/bafybeih5wvr7zfw76plnb66teaa66rtgoikhhcqh55oecuoxtuw5c3dooi", globalFieldsSafe, partyFieldsSafe);

        auth.updateRole(address(multisig), 200);
        auth.zeroOwner();

        console.log("auth: ", address(auth));
        console.log("issuanceManagerFactory: ", address(issuanceManagerFactory));
        console.log("cyberCorpSingleFactory: ", address(cyberCorpSingleFactory));
        console.log("dealManagerFactory: ", address(dealManagerFactory));
        console.log("uriBuilder: ", address(uriBuilder));
        console.log("cyberCertPrinterImplementation: ", address(cyberCertPrinterImplementation));
        console.log("CyberAgreementRegistry: ", address(registry));
        console.log("CyberCorpFactory: ", address(cyberCorpFactory));
        console.log("tokenWarrantExtension: ", address(tokenWarrantExtension));
     }
}