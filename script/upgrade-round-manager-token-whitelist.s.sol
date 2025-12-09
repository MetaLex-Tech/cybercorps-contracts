// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract UpgradeRoundManagerTokenWhitelistScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        vm.startBroadcast(deployerPrivateKey);
           bytes32 salt = bytes32(
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.2")
        );

        // Required existing addresses
        address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        address deployedLexChexAddrAuth = 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2;

        address stable;
        uint256 currentChainId = block.chainid;
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

        CyberCorpFactory factoryProxy = CyberCorpFactory(
            cyberCorpFactoryProxyAddr
        );

        // Uses existing AUTH from factory
        address auth = address(
            CyberCorpFactory(cyberCorpFactoryProxyAddr).AUTH()
        );
        vm.assertEq(address(auth), 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01, "should match universal AUTH address");

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        uint256 role = BorgAuth(auth).userRoles(deployer);
        console.log("Upgrader role:", role);
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to upgrade"
            );
        }

        // 1) Upgrade RoundManagerFactory (UUPS)
        address newRoundManagerFactoryImpl = address(
            new RoundManagerFactory{salt: salt}()
        );
        console.log(
            "New RoundManagerFactory implementation:",
            newRoundManagerFactoryImpl
        );
        // Prefer upgradeToAndCall to call blank

        address roundManagerFactory = CyberCorpFactory(cyberCorpFactoryProxyAddr).roundManagerFactory();
        IUUPS(roundManagerFactory).upgradeToAndCall(
            newRoundManagerFactoryImpl,
            ""
        );
        console.log(
            "RoundManagerFactory upgraded (proxy via upgradeToAndCall):",
            roundManagerFactory
        );

        RoundManagerFactory(roundManagerFactory).setWhitelistedToken(stable, true);
        console.log("RoundManagerFactory set whitelisted token to: %s", stable);

        // 2) Deploy new RoundManager reference implementation
        RoundManager refRoundManagerImpl = new RoundManager{salt: salt}();
        RoundManagerFactory(roundManagerFactory).setRefImplementation(address(refRoundManagerImpl));
        vm.assertEq(RoundManagerFactory(roundManagerFactory).getRefImplementation(), address(refRoundManagerImpl), "new reference RoundManager implementation should set");
        console.log(
            "New RoundManager reference implementation set to: %s",
            address(refRoundManagerImpl)
        );

        vm.stopBroadcast();

        console.log("CyberCorpFactory:", address(factoryProxy));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
    }


}
