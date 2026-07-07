// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IssuanceManager} from "../../src/IssuanceManager.sol";
import {IssuanceManagerStorage} from "../../src/storage/IssuanceManagerStorage.sol";
import {IIssuanceManagerFactory} from "../../src/interfaces/IIssuanceManagerFactory.sol";

/// @dev Test-only migration helper; kept out of src/ because IssuanceManager is at the EIP-170 size limit.
contract IssuanceManagerWithMigration is IssuanceManager {
    address public constant NEW_UPGRADE_FACTORY = 0xD353972D7955F421d94d0eA8c42c88c417F7155A;

    /// @notice Migrate legacy contracts and set upgradeFactory to the known new contract (for reference implementation lookup)
    /// Also migrate its beacons for CyberCertPrinter and CyberScrip to new reference implementations
    function migrateUpgradeFactory() public {
        IssuanceManagerStorage.setUpgradeFactory(NEW_UPGRADE_FACTORY);

        address cyberCertPrinterRefImpl = IIssuanceManagerFactory(NEW_UPGRADE_FACTORY)
            .getCyberCertPrinterRefImplementation();
        IssuanceManagerStorage.upgradeCertPrinterBeaconImplementation(cyberCertPrinterRefImpl);
        emit CertPrinterBeaconImplementationUpgraded(cyberCertPrinterRefImpl);

        address cyberScripRefImpl = IIssuanceManagerFactory(NEW_UPGRADE_FACTORY).getCyberScripRefImplementation();
        if (address(IssuanceManagerStorage.getCyberScripBeacon()) == address(0)) {
            UpgradeableBeacon beaconScrip = new UpgradeableBeacon(cyberScripRefImpl, address(this));
            IssuanceManagerStorage.setCyberScripBeacon(beaconScrip);
            emit ScripBeaconImplementationUpgraded(cyberScripRefImpl);
        } else {
            IssuanceManagerStorage.updateScripBeaconImplementation(cyberScripRefImpl);
            emit ScripBeaconImplementationUpgraded(cyberScripRefImpl);
        }
    }
}
