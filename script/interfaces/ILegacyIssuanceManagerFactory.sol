pragma solidity 0.8.28;

import {ILegacyFactory} from "./ILegacyFactory.sol";

interface ILegacyIssuanceManagerFactory is ILegacyFactory {
    function upgradePrinterBeaconAt(address issuanceManager, address _newImplementation) external;
}
