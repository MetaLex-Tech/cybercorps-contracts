// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {
    K_ACCREDITED,
    K_INVESTOR_JURISDICTION,
    K_INVESTOR_TYPE,
    K_NON_US,
    K_QIB,
    K_QP,
    K_SPV_WHITELIST,
    K_SYNDICATE
} from "../src/interfaces/ILexChexBadge.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CFIUSCondition} from "../src/libs/conditions/secondary/CFIUSCondition.sol";
import {EligibilityCondition} from "../src/libs/conditions/secondary/EligibilityCondition.sol";
import {GPLPApprovalCondition} from "../src/libs/conditions/secondary/GPLPApprovalCondition.sol";
import {HolderCapCondition} from "../src/libs/conditions/secondary/HolderCapCondition.sol";
import {HoldingPeriodCondition} from "../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {KillSwitchCondition} from "../src/libs/conditions/secondary/KillSwitchCondition.sol";
import {LegalOpinionCondition} from "../src/libs/conditions/secondary/LegalOpinionCondition.sol";
import {LegionSoulboundCondition} from "../src/libs/conditions/secondary/LegionSoulboundCondition.sol";
import {LexChexBadgeKindCondition} from "../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {RegSDistributionComplianceCondition} from
    "../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {Rule144DisclosureCondition} from "../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {Section4a7DisclosureCondition} from "../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {TimeSettlementPeriodCondition} from "../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
