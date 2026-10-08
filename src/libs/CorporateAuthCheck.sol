// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ICorporateAuth} from "./CorporateAuth.sol";
import {BorgAuth} from "./auth.sol";

/// @notice Legacy compatibility is selected by authority implementation, never by the caller's number.
library CorporateAuthCheck {
    function isCorporate(address auth) internal view returns (bool) {
        (bool ok, bytes memory result) = auth.staticcall(abi.encodeCall(ICorporateAuth.supportsCorporateAuth, ()));
        return ok && result.length == 32 && abi.decode(result, (bool));
    }

    function requirePermission(address auth, bytes32 permission, uint256 legacyRole, address account) public view {
        if (isCorporate(auth)) ICorporateAuth(auth).requirePermission(permission, account);
        else BorgAuth(auth).onlyRole(legacyRole, account);
    }
}
