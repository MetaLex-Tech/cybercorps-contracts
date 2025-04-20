// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

library BorgAuthStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.borgauth.storage.v1");

    // Main storage layout struct
    struct BorgAuthData {
        address AUTH;
    }

    // Returns the storage layout
    function borgAuthStorage() internal pure returns (BorgAuthData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getAuth() internal view returns (address) {
        return borgAuthStorage().AUTH;
    }

    // Setters
    function setAuth(address _auth) internal {
        borgAuthStorage().AUTH = _auth;
    }
} 