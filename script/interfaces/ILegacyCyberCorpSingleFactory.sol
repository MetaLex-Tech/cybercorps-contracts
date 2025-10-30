pragma solidity 0.8.28;

interface ILegacyCyberCorpSingleFactory {
    function getBeaconImplementation() external view returns (address);

    function upgradeImplementation(address _newImplementation) external;
}
