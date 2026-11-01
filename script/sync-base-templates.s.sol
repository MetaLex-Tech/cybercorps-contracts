// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Register the exact exported Base templates in Robinhood's registry.
/// @dev No upgrades, admin roles, API keys, or Base connection needed at deploy
/// time. Reads the signing key from PRIVATE_KEY_MAIN in the environment.
/// Review script/res/robinhood-base-templates.json before broadcasting.
/// Never use --skip-simulation.
contract SyncBaseTemplatesScript is Script {
    address public constant REGISTRY = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
    uint256 public constant SOURCE_CHAIN = 8453;
    uint256 public constant TARGET_CHAIN = 4663;
    string public constant MANIFEST = "script/res/robinhood-base-templates.json";

    // vm.parseJson encodes object keys in alphabetical order.
    struct TemplateRecord {
        string[] globalFields;
        bytes32 id;
        string legalContractUri;
        string[] partyFields;
        string title;
    }

    error WrongChain(uint256 chainId);
    error InvalidManifest();
    error InvalidTemplate(bytes32 id);
    error DuplicateTemplate(bytes32 id);
    error ConflictingTemplate(bytes32 id);
    error RegistryReadFailed(bytes32 id, bytes reason);

    function loadManifest(string memory path) public view returns (TemplateRecord[] memory templates) {
        string memory json = vm.readFile(path);
        if (
            vm.parseJsonUint(json, ".schemaVersion") != 1 || vm.parseJsonUint(json, ".sourceChainId") != SOURCE_CHAIN
                || vm.parseJsonUint(json, ".targetChainId") != TARGET_CHAIN
                || vm.parseJsonAddress(json, ".sourceRegistry") != REGISTRY
                || vm.parseJsonAddress(json, ".targetRegistry") != REGISTRY || vm.parseJsonUint(json, ".sourceBlock") == 0
                || vm.parseJsonBytes32(json, ".sourceBlockHash") == bytes32(0)
        ) revert InvalidManifest();
        templates = abi.decode(vm.parseJson(json, ".templates"), (TemplateRecord[]));
        if (templates.length == 0 || vm.parseJsonUint(json, ".templateCount") != templates.length) {
            revert InvalidManifest();
        }
    }

    function run() external {
        runWithManifest(MANIFEST);
    }

    function runWithManifest(string memory path) public {
        _requireTargetChain();
        TemplateRecord[] memory templates = loadManifest(path);
        console2.log("Source: pinned Base manifest", path);
        _sync(templates);
    }

    function _sync(TemplateRecord[] memory templates) internal {
        // Complete preflight before starting broadcast; a late conflict must not
        // allow earlier registrations to enter an operator's transaction list.
        bool[] memory missing = preflight(templates);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        uint256 created;
        uint256 skipped;
        console2.log("Target chain", block.chainid);
        console2.log("Registry", REGISTRY);
        for (uint256 i; i < templates.length; i++) {
            TemplateRecord memory entry = templates[i];
            if (!missing[i]) {
                skipped++;
                console2.log("[matching template; skipped]", entry.title);
                continue;
            }
            console2.log("[register template]", entry.title);
            console2.logBytes32(entry.id);
            vm.broadcast(deployerPrivateKey);
            CyberAgreementRegistry(REGISTRY).createTemplate(
                entry.id, entry.title, entry.legalContractUri, entry.globalFields, entry.partyFields
            );
            _requireMatching(entry);
            created++;
        }
        console2.log("Templates registered", created);
        console2.log("Exact matches skipped", skipped);
    }

    function preflight(TemplateRecord[] memory templates) public view returns (bool[] memory missing) {
        _requireTargetChain();
        if (REGISTRY.code.length == 0 || templates.length == 0) revert InvalidManifest();
        missing = new bool[](templates.length);
        for (uint256 i; i < templates.length; i++) {
            TemplateRecord memory entry = templates[i];
            if (bytes(entry.title).length == 0 || bytes(entry.legalContractUri).length == 0) {
                revert InvalidTemplate(entry.id);
            }
            for (uint256 j; j < i; j++) {
                if (templates[j].id == entry.id) revert DuplicateTemplate(entry.id);
            }
            missing[i] = !_existsAndMatches(entry);
        }
    }

    function _requireTargetChain() internal view {
        if (block.chainid != TARGET_CHAIN) revert WrongChain(block.chainid);
    }

    function _requireMatching(TemplateRecord memory entry) internal view {
        if (!_existsAndMatches(entry)) revert InvalidTemplate(entry.id);
    }

    function _existsAndMatches(TemplateRecord memory entry) internal view returns (bool) {
        try CyberAgreementRegistry(REGISTRY).getTemplateDetails(entry.id) returns (
            string memory uri, string memory title, string[] memory globals, string[] memory parties
        ) {
            if (keccak256(abi.encode(uri, title, globals, parties)) != definitionHash(entry)) {
                revert ConflictingTemplate(entry.id);
            }
            return true;
        } catch (bytes memory reason) {
            // Treat only the registry's exact missing-template error as absence.
            // Auth failures, unknown selectors and RPC/implementation failures
            // must not be mistaken for permission to create an ID.
            if (
                keccak256(reason)
                    == keccak256(abi.encodeWithSelector(CyberAgreementRegistry.TemplateDoesNotExist.selector))
            ) {
                return false;
            }
            revert RegistryReadFailed(entry.id, reason);
        }
    }

    function definitionHash(TemplateRecord memory entry) public pure returns (bytes32) {
        return keccak256(abi.encode(entry.legalContractUri, entry.title, entry.globalFields, entry.partyFields));
    }
}
