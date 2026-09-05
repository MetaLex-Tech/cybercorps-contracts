// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IShareClassTermsController} from "../src/interfaces/IShareClassTermsController.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice One-shot migration for an existing share printer.
/// @dev The operator must review SOURCE_TOKEN_ID against the charter/class
///      authority before broadcasting. Outstanding units, including scrip,
///      are derived on-chain by the printer rather than supplied by the caller.
contract ConfigureShareClassTermsScript is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address printerAddress = vm.envAddress("CERT_PRINTER");
        address controllerAddress = vm.envAddress("SHARE_CLASS_TERMS_CONTROLLER");
        uint256 sourceTokenId = vm.envUint("SOURCE_TOKEN_ID");

        LedgerEntryToken printer = LedgerEntryToken(printerAddress);
        IssuanceManager issuanceManager = IssuanceManager(printer.issuanceManager());
        IShareClassTermsController controller = IShareClassTermsController(controllerAddress);
        BorgAuth auth = BorgAuth(address(issuanceManager.AUTH()));

        if (auth.userRoles(deployer) < auth.OWNER_ROLE()) {
            revert("Deployer is not issuance-manager AUTH owner");
        }
        if (printer.isVoided(sourceTokenId)) {
            revert("Source certificate is voided");
        }

        (,,,, bool alreadyConfigured) = controller.getClassTerms(printerAddress);
        if (alreadyConfigured) revert("Class terms already configured");

        CertificateDetails memory source = printer.getActiveCertificateDetails(sourceTokenId);
        if (source.extensionData.length == 0) {
            revert("Source certificate has no extension data");
        }

        address[] memory printers = new address[](1);
        printers[0] = printerAddress;
        bytes[] memory extensionData = new bytes[](1);
        extensionData[0] = source.extensionData;

        vm.startBroadcast(privateKey);
        issuanceManager.migrateClassTermsControllers(printers, controllerAddress, extensionData);
        vm.stopBroadcast();

        (, bytes32 termsHash, uint256 authorizedShares, uint256 issuedUnits, bool configured) =
            controller.getClassTerms(printerAddress);
        vm.assertTrue(configured, "Class terms migration did not persist");
        vm.assertTrue(termsHash != bytes32(0), "Class terms hash is empty");
        vm.assertGe(authorizedShares, issuedUnits, "Issued units exceed authorized shares");

        console2.log("Configured cert printer:", printerAddress);
        console2.logBytes32(termsHash);
        console2.log("Authorized shares:", authorizedShares);
        console2.log("Issued units:", issuedUnits);
    }
}
