// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementJson, CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {Script, console2} from "forge-std/Script.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @notice Deploy the creator-bound registry implementation; export the upgrade for a separate Safe execution.
/// @dev Forge deploys/links CyberAgreementJson using its configured sender/wallet. Only CREATE is broadcast here.
///      Writes Safe Transaction Builder JSON directly, like deploy-parentco-factory and DeploymentScript.finish.
contract DeployBoundAgreementRegistryScript is Script {
    error WrongChain(uint256 expected, uint256 actual);

    function run() external returns (address) {
        return runForChain(block.chainid);
    }

    function runForChain(uint256 expectedChain) public returns (address) {
        if (expectedChain != block.chainid) revert WrongChain(expectedChain, block.chainid);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(expectedChain);
        require(core.metalexSafe.code.length > 0, "Configured Safe has no code; use explicit testnet authority");
        return runWithArgs(expectedChain, core.cyberAgreementRegistry, core.metalexSafe, outputPrefix(expectedChain));
    }

    function outputPrefix(uint256 chainId) public pure virtual returns (string memory) {
        return string.concat("script/res/gnosis-batch-bound-registry-", vm.toString(chainId));
    }

    /// @notice Explicit targets for testnet owners or isolated rehearsals. `prefix` must be in script/res/.
    /// @dev Use a unique prefix per deployment attempt. The upgrade is simulated then reverted, never broadcast.
    function runWithArgs(uint256 expectedChain, address proxy, address authority, string memory prefix)
        public
        returns (address implementation)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        if (expectedChain != block.chainid) revert WrongChain(expectedChain, block.chainid);
        require(proxy.code.length > 0, "Registry proxy has no code");
        address previous = implementationOf(proxy);
        require(previous.code.length > 0, "Registry is not an implementation proxy");
        CyberAgreementRegistry registry = CyberAgreementRegistry(proxy);
        address auth = address(registry.AUTH());
        require(auth.code.length > 0, "Registry AUTH has no code");
        require(authority != address(0), "Zero upgrade authority");
        BorgAuth(auth).onlyRole(BorgAuth(auth).OWNER_ROLE(), authority);
        bytes32 domain = registry.DOMAIN_SEPARATOR();
        bytes32 signatureTypehash = registry.SIGNATUREDATA_TYPEHASH();
        bytes32 versionHash = keccak256(bytes(registry.version()));
        address jsonLibrary = address(CyberAgreementJson);
        require(jsonLibrary.code.length > 0, "JSON library has no code");

        // Even an owner deployer must submit the upgrade separately through the Safe.
        vm.broadcast(deployerPrivateKey);
        implementation = address(new CyberAgreementRegistry());
        require(implementation.code.length <= 24_576, "Registry exceeds EIP-170 size limit");
        bytes memory data = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, bytes("")));

        uint256 snapshot = vm.snapshotState();
        vm.prank(authority);
        (bool ok, bytes memory result) = proxy.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
        require(implementationOf(proxy) == implementation, "Upgrade simulation did not change implementation");
        require(address(registry.AUTH()) == auth, "Upgrade changed AUTH");
        require(registry.DOMAIN_SEPARATOR() == domain, "Upgrade changed EIP-712 domain");
        require(
            registry.SIGNATUREDATA_TYPEHASH() == signatureTypehash,
            "Signature schema migration requires separate review"
        );
        require(keccak256(bytes(registry.version())) == versionHash, "Upgrade changed version");
        require(
            registry.BOUND_TEMPLATE_DOMAIN() == keccak256("MetaLeX.CyberAgreementRegistry.BoundTemplate.v1"),
            "Wrong release"
        );
        // Exercise the external library through delegatecall from the upgraded proxy.
        require(bytes(registry.getContractJson(bytes32(0))).length > 0, "JSON rendering failed");
        require(vm.revertToStateAndDelete(snapshot), "Could not restore simulation state");
        require(implementationOf(proxy) == previous, "Proxy changed outside Safe execution");

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](1);
        safeTxs[0] = GnosisTransaction({to: proxy, value: 0, data: data});
        string memory safeTxJson = DeploymentUtils.formatSafeTxJson(safeTxs, block.chainid);
        string memory path = string.concat(prefix, ".json");
        vm.writeFile(path, safeTxJson);
        console2.log("CyberAgreementJson:", jsonLibrary);
        console2.log("New implementation:", implementation);
        console2.log("Previous implementation (still active):", previous);
        console2.log("Registry proxy:", proxy);
        console2.log("Upgrade authority:", authority);
        console2.log("Safe tx JSON (can be imported to Safe Transaction Builder after successful deployment):");
        console2.log("==== JSON data start ====");
        console2.log(safeTxJson);
        console2.log("==== JSON data end ====");
        console2.log("Safe batch written to:", path);
    }

    function implementationOf(address proxy) public view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }
}
