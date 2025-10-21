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
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract UpgradePublicRoundsScript is Script {
    function run() public {
        // Config
        bytes32 salt = bytes32(
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3")
        );
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        uint256 testPrivateKey = vm.envUint("TEST_KEY");

        address testDeployer = vm.addr(testPrivateKey);
        console.log("Test Deployer:", testDeployer);

        // Required existing addresses
        address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address cyberCorpSingleFactoryAddr = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        address issuanceManagerFactoryAddr = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;

        vm.startBroadcast(deployerPrivateKey);

        // 1) Deploy RoundManagerFactory (uses existing AUTH from factory)
        address auth = address(
            CyberCorpFactory(cyberCorpFactoryProxyAddr).AUTH()
        );
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);
        uint256 role = BorgAuth(auth).userRoles(deployer);
        console.log("Upgrader role:", role);
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to upgrade"
            );
        }
        RoundManagerFactory roundManagerFactory = RoundManagerFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        ));
        console.log(
            "RoundManagerFactory deployed:",
            address(roundManagerFactory)
        );

        // 2) Upgrade CyberCorpFactory (UUPS)
        address newCyberCorpFactoryImpl = address(
            new CyberCorpFactory{salt: salt}()
        );
        console.log(
            "New CyberCorpFactory implementation:",
            newCyberCorpFactoryImpl
        );
        // Prefer upgradeToAndCall to call blank

        IUUPS(cyberCorpFactoryProxyAddr).upgradeToAndCall(
            newCyberCorpFactoryImpl,
            ""
        );
        console.log(
            "CyberCorpFactory upgraded (proxy via upgradeToAndCall):",
            cyberCorpFactoryProxyAddr
        );

        // 3) Set the RoundManagerFactory address in CyberCorpFactory
        CyberCorpFactory factoryProxy = CyberCorpFactory(
            cyberCorpFactoryProxyAddr
        );
        factoryProxy.setRoundManagerFactory(address(roundManagerFactory));
        console.log(
            "CyberCorpFactory.roundManagerFactory set to:",
            address(roundManagerFactory)
        );

        // 4) Upgrade CyberCorp beacon via CyberCorpSingleFactory
        CyberCorpSingleFactory ccSingleFactory = CyberCorpSingleFactory(
            cyberCorpSingleFactoryAddr
        );
        address newCyberCorpImpl = address(new CyberCorp{salt: salt}());
        console.log("New CyberCorp implementation:", newCyberCorpImpl);
        ccSingleFactory.upgradeImplementation(newCyberCorpImpl);
        console.log(
            "CyberCorp beacon implementation set to:",
            ccSingleFactory.getBeaconImplementation()
        );

        // 5) upgrade CyberAgreementRegistry
        address newRegistryImpl = address(
            new CyberAgreementRegistry{salt: salt}()
        );
        console.log(
            "New CyberAgreementRegistry implementation:",
            newRegistryImpl
        );
        CyberAgreementRegistry(registry).upgradeToAndCall(newRegistryImpl, "");
        console.log(
            "CyberAgreementRegistry upgraded (proxy via upgradeToAndCall):",
            registry
        );

        // 5b) Upgrade IssuanceManager (Beacon via IssuanceManagerFactory)
        address newIssuanceManagerImpl = address(new IssuanceManager{salt: salt}());
        console.log("New IssuanceManager implementation:", newIssuanceManagerImpl);
        IssuanceManagerFactory(issuanceManagerFactoryAddr).upgradeImplementation(newIssuanceManagerImpl);
        console.log(
            "IssuanceManager beacon implementation set to:",
            IssuanceManagerFactory(issuanceManagerFactoryAddr).getBeaconImplementation()
        );

        //deploy CyberScrip implementation
        address newCyberScripImpl = address(new CyberScrip{salt: salt}());
        console.log("New CyberScrip implementation:", newCyberScripImpl);
        CyberCorpFactory(cyberCorpFactoryProxyAddr).setCyberCert20Implementation(newCyberScripImpl);


        // 6) upgrade CyberCertPrinter
        address newCyberCertPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        console.log("New CyberCertPrinter implementation:", newCyberCertPrinterImpl);
        factoryProxy.setCyberCertPrinterImplementation(newCyberCertPrinterImpl);

        vm.stopBroadcast();

        console.log("CyberCorpFactory:", address(factoryProxy));
        console.log("CyberCorpSingleFactory:", address(ccSingleFactory));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
        console.log("CyberCorp:", address(newCyberCorpImpl));
    }
}
