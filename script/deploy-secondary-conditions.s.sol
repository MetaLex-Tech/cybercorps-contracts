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
//import {KillSwitchCondition} from "../src/libs/conditions/secondary/KillSwitchCondition.sol";
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
import {SafeUtils} from "./libs/SafeUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys the shared secondary-trading condition singletons.
/// @dev Each condition is one instance for the whole chain, configured per SPV. The script is
///      idempotent against DeploymentConstants: a recorded proxy keeps its address and takes the
///      new code, a zero field gets a new proxy. Record every printed address afterwards.
///      The deployer only deploys. The upgrades of recorded proxies need the owner role, so
///      `runWithArgs` returns them as gated calls and does not send them.
contract DeploySecondaryConditionsScript is Script {
    using SafeUtils for GnosisTransaction[];

    GnosisTransaction[] internal gatedCalls;

    /// @dev Rule 144(d): one year of holding for a non-reporting issuer.
    uint256 private constant HOLDING_PERIOD = 365 days;
    /// @dev Rule 144(c)(2) practice: a balance sheet no older than 16 months.
    uint256 private constant DISCLOSURE_MAX_AGE = 480 days;
    /// @dev Facts the LeXcheX v1 minter bridges into a badge credential.
    uint256 private constant MINTER_ISSUER_KEYS = K_ACCREDITED | K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;

    /// @dev Values every condition initializer needs.
    struct Context {
        bytes32 proxySalt;
        bytes32 implSalt;
        address auth;
        address registry;
        address badge;
    }

    function run() public returns (DeploymentConstants.SecondaryConditionDeployment memory deployed) {
        return runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-SecondaryConditionsV1.0.0", // proxySaltStr
//            "CyberCorpV5-SecondaryConditionsV1.0.0-impl0", // implSaltStr
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-SecondaryConditionsV1.0.0", // proxySaltStr
            "CyberCorpV5-SecondaryConditionsV1.0.0-impl0", // implSaltStr
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then sends the gated calls or hands them off to the MetaLeX Safe.
    function runAndExecute(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.SecondaryConditionDeployment memory deployed) {
        GnosisTransaction[] memory calls;
        (deployed, calls) = runWithArgs(chainId, proxySaltStr, implSaltStr, deployerPrivateKey);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        address deployer = vm.addr(deployerPrivateKey);
        // On a testnet the deployer must own the core AUTH and the LeXcheX badge AUTH.
        // A zero badge AUTH means this run deploys a new one, and the deployer owns it.
        bool direct = DeploymentConstants.isTestnet(chainId) && SafeUtils.hasOwnerRole(core.auth, deployer)
            && (core.lexchexBadgeAuth == address(0) || SafeUtils.hasOwnerRole(core.lexchexBadgeAuth, deployer));
        SafeUtils.executeOrHandOff(
            calls,
            chainId,
            deployerPrivateKey,
            core.metalexSafe,
            direct,
            string.concat("script/res/gnosis-batch-deploy-secondary-conditions-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory proxySaltStr,
        string memory implSaltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.SecondaryConditionDeployment memory deployed, GnosisTransaction[] memory calls) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 proxySalt = keccak256(bytes(proxySaltStr));
        bytes32 implSalt = keccak256(bytes(implSaltStr));

        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        DeploymentConstants.SecondaryConditionDeployment memory recorded =
            DeploymentConstants.secondaryConditions(chainId);

//        // The two keys are the whole governance surface of the kill switch, so both are explicit.
//        address metalexKillAdmin = vm.envAddress("KILL_SWITCH_METALEX_MOCK");
//        address legionKillAdmin = vm.envAddress("KILL_SWITCH_LEGION_MOCK");

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("proxy salt string: %s", proxySaltStr);
        console2.log("implementation salt string: %s", implSaltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("AUTH:", core.auth);
        console2.log("CyberAgreementRegistry:", core.cyberAgreementRegistry);
//        console2.log("kill switch MetaLeX admin:", metalexKillAdmin);
//        console2.log("kill switch Legion admin:", legionKillAdmin);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        Context memory ctx = Context({
            proxySalt: proxySalt,
            implSalt: implSalt,
            auth: core.auth,
            registry: core.cyberAgreementRegistry,
            badge: _badge(core, chainId, implSalt, proxySalt, deployerAddress)
        });
        _deployThresholdConditions(ctx, recorded, deployed);
        _deployBadgeKindConditions(ctx, recorded, deployed);
        _deployClosingConditions(ctx, recorded, deployed);
//        _deployClosingConditions(ctx, recorded, deployed, metalexKillAdmin, legionKillAdmin);
        vm.stopBroadcast();

        console2.log("");
        calls = gatedCalls;
    }

    /// @dev The conditions that read no credential, plus the three that read one through a badge.
    function _deployThresholdConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
    ) internal {
        deployed.eligibility = gatedCalls.deployOrUpgrade("EligibilityCondition", 
            recorded.eligibility,
            address(new EligibilityCondition{salt: ctx.implSalt}()),
            abi.encodeCall(EligibilityCondition.initialize, (ctx.auth)),
            ctx.proxySalt
        );
        deployed.usStateOfResidence = gatedCalls.deployOrUpgrade("USStateOfResidenceCondition", 
            recorded.usStateOfResidence,
            address(new USStateOfResidenceCondition{salt: ctx.implSalt}()),
            abi.encodeCall(USStateOfResidenceCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.proxySalt
        );
        deployed.legionSoulbound = gatedCalls.deployOrUpgrade("LegionSoulboundCondition", 
            recorded.legionSoulbound,
            address(new LegionSoulboundCondition{salt: ctx.implSalt}()),
            abi.encodeCall(LegionSoulboundCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.proxySalt
        );
        deployed.holderCap = gatedCalls.deployOrUpgrade("HolderCapCondition", 
            recorded.holderCap,
            address(new HolderCapCondition{salt: ctx.implSalt}()),
            abi.encodeCall(HolderCapCondition.initialize, (ctx.auth)),
            ctx.proxySalt
        );
        deployed.cfius = gatedCalls.deployOrUpgrade("CFIUSCondition", 
            recorded.cfius,
            address(new CFIUSCondition{salt: ctx.implSalt}()),
            abi.encodeCall(CFIUSCondition.initialize, (ctx.auth, ctx.badge)),
            ctx.proxySalt
        );
        deployed.section4a7Disclosure = gatedCalls.deployOrUpgrade("Section4a7DisclosureCondition", 
            recorded.section4a7Disclosure,
            address(new Section4a7DisclosureCondition{salt: ctx.implSalt}()),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (ctx.auth, ctx.registry, DISCLOSURE_MAX_AGE)),
            ctx.proxySalt
        );
        deployed.rule144Disclosure = gatedCalls.deployOrUpgrade("Rule144DisclosureCondition", 
            recorded.rule144Disclosure,
            address(new Rule144DisclosureCondition{salt: ctx.implSalt}()),
            abi.encodeCall(Rule144DisclosureCondition.initialize, (ctx.auth, DISCLOSURE_MAX_AGE)),
            ctx.proxySalt
        );
        deployed.holdingPeriod = gatedCalls.deployOrUpgrade("HoldingPeriodCondition", 
            recorded.holdingPeriod,
            address(new HoldingPeriodCondition{salt: ctx.implSalt}()),
            abi.encodeCall(HoldingPeriodCondition.initialize, (ctx.auth, HOLDING_PERIOD)),
            ctx.proxySalt
        );
        deployed.legalOpinion = gatedCalls.deployOrUpgrade("LegalOpinionCondition", 
            recorded.legalOpinion,
            address(new LegalOpinionCondition{salt: ctx.implSalt}()),
            abi.encodeCall(LegalOpinionCondition.initialize, (ctx.auth)),
            ctx.proxySalt
        );
        deployed.regSDistributionCompliance = gatedCalls.deployOrUpgrade("RegSDistributionComplianceCondition", 
            recorded.regSDistributionCompliance,
            address(new RegSDistributionComplianceCondition{salt: ctx.implSalt}()),
            abi.encodeCall(RegSDistributionComplianceCondition.initialize, (ctx.auth)),
            ctx.proxySalt
        );
        deployed.gpLpApproval = gatedCalls.deployOrUpgrade("GPLPApprovalCondition", 
            recorded.gpLpApproval,
            address(new GPLPApprovalCondition{salt: ctx.implSalt}()),
            abi.encodeCall(GPLPApprovalCondition.initialize, (ctx.auth)),
            ctx.proxySalt
        );
    }

    /// @dev One contract, six parameterizations. The four status gates follow the party anywhere.
    ///      The two entitlement gates only count for the SPV the offer belongs to.
    function _deployBadgeKindConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
    ) internal {
        address implementation = address(new LexChexBadgeKindCondition{salt: ctx.implSalt}());
        console2.log("deployed new implementation LexChexBadgeKindCondition:", implementation);
        deployed.accreditedInvestor = _badgeKind(ctx, "AccreditedInvestor (K_ACCREDITED)", recorded.accreditedInvestor, implementation, K_ACCREDITED, false);
        deployed.qualifiedPurchaser = _badgeKind(ctx, "QualifiedPurchaser (K_QP)", recorded.qualifiedPurchaser, implementation, K_QP, true);
        deployed.qualifiedInstitutionalBuyer =
            _badgeKind(ctx, "QualifiedInstitutionalBuyer (K_QIB)", recorded.qualifiedInstitutionalBuyer, implementation, K_QIB, false);
        deployed.nonUsPerson = _badgeKind(ctx, "NonUSPerson (K_NON_US)", recorded.nonUsPerson, implementation, K_NON_US, false);
        deployed.spvWhitelist = _badgeKind(ctx, "SpvWhitelist (K_SPV_WHITELIST)", recorded.spvWhitelist, implementation, K_SPV_WHITELIST, false);
        deployed.syndicate = _badgeKind(ctx, "Syndicate (K_SYNDICATE)", recorded.syndicate, implementation, K_SYNDICATE, false);
    }

    /// @dev The fact-key and the seller flag are the whole difference between two parameterizations,
    ///      so each one gets its own proxy address from the same implementation.
    function _badgeKind(
        Context memory ctx,
        string memory name,
        address recorded,
        address implementation,
        uint256 kindKey,
        bool checkSeller
    ) internal returns (address) {
        return gatedCalls.upgradeOrNewProxy(
            name,
            recorded,
            implementation,
            abi.encodeCall(LexChexBadgeKindCondition.initialize, (ctx.auth, ctx.badge, kindKey, checkSeller)),
            ctx.proxySalt
        );
    }

    /// @dev The closing conditions are not upgradeable, so a recorded one stays exactly as it is.
    ///      This script does not deploy KillSwitchCondition. Its constructor takes the two admin
    ///      keys, so the address cannot match on all chains. A recorded one passes through.
    function _deployClosingConditions(
        Context memory ctx,
        DeploymentConstants.SecondaryConditionDeployment memory recorded,
        DeploymentConstants.SecondaryConditionDeployment memory deployed
//        , address metalexKillAdmin, address legionKillAdmin
    ) internal {
        deployed.killSwitch = recorded.killSwitch;
//        deployed.killSwitch = recorded.killSwitch != address(0)
//            ? recorded.killSwitch
//            : address(new KillSwitchCondition{salt: ctx.implSalt}(metalexKillAdmin, legionKillAdmin));
        deployed.timeSettlementPeriod = recorded.timeSettlementPeriod;
        if (deployed.timeSettlementPeriod == address(0)) {
            deployed.timeSettlementPeriod = address(new TimeSettlementPeriodCondition{salt: ctx.implSalt}());
            console2.log("deployed new contract TimeSettlementPeriodCondition:", deployed.timeSettlementPeriod);
        }
    }

    /// @dev The badge-scoped conditions refuse a zero registry at initialize, so the chain needs a
    ///      badge first. It gets its own BorgAuth: the minter holds ADMIN on `lexchexAuth`, and a
    ///      shared auth would make the badge issuer grants meaningless.
    ///      On a production chain the deployer gives the badge auth to the MetaLeX Safe, then drops its
    ///      own role. On a testnet the deployer keeps it.
    function _badge(
        DeploymentConstants.CoreDeployment memory core,
        uint256 chainId,
        bytes32 implSalt,
        bytes32 proxySalt,
        address deployer
    ) internal returns (address badge) {
        if (core.lexchexBadge != address(0)) return core.lexchexBadge;

        BorgAuth badgeAuth = new BorgAuth{salt: implSalt}(deployer);
        console2.log("queued deploying new BorgAuth LeXcheXBadge AUTH:", address(badgeAuth));
        address implementation = address(new LeXcheXBadge{salt: implSalt}());
        console2.log("deployed new implementation LeXcheXBadge:", implementation);
        badge = address(
            new ERC1967Proxy{salt: proxySalt}(implementation, abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth))))
        );
        console2.log("queued deploying new proxy LeXcheXBadge:", badge);
        // The v1 minter bridges an accreditation into a badge credential.
        LeXcheXBadge(badge).setIssuerKeys(core.lexchexMinter, MINTER_ISSUER_KEYS);

        if (!DeploymentConstants.isTestnet(chainId)) {
            badgeAuth.updateRole(core.metalexSafe, badgeAuth.OWNER_ROLE());
            badgeAuth.zeroOwner();
        }
    }
}
