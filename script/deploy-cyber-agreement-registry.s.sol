// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {ParentCoFactory} from "../src/ParentCoFactory.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployCyberAgreementRegistryScript is Script {

    error UnexpectedChainId(uint256 chainId);

    function run() public returns (CyberAgreementRegistry registry) {
        // staging
        return runWithArgs({
            chainId: DeploymentConstants.BASE_SEPOLIA,
            deployerPrivateKey: vm.envUint("PRIVATE_KEY_MAIN"),
            saltStr: "CyberAgreementRegistry.encryption.v1.dev0",
            auth: BorgAuth(address(0)) // deploy a new one
        });
    }

    function runWithArgs(
        uint256 chainId,
        uint256 deployerPrivateKey,
        string memory saltStr,
        BorgAuth auth // if provided, use it instead of deploying a new one
    ) public returns (CyberAgreementRegistry registry) {
        if (block.chainid != chainId) {
            revert UnexpectedChainId(block.chainid);
        }

        address deployerAddress = vm.addr(deployerPrivateKey);
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        console2.log("==== Configs ====");
        console2.log("chain ID: %d", chainId);
        console2.log("deployer: %s", deployerAddress);
        console2.log("saltStr: %s", saltStr);
        console2.log("auth: %s", address(auth));
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        bool deployAuth = auth == BorgAuth(address(0));

        if (deployAuth) {
            auth = new BorgAuth{salt: salt}(deployerAddress);
        }

        registry = CyberAgreementRegistry(address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        ));

        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        if (deployAuth) {
            console2.log("Auth:", address(auth));
        }
        console2.log("CyberAgreementRegistry:", address(registry));
        console2.log("");
    }
}
