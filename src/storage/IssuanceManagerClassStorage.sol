// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../CyberCorpConstants.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/ILedgerEntryToken.sol";
import "../interfaces/IShareClassTermsController.sol";
import "./IssuanceManagerStorage.sol";

/// @title IssuanceManagerClassStorage - cold-path class administration, delegatecalled
/// @author MetaLeX Labs, Inc.
/// @notice Carries the security-class registry mutators and the class-terms controller
///         administration that IssuanceManagerStorage can no longer hold: the merged
///         IssuanceManagerStorage library crossed the EIP-170 runtime limit, and these
///         are the cold administrative entry points (owner-gated, called rarely), so they
///         live in a second linked library. Same storage, same manager context — both
///         libraries are delegatecalled by the IssuanceManager, so `address(this)` and
///         the namespaced storage slot are identical across them.
library IssuanceManagerClassStorage {
    /// @notice Registers a new class; classIds are sequential starting at 1 (0 = unclassified).
    function executeDefineSecurityClass(
        SecurityClass classType,
        string memory documentURI,
        address dataExtension,
        bytes memory classData
    ) external returns (uint256 classId) {
        IssuanceManagerStorage.IssuanceManagerData storage s = IssuanceManagerStorage.issuanceManagerStorage();
        if (s.classIdByType[classType] != 0) revert IssuanceManagerStorage.SecurityClassAlreadyDefined();
        classId = ++s.securityClassCount;
        s.securityClasses[classId] = SecurityClassInfo(classType, documentURI, dataExtension, classData);
        s.classIdByType[classType] = classId;
        emit IIssuanceManager.SecurityClassDefined(classId, classType, documentURI, dataExtension);
    }

    function executeUpdateSecurityClass(
        uint256 classId,
        SecurityClass classType,
        string memory documentURI,
        address dataExtension,
        bytes memory classData
    ) external {
        IssuanceManagerStorage.IssuanceManagerData storage s = IssuanceManagerStorage.issuanceManagerStorage();
        if (classId == 0 || classId > s.securityClassCount) revert IssuanceManagerStorage.ClassDoesNotExist();
        // Re-index classIdByType when the type changes, otherwise the reverse index keeps pointing at the
        // old type and the new type reads as undefined, letting a second class be created for it.
        SecurityClass oldType = s.securityClasses[classId].classType;
        if (classType != oldType) {
            if (s.classIdByType[classType] != 0) revert IssuanceManagerStorage.SecurityClassAlreadyDefined();
            delete s.classIdByType[oldType];
            s.classIdByType[classType] = classId;
        }
        s.securityClasses[classId] = SecurityClassInfo(classType, documentURI, dataExtension, classData);
        emit IIssuanceManager.SecurityClassUpdated(classId, classType, documentURI, dataExtension);
    }

    /// @notice Assigns a printer (the series scope) to a class; classId 0 clears the assignment.
    /// Also the backfill path for printers created before the class registry existed.
    function executeSetPrinterClass(address printer, uint256 classId) external {
        IssuanceManagerStorage.IssuanceManagerData storage s = IssuanceManagerStorage.issuanceManagerStorage();
        if (!IssuanceManagerStorage.isPrinter(printer)) revert IssuanceManagerStorage.NotAPrinter();
        if (classId > s.securityClassCount) revert IssuanceManagerStorage.ClassDoesNotExist();
        s.printerClassIds[printer] = classId;
        emit IIssuanceManager.PrinterClassAssigned(printer, classId);
    }

    function executeMigrateClassTermsControllers(
        address[] calldata certAddresses,
        address controller,
        bytes[] calldata extensionData
    ) external {
        if (certAddresses.length != extensionData.length) {
            revert IssuanceManagerStorage.ClassTermsMigrationLengthMismatch();
        }
        for (uint256 i = 0; i < certAddresses.length; ++i) {
            address certAddress = certAddresses[i];
            ILedgerEntryToken printer = ILedgerEntryToken(certAddress);
            address currentExtension = printer.getExtension(0);
            if (currentExtension != controller) {
                (bool isController,) =
                    currentExtension.staticcall(abi.encodeCall(IShareClassTermsController.getClassTerms, (certAddress)));
                if (currentExtension.code.length != 0 && isController) {
                    revert IssuanceManagerStorage.ClassTermsControllerAlreadyInstalled();
                }
                printer.setExtension(0, controller);
            }
            IShareClassTermsController(controller).configureClassTerms(certAddress, extensionData[i]);
        }
    }

    function executeAmendClassTerms(address certAddress, bytes calldata extensionData) external {
        address controller = ILedgerEntryToken(certAddress).getExtension(0);
        IShareClassTermsController(controller).amendClassTerms(certAddress, extensionData);
    }
}
