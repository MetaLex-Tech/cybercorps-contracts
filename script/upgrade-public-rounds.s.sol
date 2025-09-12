// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {EOI} from "../src/storage/RoundManagerStorage.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {Vm} from "forge-std/Test.sol";
import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";

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
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV1")
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        uint256 testPrivateKey = vm.envUint("TEST_KEY");

        address testDeployer = vm.addr(testPrivateKey);
        console.log("Test Deployer:", testDeployer);

        // Required existing addresses
        address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address cyberCorpSingleFactoryAddr = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
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
        RoundManagerFactory roundManagerFactory = new RoundManagerFactory{
            salt: salt
        }(auth);
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

        // 6) upgrade CyberCertPrinter
        address newCyberCertPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        console.log("New CyberCertPrinter implementation:", newCyberCertPrinterImpl);
        factoryProxy.setCyberCertPrinterImplementation(newCyberCertPrinterImpl);

        console.log("CyberCorpFactory:", address(factoryProxy));
        console.log("CyberCorpSingleFactory:", address(ccSingleFactory));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
        console.log("CyberCorp:", address(newCyberCorpImpl));

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: deployer,
            name: "CEO",
            contact: "ceo@cybercorp.com",
            title: "1234567890"
        });

        CyberCertData[] memory certData = new CyberCertData[](1);

        certData[0] = CyberCertData({
            name: "CyberCorp",
            symbol: "CC",
            uri: "ipfs://bafkreigz4o4kqxmkcln2742v47hms7eacd7v3c43lvr7k7i5h6e7nfl77i",
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesA,
            extension: address(0),
            defaultLegend: new string[](0)
        });

        string[] memory roundPartyValues = new string[](5);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";
        roundPartyValues[2] = "Alice Officer";
        roundPartyValues[3] = "CEO";
        roundPartyValues[4] = "Alice Officer";

        bytes memory escrowedSig = hex"01";

        //test deploy a new CyberCorp and start a public round using the factory
        (
            address cyberCorp,
            address autha,
            address issuance,
            address dealManager,
            address roundManager,
            bytes32 roundId
        ) = CyberCorpFactory(cyberCorpFactoryProxyAddr)
                .deployCyberCorpAndCreatePublicRound(
                    block.timestamp,
                    "Series A",
                    "CyberCorp",
                    "Limited Liability Company",
                    "Juris",
                    "Contact Details",
                    "Dispute Res",
                    address(deployer),
                    officer,
                    certData,
                    0x0000000000000000000000000000000000000000000000000000000000000020,
                    address(usdc),
                    1000,
                    1000000000000000,
                    roundPartyValues,
                    escrowedSig,
                    RoundType.FCFS,
                    100000000000,
                    1,
                    10000000,
                    block.timestamp - 1,
                    block.timestamp + 14 days
                );
        vm.stopBroadcast();

        vm.startBroadcast(testPrivateKey);
        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 1,
            maxAmount: 1
        });

        address[] memory parties = new address[](2);
        parties[0] = deployer;
        parties[1] = testDeployer;

        //get the template data for templateID 0x0000000000000000000000000000000000000000000000000000000000000020
        (
            string memory legalUri,
            ,
            string[] memory globalFields,
            string[] memory partyFields
        ) = CyberAgreementRegistry(registry).getTemplateDetails(
                0x0000000000000000000000000000000000000000000000000000000000000020
            );

        bytes32 contractId = keccak256(
            abi.encode(
                0x0000000000000000000000000000000000000000000000000000000000000020,
                block.timestamp,
                roundPartyValues,
                parties
            )
        );

        bytes memory signature = _computeEOISignature(
            vm,
            CyberAgreementRegistry(registry),
            0x0000000000000000000000000000000000000000000000000000000000000020,
            block.timestamp,
            roundPartyValues,
            roundPartyValues,
            deployer,
            testPrivateKey
        );

        /*        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry,
        string memory name*/
        ERC20(payable(usdc)).approve(address(roundManager), type(uint256).max);
        RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            roundPartyValues,
            roundPartyValues,
            signature,
            block.timestamp,
            new address[](0),
            bytes32(0),
            block.timestamp + 7 days,
            "Investor 1"
        );
        vm.stopBroadcast();
    }

    function _computeEOISignature(
        Vm vm,
        CyberAgreementRegistry registry,
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        string[] memory partyValues,
        address authorityOfficer,
        uint256 signerPrivKey
    ) internal view returns (bytes memory) {
        (
            string memory legalUri,
            ,
            string[] memory glFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(
            abi.encode(templateId, salt, globalValues, parties)
        );
        return
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                contractId,
                legalUri,
                glFields,
                partyFields,
                globalValues,
                partyValues,
                signerPrivKey
            );
    }
}
