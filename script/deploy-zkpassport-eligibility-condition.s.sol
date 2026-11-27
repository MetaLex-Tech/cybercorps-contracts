// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {EligibilityRules} from "../src/interfaces/IZKPassportEligibilityCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ZKPassportEligibilityCondition} from "../src/libs/conditions/ZKPassportEligibilityCondition.sol";
import {ZKPassportEligibilityConditionFactory} from "../src/libs/conditions/ZKPassportEligibilityConditionFactory.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";

interface IZKPassportRootVerifierHelpers {
    function helpers(bytes32 version) external view returns (address);
}

/// @title Deploy ZKPassportEligibilityCondition implementation and factory
/// @notice Deterministically deploys ZKPassportEligibilityCondition, ZKPassportEligibilityConditionFactory,
///         and the UUPS ERC1967Proxy for the factory using Foundry's standard CREATE2 deployer.
///
///         Ownership and security invariants:
///         - Uses the chain's existing core BorgAuth (DeploymentConstants.coreV2(chainId).auth).
///           The deployer receives zero role; MetaLeX Safe holds OWNER_ROLE on Ethereum, Base, and Sepolia.
///         - Sets devModeAllowed = true ONLY on testnets (Sepolia) and false on production chains
///           (Ethereum and Base), closing Hexens MTLX1-33.
///         - Refuses chains without a deployed ZKPassportRootVerifier or v0.21.0 VerifierHelper.
///         - Idempotent: re-running skips contracts already present at their CREATE2 addresses.
///         - Produces identical deterministic addresses on Ethereum and Base.
///
///         Simulate (no broadcast):
///           forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url base
///
///         Broadcast with your own signer:
///           forge script script/deploy-zkpassport-eligibility-condition.s.sol --rpc-url sepolia --account <name> --broadcast
contract DeployZKPassportEligibilityConditionScript is Script {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev ZKPassport v0.21.0 version key; first helper version exposing getNullifierType.
    bytes32 public constant REQUIRED_ZKPASSPORT_VERSION =
        0x0000001500000000000000000000000000000000000000000000000000000000;

    bytes32 public constant CONDITION_IMPL_SALT =
        keccak256("MetaLexCyberCorp.ZKPassportEligibilityCondition.Impl.V1.0");
    bytes32 public constant FACTORY_IMPL_SALT =
        keccak256("MetaLexCyberCorp.ZKPassportEligibilityConditionFactory.Impl.V1.0");
    bytes32 public constant FACTORY_PROXY_SALT =
        keccak256("MetaLexCyberCorp.ZKPassportEligibilityConditionFactory.Proxy.V1.0");

    uint256 public constant DEFAULT_MAX_VALIDITY_PERIOD = 30 days;
    string public constant PRODUCTION_DOMAIN = "cyberraise.metalex.tech";
    string public constant SEPOLIA_DOMAIN = "staging.cyberraise.metalex.tech";

    struct DeployConfig {
        uint256 chainId;
        address auth;
        address metalexSafe;
        address verifier;
        string expectedDomain;
        uint256 defaultMaxValidityPeriod;
        bool devModeAllowed;
    }

    struct Deployed {
        address conditionImpl;
        address factoryImpl;
        address factoryProxy;
    }

    function configForChain(uint256 chainId) public pure returns (DeployConfig memory cfg) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        require(core.auth != address(0), "No core BorgAuth on this chain");
        require(core.zkpassportVerifier != address(0), "No ZKPassportVerifier configured on this chain");

        bool isTestnet = DeploymentConstants.isTestnet(chainId);
        cfg = DeployConfig({
            chainId: chainId,
            auth: core.auth,
            metalexSafe: core.metalexSafe,
            verifier: core.zkpassportVerifier,
            expectedDomain: isTestnet ? SEPOLIA_DOMAIN : PRODUCTION_DOMAIN,
            defaultMaxValidityPeriod: DEFAULT_MAX_VALIDITY_PERIOD,
            devModeAllowed: isTestnet
        });
    }

    function predictAddresses(DeployConfig memory cfg) public pure returns (Deployed memory predicted) {
        predicted.conditionImpl = Create2.computeAddress(
            CONDITION_IMPL_SALT, keccak256(type(ZKPassportEligibilityCondition).creationCode), CREATE2_DEPLOYER
        );
        predicted.factoryImpl = Create2.computeAddress(
            FACTORY_IMPL_SALT, keccak256(type(ZKPassportEligibilityConditionFactory).creationCode), CREATE2_DEPLOYER
        );
        bytes memory initData = abi.encodeCall(
            ZKPassportEligibilityConditionFactory.initialize,
            (
                cfg.auth,
                predicted.conditionImpl,
                cfg.expectedDomain,
                cfg.verifier,
                cfg.defaultMaxValidityPeriod,
                cfg.devModeAllowed
            )
        );
        bytes32 proxyInitCodeHash =
            keccak256(abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(predicted.factoryImpl, initData)));
        predicted.factoryProxy = Create2.computeAddress(FACTORY_PROXY_SALT, proxyInitCodeHash, CREATE2_DEPLOYER);
    }

    /// @notice Default entry point: uses the chain's standard domain (or ZKPASSPORT_DOMAIN env override on testnets).
    function run() public returns (Deployed memory deployed) {
        DeployConfig memory cfg = configForChain(block.chainid);
        string memory domainOverride = vm.envOr("ZKPASSPORT_DOMAIN", string(""));
        if (bytes(domainOverride).length > 0) {
            require(cfg.devModeAllowed, "ZKPASSPORT_DOMAIN override is allowed on testnets only");
            cfg.expectedDomain = domainOverride;
        }
        return runWithConfig(cfg);
    }

    /// @notice Deploy (or verify existing) implementation and factory using `cfg`.
    function runWithConfig(DeployConfig memory cfg) public returns (Deployed memory deployed) {
        require(block.chainid == cfg.chainId, "Chain ID mismatch");
        require(cfg.auth.code.length > 0, "Core BorgAuth has no code");
        require(cfg.verifier.code.length > 0, "ZKPassportVerifier has no code on this chain");

        // Confirm MetaLeX Safe holds OWNER_ROLE on Core BorgAuth.
        BorgAuth auth = BorgAuth(cfg.auth);
        require(auth.userRoles(cfg.metalexSafe) >= auth.OWNER_ROLE(), "MetaLeX Safe lacks OWNER_ROLE on Core BorgAuth");

        // Confirm live v0.21.0 VerifierHelper is deployed (exposes getNullifierType, isNationalityIn, isAgeAboveOrEqual).
        address v021Helper = IZKPassportRootVerifierHelpers(cfg.verifier).helpers(REQUIRED_ZKPASSPORT_VERSION);
        require(v021Helper != address(0) && v021Helper.code.length > 0, "ZKPassport v0.21.0 helper not deployed");

        Deployed memory predicted = predictAddresses(cfg);

        vm.startBroadcast();
        if (predicted.conditionImpl.code.length == 0) {
            address impl = address(new ZKPassportEligibilityCondition{salt: CONDITION_IMPL_SALT}());
            require(impl == predicted.conditionImpl, "Condition implementation address mismatch");
        }
        if (predicted.factoryImpl.code.length == 0) {
            address fImpl = address(new ZKPassportEligibilityConditionFactory{salt: FACTORY_IMPL_SALT}());
            require(fImpl == predicted.factoryImpl, "Factory implementation address mismatch");
        }
        if (predicted.factoryProxy.code.length == 0) {
            bytes memory initData = abi.encodeCall(
                ZKPassportEligibilityConditionFactory.initialize,
                (
                    cfg.auth,
                    predicted.conditionImpl,
                    cfg.expectedDomain,
                    cfg.verifier,
                    cfg.defaultMaxValidityPeriod,
                    cfg.devModeAllowed
                )
            );
            address proxy = address(new ERC1967Proxy{salt: FACTORY_PROXY_SALT}(predicted.factoryImpl, initData));
            require(proxy == predicted.factoryProxy, "Factory proxy address mismatch");
        }
        vm.stopBroadcast();

        deployed = predicted;
        _verifyDeployment(cfg, deployed);

        console2.log("==== ZKPassportEligibilityConditionFactory Config ====");
        console2.log("chainId:", cfg.chainId);
        console2.log("coreAuth:", cfg.auth);
        console2.log("metalexSafe:", cfg.metalexSafe);
        console2.log("verifier:", cfg.verifier);
        console2.log("v0.21.0 helper:", v021Helper);
        console2.log("expectedDomain:", cfg.expectedDomain);
        console2.log("defaultMaxValidityPeriod:", cfg.defaultMaxValidityPeriod);
        console2.log("devModeAllowed:", cfg.devModeAllowed);
        console2.log("==== Deployed ====");
        console2.log("ZKPassportEligibilityCondition impl:", deployed.conditionImpl);
        console2.log("ZKPassportEligibilityConditionFactory impl:", deployed.factoryImpl);
        console2.log("ZKPassportEligibilityConditionFactory proxy:", deployed.factoryProxy);
    }

    /// @notice Helper for Sepolia live proof rehearsal: deploys a sample GBR/USA 18+ condition and logs its scope.
    function deploySepoliaSampleCondition(address factoryAddress)
        public
        returns (address condition, string memory expectedScope)
    {
        require(DeploymentConstants.isTestnet(block.chainid), "Sample condition helper is for testnets only");
        ZKPassportEligibilityConditionFactory factory = ZKPassportEligibilityConditionFactory(factoryAddress);

        string[] memory allowed = new string[](2);
        allowed[0] = "GBR";
        allowed[1] = "USA";
        EligibilityRules memory rules = EligibilityRules({
            allowedNationalities: allowed,
            excludedNationalities: new string[](0),
            minimumAge: 18,
            enforceSanctions: false
        });

        vm.startBroadcast();
        condition = factory.deployCondition(rules, bytes32(0));
        vm.stopBroadcast();

        expectedScope = ZKPassportEligibilityCondition(condition).expectedScope();
        console2.log("==== Sepolia Sample Condition (GBR/USA, 18+, sanctions=false) ====");
        console2.log("condition:", condition);
        console2.log("expectedDomain:", ZKPassportEligibilityCondition(condition).expectedDomain());
        console2.log("expectedScope:", expectedScope);
    }

    function _verifyDeployment(DeployConfig memory cfg, Deployed memory deployed) internal view {
        require(deployed.conditionImpl.code.length > 0, "Condition impl missing code");
        require(deployed.factoryImpl.code.length > 0, "Factory impl missing code");
        require(deployed.factoryProxy.code.length > 0, "Factory proxy missing code");

        address actualFactoryImpl = address(uint160(uint256(vm.load(deployed.factoryProxy, IMPLEMENTATION_SLOT))));
        vm.assertEq(actualFactoryImpl, deployed.factoryImpl, "factory proxy implementation slot");

        ZKPassportEligibilityConditionFactory factory = ZKPassportEligibilityConditionFactory(deployed.factoryProxy);
        vm.assertEq(factory.DEPLOY_VERSION(), "1.0", "DEPLOY_VERSION");
        vm.assertEq(factory.implementation(), deployed.conditionImpl, "beacon implementation");
        vm.assertEq(address(factory.AUTH()), cfg.auth, "AUTH");
        vm.assertEq(factory.verifier(), cfg.verifier, "verifier");
        vm.assertEq(factory.expectedDomain(), cfg.expectedDomain, "expectedDomain");
        vm.assertEq(factory.defaultMaxValidityPeriod(), cfg.defaultMaxValidityPeriod, "defaultMaxValidityPeriod");
        vm.assertEq(factory.devModeAllowed(), cfg.devModeAllowed, "devModeAllowed");
    }
}