import {USStateOfResidenceCondition} from "../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys the shared secondary-trading condition singletons.
/// @dev Each condition is one instance for the whole chain, configured per SPV. The script is
///      idempotent against DeploymentConstants: a recorded proxy keeps its address and takes the
///      new code, a zero field gets a new proxy. Record every printed address afterwards.
contract DeploySecondaryConditionsScript is Script {
    /// @dev Rule 144(d): one year of holding for a non-reporting issuer.
    uint256 private constant HOLDING_PERIOD = 365 days;
    /// @dev Rule 144(c)(2) practice: a balance sheet no older than 16 months.
    uint256 private constant DISCLOSURE_MAX_AGE = 480 days;
    /// @dev Facts the LeXcheX v1 minter bridges into a badge credential.
    uint256 private constant MINTER_ISSUER_KEYS = K_ACCREDITED | K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;

    /// @dev Values every condition initializer needs.
    struct Context {
        bytes32 salt;
        address auth;
        address registry;
        address badge;
    }

    function run() public returns (DeploymentConstants.SecondaryConditionDeployment memory deployed) {
        return runWithArgs(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-SecondaryConditionsV1.0.0",
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-SecondaryConditionsV1.0.0",
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.SecondaryConditionDeployment memory deployed) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 salt = keccak256(bytes(saltStr));

        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        DeploymentConstants.SecondaryConditionDeployment memory recorded =
            DeploymentConstants.secondaryConditions(chainId);

        // The two keys are the whole governance surface of the kill switch, so both are explicit.
        address metalexKillAdmin = vm.envAddress("KILL_SWITCH_METALEX_MOCK");
        address legionKillAdmin = vm.envAddress("KILL_SWITCH_LEGION_MOCK");

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("AUTH:", core.auth);
        console2.log("CyberAgreementRegistry:", core.cyberAgreementRegistry);
        console2.log("kill switch MetaLeX admin:", metalexKillAdmin);
        console2.log("kill switch Legion admin:", legionKillAdmin);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        Context memory ctx = Context({
            salt: salt,
            auth: core.auth,
            registry: core.cyberAgreementRegistry,
            badge: _badge(core, salt, deployerAddress)
        });
        _deployThresholdConditions(ctx, recorded, deployed);
        _deployBadgeKindConditions(ctx, recorded, deployed);
        _deployClosingConditions(ctx, recorded, deployed, metalexKillAdmin, legionKillAdmin);
        vm.stopBroadcast();

        _logDeployed(ctx.badge, deployed);
    }

    /// @dev The conditions that read no credential, plus the three that read one through a badge.
    function _deployThresholdConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
    ) internal {
        deployed.eligibility = _deployOrUpgrade(
            recorded.eligibility,
            address(new EligibilityCondition{salt: ctx.salt}()),
            abi.encodeCall(EligibilityCondition.initialize, (ctx.auth)),
            ctx.salt
        );
        deployed.usStateOfResidence = _deployOrUpgrade(
            recorded.usStateOfResidence,
            address(new USStateOfResidenceCondition{salt: ctx.salt}()),
            abi.encodeCall(USStateOfResidenceCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.salt
        );
        deployed.legionSoulbound = _deployOrUpgrade(
            recorded.legionSoulbound,
            address(new LegionSoulboundCondition{salt: ctx.salt}()),
            abi.encodeCall(LegionSoulboundCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.salt
        );
        deployed.holderCap = _deployOrUpgrade(
            recorded.holderCap,
            address(new HolderCapCondition{salt: ctx.salt}()),
            abi.encodeCall(HolderCapCondition.initialize, (ctx.auth)),
            ctx.salt
        );
        deployed.cfius = _deployOrUpgrade(
            recorded.cfius,
            address(new CFIUSCondition{salt: ctx.salt}()),
            abi.encodeCall(CFIUSCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.salt
        );
        deployed.section4a7Disclosure = _deployOrUpgrade(
            recorded.section4a7Disclosure,
            address(new Section4a7DisclosureCondition{salt: ctx.salt}()),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (ctx.auth, ctx.registry, DISCLOSURE_MAX_AGE)),
            ctx.salt
        );
        deployed.rule144Disclosure = _deployOrUpgrade(
            recorded.rule144Disclosure,
            address(new Rule144DisclosureCondition{salt: ctx.salt}()),
            abi.encodeCall(Rule144DisclosureCondition.initialize, (ctx.auth, DISCLOSURE_MAX_AGE)),
            ctx.salt
        );
        deployed.holdingPeriod = _deployOrUpgrade(
            recorded.holdingPeriod,
            address(new HoldingPeriodCondition{salt: ctx.salt}()),
            abi.encodeCall(HoldingPeriodCondition.initialize, (ctx.auth, HOLDING_PERIOD)),
            ctx.salt
        );
        deployed.legalOpinion = _deployOrUpgrade(
            recorded.legalOpinion,
            address(new LegalOpinionCondition{salt: ctx.salt}()),
            abi.encodeCall(LegalOpinionCondition.initialize, (ctx.auth)),
            ctx.salt
        );
        deployed.regSDistributionCompliance = _deployOrUpgrade(
            recorded.regSDistributionCompliance,
            address(new RegSDistributionComplianceCondition{salt: ctx.salt}()),
            abi.encodeCall(RegSDistributionComplianceCondition.initialize, (ctx.auth)),
            ctx.salt
        );
        deployed.gpLpApproval = _deployOrUpgrade(
            recorded.gpLpApproval,
            address(new GPLPApprovalCondition{salt: ctx.salt}()),
            abi.encodeCall(GPLPApprovalCondition.initialize, (ctx.auth)),
            ctx.salt
        );
    }

    /// @dev One contract, six parameterizations. The four status gates follow the party anywhere.
    ///      The two entitlement gates only count for the SPV the offer belongs to.
    function _deployBadgeKindConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
    ) internal {
        address implementation = address(new LexChexBadgeKindCondition{salt: ctx.salt}());
        deployed.accreditedInvestor = _badgeKind(ctx, recorded.accreditedInvestor, implementation, K_ACCREDITED, false);
        deployed.qualifiedPurchaser = _badgeKind(ctx, recorded.qualifiedPurchaser, implementation, K_QP, true);
        deployed.qualifiedInstitutionalBuyer =
            _badgeKind(ctx, recorded.qualifiedInstitutionalBuyer, implementation, K_QIB, false);
        deployed.nonUsPerson = _badgeKind(ctx, recorded.nonUsPerson, implementation, K_NON_US, false);
        deployed.spvWhitelist = _badgeKind(ctx, recorded.spvWhitelist, implementation, K_SPV_WHITELIST, false);
        deployed.syndicate = _badgeKind(ctx, recorded.syndicate, implementation, K_SYNDICATE, false);
    }

    /// @dev The fact-key and the seller flag are the whole difference between two parameterizations,
    ///      so each one gets its own proxy address from the same implementation.
    function _badgeKind(
        Context memory ctx,
        address recorded,
        address implementation,
        uint256 kindKey,
        bool checkSeller
    ) internal returns (address) {
        return _deployOrUpgrade(
            recorded,
            implementation,
            abi.encodeCall(LexChexBadgeKindCondition.initialize, (ctx.auth, ctx.badge, kindKey, checkSeller)),
            ctx.salt
        );
    }

    /// @dev Neither closing condition is upgradeable, so a recorded one stays exactly as it is.
    function _deployClosingConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed,
        address metalexKillAdmin,
        address legionKillAdmin
    ) internal {
        deployed.killSwitch = recorded.killSwitch != address(0)
            ? recorded.killSwitch
            : address(new KillSwitchCondition{salt: ctx.salt}(metalexKillAdmin, legionKillAdmin));
        deployed.timeSettlementPeriod = recorded.timeSettlementPeriod != address(0)
            ? recorded.timeSettlementPeriod
            : address(new TimeSettlementPeriodCondition{salt: ctx.salt}());
    }

    /// @dev A recorded proxy keeps its address and takes the new code. A zero one gets a new proxy.
    function _deployOrUpgrade(
        address recorded,
        address implementation,
        bytes memory initCall,
        bytes32 salt
    ) internal returns (address) {
        if (recorded != address(0)) {
            UUPSUpgradeable(recorded).upgradeToAndCall(implementation, "");
            return recorded;
        }
        return address(new ERC1967Proxy{salt: salt}(implementation, initCall));
    }

    /// @dev The badge-scoped conditions refuse a zero registry at initialize, so the chain needs a
    ///      badge first. It gets its own BorgAuth: the minter holds ADMIN on `lexchexAuth`, and a
    ///      shared auth would make the badge issuer grants meaningless.
    function _badge(
        DeploymentConstants.CoreDeployment memory core,
        bytes32 salt,
        address deployer
    ) internal returns (address badge) {
        if (core.lexchexBadge != address(0)) return core.lexchexBadge;

        BorgAuth badgeAuth = new BorgAuth{salt: salt}(deployer);
        badge = address(
            new ERC1967Proxy{salt: salt}(
                address(new LeXcheXBadge{salt: salt}()),
                abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth)))
            )
        );
        // The v1 minter bridges an accreditation into a badge credential.
        LeXcheXBadge(badge).setIssuerKeys(core.lexchexMinter, MINTER_ISSUER_KEYS);

        console2.log("Deployed LeXcheXBadge AUTH:", address(badgeAuth));
        console2.log("Deployed LeXcheXBadge:", badge);
    }

    function _logDeployed(
        address badge,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
    ) internal pure {
        console2.log("==== Deployed ====");
        console2.log("LeXcheXBadge:", badge);
        console2.log("EligibilityCondition:", deployed.eligibility);
        console2.log("USStateOfResidenceCondition:", deployed.usStateOfResidence);
        console2.log("LegionSoulboundCondition:", deployed.legionSoulbound);
        console2.log("HolderCapCondition:", deployed.holderCap);
        console2.log("CFIUSCondition:", deployed.cfius);
        console2.log("Section4a7DisclosureCondition:", deployed.section4a7Disclosure);
        console2.log("Rule144DisclosureCondition:", deployed.rule144Disclosure);
        console2.log("HoldingPeriodCondition:", deployed.holdingPeriod);
        console2.log("LegalOpinionCondition:", deployed.legalOpinion);
        console2.log("RegSDistributionComplianceCondition:", deployed.regSDistributionCompliance);
        console2.log("GPLPApprovalCondition:", deployed.gpLpApproval);
        console2.log("AccreditedInvestor (K_ACCREDITED):", deployed.accreditedInvestor);
        console2.log("QualifiedPurchaser (K_QP):", deployed.qualifiedPurchaser);
        console2.log("QualifiedInstitutionalBuyer (K_QIB):", deployed.qualifiedInstitutionalBuyer);
        console2.log("NonUSPerson (K_NON_US):", deployed.nonUsPerson);
        console2.log("SpvWhitelist (K_SPV_WHITELIST):", deployed.spvWhitelist);
        console2.log("Syndicate (K_SYNDICATE):", deployed.syndicate);
        console2.log("KillSwitchCondition:", deployed.killSwitch);
        console2.log("TimeSettlementPeriodCondition:", deployed.timeSettlementPeriod);
        console2.log("");
    }
}
