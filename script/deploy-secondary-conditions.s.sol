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
import {
    RegSDistributionComplianceCondition
} from "../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {Rule144DisclosureCondition} from "../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {Section4a7DisclosureCondition} from "../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {TimeSettlementPeriodCondition} from "../src/libs/conditions/secondary/TimeSettlementPeriodCondition.sol";
import {USStateOfResidenceCondition} from "../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Deploys the shared secondary-trading condition singletons.
/// @dev Each condition is one instance for the whole chain, configured per SPV. The script is
///      idempotent against DeploymentConstants: an existing proxy keeps its address and takes the
///      new code, a zero field gets a new proxy. Add every printed address to DeploymentConstants afterwards.
///      An upgrade needs the owner role on its auth. The deployer sends it when it holds the role.
///      Otherwise `runWithArgs` returns it as a Safe call. See `DeploymentScript`.
contract DeploySecondaryConditionsScript is DeploymentScript {
    /// @dev Rule 144(d): one year of holding for a non-reporting issuer.
    uint256 private constant HOLDING_PERIOD = 365 days;
    /// @dev Rule 144(c)(2) practice: a balance sheet no older than 16 months.
    uint256 private constant DISCLOSURE_MAX_AGE = 480 days;
    /// @dev Facts the LeXcheX v1 minter bridges into a badge credential.
    uint256 private constant MINTER_ISSUER_KEYS = K_ACCREDITED | K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;

    /// @dev Values every condition initializer needs.
    struct Context {
        string proxySaltStr;
        address auth;
        address registry;
        address badge;
    }

    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-SecondaryConditionsV1.0.0", // proxySaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-SecondaryConditionsV1.0.0", // proxySaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey) public {
        runWithArgs(chainId, proxySaltStr, deployerPrivateKey);
        finish(
            "[Safe batch]",
            string.concat("script/res/gnosis-batch-deploy-secondary-conditions-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(uint256 chainId, string memory proxySaltStr, uint256 deployerPrivateKey)
        public
        returns (GnosisTransaction[] memory)
    {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        DeploymentConstants.SecondaryConditionDeployment memory existing =
            DeploymentConstants.secondaryConditions(chainId);

        console2.log("==== DeploySecondaryConditionsScript Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] proxy salt string: %s", proxySaltStr);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] CyberAgreementRegistry:", core.cyberAgreementRegistry);
        console2.log("");

        Context memory ctx = Context({
            proxySaltStr: proxySaltStr,
            auth: core.auth,
            registry: core.cyberAgreementRegistry,
            badge: _badge(core, chainId, proxySaltStr)
        });
        _deployThresholdConditions(ctx, existing);
        _deployBadgeKindConditions(ctx, existing);
        _deployClosingConditions(ctx, existing);

        console2.log(" ");
        return safeTxs;
    }

    /// @dev The conditions that read no credential, plus the three that read one through a badge.
    function _deployThresholdConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory existing
    ) internal {
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "EligibilityCondition",
            existing.eligibility,
            type(EligibilityCondition).creationCode,
            abi.encodeCall(EligibilityCondition.initialize, (ctx.auth))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "USStateOfResidenceCondition",
            existing.usStateOfResidence,
            type(USStateOfResidenceCondition).creationCode,
            abi.encodeCall(USStateOfResidenceCondition.initialize, (ctx.auth, ctx.badge))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "LegionSoulboundCondition",
            existing.legionSoulbound,
            type(LegionSoulboundCondition).creationCode,
            abi.encodeCall(LegionSoulboundCondition.initialize, (ctx.auth, ctx.badge))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "HolderCapCondition",
            existing.holderCap,
            type(HolderCapCondition).creationCode,
            abi.encodeCall(HolderCapCondition.initialize, (ctx.auth))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "CFIUSCondition",
            existing.cfius,
            type(CFIUSCondition).creationCode,
            abi.encodeCall(CFIUSCondition.initialize, (ctx.auth, ctx.badge))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "Section4a7DisclosureCondition",
            existing.section4a7Disclosure,
            type(Section4a7DisclosureCondition).creationCode,
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (ctx.auth, ctx.registry, DISCLOSURE_MAX_AGE))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "Rule144DisclosureCondition",
            existing.rule144Disclosure,
            type(Rule144DisclosureCondition).creationCode,
            abi.encodeCall(Rule144DisclosureCondition.initialize, (ctx.auth, DISCLOSURE_MAX_AGE))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "HoldingPeriodCondition",
            existing.holdingPeriod,
            type(HoldingPeriodCondition).creationCode,
            abi.encodeCall(HoldingPeriodCondition.initialize, (ctx.auth, HOLDING_PERIOD))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "LegalOpinionCondition",
            existing.legalOpinion,
            type(LegalOpinionCondition).creationCode,
            abi.encodeCall(LegalOpinionCondition.initialize, (ctx.auth))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "RegSDistributionComplianceCondition",
            existing.regSDistributionCompliance,
            type(RegSDistributionComplianceCondition).creationCode,
            abi.encodeCall(RegSDistributionComplianceCondition.initialize, (ctx.auth))
        );
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            "GPLPApprovalCondition",
            existing.gpLpApproval,
            type(GPLPApprovalCondition).creationCode,
            abi.encodeCall(GPLPApprovalCondition.initialize, (ctx.auth))
        );
    }

    /// @dev One contract, six parameterizations. The four status gates follow the party anywhere.
    ///      The two entitlement gates only count for the SPV the offer belongs to.
    function _deployBadgeKindConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory existing
    ) internal {
        // The proxies share one implementation. Compare with the one that an existing proxy uses.
        (address implementation,) = deployIfDifferent(
            "[deploy implementation]",
            "LexChexBadgeKindCondition",
            type(LexChexBadgeKindCondition).creationCode,
            implementationOf(existing.accreditedInvestor)
        );
        _badgeKind(
            ctx, "AccreditedInvestor (K_ACCREDITED)", existing.accreditedInvestor, implementation, K_ACCREDITED, false
        );
        _badgeKind(ctx, "QualifiedPurchaser (K_QP)", existing.qualifiedPurchaser, implementation, K_QP, true);
        _badgeKind(
            ctx,
            "QualifiedInstitutionalBuyer (K_QIB)",
            existing.qualifiedInstitutionalBuyer,
            implementation,
            K_QIB,
            false
        );
        _badgeKind(ctx, "NonUSPerson (K_NON_US)", existing.nonUsPerson, implementation, K_NON_US, false);
        _badgeKind(ctx, "SpvWhitelist (K_SPV_WHITELIST)", existing.spvWhitelist, implementation, K_SPV_WHITELIST, false);
        _badgeKind(ctx, "Syndicate (K_SYNDICATE)", existing.syndicate, implementation, K_SYNDICATE, false);
    }

    /// @dev The fact-key and the seller flag are the whole difference between two parameterizations,
    ///      so each one gets its own proxy address from the same implementation.
    function _badgeKind(
        Context memory ctx,
        string memory name,
        address existing,
        address implementation,
        uint256 kindKey,
        bool checkSeller
    ) internal {
        upgradeOrDeployProxyIfDiffImpl(
            ctx.auth,
            ctx.proxySaltStr,
            name,
            existing,
            implementation,
            abi.encodeCall(LexChexBadgeKindCondition.initialize, (ctx.auth, ctx.badge, kindKey, checkSeller))
        );
    }

    /// @dev The closing conditions are not upgradeable, so an existing one stays exactly as it is.
    ///      The kill switch constructor takes the two admin keys, which differ per chain. CREATE3 keeps the
    ///      address the same on all chains anyway.
    function _deployClosingConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory existing
    ) internal {
        bytes memory killSwitchInitCode;
        if (existing.killSwitch == address(0)) {
            // The two admin keys are the whole governance of the kill switch, so both are explicit.
            address metalexKillAdmin = vm.envAddress("KILL_SWITCH_METALEX_ADMIN");
            address legionKillAdmin = vm.envAddress("KILL_SWITCH_LEGION_ADMIN");
            console2.log("[deploy condition] kill switch MetaLeX admin:", metalexKillAdmin);
            console2.log("[deploy condition] kill switch Legion admin:", legionKillAdmin);
            killSwitchInitCode =
                abi.encodePacked(type(KillSwitchCondition).creationCode, abi.encode(metalexKillAdmin, legionKillAdmin));
        }
        deployIfNotExist(
            "[deploy condition]", ctx.proxySaltStr, "KillSwitchCondition", existing.killSwitch, killSwitchInitCode
        );
        deployIfNotExist(
            "[deploy condition]",
            ctx.proxySaltStr,
            "TimeSettlementPeriodCondition",
            existing.timeSettlementPeriod,
            type(TimeSettlementPeriodCondition).creationCode
        );
    }

    /// @dev The badge-scoped conditions refuse a zero registry at initialize, so the chain needs a
    ///      badge first. It gets its own BorgAuth: the minter holds ADMIN on `lexchexAuth`, and a
    ///      shared auth would make the badge issuer grants meaningless.
    ///      An existing badge takes the new code. Its upgrade needs the owner role on the badge auth.
    ///      On a production chain the deployer gives a new badge auth to the MetaLeX Safe, then drops its
    ///      own role. On a testnet the deployer keeps it.
    function _badge(DeploymentConstants.CoreDeployment memory core, uint256 chainId, string memory proxySaltStr)
        internal
        returns (address badge)
    {
        (address badgeAuth,) = deployIfNotExist(
            "[deploy auth]",
            proxySaltStr,
            "LeXcheXBadge AUTH",
            core.lexchexBadgeAuth,
            abi.encodePacked(type(BorgAuth).creationCode, abi.encode(deployer))
        );
        bool isNew;
        (badge, isNew) = upgradeOrDeployProxyIfDiffImpl(
            badgeAuth,
            proxySaltStr,
            "LeXcheXBadge",
            core.lexchexBadge,
            type(LeXcheXBadge).creationCode,
            abi.encodeCall(LeXcheXBadge.initialize, (badgeAuth))
        );
        if (!isNew) return badge;

        // The v1 minter bridges an accreditation into a badge credential.
        execute(
            "[set up badge]",
            badgeAuth,
            badge,
            abi.encodeCall(LeXcheXBadge.setIssuerKeys, (core.lexchexMinter, MINTER_ISSUER_KEYS)),
            "setting the LeXcheX minter issuer keys on LeXcheXBadge"
        );

        if (!DeploymentConstants.isTestnet(chainId)) {
            execute(
                "[set up badge]",
                badgeAuth,
                badgeAuth,
                abi.encodeCall(BorgAuth.updateRole, (safe, BorgAuth(badgeAuth).OWNER_ROLE())),
                "giving the Safe the owner role on LeXcheXBadge AUTH"
            );
            execute(
                "[set up badge]",
                badgeAuth,
                badgeAuth,
                abi.encodeCall(BorgAuth.zeroOwner, ()),
                "dropping the deployer role on LeXcheXBadge AUTH"
            );
        }
    }
}
