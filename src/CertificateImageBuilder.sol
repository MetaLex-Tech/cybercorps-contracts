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

import "./creds/storage/lexchexStorage.sol";

/// @title CertificateImageBuilder
/// @notice Minimal SVG builder used by CertificateUriBuilder; mirrors LeXcheX styling
library CertificateImageBuilder {
    function buildLexChexSVG(Accreditation memory acc) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xhtml="http://www.w3.org/1999/xhtml" version="1.1" width="1000" height="650">',
            '<rect width="100%" height="100%"  fill="#191a18"/>',
            _generateMetaLeXLogo(),
            _generateSVGBody(acc),
            '</svg>'
        ));
    }

    function buildCertificateSVG(
        string memory corpName,
        string memory securityType,
        string memory officerName,
        string memory officerTitle,
        uint256 units,
        uint256 valuation
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="1000" height="650">',
            '<rect width="100%" height="100%" fill="#191a18"/>',
            _generateDefs(),
            '<rect width="100%" height="100%" fill="url(#grad1)"/>',
            '<text x="90" y="120" font-family="Georgia" font-size="42" fill="#f2f2f2">', corpName, '</text>',
            '<text x="90" y="170" font-family="Georgia" font-size="26" fill="#daff00">', securityType, '</text>',
            '<text x="90" y="240" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".9">Officer</text>',
            '<text x="220" y="240" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".9">', officerName, ' (', officerTitle, ')</text>',
            '<text x="90" y="280" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".8">Units</text>',
            '<text x="220" y="280" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".8">', _uintToString(units), '</text>',
            '<text x="90" y="320" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".8">Issuer Valuation (USD)</text>',
            '<text x="390" y="320" font-family="Georgia" font-size="20" fill="#f2f2f2" opacity=".8">', _uintToString(valuation), '</text>',
            _generateMetaLeXLogo(),
            '</svg>'
        ));
    }

    function _generateMetaLeXLogo() private pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg x="880" y="570" width="61" height="30" viewBox="0 0 61 30" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<path d="M29.5488 0C30.5107 0 31.291 0.779753 31.291 1.74121V11.957C31.291 12.543 30.9957 13.0902 30.5059 13.4121L6.69629 29.0605C6.41221 29.2472 6.07921 29.3467 5.73926 29.3467H1.74121C0.779536 29.3465 0 28.5668 0 27.6055V19.9648C8.27261e-05 19.3799 0.293816 18.8339 0.782227 18.5117L28.415 0.288086C28.6996 0.100412 29.0331 0 29.374 0H29.5488ZM54.7832 0.000976562C55.745 0.000976562 56.5243 0.77984 56.5244 1.74121V11.957C56.5244 12.543 56.23 13.0902 55.7402 13.4121L31.9307 29.0605C31.6465 29.2473 31.3137 29.3467 30.9736 29.3467H26.9756C26.0139 29.3466 25.2344 28.5669 25.2344 27.6055V19.9648C25.2345 19.38 25.5282 18.8338 26.0166 18.5117L53.6494 0.288086C53.934 0.100488 54.2675 0.000976562 54.6084 0.000976562H54.7832ZM58.9521 15.54C59.825 14.9532 60.9997 15.5783 61 16.6299V27.792C60.9999 28.6506 60.3033 29.3467 59.4443 29.3467H48.5459C47.687 29.3466 46.9903 28.6505 46.9902 27.792V24.3594C46.9902 23.842 47.2484 23.3582 47.6777 23.0693L58.9521 15.54Z" fill="#DAFF00"/>',
                '</svg>'
            )
        );
    }

    function _generateSVGBody(Accreditation memory acc) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="0" y="83" width="1000px" height="50px" fill="url(#linGrad)"></rect>',
                '<text x="212" y="126" font-family="Georgia " font-size="53" fill="url(#textGrad)">U.S. Accredited Investor</text>',
                '<text x="249" y="226" font-family="Georgia" font-size="25" fill="#f2f2f2">THE HOLDER OF THIS CERTIFICATE IS A</text>',
                '<text x="318" y="266" font-family="Georgia" font-size="25" fill="#f2f2f2">U.S. ACCREDITED INVESTOR </text>',
                _generateDefs(),
                '<rect width="100%" height="100%" fill="url(#grad1)" />',
                '<text x="150" y="360" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6" >CERTIFIED BY</text>',
                '<text x="385" y="355" font-family="Georgia" font-size="30" fill="url(#textGrad)" >Gabriel Shapiro, Esq., of MetaLeX</text>',
                '<rect x="380" y="363" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="150" y="450" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">GOOD UNTIL</text>',
                '<text x="495" y="440" font-family="Georgia" font-size="30" fill="url(#textGrad)" >',
                _timestampToDate(acc.expiryDate),
                '</text>',
                '<rect x="380" y="453" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="325" y="570" font-family="Georgia" font-size="17" fill="#f2f2f2" opacity=".6">Non-transferable. Soul-bound. Verified on-chain.</text>',
                '<text x="210" y="600" font-family="Georgia" font-size="15" fill="#f2f2f2" opacity=".24">',
                _bytes32ToHexString(acc.agreementId),
                '</text>'
            )
        );
    }

    function _generateDefs() private pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<defs>',
                '<radialGradient id="grad1" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.07" />',
                '<stop offset="100%" style="stop-color:#191a18; stop-opacity:.07" />',
                '</radialGradient>',
                '<linearGradient id="linGrad">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.4" />',
                '<stop offset="20%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="80%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="100%" style="stop-color:#daff00; stop-opacity:.4" />',
                '</linearGradient>',
                '<linearGradient id="textGrad" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#F2F8CB; stop-opacity:1" />',
                '</linearGradient>',
                '</defs>'
            )
        );
    }

    function _timestampToDate(uint256 timestamp) private pure returns (string memory) {
        uint256 day = ((timestamp / 86400) % 31) + 1;
        uint256 month = ((timestamp / 2629743) % 12) + 1;
        uint256 year = (timestamp / 31556926) + 1970;
        return string(abi.encodePacked(_uintToString(month), '/', _uintToString(day), '/', _uintToString(year)));
    }

    function _bytes32ToHexString(bytes32 value) private pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = bytes1(uint8(uint256(uint8(value[i] >> 4)) + (uint256(uint8(value[i] >> 4)) < 10 ? 48 : 87)));
            str[i * 2 + 1] = bytes1(uint8(uint256(uint8(value[i] & 0x0f)) + (uint256(uint8(value[i] & 0x0f)) < 10 ? 48 : 87)));
        }
        return string(abi.encodePacked("0x", string(str)));
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


