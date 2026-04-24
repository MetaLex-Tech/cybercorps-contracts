// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

/// @notice Deploy a new `IssuanceManager` implementation and set it as the
///         reference implementation on `IssuanceManagerFactory` (used for new
///         ERC1967 proxy deployments and `computeIssuanceManagerAddress`).
/// @dev Uses `DeploymentConstants.coreV2` for defaults; override with env vars.
///      Requires `PRIVATE_KEY_MAIN` for an address with `AUTH.OWNER_ROLE()`.
contract UpgradeIssuanceManagerRefScript is Script {
    bytes32 internal constant UPGRADE_SALT =
        keccak256("MetaLexCyberCorp.IssuanceManager.RefUpgrade.1");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(block.chainid);

        address issuanceManagerFactoryAddr = vm.envOr(
            "ISSUANCE_MANAGER_FACTORY",
            address(0)
        );
        if (issuanceManagerFactoryAddr == address(0)) {
            address cyberCorpFactoryProxyAddr = vm.envOr(
                "CYBERCORP_FACTORY",
                deployment.cyberCorpFactory
            );
            issuanceManagerFactoryAddr = CyberCorpFactory(
                cyberCorpFactoryProxyAddr
            ).issuanceManagerFactory();
        }

        IssuanceManagerFactory issuanceManagerFactory = IssuanceManagerFactory(
            issuanceManagerFactoryAddr
        );
        address auth = address(issuanceManagerFactory.AUTH());

        uint256 role = BorgAuth(auth).userRoles(deployer);
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to run upgrades"
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        address newIssuanceManagerImpl = address(
            new IssuanceManager{salt: UPGRADE_SALT}()
        );
        console2.log(
            "New IssuanceManager implementation:",
            newIssuanceManagerImpl
        );

        address oldRef = issuanceManagerFactory.getRefImplementation();
        console2.log("IssuanceManagerFactory:", issuanceManagerFactoryAddr);
        console2.log("  previous ref implementation:", oldRef);

        issuanceManagerFactory.setRefImplementation(newIssuanceManagerImpl);

        vm.assertEq(
            issuanceManagerFactory.getRefImplementation(),
            newIssuanceManagerImpl,
            "IssuanceManagerFactory reference implementation mismatch"
        );

        console2.log("  new ref implementation:", newIssuanceManagerImpl);

        vm.stopBroadcast();
    }
}
