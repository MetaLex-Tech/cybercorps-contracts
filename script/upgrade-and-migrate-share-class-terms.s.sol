// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IIssuanceManagerFactory} from "../src/interfaces/IIssuanceManagerFactory.sol";
import {IShareClassTermsController} from "../src/interfaces/IShareClassTermsController.sol";
import {IShareClassTermsExtension} from "../src/interfaces/IShareClassTermsExtension.sol";
import {ICertificateExtension} from "../src/storage/extensions/ICertificateExtension.sol";
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

        // A legacy printer with no active certificate (never issued, or every lot voided) has no
        // source to derive terms from — yet the completeness scan below rightly refuses to let it
        // be omitted, and the bare 4.2 acceptance refuses the corp. For those printers, pass
        // type(uint256).max as the SOURCE_TOKEN_IDS entry and supply the reconciled terms bytes
        // directly via comma-delimited SOURCELESS_TERMS (consumed in printer order). Supplied
        // terms carry the same reconciliation duty as a source certificate: charter/class
        // authority evidence per the runbook.
        bytes[] memory sourcelessTerms = vm.envOr("SOURCELESS_TERMS", ",", new bytes[](0));
        uint256 sourcelessUsed = 0;

        bytes[] memory extensionData = new bytes[](printers.length);
        for (uint256 i = 0; i < printers.length; ++i) {
            LedgerEntryToken printer = LedgerEntryToken(printers[i]);
            if (printer.issuanceManager() != issuanceManagerAddress) {
                revert("Printer belongs to a different IssuanceManager");
            }
            (,,,, bool alreadyConfigured) = controller.getClassTerms(printers[i]);
            if (alreadyConfigured) revert("Class terms already configured");

            if (sourceTokenIds[i] == type(uint256).max) {
                if (sourcelessUsed >= sourcelessTerms.length) {
                    revert("SOURCELESS_TERMS entry missing for sourceless printer");
                }
                bytes memory supplied = sourcelessTerms[sourcelessUsed++];
                if (supplied.length == 0) revert("Empty SOURCELESS_TERMS entry");
                // The supplied value must be a FULL share extension payload (abi-encoded
                // ShareCertData) — exactly what a source certificate's extensionData carries —
                // because the controller's renderer decodes that shape, not bare SeriesTerms
                // bytes. Validate through the controller's own extractor before broadcasting,
                // so a wrong encoding fails here with a clear message instead of reverting the
                // atomic upgrade with InvalidShareExtensionData.
                try IShareClassTermsExtension(controllerAddress).getSeriesTermsData(supplied) returns (
                    bytes memory termsData, uint256
                ) {
                    if (termsData.length == 0) {
                        revert("SOURCELESS_TERMS entry decodes to empty SeriesTerms");
                    }
                } catch {
                    revert(
                        "SOURCELESS_TERMS entry is not a full share extension payload (abi-encoded ShareCertData)"
                    );
                }
                extensionData[i] = supplied;
                continue;
            }

            if (printer.isVoided(sourceTokenIds[i])) {
                revert("Source certificate is voided");
            }
            CertificateDetails memory source = printer.getActiveCertificateDetails(sourceTokenIds[i]);
            if (source.extensionData.length == 0) {
                revert("Source certificate has no extension data");
            }
            extensionData[i] = source.extensionData;
        }
        if (sourcelessUsed != sourcelessTerms.length) {
            revert("Unconsumed SOURCELESS_TERMS entries");
        }

        // Completeness check: validating only the supplied array is not enough. 4.2 fails closed
        // on every legacy SHARE printer, so one omitted from CERT_PRINTERS would come out of this
        // "successful" upgrade with issuance, assignment, secondary transfers, and scrip
        // operations reverting. Enumerate the manager's full printer roster and refuse to
        // broadcast unless every legacy SHARE printer is either in the migration batch or
        // already carries a controller.
        bytes32 shareType = keccak256("SHARE");
        for (uint256 i = 0;; i++) {
            address enumerated;
            try issuanceManager.printers(i) returns (address p) {
                enumerated = p;
            } catch {
                break;
            }
            address ext = LedgerEntryToken(enumerated).getExtension(0);
            if (ext == address(0) || ext.code.length == 0) continue;
            (bool ok, bytes memory ret) =
                ext.staticcall(abi.encodeCall(ICertificateExtension.supportsExtensionType, (shareType)));
            if (!ok || ret.length < 32 || !abi.decode(ret, (bool))) continue;
            // A controller-backed printer only counts as migrated when its class state is
            // CONFIGURED: an installed-but-unconfigured controller still fails closed on every
            // lifecycle call, and omitting such a printer here would report a successful upgrade
            // that leaves it unusable — including it lets the migration loop configure it.
            (bool isController, bytes memory ctRet) =
                ext.staticcall(abi.encodeCall(IShareClassTermsController.getClassTerms, (enumerated)));
            if (isController && ctRet.length >= 160) {
                (,,,, bool configured) = abi.decode(ctRet, (bytes, bytes32, uint256, uint256, bool));
                if (configured) continue;
            }
            bool included = false;
            for (uint256 j = 0; j < printers.length; ++j) {
                if (printers[j] == enumerated) {
                    included = true;
                    break;
                }
            }
            if (!included) {
                console2.log("Legacy SHARE printer missing from CERT_PRINTERS:", enumerated);
                revert("Legacy SHARE printer omitted from migration batch");
            }
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
