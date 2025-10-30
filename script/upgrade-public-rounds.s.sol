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
        address legacyCyberCorpSingleFactoryAddr = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        address legacyIssuanceManagerFactoryAddr = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;

        CyberCorpFactory factoryProxy = CyberCorpFactory(
            cyberCorpFactoryProxyAddr
        );

        vm.startBroadcast(deployerPrivateKey);

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

        // 1) Deploy RoundManagerFactory
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
        factoryProxy.setRoundManagerFactory(address(roundManagerFactory));
        console.log(
            "CyberCorpFactory.roundManagerFactory set to:",
            address(roundManagerFactory)
        );

        // 4) Deploy new CyberCorpSingleFactory
        // Deploy new reference implementation
        CyberCorp refCorp = new CyberCorp{salt: salt}(); // Use create2 here so it and hence the new factory has a stable address regardless of the deployer's state
        console.log(
            "New CyberCorp implementation: %s",
            address(refCorp)
        );
        // Deploy new UUPSUpgradeable
        CyberCorpSingleFactory newCyberCorpSingleFactory = CyberCorpSingleFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberCorpSingleFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberCorpSingleFactory.initialize.selector,
                        address(auth),
                        address(refCorp)
                    )
                )
            )
        );
        console.log(
            "CyberCorpSingleFactory deployed:",
            address(newCyberCorpSingleFactory)
        );
        // Replace the old one in CyberCorpFactory
        factoryProxy.setCyberCorpSingleFactory(address(newCyberCorpSingleFactory));
        // Verify the upgrade was successful
        vm.assertEq(newCyberCorpSingleFactory.getRefImplementation(), address(refCorp), "unexpected CyberCorp reference implementation");
        console.log(
            "CyberCorpFactory.cyberCorpSingleFactory set to:",
            address(newCyberCorpSingleFactory)
        );

        // 5) Deploy new IssuanceManagerFactory
        // Deploy new reference implementations
        IssuanceManager refIm = new IssuanceManager{salt: salt}();
        CyberCertPrinter refCertPrinter = new CyberCertPrinter{salt: salt}();
        CyberScrip refScrip = new CyberScrip{salt: salt}();
        console.log(
            "New IssuanceManager implementation:",
            address(refIm)
        );
        console.log(
            "New CyberCertPrinter implementation:",
            address(refCertPrinter)
        );
        console.log(
            "New CyberScrip implementation:",
            address(refScrip)
        );
        // Deploy new UUPSUpgradeable
        IssuanceManagerFactory newImFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new IssuanceManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        address(refIm),
                        address(refCertPrinter),
                        address(refScrip)
                    )
                )
            )
        );
        console.log(
            "IssuanceManagerFactory deployed:",
            address(newImFactory)
        );
        // Replace the old one in CyberCorpFactory
        factoryProxy.setIssuanceManagerFactory(address(newImFactory));
        // Verify the upgrade was successful
        vm.assertEq(newImFactory.getRefImplementation(), address(refIm), "unexpected IssuanceManager reference implementation");
        console.log(
            "CyberCorpFactory.issuanceManagerFactory set to:",
            address(newImFactory)
        );

        // 6) Deploy new DealManagerFactory
        // Deploy new reference implementation
        DealManager refDm = new DealManager{salt: salt}(); // Use create2 here so it and hence the new factory has a stable address regardless of the deployer's state
        console.log(
            "New DealManager implementation:",
            address(refDm)
        );
        // Deploy new UUPSUpgradeable
        DealManagerFactory newDmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new DealManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector,
                        address(auth),
                        address(refDm)
                    )
                )
            )
        );
        console.log(
            "DealManagerFactory deployed:",
            address(newDmFactory)
        );
        // Replace the old one in CyberCorpFactory
        factoryProxy.setDealManagerFactory(address(newDmFactory));
        // Verify the upgrade was successful
        vm.assertEq(newDmFactory.getRefImplementation(), address(refDm), "unexpected DealManager reference implementation");
        console.log(
            "CyberCorpFactory.dealManagerFactory set to:",
            address(newDmFactory)
        );

        // 7) Upgrade CyberCorp beacon via CyberCorpSingleFactory
        ILegacyFactory legacyCcSingleFactory = ILegacyFactory(
            legacyCyberCorpSingleFactoryAddr
        );
        legacyCcSingleFactory.upgradeImplementation(address(refCorp));
        vm.assertEq(legacyCcSingleFactory.getBeaconImplementation(), address(refCorp), "legacy CyberCorp beacon implementation should've set to the reference one");
        console.log(
            "CyberCorp beacon implementation set to:",
            legacyCcSingleFactory.getBeaconImplementation()
        );

        // 8) upgrade CyberAgreementRegistry
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

        // 9) Upgrade IssuanceManager (Beacon via IssuanceManagerFactory)
        ILegacyFactory legacyIssuanceManagerFactory = ILegacyFactory(
            legacyIssuanceManagerFactoryAddr
        );
        legacyIssuanceManagerFactory.upgradeImplementation(address(refIm));
        vm.assertEq(legacyIssuanceManagerFactory.getBeaconImplementation(), address(refIm), "legacy IssuanceManager beacon implementation should've set to the reference one");
        console.log(
            "IssuanceManager beacon implementation set to:",
            legacyIssuanceManagerFactory.getBeaconImplementation()
        );

        vm.stopBroadcast();

        console.log("CyberCorpFactory:", address(factoryProxy));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
    }
}
