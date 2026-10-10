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

contract UpgradePublicRoundsBaseSepoliaScript is Script {
    function run() public returns (
        IssuanceManagerFactory newImFactory,
        RoundManagerFactory roundManagerFactory
    ) {
        return runWithArgs(vm.envUint("PRIVATE_KEY_MAIN"));
    }

    function runWithArgs(uint256 deployerPrivateKey) public returns (
        IssuanceManagerFactory newImFactory,
        RoundManagerFactory roundManagerFactory
    ) {
        address deployer = vm.addr(deployerPrivateKey);
        // Config
        bytes32 salt = bytes32(
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.1")
        );
        
        // Required existing addresses
        address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address legacyCyberCorpSingleFactoryAddr = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        address legacyIssuanceManagerFactoryAddr = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        address deployedLexChexAddrAuth = 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2;
        address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

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

        console.log("Deployer:", deployer);
        uint256 role = BorgAuth(auth).userRoles(deployer);
        console.log("Upgrader role:", role);
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to upgrade"
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1) Deploy RoundManagerFactory
        roundManagerFactory = RoundManagerFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager{salt: salt}())
                )
            )
        ));
        console.log(
            "RoundManagerFactory deployed:",
            address(roundManagerFactory)
        );

        roundManagerFactory.setWhitelistedToken(stable, true);

        // 2) Set the RoundManagerFactory address in CyberCorpFactory
        factoryProxy.setRoundManagerFactory(address(roundManagerFactory));
        console.log(
            "CyberCorpFactory.roundManagerFactory set to:",
            address(roundManagerFactory)
        );

        // 3) Deploy new IssuanceManagerFactory
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
        newImFactory = IssuanceManagerFactory(
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

        vm.stopBroadcast();
    }
}
