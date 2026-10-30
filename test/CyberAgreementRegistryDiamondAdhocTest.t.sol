// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {Test} from "forge-std/Test.sol";

// Puts the current registry code behind the live Base proxy and compares the live state.
contract CyberAgreementRegistryDiamondAdhocTest is Test {
    address constant REGISTRY = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
    bytes32 constant AGREEMENT_ID = 0x78f6ea3db4c0a2d53384b845ccdaa42419787e6c12fa618594eba1704f10dd84;
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function testLiveStateAfterUpgrade() public {
        vm.createSelectFork("base", 53264116);
        CyberAgreementRegistry registry = CyberAgreementRegistry(REGISTRY);

        string memory version = registry.version();
        bytes32 domain = registry.DOMAIN_SEPARATOR();
        address[] memory parties = registry.getParties(AGREEMENT_ID);
        string memory json = registry.getContractJson(AGREEMENT_ID);

        vm.store(REGISTRY, IMPLEMENTATION_SLOT, bytes32(uint256(uint160(address(new CyberAgreementRegistry())))));

        assertEq(registry.version(), version, "version");
        assertEq(registry.DOMAIN_SEPARATOR(), domain, "domain separator");
        assertEq(registry.getParties(AGREEMENT_ID), parties, "parties");
        assertEq(registry.getContractJson(AGREEMENT_ID), json, "agreement json");
    }
}
