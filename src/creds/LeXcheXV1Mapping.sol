/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o

ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.*/

pragma solidity 0.8.28;

import {InvestorType} from "../interfaces/ILexChexBadge.sol";

/// @title  LeXcheXV1Mapping - reads a LeXcheX v1 accreditation field as a badge fact
/// @author MetaLeX Labs, Inc.
/// @notice v1 stores investorType as a free-form string ("Natural person", "individual", "LLC"), so bridging a
/// v1 token into the badge has to turn that string into an InvestorType. The vocabulary is fixed here rather
/// than configured, so what a bridged credential can claim is fixed at deploy time.
/// @dev A string this does not recognise returns UNSET, and the bridge then asserts no K_INVESTOR_TYPE at all.
/// Guessing would be worse: the count behind an INDIVIDUAL feeds the §3(c)(1)(A) look-through, and an
/// unasserted fact reads empty, which every condition already handles.
library LeXcheXV1Mapping {
    /// @notice The badge InvestorType a v1 investorType string stands for; UNSET when it stands for none.
    /// Matching is case-insensitive and ignores surrounding spaces, since v1 records were typed by hand.
    function investorTypeOf(string memory investorType) internal pure returns (InvestorType) {
        bytes32 h = keccak256(bytes(_normalize(investorType)));

        if (h == keccak256("individual") || h == keccak256("natural person") || h == keccak256("person")) {
            return InvestorType.INDIVIDUAL;
        }
        if (
            h == keccak256("llc") || h == keccak256("corporation") || h == keccak256("corp")
                || h == keccak256("inc") || h == keccak256("incorporated") || h == keccak256("company")
                || h == keccak256("trust") || h == keccak256("partnership") || h == keccak256("lp")
                || h == keccak256("llp") || h == keccak256("fund") || h == keccak256("entity")
        ) {
            return InvestorType.ENTITY;
        }
        return InvestorType.UNSET;
    }

    /// @dev Trim spaces, then lowercase ASCII. Bytes outside A-Z pass through, so a non-ASCII string is left
    /// alone and simply fails to match.
    function _normalize(string memory s) private pure returns (string memory) {
        bytes memory b = bytes(s);
        uint256 start = 0;
        uint256 end = b.length;
        while (start < end && b[start] == 0x20) ++start;
        while (end > start && b[end - 1] == 0x20) --end;

        bytes memory out = new bytes(end - start);
        for (uint256 i = 0; i < out.length; ++i) {
            bytes1 c = b[start + i];
            out[i] = (c >= 0x41 && c <= 0x5A) ? bytes1(uint8(c) + 32) : c;
        }
        return string(out);
    }
}
