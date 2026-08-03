// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ILexChexBadge} from "../../interfaces/ILexChexBadge.sol";
import {USJurisdictionPolicy} from "./USJurisdictionPolicy.sol";

/// @title  LookThroughPolicy - ICA §3(c)(1)(A) U.S.-investor classification
/// @author MetaLeX Labs, Inc.
/// @notice The look-through's own reading of the badge's jurisdiction facts. The badge stores them; deciding
/// what they mean for the holder count is this policy's job, so the credential layer stays a plain registry
/// that every condition can read differently.
/// @dev Shared by HolderCapCondition (the incoming acquirer) and the printer's cached holder tally (existing
/// holders of record) so both classify on identical terms — a drift between them would corrupt the cap math.
///
/// | `K_LOOKTHROUGH_JURISDICTION` ↓ / `K_INVESTOR_JURISDICTION` → | EMPTY  | US     | non-US |
/// |--------------------------------------------------------------|--------|--------|--------|
/// | EMPTY                                                        | US     | US     | non-US |
/// | US                                                           | US     | US     | US     |
/// | non-US                                                       | non-US | US     | non-US |
///
/// Conservative twice over: U.S. if either fact is U.S. (an offshore feeder with U.S. beneficial owners is
/// counted, and a U.S. party is never declassified), and U.S. when neither is established.
library LookThroughPolicy {
    /// @notice Whether the owner counts as a U.S. investor for the §3(c)(1)(A) look-through, and when that
    /// answer expires — 0 when it never does, matching the badge's own convention.
    /// @dev Only a non-U.S. answer expires. It rests on credentials that lapse with no transaction to
    /// observe, and a lapsed fact reads empty, which reads U.S. — so a cached non-U.S. booking silently
    /// understates the U.S. count once the evidence goes. A U.S. answer can only drift the other way, which
    /// overstates and is safe, so a caller has nothing to watch for.
    function isUSInvestor(ILexChexBadge badge, address owner) internal view returns (bool isUS, uint64 expiry) {
        // No registry means nothing is established about anyone, which reads U.S. like any other unknown
        if (address(badge) == address(0)) return (true, 0);
        (string memory regulatory, uint64 regulatoryExpiry) = badge.getLookThroughJurisdiction(owner);
        (string memory physical, uint64 physicalExpiry) = badge.getInvestorJurisdiction(owner);
        // Unknown non-US status is treated as US to be conservative
        if (bytes(regulatory).length == 0 && bytes(physical).length == 0) return (true, 0);
        if (USJurisdictionPolicy.isUS(regulatory) || USJurisdictionPolicy.isUS(physical)) return (true, 0);
        // Non-empty means a valid credential answered, and the badge cannot mint one without an expiry, so
        // this is never 0
        expiry = _earlier(regulatoryExpiry, physicalExpiry);
    }

    /// @dev Earlier of two expiries, where 0 means the fact was not answered at all
    function _earlier(uint64 a, uint64 b) private pure returns (uint64) {
        if (a == 0) return b;
        if (b == 0) return a;
        return a < b ? a : b;
    }
}
