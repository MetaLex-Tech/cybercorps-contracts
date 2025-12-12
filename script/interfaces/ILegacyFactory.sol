pragma solidity 0.8.28;

interface ILegacyFactory {
    function beacon() external view returns (address);

    function getBeaconImplementation() external view returns (address);

    function upgradeImplementation(address _newImplementation) external;
}
