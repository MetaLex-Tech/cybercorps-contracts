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
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.1")
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
                    address(new RoundManager{salt: salt}())
                )
            )
        ));
        console.log(
            "RoundManagerFactory deployed:",
            address(roundManagerFactory)
        );

        roundManagerFactory.setWhitelistedToken(stable, true);

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
        factoryProxy.setLexchexAuth(deployedLexChexAddrAuth);
        roundManagerFactory.setDefaultFeeRatio(30);
        roundManagerFactory.setPlatformPayable(multisig);
        newDmFactory.setDefaultFeeRatio(30);
        newDmFactory.setPlatformPayable(multisig);

        //add CyberCorpFactory as owner on lexchex auth
        BorgAuth(deployedLexChexAddrAuth).updateRole(address(factoryProxy), BorgAuth(deployedLexChexAddrAuth).OWNER_ROLE());

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

        //update templates

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

        vm.stopBroadcast();

        console.log("CyberCorpFactory:", address(factoryProxy));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
    }
}
