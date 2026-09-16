// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface IDeploymentNamespace {
    function deploymentSalt(bytes32 salt, address deployer) external pure returns (bytes32);
}

/// @notice Stateless helpers for permissionless factory deployment.
library FactoryDeploymentLib {
    error IncompatibleComponentFactory(address factory);

    /// @dev Every caller has its own CREATE2 namespace, without a deployment role.
    function deploymentSalt(bytes32 salt, address deployer) internal pure returns (bytes32) {
        return keccak256(abi.encode(deployer, salt));
    }

    /// @dev Reject partial upgrades that would still allow direct salt squatting.
    function requireNamespace(address factory, bytes32 salt) internal view {
        (bool ok, bytes memory result) = factory.staticcall(
            abi.encodeCall(IDeploymentNamespace.deploymentSalt, (salt, address(this)))
        );
        if (!ok || result.length != 32 || abi.decode(result, (bytes32)) != deploymentSalt(salt, address(this))) {
            revert IncompatibleComponentFactory(factory);
        }
    }

    function requireNamespaces(address[4] memory factories, bytes32 salt) internal view {
        for (uint256 i; i < factories.length; ++i) requireNamespace(factories[i], salt);
    }
}
