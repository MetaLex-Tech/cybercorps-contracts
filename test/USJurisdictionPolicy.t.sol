// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {USJurisdictionPolicy} from "../src/libs/policies/USJurisdictionPolicy.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Unit tests for the shared reading of a jurisdiction credential as U.S. or not. Every condition
/// that has to tell a U.S. party from a foreign one goes through this, so the accepted set is fixed here
/// rather than per-consumer; each consumer's own suite covers the polarity it reads the answer with.
///
/// Invariants guarded:
///  1. Exactly three spellings are U.S. — "US", "USA", "United States".
///  2. Matching is exact: case, punctuation and surrounding whitespace all disqualify.
///  3. An empty jurisdiction is not U.S., so a consumer for which "not U.S." is the passing answer must
///     reject the unestablished case itself before calling in.
contract USJurisdictionPolicyTest is Test {
    function test_CanonicalSpellings_AreUS() public pure {
        string[3] memory us = ["US", "USA", "United States"];
        for (uint256 i = 0; i < us.length; i++) {
            assertTrue(USJurisdictionPolicy.isUS(us[i]), us[i]);
        }
    }

    function test_ForeignCodes_AreNotUS() public pure {
        string[4] memory foreign = ["KY", "GB", "SG", "Cayman Islands"];
        for (uint256 i = 0; i < foreign.length; i++) {
            assertFalse(USJurisdictionPolicy.isUS(foreign[i]), foreign[i]);
        }
    }

    // Near-misses of the canonical spellings: none of them read as U.S.
    function test_NonCanonicalVariants_AreNotUS() public pure {
        string[7] memory variants = ["us", "usa", "Usa", "U.S.", "U.S.A.", " US", "united states"];
        for (uint256 i = 0; i < variants.length; i++) {
            assertFalse(USJurisdictionPolicy.isUS(variants[i]), variants[i]);
        }
    }

    // Unestablished reads as not-U.S. here; whether that is the safe answer is the consumer's call.
    function test_Empty_IsNotUS() public pure {
        assertFalse(USJurisdictionPolicy.isUS(""));
    }
}
