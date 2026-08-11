// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IIssuanceManagerFactory} from "../src/interfaces/IIssuanceManagerFactory.sol";
import {IShareClassTermsController} from "../src/interfaces/IShareClassTermsController.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/LedgerEntryTokenStorage.sol";

/// @notice Upgrades one corp's IssuanceManager and migrates every supplied
///         share printer in the same transaction.
/// @dev Comma-delimit CERT_PRINTERS and SOURCE_TOKEN_IDS in matching order.
///      Each source certificate must first be reconciled to its legal class
///      authority. Simulate without --broadcast before any owner-authorized run.
contract UpgradeAndMigrateShareClassTermsScript is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address issuanceManagerAddress = vm.envAddress("ISSUANCE_MANAGER");
        address implementation = vm.envAddress("ISSUANCE_MANAGER_IMPLEMENTATION");
        address controllerAddress = vm.envAddress("SHARE_CLASS_TERMS_CONTROLLER");
        address[] memory printers = vm.envAddress("CERT_PRINTERS", ",");
        uint256[] memory sourceTokenIds = vm.envUint("SOURCE_TOKEN_IDS", ",");

        if (printers.length == 0) revert("No cert printers supplied");
        if (printers.length != sourceTokenIds.length) {
            revert("CERT_PRINTERS and SOURCE_TOKEN_IDS length mismatch");
        }
        if (implementation.code.length == 0) {
            revert("IssuanceManager implementation has no code");
        }
        if (controllerAddress.code.length == 0) {
            revert("ShareClassTermsController has no code");
        }

        IssuanceManager issuanceManager = IssuanceManager(issuanceManagerAddress);
        IssuanceManager targetImplementation = IssuanceManager(implementation);
        IShareClassTermsController controller = IShareClassTermsController(controllerAddress);
        BorgAuth auth = BorgAuth(address(issuanceManager.AUTH()));

        if (auth.userRoles(deployer) < auth.OWNER_ROLE()) {
            revert("Deployer is not issuance-manager AUTH owner");
        }
        if (keccak256(bytes(targetImplementation.DEPLOY_VERSION())) != keccak256(bytes("4.2"))) {
            revert("Target implementation is not IssuanceManager 4.2");
        }
        if (
            IIssuanceManagerFactory(issuanceManager.getUpgradeFactory()).getRefImplementation()
                != implementation
        ) {
            revert("Target is not the IssuanceManager factory reference");
        }

        bytes[] memory extensionData = new bytes[](printers.length);
        for (uint256 i = 0; i < printers.length; ++i) {
            LedgerEntryToken printer = LedgerEntryToken(printers[i]);
            if (printer.issuanceManager() != issuanceManagerAddress) {
                revert("Printer belongs to a different IssuanceManager");
            }
            if (printer.isVoided(sourceTokenIds[i])) {
                revert("Source certificate is voided");
            }
            (,,,, bool alreadyConfigured) = controller.getClassTerms(printers[i]);
            if (alreadyConfigured) revert("Class terms already configured");

            CertificateDetails memory source = printer.getActiveCertificateDetails(sourceTokenIds[i]);
            if (source.extensionData.length == 0) {
                revert("Source certificate has no extension data");
            }
            extensionData[i] = source.extensionData;
        }

        bytes memory migrationCall =
            abi.encodeCall(IssuanceManager.migrateClassTermsControllers, (printers, controllerAddress, extensionData));

        vm.startBroadcast(privateKey);
        issuanceManager.upgradeToAndCall(implementation, migrationCall);
        vm.stopBroadcast();

        vm.assertEq(issuanceManager.DEPLOY_VERSION(), "4.2", "IssuanceManager version mismatch");
        for (uint256 i = 0; i < printers.length; ++i) {
            LedgerEntryToken printer = LedgerEntryToken(printers[i]);
            vm.assertEq(printer.getExtension(0), controllerAddress, "Printer controller mismatch");
            (, bytes32 termsHash, uint256 authorizedShares, uint256 issuedUnits, bool configured) =
                controller.getClassTerms(printers[i]);
            vm.assertTrue(configured, "Class terms migration did not persist");
            vm.assertTrue(termsHash != bytes32(0), "Class terms hash is empty");
            vm.assertGe(authorizedShares, issuedUnits, "Issued units exceed authorized shares");

            console2.log("Migrated cert printer:", printers[i]);
            console2.logBytes32(termsHash);
            console2.log("Authorized shares:", authorizedShares);
            console2.log("Issued units:", issuedUnits);
        }
    }
}
