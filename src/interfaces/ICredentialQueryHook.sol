// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Credential} from "../creds/storage/lexchexBadgeStorage.sol";

/// @title  ICredentialQueryHook - caller-supplied test for one credential
/// @author MetaLeX Labs, Inc.
/// @notice Lets a caller ask the badge something its fact-keys cannot express. The badge picks the eligible
/// credentials and how matches are resolved; the hook says which ones count. Its usual job is reading
/// `Credential.data`, whose schema the badge never learns.
/// @dev The hook is untrusted code the caller chose. Reads are view, so it cannot change state, but one that
/// reverts or burns gas breaks the read for whoever passed it.
interface ICredentialQueryHook {
    /// @param owner    Holder whose set is being scanned.
    /// @param tokenId  Credential under test.
    /// @param cred     Its record, passed in full so the hook needs no callback.
    /// @param hookData The caller's payload, forwarded untouched. The hook defines its schema; the badge only
    ///                 carries it. This is how a query carries context info.
    /// @return True when this credential counts.
    function matchesCredential(address owner, uint256 tokenId, Credential calldata cred, bytes calldata hookData)
        external
        view
        returns (bool);
}
