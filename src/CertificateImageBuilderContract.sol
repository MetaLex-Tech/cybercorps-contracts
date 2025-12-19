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
import "./interfaces/ICertificateImageBuilder.sol";

/// @title CertificateImageBuilderContract
/// @notice Standalone contract for building certificate SVG images
/// @dev Deployed separately to reduce CertificateUriBuilder contract size
contract CertificateImageBuilderContract is ICertificateImageBuilder {
    
    /// @inheritdoc ICertificateImageBuilder
    function buildCertificateSVG(
        CertificateSVGParams calldata params,
        uint256 timestamp
    ) external pure override returns (string memory) {
        return string(abi.encodePacked(
            _getSVGHeader(),
            _getSVGBackground(),
            _buildSVGContent(params, timestamp),
            '</svg>'
        ));
    }

    function _getSVGHeader() private pure returns (string memory) {
        return '<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_23552_60894)"><rect width="1024" height="1024" fill="#141413"/>';
    }

    function _getSVGBackground() private pure returns (string memory) {
        return string(abi.encodePacked(
            _getBackgroundPaths(),
            _getSVGDecorativeElements()
        ));
    }

    function _getBackgroundPaths() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M972.495 106.002C980.492 106.002 986.974 112.482 986.975 120.476V205.417C986.975 210.289 984.523 214.835 980.45 217.512L782.487 347.62C780.125 349.173 777.359 350 774.532 350H741.29C733.293 350 726.81 343.519 726.81 335.525V271.998C726.81 267.134 729.254 262.596 733.315 259.917L963.065 108.395C965.432 106.834 968.205 106.002 971.04 106.002H972.495ZM1007.15 235.208C1014.41 230.324 1024.18 235.523 1024.18 244.27V337.072C1024.18 344.212 1018.39 349.999 1011.25 349.999H920.636C913.494 349.999 907.703 344.212 907.703 337.072V308.529C907.703 304.228 909.844 300.208 913.414 297.806L1007.15 235.208ZM762.685 106C770.682 106 777.165 112.481 777.165 120.475V205.415C777.165 210.287 774.712 214.833 770.64 217.51L572.677 347.618C570.314 349.171 567.549 349.998 564.722 349.998H531.479C523.483 349.998 517 343.517 517 335.523V271.997C517 267.133 519.444 262.594 523.506 259.915L753.256 108.393C755.622 106.832 758.395 106 761.229 106H762.685Z" fill="#F2F2F2" fill-opacity="0.02"/>',
            '<path d="M51.6885 106.002C43.6916 106.002 37.2093 112.482 37.209 120.476V205.417C37.209 210.289 39.6607 214.835 43.7334 217.512L241.696 347.62C244.059 349.173 246.824 350 249.651 350H282.894C290.891 350 297.374 343.519 297.374 335.525V271.998C297.374 267.134 294.93 262.596 290.868 259.917L61.1182 108.395C58.7517 106.834 55.9786 106.002 53.1436 106.002H51.6885ZM17.0303 235.208C9.77133 230.324 0.000366211 235.523 0 244.27V337.072C6.10352e-05 344.212 5.78955 349.999 12.9316 349.999H103.548C110.69 349.999 116.48 344.212 116.48 337.072V308.529C116.48 304.228 114.339 300.208 110.77 297.806L17.0303 235.208ZM261.499 106C253.502 106 247.019 112.481 247.019 120.475V205.415C247.019 210.287 249.471 214.833 253.544 217.51L451.507 347.618C453.869 349.171 456.635 349.998 459.462 349.998H492.704C500.701 349.998 507.184 343.517 507.184 335.523V271.997C507.184 267.133 504.739 262.594 500.678 259.915L270.928 108.393C268.561 106.832 265.789 106 262.954 106H261.499Z" fill="#F2F2F2" fill-opacity="0.02"/>',
            '<circle cx="512" cy="512" r="512" fill="url(#paint0_radial_23552_60894)" fill-opacity="0.04"/>'
        ));
    }

    function _getSVGDecorativeElements() private pure returns (string memory) {
        return string(abi.encodePacked(
            _getTopDecorations(),
            _getMidDecorations(),
            '</g>'
        ));
    }

    function _getTopDecorations() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M120 163H96L120 147V163Z" fill="#262624" />',
            '<rect width="68" height="16" transform="translate(120 147)" fill="#262624" />',
            '<path d="M188 163H212L188 147V163Z" fill="#262624" />',
            '<rect width="144" height="47" transform="translate(80 163)" fill="#1d1d1c" />',
            '<path d="M120 210H108L120 218V210Z" fill="#262624" />',
            '<rect width="64" height="8" transform="translate(120 210)" fill="#262624" />',
            '<path d="M184 210H196L184 218V210Z" fill="#262624" />',
            '<path d="M840 163H816L840 147V163Z" fill="#262624" />',
            '<rect width="64" height="16" transform="translate(840 147)" fill="#262624"/>',
            '<path d="M904 163H928L904 147V163Z" fill="#262624" />',
            '<rect width="144" height="47" transform="translate(800 163)" fill="#1d1d1c" />',
            '<path d="M840 210H828L840 218V210Z" fill="#262624" />',
            '<rect width="64" height="8" transform="translate(840 210)" fill="#262624" />',
            '<path d="M904 210H916L904 218V210Z" fill="#262624" />'
        ));
    }

    function _getMidDecorations() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<mask id="path-13-inside-1_23552_60894" fill="white"><path d="M80 218H944V351H80V218Z"/></mask>',
            '<path d="M80 218H944V351H80V218Z" fill="url(#paint1_radial_23552_60894)" fill-opacity="0.1"/>',
            '<path d="M944 351V350H80V351V352H944V351Z" fill="url(#paint2_linear_23552_60894)" mask="url(#path-13-inside-1_23552_60894)"/>',
            '<path d="M597 351L593 357L431 357L427 351L597 351Z" fill="#DAFF00"/>',
            '<line x1="128" y1="741.5" x2="426" y2="741.5" stroke="#F2F2F2" stroke-opacity="0.24"/>',
            '<path d="M245 742H221L245 758V742Z" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<rect width="76" height="16" transform="translate(245 742)" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<path d="M321 742H345L321 758V742Z" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<line x1="598" y1="741.5" x2="896" y2="741.5" stroke="#F2F2F2" stroke-opacity="0.24"/>',
            '<path d="M715 742H691L715 758V742Z" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<rect width="77" height="16" transform="translate(715 742)" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<path d="M792 742H816L792 758V742Z" fill="#F2F2F2" fill-opacity="0.06"/>',
            '<path d="M427 814L431 808L593 808L597 814L427 814Z" fill="#DAFF00"/>',
            '<mask id="path-23-inside-2_23552_60894" fill="white"><path d="M944 922L80 922L80 814L944 814L944 922Z"/></mask>',
            '<path d="M944 922L80 922L80 814L944 814L944 922Z" fill="url(#paint3_radial_23552_60894)" fill-opacity="0.1"/>',
            '<path d="M80 814L80 815L944 815L944 814L944 813L80 813L80 814Z" fill="url(#paint4_linear_23552_60894)" mask="url(#path-23-inside-2_23552_60894)"/>'
        ));
    }

    function _buildSVGContent(
        CertificateSVGParams calldata params,
        uint256 timestamp
    ) private pure returns (string memory) {
        (string memory day, string memory month, string memory year) = _getDateComponents(timestamp);
        
        return string(abi.encodePacked(
            _buildDefs(),
            _buildHeader(params),
            _buildMiddleSection(params),
            _buildFooter(params, day, month, year)
        ));
    }

    function _buildDefs() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<defs>',
            '<radialGradient id="paint0_radial_23552_60894" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(512 512) rotate(90) scale(512)">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#191A18"/></radialGradient>',
            '<radialGradient id="paint1_radial_23552_60894" cx="0" cy="0" r="1" gradientTransform="matrix(-0.0961874 -88.2743 380.979 -0.400474 534.169 323.929)" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></radialGradient>',
            '<linearGradient id="paint2_linear_23552_60894" x1="80" y1="284.5" x2="944" y2="284.5" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00" stop-opacity="0"/><stop offset="0.524038" stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient>',
            '<radialGradient id="paint3_radial_23552_60894" cx="0" cy="0" r="1" gradientTransform="matrix(0.0961936 71.6814 -380.979 0.32523 489.831 835.982)" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></radialGradient>',
            '<linearGradient id="paint4_linear_23552_60894" x1="944" y1="868" x2="80" y2="868" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00" stop-opacity="0"/><stop offset="0.524038" stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient>',
            '<clipPath id="clip0_23552_60894"><rect width="1024" height="1024" fill="white"/></clipPath></defs>'
        ));
    }

    function _buildHeader(CertificateSVGParams calldata params) private pure returns (string memory) {
        string memory formattedUnits = _formatUnits(params.units, params.securityType);
        return string(abi.encodePacked(
            '<text x="512" y="250" font-size="53" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">', params.corpName, '</text>',
            '<text x="152" y="159" font-size="11" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">Token ID</text>',
            '<text x="152" y="198" font-size="35" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">#', _uintToString(params.tokenId), '</text>',
            '<text x="872" y="158" font-size="11" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">', _getBaseUnit(params.securityType), '</text>',
            '<text x="872" y="198" font-size="35" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">', formattedUnits, '</text>',
            '<text x="512" y="308" font-size="25" font-family="system-ui" text-anchor="middle" fill="#DAFF00">', _securitySeriesToString(params.securitySeries), ' ', _securityClassToString(params.securityType), '</text>'
        ));
    }

    function _buildMiddleSection(CertificateSVGParams calldata params) private pure returns (string memory) {
        if (_isConvertible(params.securityType)) {
            return _buildMiddleConvertible(params);
        }
        return _buildMiddleShares(params);
    }

    function _buildMiddleConvertible(CertificateSVGParams calldata params) private pure returns (string memory) {
        string memory formattedUnits = _formatUnits(params.units, params.securityType);
        string memory securityFullName = _getSecurityFullName(params.securityType);
        return string(abi.encodePacked(
            '<text x="150" y="418" font-weight="600" font-size="18" font-family="system-ui" fill="#f2f2f2">This Certifies that </text>',
            '<text x="420" y="418" font-size="18" font-family="system-ui" text-anchor="middle" fill="#DAFF00">', params.ownerName, '</text>',
            '<line x1="310" x2="520" y1="423" y2="423" stroke-width="2" stroke="#333423"/>',
            '<line x1="760" x2="870" y1="418" y2="418" stroke-width="2" stroke="#333423"/>',
            '<text x="540" y="418" font-size="18" font-family="system-ui" fill="#9A9A98">is the registered holder of</text>',
            '<text x="810" y="414" font-size="18" font-family="system-ui" text-anchor="middle" fill="#DAFF00">1</text>',
            '<text x="330" y="450" font-size="18" font-family="system-ui" text-anchor="middle" fill="#DAFF00">', securityFullName, '</text>',
            _buildMiddleConvertiblePart2(params, formattedUnits)
        ));
    }

    function _buildMiddleConvertiblePart2(CertificateSVGParams calldata params, string memory formattedUnits) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<line x1="150" x2="510" y1="455" y2="455" stroke-width="2" stroke="#333423"/>',
            '<text x="520" y="450" font-size="18" font-family="system-ui" fill="#9A9A98">of</text>',
            '<text x="630" y="450" font-size="18" font-family="system-ui" fill="#DAFF00">', params.corpName, '</text>',
            '<line x1="550" x2="870" y1="455" y2="455" stroke-width="2" stroke="#333423"/>',
            '<text x="150" y="482" font-size="18" font-family="system-ui" fill="#9A9A98">purchased from the said Entity for</text>',
            '<text x="490" y="482" font-size="18" font-family="system-ui" fill="#DAFF00">', formattedUnits, '</text>',
            '<line x1="450" x2="600" y1="487" y2="487" stroke-width="2" stroke="#333423"/>',
            '<text x="610" y="482" font-size="18" font-family="system-ui" fill="#9A9A98">and transferable only in </text>',
            '<text x="150" y="514" font-size="18" font-family="system-ui" fill="#9A9A98">accordance with the terms and conditions thereof and any other applicable agreements</text>',
            '<text x="150" y="546" font-size="18" font-family="system-ui" fill="#9A9A98"> between or involving or applicable to the said Entity and the said registered Holder.</text>'
        ));
    }

    function _buildMiddleShares(CertificateSVGParams calldata params) private pure returns (string memory) {
        string memory formattedUnits = _formatUnits(params.units, params.securityType);
        string memory unitType = _buildUnitType(params.securityType, params.securitySeries);
        return string(abi.encodePacked(
            '<text x="235" y="418" font-weight="600" font-size="20" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">This Certifies That</text>',
            '<line x1="330" x2="635" y1="425" y2="425" stroke-width="2" stroke="#333423"/>',
            '<text x="482.5" y="418" font-size="20" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', params.ownerName, '</text>',
            '<text x="760" y="418" font-size="20" font-family="system-ui" fill="#9A9A98" text-anchor="middle">is the registered holder of</text>',
            '<text x="222.5" y="463" font-size="20" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', formattedUnits, '</text>',
            '<line x1="150" x2="295" y1="468" y2="468" stroke-width="2" stroke="#333423"/>',
            _buildMiddleSharesPart2(params, unitType)
        ));
    }

    function _buildMiddleSharesPart2(CertificateSVGParams calldata params, string memory unitType) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="437.5" y="463" font-size="20" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', unitType, '</text>',
            '<line x1="320" x2="555" y1="468" y2="468" stroke-width="2" stroke="#333423"/>',
            '<text x="747.5" y="463" font-size="20" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', params.corpName, '</text>',
            '<line x1="620" x2="875" y1="468" y2="468" stroke-width="2" stroke="#333423"/>',
            '<text x="580" y="463" font-size="20" font-family="system-ui" fill="#9A9A98">of</text>',
            '<text x="150" y="518" font-size="20" font-family="system-ui" fill="#9A9A98">transferable only on the books of the Corporation by the holder hereof in person or by</text>',
            '<text x="150" y="545" font-size="20" font-family="system-ui" fill="#9A9A98">Attorney upon surrender of this Certificate properly endorsed.</text>'
        ));
    }

    function _buildFooter(
        CertificateSVGParams calldata params,
        string memory day,
        string memory month,
        string memory year
    ) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="150" y="590" font-weight="600" font-size="18" font-family="system-ui" fill="#f2f2f2">In Witness Whereof</text>',
            '<text x="310" y="590" font-size="18" font-family="system-ui" fill="#9A9A98">, the said Entity has caused this Certificate to be signed by its duly</text>',
            '<text x="150" y="620" font-size="18" font-family="system-ui" fill="#9A9A98">authorized officer(s)</text>',
            _buildFooterDate(day, month, year),
            _buildFooterSignature(params)
        ));
    }

    function _buildFooterDate(string memory day, string memory month, string memory year) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="175" y="675" font-size="18" font-family="system-ui" fill="#9A9A98" text-anchor="middle">This</text>',
            '<text x="285" y="675" font-size="18" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', day, '</text>',
            '<line x1="200" x2="370" y1="680" y2="680" stroke-width="2" stroke="#333423"/>',
            '<text x="417.5" y="675" font-size="18" font-family="system-ui" fill="#9A9A98" text-anchor="middle">day of</text>',
            '<text x="565" y="675" font-size="18" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', month, '</text>',
            '<line x1="465" x2="675" y1="680" y2="680" stroke-width="2" stroke="#333423"/>',
            '<text x="705" y="675" font-size="18" font-family="system-ui" fill="#9A9A98" text-anchor="middle">A.D.</text>',
            '<text x="820" y="675" font-size="18" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', year, '</text>',
            '<line x1="745" x2="895" y1="680" y2="680" stroke-width="2" stroke="#333423"/>'
        ));
    }

    function _buildFooterSignature(CertificateSVGParams calldata params) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="285" y="736" font-size="18" font-family="system-ui" fill="#DAFF00" text-anchor="middle">', params.officerName, '</text>',
            '<text x="283" y="753" font-size="11" font-family="system-ui" fill="#f2f2f2" text-anchor="middle">', params.officerTitle, '</text>',
            '<text x="512" y="850" font-size="11" font-family="system-ui" fill="#9A9A98" text-anchor="middle">Link to full certificate: ', params.certificateUri, '</text>'
        ));
    }

    // Helper functions
    function _formatUnits(uint256 units, SecurityClass securityType) private pure returns (string memory) {
        string memory formattedUnits = _uintToString(units);
        if (_isDollarBased(securityType)) {
            return string(abi.encodePacked("$", formattedUnits));
        }
        return formattedUnits;
    }

    function _isDollarBased(SecurityClass _class) private pure returns (bool) {
        return _class == SecurityClass.SAFE || _class == SecurityClass.SAFT || _class == SecurityClass.SAFTE;
    }

    function _isConvertible(SecurityClass _class) private pure returns (bool) {
        return _class == SecurityClass.SAFE || 
               _class == SecurityClass.SAFT || 
               _class == SecurityClass.SAFTE || 
               _class == SecurityClass.ConvertibleNote ||
               _class == SecurityClass.TokenWarrant ||
               _class == SecurityClass.TokenPurchaseAgreement;
    }

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
        return "";
    }

    function _getBaseUnit(SecurityClass _class) private pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "Dollars";
        if (_class == SecurityClass.SAFT) return "Dollars";
        if (_class == SecurityClass.SAFTE) return "Dollars";
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
        return "Unknown";
    }

    function _buildUnitType(SecurityClass _class, SecuritySeries _series) private pure returns (string memory) {
        if (_class == SecurityClass.SAFE || _class == SecurityClass.SAFT || _class == SecurityClass.SAFTE) {
            return string(abi.encodePacked("Dollars of the ", _securitySeriesToString(_series), " ", _securityClassToString(_class)));
        }
        return _getBaseUnit(_class);
    }

    function _getSecurityFullName(SecurityClass _class) private pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "Simple Agreement for Future Equity";
        if (_class == SecurityClass.SAFT) return "Simple Agreement for Future Tokens";
        if (_class == SecurityClass.SAFTE) return "Simple Agreement for Future Tokens or Equity";
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
        return "Unknown";
    }

    function _getDateComponents(uint256 timestamp) private pure returns (string memory day, string memory month, string memory year) {
        uint256 totalDays = timestamp / 86400;
        uint256 y = 1970;
        uint256 daysRemaining = totalDays;
        
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
        
        day = _uintToString(daysRemaining + 1);
        month = _getMonthName(m + 1);
        year = _uintToString(y);
    }

    function _isLeapYear(uint256 y) private pure returns (bool) {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    function _getMonthName(uint256 month) private pure returns (string memory) {
        if (month == 1) return "January";
        if (month == 2) return "February";
        if (month == 3) return "March";
        if (month == 4) return "April";
        if (month == 5) return "May";
        if (month == 6) return "June";
        if (month == 7) return "July";
        if (month == 8) return "August";
        if (month == 9) return "September";
        if (month == 10) return "October";
        if (month == 11) return "November";
        if (month == 12) return "December";
        return "Unknown";
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

