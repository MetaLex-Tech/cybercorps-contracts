// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {ILegacyDealManagerFactory} from "./interfaces/ILegacyDealManagerFactory.sol";
import {GnosisTransaction} from "./libs/safe.sol";

contract UpgradeCyberCorpFactoriesScript is Script {

    function run() public returns (CyberCorpSingleFactory, IssuanceManagerFactory, DealManagerFactory, GnosisTransaction[] memory) {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        address deployerAddress = vm.addr(deployerPrivateKey);

        // Universal registry address
        address cyberCorpFactory = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        BorgAuth auth = CyberAgreementRegistry(registry).AUTH();
        vm.assertEq(address(auth), 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01, "should match universal AUTH address");

        vm.startBroadcast(deployerPrivateKey);

        //
        // Deploy new CyberCorpSingleFactory
        //

        // Deploy new CyberCorp reference implementation
        CyberCorp refCorp = new CyberCorp{salt: salt}(); // Use create2 here so it and hence the new factory has a stable address regardless of the deployer's state
        console.log("New CyberCorp reference implementation deployed at: %s", address(refCorp));

        // Deploy new UUPSUpgradeable DealManagerFactory
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
        console.log("New CyberCorpSingleFactory deployed at: %s", address(newCyberCorpSingleFactory));

        // Verify the upgrade was successful
        vm.assertEq(newCyberCorpSingleFactory.getRefImplementation(), address(refCorp), "unexpected CyberCorp reference implementation");

        //
        // Deploy new IssuanceManagerFactory
        //

        // Deploy new IssuanceManager reference implementation
        // Use create2 here so it and hence the new factory has a stable address regardless of the deployer's state
        IssuanceManager refIm = new IssuanceManager{salt: salt}();
        CyberCertPrinter refCertPrinter = new CyberCertPrinter{salt: salt}();
        CyberScrip refScrip = new CyberScrip{salt: salt}();
        console.log("New IssuanceManager reference implementation deployed at: %s", address(refIm));
        console.log("New CyberCertPrinter reference implementation deployed at: %s", address(refCertPrinter));
        console.log("New CyberScrip reference implementation deployed at: %s", address(refScrip));

        // Deploy new UUPSUpgradeable DealManagerFactory
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
        console.log("New IssuanceManagerFactory deployed at: %s", address(newImFactory));

        // Verify the upgrade was successful
        vm.assertEq(newImFactory.getRefImplementation(), address(refIm), "unexpected IssuanceManager reference implementation");

        //
        // Deploy new DealManagerFactory
        //

        // Deploy new DealManager reference implementation
        DealManager refDm = new DealManager{salt: salt}(); // Use create2 here so it and hence the new factory has a stable address regardless of the deployer's state
        console.log("New DealManager reference implementation deployed at: %s", address(refDm));

        // Deploy new UUPSUpgradeable DealManagerFactory
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
        console.log("New DealManagerFactory deployed at: %s", address(newDmFactory));

        // Verify the upgrade was successful
        vm.assertEq(newDmFactory.getRefImplementation(), address(refDm), "unexpected DealManager reference implementation");

        vm.stopBroadcast();

        //
        // Create Safe txs to replace old factories
        //

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](3);

        safeTxs[0] = GnosisTransaction({
            to: cyberCorpFactory,
            value: 0 ether,
            data: abi.encodeWithSelector(
                CyberCorpFactory.setCyberCorpSingleFactory.selector,
                newCyberCorpSingleFactory
            )
        });
        safeTxs[1] = GnosisTransaction({
            to: cyberCorpFactory,
            value: 0 ether,
            data: abi.encodeWithSelector(
                CyberCorpFactory.setIssuanceManagerFactory.selector,
                newImFactory
            )
        });
        safeTxs[2] = GnosisTransaction({
            to: cyberCorpFactory,
            value: 0 ether,
            data: abi.encodeWithSelector(
                CyberCorpFactory.setDealManagerFactory.selector,
                newDmFactory
            )
        });

        console.log("Safe txs (for replacing old factories):");
        for (uint256 i = 0; i < safeTxs.length; i++) {
            console.log("  tx #%d", i);
            console.log("    to:", safeTxs[i].to);
            console.log("    value:", safeTxs[i].value);
            console.log("    data:");
            console.logBytes(safeTxs[i].data);
            console.log("");
        }

        return (newCyberCorpSingleFactory, newImFactory, newDmFactory, safeTxs);
    }
}
