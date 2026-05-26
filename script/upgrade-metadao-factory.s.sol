// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract UpgradeMetaDAOFactoryScript is Script {
    function run() public {
        // Config
        bytes32 salt = bytes32(
            keccak256("MetaDAOFactory.UpgradeV2.0.1")
        );
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);

        // Required existing addresses
        address metaDAOFactoryProxyAddr = 0x734aE2b36f663D0F4233Ce4a02c13b5EB8ec959D;

        vm.startBroadcast(deployerPrivateKey);

        // 1) Verify Deployer has permissions
        address auth = address(
            MetaDAOFactory(metaDAOFactoryProxyAddr).AUTH()
        );
        
        console.log("Deployer:", deployer);
        uint256 role = BorgAuth(auth).userRoles(deployer);
        console.log("Upgrader role:", role);
        
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to upgrade"
            );
        }

        // 2) Deploy new implementation
        address newImpl = address(
            new MetaDAOFactory{salt: salt}()
        );
        console.log("New MetaDAOFactory implementation deployed at:", newImpl);

        // 3) Perform upgrade
        IUUPS(metaDAOFactoryProxyAddr).upgradeToAndCall(newImpl, "");
        
        console.log(
            "MetaDAOFactory proxy at",
            metaDAOFactoryProxyAddr,
            "upgraded to new implementation using upgradeToAndCall."
        );

        // 4) Set new factories
        MetaDAOFactory factory = MetaDAOFactory(metaDAOFactoryProxyAddr);
        
        factory.setRoundManagerFactory(0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9);
        factory.setCyberCorpSingleFactory(0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4);
        factory.setIssuanceManagerFactory(0xD353972D7955F421d94d0eA8c42c88c417F7155A);
        factory.setDealManagerFactory(0x3982b078f2ac306219c9540Ebc908360a960C251);
        factory.setRegistryAddress(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);

        console.log("Factories updated in MetaDAOFactory.");

        vm.stopBroadcast();
    }
}

