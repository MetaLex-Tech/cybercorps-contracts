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
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity ^0.8.28;

import "./CyberCorpConstants.sol";
import {CertificateText} from "./libs/CertificateText.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/// @title CertificateImageContentBuilder
/// @notice Helper library generating the gradient defs and dynamic text content
///         of the "Ledger Entry Token" certificate SVG
library CertificateImageContentBuilder {
    function buildSVGContent(
        CertificateSVGParams memory params,
        uint256 timestamp
    ) public pure returns (string memory) {
        string memory dateStr = _formatDate(timestamp);

        return string(abi.encodePacked(
            _buildDefs(),
            '<rect width="1" height="31" transform="translate(511 391)" fill="url(#paint0_linear_62908_10123)"/>',
            '<g font-family="system-ui">',
            _buildHeaderText(params),
            _buildPartiesText(params),
            _buildStatsText(params, dateStr),
            _buildOfficerText(params),
            _buildRestrictionsText(params.transferRestrictions),
            _buildFooter(params),
            '</g>',
            _buildVoidedStamp(params.isVoided)
        ));
    }

    /// @notice Footer naming the issuing company. One sentence for every company, settled by the owner on
    ///         2026-10-11. It makes no statutory claim, so the token of a non-Delaware or non-corporate
    ///         issuer no longer asserts a place on another company's DGCL stock ledger.
    /// @dev The name is cut at 26 code points, the parties block's limit. The sentence alone takes about
    ///      620px of the 1024px width at 14px in a wide system font, so the header's limit of 38 would let
    ///      a long upper-case name run past the edge.
    function _buildFooter(CertificateSVGParams memory params) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="512" y="885" font-size="14" fill="#9A9A98" text-anchor="middle">This constitutes an official entry on the tokenized securities ledger of ',
            CertificateText.xml(params.corpName, 26),
            '.</text>'
        ));
    }

    /// @notice Rotated "VOIDED" stamp overlaid on the certificate when it has been voided
    function _buildVoidedStamp(bool voided) private pure returns (string memory) {
        if (!voided) return "";
        return string(abi.encodePacked(
            '<g transform="rotate(-12 312 160)">',
            '<rect x="350" y="705" width="505" height="110" fill="none" stroke="#f19a8e" stroke-width="4"/>',
            '<text x="605" y="760" fill="#f19a8e" font-family="Arial, sans-serif" font-size="90" font-weight="bold" text-anchor="middle" dominant-baseline="central">VOIDED</text>',
            '</g>'
        ));
    }

    function _buildDefs() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<defs>',
            '<radialGradient id="paint0_radial_63528_2" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(512 512) rotate(90) scale(512)">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#191A18"/></radialGradient>',
            '<radialGradient id="paint1_radial_63528_2" cx="0" cy="0" r="1" gradientTransform="matrix(-0.0961874 -69.0265 380.979 -0.313153 534.169 226.832)" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></radialGradient>',
            '<linearGradient id="paint2_linear_63528_2" x1="80" y1="196" x2="944" y2="196" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00" stop-opacity="0"/><stop offset="0.524038" stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient>',
            '<linearGradient id="paint4_linear_63528_2" x1="872" y1="212.5" x2="872" y2="228.5" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#F2F8CB"/></linearGradient>',
            '<linearGradient id="paint5_linear_63528_2" x1="832" y1="220.5" x2="912" y2="220.5" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient>',
            '<linearGradient id="paint4_linear_void" x1="872" y1="212.5" x2="872" y2="228.5" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#FF2E2E"/><stop offset="1" stop-color="#F8CBCB"/></linearGradient>',
            '<linearGradient id="paint5_linear_void" x1="832" y1="220.5" x2="912" y2="220.5" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#FF2E2E"/><stop offset="1" stop-color="#FF2E2E" stop-opacity="0"/></linearGradient>',
            _buildDefsPart2()
        ));
    }

    function _buildDefsPart2() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<linearGradient id="vg" x1="0" y1="0" x2="0" y2="1">',
            '<stop stop-color="#D9D9D9" stop-opacity="0"/><stop offset="0.514423" stop-color="white" stop-opacity="0.2"/><stop offset="1" stop-color="#F2F2F2" stop-opacity="0"/></linearGradient>',
            '<radialGradient id="paint11_radial_63528_2" cx="0" cy="0" r="1" gradientTransform="matrix(0.0961947 83.6284 -380.979 0.37943 489.831 880.646)" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></radialGradient>',
            '<linearGradient id="paint12_linear_63528_2" x1="944" y1="918" x2="80" y2="918" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00" stop-opacity="0"/><stop offset="0.524038" stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient>',
            '<clipPath id="clip0_63528_2"><rect width="1024" height="1024" fill="white"/></clipPath>',
            '<linearGradient id="paint0_linear_62908_10123" x1="0.5" y1="0" x2="0.5" y2="61" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#D9D9D9" stop-opacity="0"/><stop offset="0.514423" stop-color="white" stop-opacity="0.2"/><stop offset="1" stop-color="#F2F2F2" stop-opacity="0"/></linearGradient>',
            '<linearGradient id="paint0_linear_62908_10150" x1="600" y1="500" x2="600" y2="620" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset=".39" stop-color="#F2F8CB"/></linearGradient>',
            '</defs>'
        ));
    }

    function _buildHeaderText(CertificateSVGParams memory params) private pure returns (string memory) {
        string memory units = _formatUnits(params);
        return string(abi.encodePacked(
            '<text x="512" y="190" font-size="32" fill="#f2f2f2" text-anchor="middle">', CertificateText.xml(params.corpName, 38), '</text>',
            '<text x="152" y="85" font-size="11" fill="#f2f2f2" text-anchor="middle">Token ID</text>',
            '<text x="152" y="124" font-size="35" fill="#f2f2f2" text-anchor="middle">#', _uintToString(params.tokenId), '</text>',
            '<text x="835" y="85" font-size="11" fill="#f2f2f2" text-anchor="middle">', _getBaseUnit(params.securityType), '</text>',
            '<text x="838" y="124" font-size="', _fitFontSize(units, 240, 35), '" fill="#f2f2f2" text-anchor="middle">', units, '</text>',
            !params.statusKnown ? "" : params.isVoided
                ? '<text x="805" y="225" font-size="11" fill="#FF2E2E" text-anchor="middle">voided</text>'
                : '<text x="805" y="225" font-size="11" fill="#DAFF00" text-anchor="middle">active</text>',
            '<text x="110" y="229" font-size="18" fill="#9A9A98">Ledger Entry Token</text>'
        ));
    }

    function _buildPartiesText(CertificateSVGParams memory params) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="230" y="318" font-size="14" fill="#9A9A98">Issuer </text>',
            '<text x="230" y="344" font-size="16" fill="#f2f2f2">', CertificateText.xml(params.corpName, 26), ' </text>',
            '<text x="230" y="364" font-size="11" fill="#9A9A98">', _truncatedAddress(params.issuerAddress), '</text>',
            '<text x="630" y="318" font-size="14" fill="#9A9A98">Registered Owner </text>',
            '<text x="630" y="344" font-size="16" fill="#f2f2f2">', CertificateText.xml(params.ownerName, 26), ' </text>',
            '<text x="630" y="364" font-size="11" fill="#9A9A98">', _truncatedAddress(params.ownerAddress), '</text>',
            '<text x="505" y="418" font-size="14" fill="#9A9A98" text-anchor="end">Series</text>',
            '<text x="519" y="418" font-size="14" fill="#9A9A98">Class</text>',
            '<text x="512" y="438" font-size="14" fill="#f2f2f2" text-anchor="middle">', _securityName(params), '</text>'
        ));
    }

    /// @dev The charter form puts the series before the class: "Series Seed 2 Preferred Stock".
    ///      The series comes from the series name when it is set, else from the series enum.
    ///      The name is free text. Escape it and cut it at 50 code points so that it fits the artwork.
    ///      A security without a series (`NA`) shows the class only.
    function _securityName(CertificateSVGParams memory params) private pure returns (string memory) {
        string memory class = _securityClassToString(params.securityType);
        string memory series = bytes(params.seriesName).length == 0
            ? _securitySeriesToString(params.securitySeries)
            : CertificateText.xml(params.seriesName, 50);
        if (bytes(series).length == 0) return class;
        return string.concat(series, ' ', class);
    }

    function _buildStatsText(
        CertificateSVGParams memory params,
        string memory dateStr
    ) private pure returns (string memory) {
        string memory units = _formatUnits(params);
        string memory consideration = _formatConsideration(params);
        return string(abi.encodePacked(
            '<text x="140" y="500" font-size="14" fill="#9A9A98">Units</text>',
            '<text x="150" y="540" font-size="', _fitFontSize(units, 225, 34), '" font-weight="700" fill="url(#paint0_linear_62908_10150)">', units, '</text>',
            '<text x="385" y="500" font-size="14" fill="#9A9A98">Consideration</text>',
            '<text x="390" y="540" font-size="', _fitFontSize(consideration, 245, 34), '" font-weight="700" fill="url(#paint0_linear_62908_10150)">', consideration, '</text>',
            '<text x="645" y="500" font-size="14" fill="#9A9A98">Issue Date</text>',
            '<text x="660" y="540" font-size="34" font-weight="700" fill="url(#paint0_linear_62908_10150)">', dateStr, '</text>'
        ));
    }

    function _buildOfficerText(
        CertificateSVGParams memory params
    ) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="512" y="590" font-size="14" fill="#9A9A98" text-anchor="middle">Authorizing Officer</text>',
            '<text x="512" y="620" font-size="18" fill="#f2f2f2" text-anchor="middle">', CertificateText.xml(params.officerName, 55), '</text>',
            '<text x="512" y="645" font-size="16" fill="#9A9A98" text-anchor="middle">', CertificateText.xml(params.officerTitle, 55), '</text>'
        ));
    }

    function _buildRestrictionsText(string[] memory restrictions) private pure returns (string memory) {
        string memory result = '<text x="131" y="670" font-size="14" fill="#9A9A98">Transfer Restrictions:</text>';
        for (uint256 i = 0; i < restrictions.length && i < 6; i++) {
            result = string(abi.encodePacked(
                result,
                '<text x="131" y="', _uintToString(690 + i * 20), '" font-size="11" fill="#9A9A98">[', _uintToString(i + 1), '] ', CertificateText.xml(restrictions[i], 105), ' </text>'
            ));
        }
        if (restrictions.length > 6) result = string.concat(result, '<text x="131" y="810" font-size="11" fill="#9A9A98">Additional restrictions in token metadata</text>');
        return result;
    }

    // ------------------------------------------------------------------
    // Formatting helpers
    // ------------------------------------------------------------------

    function _securityClassToString(SecurityClass _class) private pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "SAFE";
        if (_class == SecurityClass.SAFT) return "SAFT";
        if (_class == SecurityClass.SAFTE) return "SAFTE";
        if (_class == SecurityClass.TokenPurchaseAgreement) return "Token Purchase Agreement";
        if (_class == SecurityClass.TokenWarrant) return "Token Warrant";
        if (_class == SecurityClass.ConvertibleNote) return "Convertible Note";
        if (_class == SecurityClass.CommonStock) return "Common Stock";
        if (_class == SecurityClass.StockOption) return "Stock Option";
        if (_class == SecurityClass.PreferredStock) return "Preferred Stock";
        if (_class == SecurityClass.RestrictedStockPurchaseAgreement) return "Restricted Stock Purchase Agreement";
        if (_class == SecurityClass.RestrictedStockUnit) return "Restricted Stock Unit";
        if (_class == SecurityClass.RestrictedTokenPurchaseAgreement) return "Restricted Token Purchase Agreement";
        if (_class == SecurityClass.RestrictedTokenUnit) return "Restricted Token Unit";
        if (_class == SecurityClass.MembershipInterest) return "Membership Interest";
        return "Unknown";
    }

    function _securitySeriesToString(SecuritySeries _series) private pure returns (string memory) {
        if (_series == SecuritySeries.SeriesPreSeed) return "Pre-Seed";
        if (_series == SecuritySeries.SeriesSeed) return "Series Seed";
        if (_series == SecuritySeries.SeriesA) return "Series A";
        if (_series == SecuritySeries.SeriesB) return "Series B";
        if (_series == SecuritySeries.SeriesC) return "Series C";
        if (_series == SecuritySeries.SeriesD) return "Series D";
        if (_series == SecuritySeries.SeriesE) return "Series E";
        if (_series == SecuritySeries.SeriesF) return "Series F";
        if (_series == SecuritySeries.NA) return "";
        if (_series == SecuritySeries.ACE) return "ACE";
        return "";
    }

    function _getBaseUnit(SecurityClass _class) private pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "Instruments";
        if (_class == SecurityClass.SAFT) return "Instruments";
        if (_class == SecurityClass.SAFTE) return "Instruments";
        if (_class == SecurityClass.TokenPurchaseAgreement) return "Tokens";
        if (_class == SecurityClass.TokenWarrant) return "Tokens";
        if (_class == SecurityClass.ConvertibleNote) return "Notes";
        if (_class == SecurityClass.CommonStock) return "Shares";
        if (_class == SecurityClass.StockOption) return "Shares";
        if (_class == SecurityClass.PreferredStock) return "Shares";
        if (_class == SecurityClass.RestrictedStockPurchaseAgreement) return "Units";
        if (_class == SecurityClass.RestrictedStockUnit) return "Units";
        if (_class == SecurityClass.RestrictedTokenPurchaseAgreement) return "Units";
        if (_class == SecurityClass.RestrictedTokenUnit) return "Units";
        if (_class == SecurityClass.MembershipInterest) return "Units";
        return "Unknown";
    }

    /// @notice Convertible securities (SAFEs/SAFTs/SAFTEs etc.) represent a single instrument
    function _isConvertible(SecurityClass _class) private pure returns (bool) {
        return _class == SecurityClass.SAFE ||
               _class == SecurityClass.SAFT ||
               _class == SecurityClass.SAFTE ||
               _class == SecurityClass.ConvertibleNote ||
               _class == SecurityClass.TokenWarrant ||
               _class == SecurityClass.TokenPurchaseAgreement;
    }

    /// @notice Units displayed: unitsRepresented for shares/units, always 1 for convertibles
    function _formatUnits(CertificateSVGParams memory params) private pure returns (string memory) {
        if (_isConvertible(params.securityType)) {
            return "1";
        }
        return _formatDecimal18(params.units);
    }

    /// @notice Consideration displayed: price per share for shares/units (e.g. "0.0000001/sh"),
    ///         total consideration for convertibles, without assuming a currency.
    function _formatConsideration(CertificateSVGParams memory params) private pure returns (string memory) {
        if (!params.considerationKnown) return "";
        if (_isConvertible(params.securityType)) {
            return _formatDecimal18(params.consideration);
        }
        if (params.units == 0) {
            return "";
        }
        // mulDiv handles a 512-bit product, provided the quotient fits in uint256.
        if (params.units < 1e18 && params.consideration > Math.mulDiv(type(uint256).max, params.units, 1e18)) return "";
        uint256 perUnit = Math.mulDiv(params.consideration, 1e18, params.units);
        string memory suffix = (params.securityType == SecurityClass.CommonStock || params.securityType == SecurityClass.PreferredStock || params.securityType == SecurityClass.StockOption) ? "/sh" : "/unit";
        return string(abi.encodePacked(_formatPrice(perUnit), suffix));
    }

    /// @notice Rounds the price per unit for display. The price is a derived figure, not a ledger fact.
    ///         A price of 1 or more keeps 4 decimals.
    ///         A price below 1 keeps 4 digits from its first non-zero digit. Thus a tiny price does not show as 0.
    ///
    ///         | Exact price      | Shown         |
    ///         |------------------|---------------|
    ///         | 26.213300999...  | 26.2133       |
    ///         | 1.99995          | 2             |
    ///         | 0.666666...      | 0.6667        |
    ///         | 0.0000001        | 0.0000001     |
    ///         | 0.0000000666...  | 0.00000006667 |
    function _formatPrice(uint256 value) private pure returns (string memory) {
        uint256 leadingZeros;
        for (uint256 v = value; v < 1e17 && leadingZeros < 14; v *= 10) leadingZeros++;
        uint256 decimals = 4 + leadingZeros;
        uint256 scale = 10 ** (18 - decimals);
        uint256 rounded = value / scale;
        if (value % scale >= scale / 2) rounded++;
        return _formatFixed(rounded, decimals);
    }

    /// @notice A long number gets a smaller font so that it stays in its column.
    ///         A digit in the bold system font is about 0.6 of the font size wide.
    function _fitFontSize(string memory text, uint256 width, uint256 maxSize) private pure returns (string memory) {
        uint256 len = bytes(text).length;
        if (len == 0) return _uintToString(maxSize);
        return _uintToString(Math.min(maxSize, width * 5 / (len * 3)));
    }

    /// @notice Formats an 18-decimal value without dropping fractional units.
    function _formatDecimal18(uint256 value) private pure returns (string memory) {
        return _formatFixed(value, 18);
    }

    /// @notice Formats a value with `decimals` fractional digits. It drops trailing zeros.
    function _formatFixed(uint256 value, uint256 decimals) private pure returns (string memory) {
        uint256 scale = 10 ** decimals;
        uint256 wholePart = value / scale;
        uint256 frac = value % scale;
        if (frac == 0) {
            return _formatNumberWithCommas(wholePart);
        }

        bytes memory fracDigits = new bytes(decimals);
        uint256 f = frac;
        for (uint256 i = decimals; i > 0; i--) {
            fracDigits[i - 1] = bytes1(uint8(48 + (f % 10)));
            f /= 10;
        }
        uint256 len = decimals;
        while (len > 0 && fracDigits[len - 1] == "0") {
            len--;
        }
        bytes memory trimmed = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            trimmed[i] = fracDigits[i];
        }
        return string(abi.encodePacked(_formatNumberWithCommas(wholePart), ".", trimmed));
    }

    /// @notice Formats a timestamp as "M-D-YYYY" (e.g. "7-1-2026")
    function _formatDate(uint256 timestamp) private pure returns (string memory) {
        // Zero is unknown. Support Gregorian UTC dates through 9999-12-31.
        if (timestamp == 0 || timestamp > 253402300799) return "";
        uint256 totalDays = timestamp / 86400;

        uint256 y = 1970;
        uint256 daysRemaining = totalDays;
        // A Gregorian 400-year cycle is exact, limiting the loop to 399 iterations.
        y += (daysRemaining / 146097) * 400;
        daysRemaining %= 146097;
        while (daysRemaining >= (_isLeapYear(y) ? 366 : 365)) {
            daysRemaining -= _isLeapYear(y) ? 366 : 365;
            y++;
        }

        uint8[12] memory daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if (_isLeapYear(y)) {
            daysInMonth[1] = 29;
        }

        uint256 m = 0;
        while (m < 12 && daysRemaining >= daysInMonth[m]) {
            daysRemaining -= daysInMonth[m];
            m++;
        }

        return string(abi.encodePacked(
            _uintToString(m + 1), "-", _uintToString(daysRemaining + 1), "-", _uintToString(y)
        ));
    }

    function _isLeapYear(uint256 y) private pure returns (bool) {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    /// @notice Truncates an address to "0x12345678...1234567890" form
    function _truncatedAddress(address addr) private pure returns (string memory) {
        if (addr == address(0)) return "";
        bytes memory hexChars = "0123456789abcdef";
        bytes memory full = new bytes(40);
        uint160 value = uint160(addr);
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(value >> (8 * (19 - i)));
            full[i * 2] = hexChars[b >> 4];
            full[i * 2 + 1] = hexChars[b & 0x0f];
        }
        bytes memory head = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            head[i] = full[i];
        }
        bytes memory tail = new bytes(10);
        for (uint256 i = 0; i < 10; i++) {
            tail[i] = full[30 + i];
        }
        return string(abi.encodePacked("0x", head, "...", tail));
    }

    /// @notice Formats a number with commas as thousand separators (e.g. 2,500,000)
    function _formatNumberWithCommas(uint256 _i) private pure returns (string memory) {
        if (_i == 0) return "0";

        uint256 j = _i;
        uint256 digitCount;
        while (j != 0) {
            digitCount++;
            j /= 10;
        }

        uint256 commaCount = (digitCount - 1) / 3;
        uint256 totalLength = digitCount + commaCount;

        bytes memory result = new bytes(totalLength);
        uint256 pos = totalLength;
        uint256 digitsSinceComma = 0;

        while (_i != 0) {
            if (digitsSinceComma == 3) {
                pos--;
                result[pos] = ",";
                digitsSinceComma = 0;
            }
            pos--;
            result[pos] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
            digitsSinceComma++;
        }

        return string(result);
    }

    function _uintToString(uint256 _i) private pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (_i != 0) {
            k--;
            bstr[k] = bytes1(uint8(48 + uint256(_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }
}
