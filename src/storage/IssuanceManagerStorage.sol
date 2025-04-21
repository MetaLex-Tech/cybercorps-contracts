// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

library IssuanceManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.issuancemanager.storage.v1");

    // Main storage layout struct
    struct IssuanceManagerData {
        UpgradeableBeacon CyberCertPrinterBeacon;
        address CORP;
        address uriBuilder;
        address[] printers;
    }

    // Returns the storage layout
    function issuanceManagerStorage() internal pure returns (IssuanceManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getCORP() internal view returns (address) {
        return issuanceManagerStorage().CORP;
    }

    function getUriBuilder() internal view returns (address) {
        return issuanceManagerStorage().uriBuilder;
    }

    function getCyberCertPrinterBeacon() internal view returns (UpgradeableBeacon) {
        return issuanceManagerStorage().CyberCertPrinterBeacon;
    }

    function getPrinters() internal view returns (address[] storage) {
        return issuanceManagerStorage().printers;
    }

    // Setters
    function setCORP(address _corp) internal {
        issuanceManagerStorage().CORP = _corp;
    }

    function setUriBuilder(address _uriBuilder) internal {
        issuanceManagerStorage().uriBuilder = _uriBuilder;
    }

    function setCyberCertPrinterBeacon(UpgradeableBeacon _beacon) internal {
        issuanceManagerStorage().CyberCertPrinterBeacon = _beacon;
    }

    function addPrinter(address _printer) internal {
        issuanceManagerStorage().printers.push(_printer);
    }

    // Beacon upgrade function
    function updateBeaconImplementation(address _newImplementation) internal {
        issuanceManagerStorage().CyberCertPrinterBeacon.upgradeTo(_newImplementation);
    }
} 