// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";

interface IUUPS {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract UpgradeIssuanceManagerAndBeaconsScript is Script {
    function run() public {
        runWithArgs(type(uint256).max);
    }

    function runWithArgs(uint256 maxCount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address cyberCorpFactoryProxyAddr = vm.envAddress("CYBERCORP_FACTORY");

        CyberCorpFactory factoryProxy = CyberCorpFactory(
            cyberCorpFactoryProxyAddr
        );
        address auth = address(factoryProxy.AUTH());

        uint256 role = BorgAuth(auth).userRoles(vm.addr(deployerPrivateKey));
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert("Deployer is not AUTH owner; use the AUTH owner key");
        }

        address[] memory knownCyberCorps = KnownAddressesLoader.load(
            block.chainid,
            "/script/res/known-cyber-corps.json",
            maxCount
        );

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new reference implementations
        IssuanceManager newImImpl = new IssuanceManager();
        CyberCertPrinter newCertImpl = new CyberCertPrinter();
        CyberScrip newScripImpl = new CyberScrip();

        console2.log("New IssuanceManager impl:", address(newImImpl));
        console2.log("New CyberCertPrinter impl:", address(newCertImpl));
        console2.log("New CyberScrip impl:", address(newScripImpl));

        // Update factory reference implementations (required for UUPS upgrade checks)
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            factoryProxy.issuanceManagerFactory()
        );
        imFactory.setRefImplementation(address(newImImpl));
        imFactory.setCyberCertPrinterRefImplementation(address(newCertImpl));
        imFactory.setCyberScripRefImplementation(address(newScripImpl));

        vm.stopBroadcast();
    }
}
