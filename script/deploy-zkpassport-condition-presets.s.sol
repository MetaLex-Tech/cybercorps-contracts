// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {NonUSNationalityCondition} from "../src/libs/conditions/NonUSNationalityCondition.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy zkPassport condition presets
/// @notice Deploys new NonUSNationalityCondition proxies that differ from the chain's default condition only in
///         the excluded country list and the scope. Each proxy uses the default condition's implementation,
///         BorgAuth, domain, verifier and maximum validity, read from the chain at run time. No new contract
///         code is deployed, and the deployer gets no role: control stays with the default's BorgAuth (the
///         MetaLeX Safe on Ethereum and Base).
///
///         Presets (lists must be sorted alphabetically: the zkPassport helper compares them in order):
///         - Embargo screen: excludes CUB, IRN, PRK (OFAC FAQ 10 country-wide embargoes); U.S. investors allowed.
///         - Sanctions screen: excludes no nationality; only the sanctions-list check applies.
///
///         Run without --broadcast to simulate. Broadcast with your own signer, for example:
///         forge script script/deploy-zkpassport-condition-presets.s.sol --rpc-url base --account <name> --broadcast
contract DeployZkPassportConditionPresetsScript is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    string internal constant SALT_PREFIX = "MetaLexCyberCorp.ZkpassportConditionPreset.V1.2.0.";

    struct Preset {
        string name;
        string scope;
        string[] excludedCountries;
    }

    struct Deployed {
        address embargoScreen;
        address sanctionsScreen;
    }

    function run() public returns (Deployed memory deployed) {
        return runWithDefault(defaultCondition(block.chainid));
    }

    /// @notice The chain's default condition, which the app attaches to new non-U.S. rounds.
    function defaultCondition(uint256 chainId) public pure returns (address condition) {
        condition = DeploymentConstants.coreV2(chainId).zkpassportCondition;
        require(condition != address(0), "No default zkPassport condition on this chain");
    }

    function presets() public pure returns (Preset[2] memory list) {
        string[] memory embargo = new string[](3);
        embargo[0] = "CUB";
        embargo[1] = "IRN";
        embargo[2] = "PRK";
        list[0] = Preset({name: "EmbargoScreen", scope: "embargo-screen", excludedCountries: embargo});
        list[1] = Preset({name: "SanctionsScreen", scope: "sanctions-screen", excludedCountries: new string[](0)});
    }

    function runWithDefault(address defaultAddress) public returns (Deployed memory deployed) {
        NonUSNationalityCondition source = NonUSNationalityCondition(defaultAddress);
        address implementation = address(uint160(uint256(vm.load(defaultAddress, IMPLEMENTATION_SLOT))));
        require(implementation.code.length > 0, "Default condition has no implementation");

        address auth = address(source.AUTH());
        string memory domain = source.expectedDomain();
        address verifier = address(source.verifier());
        uint256 maxValidityPeriod = source.maxValidityPeriod();

        Preset[2] memory list = presets();
        address[2] memory addresses;

        vm.startBroadcast();
        for (uint256 i = 0; i < list.length; i++) {
            bytes32 salt = keccak256(bytes(string.concat(SALT_PREFIX, list[i].name)));
            addresses[i] = address(
                new ERC1967Proxy{salt: salt}(
                    implementation,
                    abi.encodeCall(
                        NonUSNationalityCondition.initialize,
                        (auth, domain, list[i].scope, verifier, maxValidityPeriod, list[i].excludedCountries)
                    )
                )
            );
        }
        vm.stopBroadcast();

        for (uint256 i = 0; i < list.length; i++) {
            _check(addresses[i], implementation, auth, domain, verifier, maxValidityPeriod, list[i]);
        }

        deployed = Deployed({embargoScreen: addresses[0], sanctionsScreen: addresses[1]});

        console2.log("==== Source (default condition) ====");
        console2.log("chainId:", block.chainid);
        console2.log("default condition:", defaultAddress);
        console2.log("implementation:", implementation);
        console2.log("auth:", auth);
        console2.log("domain:", domain);
        console2.log("maxValidityPeriod:", maxValidityPeriod);
        console2.log("==== Deployed ====");
        console2.log("Embargo screen (CUB, IRN, PRK):", deployed.embargoScreen);
        console2.log("Sanctions screen (no nationality list):", deployed.sanctionsScreen);
    }

    function _check(
        address condition,
        address implementation,
        address auth,
        string memory domain,
        address verifier,
        uint256 maxValidityPeriod,
        Preset memory preset
    ) internal view {
        NonUSNationalityCondition deployed = NonUSNationalityCondition(condition);
        vm.assertEq(
            address(uint160(uint256(vm.load(condition, IMPLEMENTATION_SLOT)))), implementation, "implementation"
        );
        vm.assertEq(address(deployed.AUTH()), auth, "auth");
        vm.assertEq(deployed.expectedDomain(), domain, "domain");
        vm.assertEq(deployed.expectedScope(), preset.scope, "scope");
        vm.assertEq(address(deployed.verifier()), verifier, "verifier");
        vm.assertEq(deployed.maxValidityPeriod(), maxValidityPeriod, "maxValidityPeriod");
        for (uint256 i = 0; i < preset.excludedCountries.length; i++) {
            vm.assertEq(deployed.excludedCountries(i), preset.excludedCountries[i], "excludedCountries");
        }
        // The list ends where the getter reverts.
        (bool ok,) =
            condition.staticcall(abi.encodeWithSignature("excludedCountries(uint256)", preset.excludedCountries.length));
        vm.assertFalse(ok, "excludedCountries is longer than the preset");
    }
}
