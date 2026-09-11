// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {BorgAuth, BorgAuthACL} from "../src/libs/auth.sol";

import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script, console2} from "forge-std/Script.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice Re-upgrades the singleton proxies that MTLX1-26 and MTLX1-37 changed.
/// @dev Run this after `upgrade-v5.s.sol`. Only CyberCorpFactory (MTLX1-26) and
///      CyberAgreementRegistry (MTLX1-37) have new bytecode, so the other v5
///      implementations and the per-corp Safe batch stay as they are.
///      Two interface changes go live with this run. Update the off-chain callers
///      at the same time:
///      - CyberAgreementRegistry SIGNATUREDATA_TYPEHASH has a new `signer` field.
///        Signatures made under the old type hash stop working.
///      - CyberCorpFactory.deployCyberCorpWithRound takes a new `metadataSignature`
///        parameter and reverts without a valid officer signature.
contract UpgradeV5Mtlx1_26_37Script is Script {
    uint256 private constant ETHEREUM = 1;
    uint256 private constant BASE = 8453;
    uint256 private constant BASE_SEPOLIA = 84532;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct Implementations {
        address cyberCorpFactory;
        address registry;
    }

    struct Targets {
        address cyberCorpFactory;
        address registry;
        address legalDocRegistry;
    }

    function run() external {
        if (block.chainid != ETHEREUM && block.chainid != BASE && block.chainid != BASE_SEPOLIA) {
            revert("v5 upgrade supports Ethereum, Base and Base Sepolia only");
        }
        if (!vm.envOr("CONFIRM_V5_SINGLETON_UPGRADE", false)) {
            revert("Set CONFIRM_V5_SINGLETON_UPGRADE=true");
        }

        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        Targets memory targets = _targets();

        // Each proxy can point to its own BorgAuth. Check all of them first, so the
        // broadcast cannot stop part way.
        _requireOwner(targets.cyberCorpFactory, deployer, "CyberCorpFactory");
        _requireOwner(targets.registry, deployer, "CyberAgreementRegistry");
        if (targets.legalDocRegistry != address(0)) {
            _requireOwner(targets.legalDocRegistry, deployer, "LegalDocRegistry");
        }

        vm.startBroadcast(privateKey);
        Implementations memory impls = _deployImplementations();

        // LegalDocRegistry runs the same implementation as the main registry.
        _upgradeProxy(targets.registry, impls.registry, "CyberAgreementRegistry");
        if (targets.legalDocRegistry != address(0)) {
            _upgradeProxy(targets.legalDocRegistry, impls.registry, "LegalDocRegistry");
        } else {
            console2.log("LegalDocRegistry not set, skipping");
        }

        _upgradeProxy(targets.cyberCorpFactory, impls.cyberCorpFactory, "CyberCorpFactory");

        vm.stopBroadcast();
    }

    function _targets() internal view returns (Targets memory targets) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        targets.cyberCorpFactory = vm.envOr("CYBERCORP_FACTORY", core.cyberCorpFactory);
        targets.registry = vm.envOr("CYBER_AGREEMENT_REGISTRY", core.cyberAgreementRegistry);
        // Optional on Base Sepolia so a rehearsal works without a LegalDocRegistry deployment.
        targets.legalDocRegistry = block.chainid == BASE_SEPOLIA
            ? vm.envOr("LEGAL_DOC_REGISTRY", address(0))
            : vm.envAddress("LEGAL_DOC_REGISTRY");
    }

    function _deployImplementations() internal returns (Implementations memory impls) {
        impls.cyberCorpFactory = address(new CyberCorpFactory());
        impls.registry = address(new CyberAgreementRegistry());

        console2.log("V5 CyberCorpFactory:", impls.cyberCorpFactory);
        console2.log("V5 CyberAgreementRegistry:", impls.registry);
    }

    function _requireOwner(address proxy, address caller, string memory name) internal view {
        if (proxy == address(0)) revert("Missing proxy address");
        BorgAuth auth = BorgAuthACL(proxy).AUTH();
        if (auth.userRoles(caller) < auth.OWNER_ROLE()) {
            console2.log("PRIVATE_KEY_MAIN is not the AUTH owner of", name, proxy);
            revert("PRIVATE_KEY_MAIN is not the AUTH owner");
        }
    }

    function _upgradeProxy(address proxy, address implementation, string memory name) internal {
        if (proxy == address(0)) revert("Missing proxy address");
        IUUPS(proxy).upgradeToAndCall(implementation, "");
        if (_implementationOf(proxy) != implementation) {
            revert("Implementation slot mismatch");
        }
        console2.log("Upgraded", name, proxy);
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
