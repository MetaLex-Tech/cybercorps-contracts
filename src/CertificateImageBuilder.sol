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
import "./creds/storage/lexchexStorage.sol";
import "./CertificateImageContentBuilder.sol";

/// @title CertificateImageBuilder
/// @notice SVG builder used by CertificateUriBuilder; renders the "Ledger Entry Token" certificate
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
        CertificateSVGParams memory params,
        uint256 timestamp
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            _getSVGHeader(),
            _getSVGFrame(params.isVoided),
            '</g>',
            CertificateImageContentBuilder.buildSVGContent(params, timestamp),
            '</svg>'
        ));
    }

    function _getSVGHeader() private pure returns (string memory) {
        return '<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_63528_2)"><rect width="1024" height="1024" fill="#141413"/>';
    }

    /// @notice Static frame: corner motifs, top/bottom bands, stats panel and bottom tiles
    function _getSVGFrame(bool voided) private pure returns (string memory) {
        return string(abi.encodePacked(
            _getCornerMotifs(),
            _getTopDecorations(),
            _getTopBand(voided),
            _getStatsPanel(),
            _getBottomBand(),
            _getBottomTiles()
        ));
    }

    function _getCornerMotifs() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<path id="corner" d="M972.495 3.00195C980.492 3.00207 986.974 9.48185 986.975 17.4756V102.417C986.975 107.289 984.523 111.835 980.45 114.512L782.487 244.62C780.125 246.173 777.359 247 774.532 247H741.29C733.293 247 726.81 240.519 726.81 232.525V168.998C726.81 164.134 729.254 159.596 733.315 156.917L963.065 5.39453C965.432 3.83384 968.205 3.00195 971.04 3.00195H972.495ZM1007.15 132.208C1014.41 127.324 1024.18 132.523 1024.18 141.27V234.072C1024.18 241.212 1018.39 246.999 1011.25 246.999H920.636C913.494 246.999 907.703 241.212 907.703 234.072V205.529C907.703 201.228 909.844 197.208 913.414 194.806L1007.15 132.208ZM762.685 3C770.682 3 777.165 9.48058 777.165 17.4746V102.415C777.165 107.287 774.712 111.833 770.64 114.51L572.677 244.618C570.314 246.171 567.549 246.998 564.722 246.998H531.479C523.483 246.998 517 240.517 517 232.523V168.997C517 164.133 519.444 159.594 523.506 156.915L753.256 5.39258C755.622 3.83203 758.395 3.00007 761.229 3H762.685Z" fill="#F2F2F2" fill-opacity="0.02"/>',
            '<use href="#corner" transform="matrix(-1 0 0 1 1024.184 0)"/>',
            '<circle cx="512" cy="512" r="512" fill="url(#paint0_radial_63528_2)" fill-opacity="0.04"/>'
        ));
    }

    function _getTopDecorations() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<g fill="#F2F2F2">',
            '<path d="M121 89H97L121 73V89Z" fill-opacity="0.06"/>',
            '<rect width="68" height="16" transform="translate(121 73)" fill-opacity="0.06"/>',
            '<path d="M189 89H213L189 73V89Z" fill-opacity="0.06"/>',
            '<rect width="146" height="47" transform="translate(80 89)" fill-opacity="0.03"/>',
            '<path d="M121 136H109L121 144V136Z" fill-opacity="0.06"/>',
            '<rect width="64" height="8" transform="translate(121 136)" fill-opacity="0.06"/>',
            '<path d="M185 136H197L185 144V136Z" fill-opacity="0.06"/>',
            '<path d="M805 89H781L805 73V89Z" fill-opacity="0.06"/>',
            '<rect width="64" height="16" transform="translate(805 73)" fill-opacity="0.06"/>',
            '<path d="M869 89H893L869 73V89Z" fill-opacity="0.06"/>',
            '<rect width="214" height="47" transform="translate(730 89)" fill-opacity="0.03"/>',
            '<path d="M805 136H793L805 144V136Z" fill-opacity="0.06"/>',
            '<rect width="64" height="8" transform="translate(805 136)" fill-opacity="0.06"/>',
            '<path d="M869 136H881L869 144V136Z" fill-opacity="0.06"/>',
            '</g>'
        ));
    }

    function _getTopBand(bool voided) private pure returns (string memory) {
        return string(abi.encodePacked(
            '<mask id="path-13-inside-1_63528_2" fill="white"><path d="M80 144H944V248H80V144Z"/></mask>',
            '<rect x="1" y="1" width="78" height="14" rx="3" stroke="url(#paint1_linear_62911_11497)" stroke-opacity="0.1" stroke-width="2"/>',
            '<defs><linearGradient id="paint1_linear_62911_11497" x1="0" y1="8" x2="80" y2="8" gradientUnits="userSpaceOnUse">',
            '<stop stop-color="#DAFF00"/><stop offset="1" stop-color="#DAFF00" stop-opacity="0"/></linearGradient></defs>',
            '<path d="M80 144H944V248H80V144Z" fill="url(#paint1_radial_63528_2)" fill-opacity="0.1"/>',
            '<path d="M944 248V247H80V248V249H944V248Z" fill="url(#paint2_linear_63528_2)" mask="url(#path-13-inside-1_63528_2)"/>',
            _getStatusPill(voided),
            '<path d="M597 248L593 254L431 254L427 248L597 248Z" fill="#DAFF00"/>',
            '<rect x="511.5" y="309.5" width="1" height="61" fill="url(#vg)"/>'
        ));
    }

    /// @notice Status pill next to the "active"/"voided" label: lime when active, red when voided
    function _getStatusPill(bool voided) private pure returns (string memory) {
        if (voided) {
            return string(abi.encodePacked(
                '<rect x="832" y="212.5" width="80" height="16" rx="4" fill="url(#paint4_linear_void)"/>',
                '<rect x="833" y="213.5" width="78" height="14" rx="3" stroke="url(#paint5_linear_void)" stroke-opacity="0.1" stroke-width="2"/>'
            ));
        }
        return string(abi.encodePacked(
            '<rect x="832" y="212.5" width="80" height="16" rx="4" fill="url(#paint4_linear_63528_2)"/>',
            '<rect x="833" y="213.5" width="78" height="14" rx="3" stroke="url(#paint5_linear_63528_2)" stroke-opacity="0.1" stroke-width="2"/>'
        ));
    }

    function _getStatsPanel() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M128 478C128 474.686 130.686 472 134 472H890C893.314 472 896 474.686 896 478V557C896 560.314 893.314 563 890 563H134C130.686 563 128 560.314 128 557V478Z" fill="#F2F2F2" fill-opacity="0.03"/>',
            '<rect x="128" y="487" width="1" height="61" fill="url(#vg)"/>',
            '<rect x="383.667" y="487" width="1" height="61" fill="url(#vg)"/>',
            '<rect x="639.333" y="487" width="1" height="61" fill="url(#vg)"/>',
            '<rect x="895" y="487" width="1" height="61" fill="url(#vg)"/>'
        ));
    }

    function _getBottomBand() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<path d="M427 855L431 849L593 849L597 855L427 855Z" fill="#DAFF00"/>',
            '<mask id="path-26-inside-2_63528_2" fill="white"><path d="M944 981L80 981L80 855L944 855L944 981Z"/></mask>',
            '<path d="M944 981L80 981L80 855L944 855L944 981Z" fill="url(#paint11_radial_63528_2)" fill-opacity="0.1"/>',
            '<path d="M80 855L80 856L944 856L944 855L944 854L80 854L80 855Z" fill="url(#paint12_linear_63528_2)" mask="url(#path-26-inside-2_63528_2)"/>',
            '<path d="M899 1020L883 1020L899 996L899 1020Z" fill="#F2F2F2" fill-opacity="0.01"/>'
        ));
    }

    /// @notice Bottom "In code we trust" tile row, defined once and reused via <use>
    function _getBottomTiles() private pure returns (string memory) {
        return string(abi.encodePacked(
            '<defs><g id="t" fill="#F2F2F2">',
            '<path d="M20 1020L4 1020L20 996L20 1020Z" fill-opacity="0.01"/>',
            '<rect width="105" height="24.0001" transform="matrix(1 0 0 -1 20 1020)" fill-opacity="0.01"/>',
            _getBottomTileText(),
            '<path d="M125 1020L141 1020L125 996L125 1020Z" fill-opacity="0.01"/>',
            '</g></defs>',
            '<use href="#t"/><use href="#t" x="125.571"/><use href="#t" x="251.143"/><use href="#t" x="376.714"/>',
            '<use href="#t" x="502.286"/><use href="#t" x="627.857"/><use href="#t" x="753.429"/><use href="#t" x="879"/>'
        ));
    }

    /// @notice The "In code we trust" text paths for the bottom tile
    function _getBottomTileText() private pure returns (string memory) {
        return '<path fill-opacity="0.06" d="M30.11 1011.5L28.89 1011.5L28.89 1004.41L30.11 1004.41L30.11 1011.5ZM32.878 1008.69L32.878 1011.5L31.718 1011.5L31.718 1006.63L32.848 1006.63L32.848 1007.28C33.168 1006.72 33.748 1006.49 34.288 1006.49C35.478 1006.49 36.048 1007.35 36.048 1008.42L36.048 1011.5L34.888 1011.5L34.888 1008.62C34.888 1008.02 34.618 1007.54 33.888 1007.54C33.228 1007.54 32.878 1008.05 32.878 1008.69ZM45.412 1007.55C44.702 1007.55 44.072 1008.08 44.072 1009.06C44.072 1010.04 44.702 1010.59 45.432 1010.59C46.192 1010.59 46.542 1010.06 46.652 1009.69L47.672 1010.06C47.442 1010.82 46.712 1011.65 45.432 1011.65C44.002 1011.65 42.912 1010.54 42.912 1009.06C42.912 1007.56 44.002 1006.48 45.402 1006.48C46.712 1006.48 47.432 1007.3 47.632 1008.08L46.592 1008.46C46.482 1008.03 46.152 1007.55 45.412 1007.55ZM50.9202 1010.61C51.6402 1010.61 52.2802 1010.08 52.2802 1009.06C52.2802 1008.05 51.6402 1007.53 50.9202 1007.53C50.2102 1007.53 49.5602 1008.05 49.5602 1009.06C49.5602 1010.07 50.2102 1010.61 50.9202 1010.61ZM50.9202 1006.48C52.3802 1006.48 53.4502 1007.57 53.4502 1009.06C53.4502 1010.56 52.3802 1011.65 50.9202 1011.65C49.4702 1011.65 48.4002 1010.56 48.4002 1009.06C48.4002 1007.57 49.4702 1006.48 50.9202 1006.48ZM55.4294 1009.05C55.4294 1009.98 55.9494 1010.6 56.7394 1010.6C57.4994 1010.6 58.0294 1009.97 58.0294 1009.04C58.0294 1008.11 57.5094 1007.53 56.7494 1007.53C55.9894 1007.53 55.4294 1008.12 55.4294 1009.05ZM59.1494 1004.26L59.1494 1010.61C59.1494 1011.05 59.1894 1011.42 59.1994 1011.5L58.0894 1011.5C58.0694 1011.39 58.0394 1011.07 58.0394 1010.87C57.8094 1011.28 57.2994 1011.62 56.6094 1011.62C55.2094 1011.62 54.2694 1010.52 54.2694 1009.05C54.2694 1007.65 55.2194 1006.5 56.5894 1006.5C57.4394 1006.5 57.8694 1006.89 58.0194 1007.2L58.0194 1004.26L59.1494 1004.26ZM61.4652 1008.53L63.8552 1008.53C63.8352 1007.96 63.4552 1007.45 62.6552 1007.45C61.9252 1007.45 61.5052 1008.01 61.4652 1008.53ZM63.9852 1009.8L64.9652 1010.11C64.7052 1010.96 63.9352 1011.65 62.7652 1011.65C61.4452 1011.65 60.2752 1010.69 60.2752 1009.04C60.2752 1007.5 61.4152 1006.48 62.6452 1006.48C64.1452 1006.48 65.0252 1007.47 65.0252 1009.01C65.0252 1009.2 65.0052 1009.36 64.9952 1009.38L61.4352 1009.38C61.4652 1010.12 62.0452 1010.65 62.7652 1010.65C63.4652 1010.65 63.8252 1010.28 63.9852 1009.8ZM74.7829 1006.63L75.9829 1006.63L77.1329 1010L78.1029 1006.63L79.2829 1006.63L77.7229 1011.5L76.5629 1011.5L75.3529 1008L74.1729 1011.5L72.9829 1011.5L71.4029 1006.63L72.6429 1006.63L73.6329 1010L74.7829 1006.63ZM81.016 1008.53L83.406 1008.53C83.386 1007.96 83.006 1007.45 82.206 1007.45C81.476 1007.45 81.056 1008.01 81.016 1008.53ZM83.536 1009.8L84.516 1010.11C84.256 1010.96 83.486 1011.65 82.316 1011.65C80.996 1011.65 79.826 1010.69 79.826 1009.04C79.826 1007.5 80.966 1006.48 82.196 1006.48C83.696 1006.48 84.576 1007.47 84.576 1009.01C84.576 1009.2 84.556 1009.36 84.546 1009.38L80.986 1009.38C81.016 1010.12 81.596 1010.65 82.316 1010.65C83.016 1010.65 83.376 1010.28 83.536 1009.8ZM93.0137 1005.14L93.0137 1006.63L94.0237 1006.63L94.0237 1007.66L93.0137 1007.66L93.0137 1009.92C93.0137 1010.35 93.2037 1010.53 93.6337 1010.53C93.7937 1010.53 93.9837 1010.5 94.0337 1010.49L94.0337 1011.45C93.9637 1011.48 93.7437 1011.56 93.3237 1011.56C92.4237 1011.56 91.8637 1011.02 91.8637 1010.11L91.8637 1007.66L90.9637 1007.66L90.9637 1006.63L91.2137 1006.63C91.7337 1006.63 91.9637 1006.3 91.9637 1005.87L91.9637 1005.14L93.0137 1005.14ZM97.986 1006.6L97.986 1007.78C97.856 1007.76 97.726 1007.75 97.606 1007.75C96.706 1007.75 96.296 1008.27 96.296 1009.18L96.296 1011.5L95.136 1011.5L95.136 1006.63L96.266 1006.63L96.266 1007.41C96.496 1006.88 97.036 1006.57 97.676 1006.57C97.816 1006.57 97.936 1006.59 97.986 1006.6ZM102.076 1010.96C101.836 1011.4 101.266 1011.64 100.696 1011.64C99.5355 1011.64 98.8555 1010.78 98.8555 1009.7L98.8555 1006.63L100.016 1006.63L100.016 1009.49C100.016 1010.09 100.296 1010.6 100.996 1010.6C101.666 1010.6 102.016 1010.15 102.016 1009.51L102.016 1006.63L103.176 1006.63L103.176 1010.61C103.176 1011.01 103.206 1011.32 103.226 1011.5L102.116 1011.5C102.096 1011.39 102.076 1011.16 102.076 1010.96ZM104.278 1010.18L105.288 1009.9C105.328 1010.34 105.658 1010.73 106.278 1010.73C106.758 1010.73 107.008 1010.47 107.008 1010.17C107.008 1009.91 106.828 1009.71 106.438 1009.63L105.718 1009.47C104.858 1009.28 104.408 1008.72 104.408 1008.05C104.408 1007.2 105.188 1006.48 106.198 1006.48C107.558 1006.48 107.998 1007.36 108.078 1007.84L107.098 1008.12C107.058 1007.84 106.848 1007.39 106.198 1007.39C105.788 1007.39 105.498 1007.65 105.498 1007.95C105.498 1008.21 105.688 1008.4 105.988 1008.46L106.728 1008.61C107.648 1008.81 108.128 1009.37 108.128 1010.09C108.128 1010.83 107.528 1011.65 106.288 1011.65C104.878 1011.65 104.338 1010.73 104.278 1010.18ZM110.797 1005.14L110.797 1006.63L111.807 1006.63L111.807 1007.66L110.797 1007.66L110.797 1009.92C110.797 1010.35 110.987 1010.53 111.417 1010.53C111.577 1010.53 111.767 1010.5 111.817 1010.49L111.817 1011.45C111.747 1011.48 111.527 1011.56 111.107 1011.56C110.207 1011.56 109.647 1011.02 109.647 1010.11L109.647 1007.66L108.747 1007.66L108.747 1006.63L108.997 1006.63C109.517 1006.63 109.747 1006.3 109.747 1005.87L109.747 1005.14L110.797 1005.14Z"/>';
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

    function _bytes32ToHexString(bytes32 value) private pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = bytes1(uint8(uint256(uint8(value[i] >> 4)) + (uint256(uint8(value[i] >> 4)) < 10 ? 48 : 87)));
            str[i * 2 + 1] = bytes1(uint8(uint256(uint8(value[i] & 0x0f)) + (uint256(uint8(value[i] & 0x0f)) < 10 ? 48 : 87)));
        }
        return string(abi.encodePacked("0x", string(str)));
    }
}
