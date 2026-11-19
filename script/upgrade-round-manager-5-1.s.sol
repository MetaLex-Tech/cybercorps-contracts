// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice Releases RoundManager 5.1 (minimum raise) and writes the Safe batches for it.
/// @dev Two kinds of batch, because MetaLeX publishes and each company opts in:
///      1. MetaLeX Safe (`run`): `RoundManagerFactory.setRefImplementation(new implementation)`. The script
///         deploys the implementation (Forge deploys and links `RoundManagerStorage` and `LexScrowStorage`
///         with it). The deployer sends the setter itself only when it holds the owner role on the core
///         AUTH (testnets). On production chains the Safe holds that role, so the call goes to the batch.
///      2. Company Safe: `roundManager.upgradeToAndCall(new implementation, "")`. A RoundManager accepts only
///         its factory's reference implementation (`NotRefImplementation`), so a company batch works only
///         after batch 1 is executed. `run` writes one for each known company on the chain whose
///         RoundManager runs v5; `corpBatch` writes one for a single company and checks its owner.
///      Only v5 companies take the single call. A company on an older release needs the whole v5
///      company upgrade (`upgrade-v5.s.sol`, `corpUpgradeCalls`), which then picks up 5.1 from the
///      factory reference.
///      Each file is Safe Transaction Builder JSON. A file from a run without `--broadcast` references
///      simulated addresses: import only the files from the successful broadcast run, after checking the
///      receipts. See `script/README-round-manager-5-1.md`.
contract UpgradeRoundManagerV51Script is DeploymentScript {
    string internal constant RELEASE = "5.1";
    string internal constant PREVIOUS_RELEASE = "5";

    /// @dev A stand-in owner for the company simulation in `run`. It exists only inside a reverted snapshot.
    address internal constant SIMULATED_CORP_OWNER =
        address(uint160(uint256(keccak256("RoundManager 5.1 simulated owner"))));
    /// @dev `BorgAuth.userRoles` is the mapping at slot 1 (slot 0 holds `pendingOwner`).
    uint256 internal constant USER_ROLES_SLOT = 1;

    enum CorpStatus {
        Ready,
        AlreadyUpgraded,
        NoRoundManager,
        NotV5,
        SimulationFailed
    }

    /// @notice Deploys the implementation, writes the MetaLeX batch, then the company batches.
    function run() external {
        runWithArgs(block.chainid, vm.envUint("PRIVATE_KEY_MAIN"), type(uint256).max);
    }

    /// @param maxCorps the most known companies to write a batch for (`type(uint256).max` for all)
    /// @return implementation the RoundManager reference after the MetaLeX batch (simulated when queued)
    function runWithArgs(uint256 chainId, uint256 deployerPrivateKey, uint256 maxCorps)
        public
        returns (address implementation)
    {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        console2.log("==== UpgradeRoundManagerV51Script Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] RoundManagerFactory:", core.roundManagerFactory);

        RoundManagerFactory factory = RoundManagerFactory(core.roundManagerFactory);
        require(address(factory).code.length > 0, "RoundManagerFactory has no code");
        require(address(factory.AUTH()) == core.auth, "RoundManagerFactory AUTH is not the core AUTH");
        require(
            DeploymentUtils.hasOwnerRole(core.auth, core.metalexSafe)
                || DeploymentUtils.hasOwnerRole(core.auth, deployer),
            "Neither the Safe nor the deployer owns the core AUTH"
        );

        address previous = factory.getRefImplementation();
        string memory previousVersion = RoundManager(previous).DEPLOY_VERSION();
        console2.log("[config] current reference:", previous);
        console2.log(string.concat("[config] current reference version: ", previousVersion));
        require(
            _eq(previousVersion, PREVIOUS_RELEASE) || _eq(previousVersion, RELEASE),
            "Unexpected reference version; this script releases 5 -> 5.1 only"
        );
        console2.log("");

        deployAndSetRefImplementation(
            core.auth,
            address(factory),
            previous,
            RoundManagerFactory.setRefImplementation.selector,
            "RoundManager",
            type(RoundManager).creationCode
        );
        finish("[MetaLeX Safe batch]", metalexBatchPath(chainId));

        // From here the state includes the MetaLeX batch (simulated as the Safe when it was queued).
        implementation = factory.getRefImplementation();
        require(_eq(RoundManager(implementation).DEPLOY_VERSION(), RELEASE), "Reference is not RoundManager 5.1");
        require(implementation.code.length <= 24_576, "RoundManager exceeds EIP-170 size limit");
        require(RoundManager(implementation).SETTLE_WINDOW() == 2 days, "Unexpected SETTLE_WINDOW");
        console2.log("[result] RoundManager 5.1 reference:", implementation);
        console2.log("");

        _writeKnownCorpBatches(chainId, implementation, maxCorps);
    }

    /// @notice Writes the company batch for one company and checks it as that company's owner.
    /// @dev Run it after the MetaLeX batch is executed, so that the live reference is 5.1. It covers
    ///      companies that are not in `known-cyber-corps.json`. It broadcasts nothing.
    /// @param owner the address that will execute the batch (normally the company's Safe)
    function corpBatch(address corp, address owner) external returns (string memory path) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        address implementation = RoundManagerFactory(core.roundManagerFactory).getRefImplementation();
        require(
            _eq(RoundManager(implementation).DEPLOY_VERSION(), RELEASE),
            "The factory reference is not 5.1 yet: execute the MetaLeX Safe batch first"
        );
        (CorpStatus status, address roundManager) = _checkCorp(corp, implementation, owner);
        require(status == CorpStatus.Ready, _statusText(status));
        path = _writeCorpBatch(block.chainid, corp, roundManager, implementation);
    }

    /// @notice The MetaLeX Safe batch file for `chainId`.
    function metalexBatchPath(uint256 chainId) public view virtual returns (string memory) {
        return string.concat("script/res/gnosis-batch-round-manager-5-1-", vm.toString(chainId), ".json");
    }

    /// @notice The company batch file for `corp` on `chainId`.
    function corpBatchPath(uint256 chainId, address corp) public view virtual returns (string memory) {
        return string.concat(corpBatchDir(chainId), "/gnosis-batch-", vm.toString(corp), ".json");
    }

    function corpBatchDir(uint256 chainId) public view virtual returns (string memory) {
        return string.concat("script/res/round-manager-5-1/", vm.toString(chainId));
    }

    /// @notice The known-companies list that `run` reads, relative to the project root.
    function knownCorpsPath() public view virtual returns (string memory) {
        return "/script/res/known-cyber-corps.json";
    }

    function _writeKnownCorpBatches(uint256 chainId, address implementation, uint256 maxCorps) internal {
        // `KnownAddressesLoader.load` returns one address for a limit of 0, so 0 stops here.
        if (maxCorps == 0) {
            console2.log("[company] no company batches requested");
            return;
        }
        address[] memory corps = KnownAddressesLoader.load(chainId, knownCorpsPath(), maxCorps);
        uint256 written;
        for (uint256 i = 0; i < corps.length; i++) {
            (CorpStatus status, address roundManager) = _checkCorp(corps[i], implementation, address(0));
            if (status != CorpStatus.Ready) {
                console2.log(string.concat("[company] skip ", vm.toString(corps[i]), ": ", _statusText(status)));
                continue;
            }
            string memory path = _writeCorpBatch(chainId, corps[i], roundManager, implementation);
            console2.log(string.concat("[company] batch for ", vm.toString(corps[i]), ": ", path));
            written++;
        }
        console2.log(
            string.concat(
                "[company] wrote ", vm.toString(written), " company batches of ", vm.toString(corps.length), " known"
            )
        );
        console2.log("[company] Each company batch works only after the MetaLeX batch is executed.");
    }

    /// @notice Checks that `corp`'s RoundManager runs v5 and that the upgrade to `implementation` works.
    /// @dev The upgrade runs inside a snapshot that is reverted. With a zero `owner`, a stand-in gets the owner
    ///      role on the RoundManager's AUTH inside that snapshot, because the script does not know the company's
    ///      Safe. A nonzero `owner` must already hold the owner role.
    function _checkCorp(address corp, address implementation, address owner)
        internal
        returns (CorpStatus status, address roundManager)
    {
        (bool found, bytes memory result) = corp.staticcall(abi.encodeWithSignature("roundManager()"));
        if (!found || result.length != 32) return (CorpStatus.NoRoundManager, address(0));
        roundManager = abi.decode(result, (address));
        if (roundManager == address(0) || roundManager.code.length == 0) {
            return (CorpStatus.NoRoundManager, roundManager);
        }
        address current = implementationOf(roundManager);
        if (current == implementation) return (CorpStatus.AlreadyUpgraded, roundManager);
        (bool ok, bytes memory version) = roundManager.staticcall(abi.encodeWithSignature("DEPLOY_VERSION()"));
        if (!ok || !_eq(abi.decode(version, (string)), PREVIOUS_RELEASE)) return (CorpStatus.NotV5, roundManager);

        address auth = address(RoundManager(roundManager).AUTH());
        uint256 snapshot = vm.snapshotState();
        if (owner == address(0)) {
            owner = SIMULATED_CORP_OWNER;
            vm.store(auth, keccak256(abi.encode(owner, USER_ROLES_SLOT)), bytes32(uint256(200)));
        }
        bool works = DeploymentUtils.hasOwnerRole(auth, owner);
        if (works) {
            vm.prank(owner);
            (works,) = roundManager.call(abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, "")));
        }
        if (works) {
            works = implementationOf(roundManager) == implementation
                && _eq(RoundManager(roundManager).DEPLOY_VERSION(), RELEASE)
                && address(RoundManager(roundManager).AUTH()) == auth;
            // A 5.1 read that a v5 implementation does not have.
            (bool readOk,) = roundManager.staticcall(abi.encodeCall(RoundManager.getRoundMinimum, (bytes32(0))));
            works = works && readOk;
        }
        require(vm.revertToStateAndDelete(snapshot), "Could not restore simulation state");
        require(implementationOf(roundManager) == current, "Company RoundManager changed outside its Safe");
        status = works ? CorpStatus.Ready : CorpStatus.SimulationFailed;
    }

    function _writeCorpBatch(uint256 chainId, address corp, address roundManager, address implementation)
        internal
        returns (string memory path)
    {
        GnosisTransaction[] memory txs = new GnosisTransaction[](1);
        txs[0] = GnosisTransaction({
            to: roundManager,
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, bytes("")))
        });
        vm.createDir(corpBatchDir(chainId), true);
        path = corpBatchPath(chainId, corp);
        vm.writeFile(path, DeploymentUtils.formatSafeTxJson(txs, chainId));
    }

    function _statusText(CorpStatus status) internal pure returns (string memory) {
        if (status == CorpStatus.AlreadyUpgraded) return "RoundManager already runs 5.1";
        if (status == CorpStatus.NoRoundManager) return "no company contract or no RoundManager";
        if (status == CorpStatus.NotV5) return "RoundManager is not v5; use the v5 company upgrade (upgrade-v5.s.sol)";
        if (status == CorpStatus.SimulationFailed) return "upgrade simulation failed (owner role, factory or state)";
        return "ready";
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
