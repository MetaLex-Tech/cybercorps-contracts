// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuthV2} from "../BorgAuthV2.sol";
import {BorgAuth, BorgAuthACL} from "./auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";

/// @notice Linked deployment helpers keep authority creation bytecode out of the main factory.
library CorporateDeploymentLib {
    error InvalidAuthorityImplementation();
    error UnsupportedCorporatePermissions();

    function validateImplementation(address implementation) public view {
        if (
            implementation.code.length == 0 || !BorgAuthV2(implementation).supportsCorporateAuth()
                || BorgAuthV2(implementation).proxiableUUID()
                    != bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
        ) {
            revert InvalidAuthorityImplementation();
        }
    }

    function deployAuth(bytes32 salt, address implementation) public returns (address) {
        if (implementation == address(0)) {
            return Create2.deploy(0, salt, abi.encodePacked(type(BorgAuth).creationCode, abi.encode(address(this))));
        }
        return address(
            new ERC1967Proxy{salt: salt}(
                implementation, abi.encodeCall(BorgAuthV2.initializeCorporate, (address(this), address(this)))
            )
        );
    }

    function completeSetup(address auth, address root, address board, address officer, address[4] memory stack)
        public
    {
        for (uint256 i; i < stack.length; ++i) {
            if (!BorgAuthACL(stack[i]).supportsCorporatePermissions()) revert UnsupportedCorporatePermissions();
        }
        BorgAuthV2(auth).completeSetup(root, board, stack[0], officer, stack[1], stack[2], stack[3]);
    }
}
