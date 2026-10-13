// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {SecuritySeries} from "../CyberCorpConstants.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @notice Labels for the appended series catalog. Legacy labels stay with their callers.
/// @dev Internal functions add no linked deployment or storage. Enum order is protocol identity.
library SecuritySeriesNames {
    function expanded(SecuritySeries series, bool human) internal pure returns (string memory) {
        if (series == SecuritySeries.CommonA) return human ? "A" : "CommonA";
        if (series == SecuritySeries.CommonB) return human ? "B" : "CommonB";
        uint256 code = uint256(series);
        if (code < uint256(SecuritySeries.SeriesPreSeed2)) return "";
        uint256 offset = code - uint256(SecuritySeries.SeriesPreSeed2);
        uint256 family = offset / 9;
        string memory number = Strings.toString(offset % 9 + 2);
        string[8] memory prefixes = human
            ? [
                "Series Pre-Seed ",
                "Series Seed ",
                "Series A-",
                "Series B-",
                "Series C-",
                "Series D-",
                "Series E-",
                "Series F-"
            ]
            : ["SeriesPreSeed", "SeriesSeed", "SeriesA", "SeriesB", "SeriesC", "SeriesD", "SeriesE", "SeriesF"];
        return string.concat(prefixes[family], number);
    }
}
