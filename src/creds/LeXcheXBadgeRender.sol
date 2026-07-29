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

import "openzeppelin-contracts/utils/Strings.sol";
import "openzeppelin-contracts/utils/Base64.sol";
import "./storage/lexchexBadgeStorage.sol";

/// @title  LeXcheXBadgeRender - on-chain SVG/metadata rendering for LeXcheXBadge
/// @author MetaLeX Labs, Inc.
/// @notice Extracted from LeXcheXBadge so the SVG string literals live in a separately-deployed,
/// delegatecall-linked library, keeping the badge under the EIP-170 24,576 B limit. Pure rendering:
/// callers pass in the credential and the validity flag.
library LeXcheXBadgeRender {
    using Strings for uint256;

    string constant TITLE = "LeXcheX Credential";
    string constant DESCRIPTION = "Soulbound credential issued on the LeXcheX Badge registry.";

    function tokenURI(
        uint256 tokenId,
        Credential memory cred,
        bool valid
    ) public pure returns (string memory) {
        string memory image = generateSVGImage(TITLE, cred);

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "',
                            TITLE,
                            " #",
                            tokenId.toString(),
                            '", "description": "',
                            DESCRIPTION,
                            '",',
                            '"image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(image)),
                            '", "attributes": [',
                            '{"trait_type": "Investor Type", "value": "',
                            investorTypeLabel(cred.investorType),
                            '"},',
                            '{"trait_type": "Jurisdiction", "value": "',
                            cred.investorJurisdiction,
                            '"},',
                            bytes(cred.lookThroughJurisdiction).length > 0
                                ? string(
                                    abi.encodePacked(
                                        '{"trait_type": "Regulatory Jurisdiction", "value": "',
                                        cred.lookThroughJurisdiction,
                                        '"},'
                                    )
                                )
                                : "",
                            '{"trait_type": "Status", "value": "',
                            valid ? "Valid" : "Invalid",
                            '"},',
                            '{"trait_type": "Expiry", "value": "',
                            timestampToDate(cred.expiryDate),
                            '"}',
                            "]}"
                        )
                    )
                )
            )
        );
    }

    function generateSVGImage(string memory title, Credential memory cred) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="1000" height="650">',
                '<rect width="100%" height="100%" fill="#191a18"/>',
                generateMetaLeXLogo(),
                generateSVGBody(title, cred),
                "</svg>"
            )
        );
    }

    function generateMetaLeXLogo() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg x="880" y="570" width="61" height="30" viewBox="0 0 61 30" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<path d="M29.5488 0C30.5107 0 31.291 0.779753 31.291 1.74121V11.957C31.291 12.543 30.9957 13.0902 30.5059 13.4121L6.69629 29.0605C6.41221 29.2472 6.07921 29.3467 5.73926 29.3467H1.74121C0.779536 29.3465 0 28.5668 0 27.6055V19.9648C8.27261e-05 19.3799 0.293816 18.8339 0.782227 18.5117L28.415 0.288086C28.6996 0.100412 29.0331 0 29.374 0H29.5488ZM54.7832 0.000976562C55.745 0.000976562 56.5243 0.77984 56.5244 1.74121V11.957C56.5244 12.543 56.23 13.0902 55.7402 13.4121L31.9307 29.0605C31.6465 29.2473 31.3137 29.3467 30.9736 29.3467H26.9756C26.0139 29.3466 25.2344 28.5669 25.2344 27.6055V19.9648C25.2345 19.38 25.5282 18.8338 26.0166 18.5117L53.6494 0.288086C53.934 0.100488 54.2675 0.000976562 54.6084 0.000976562H54.7832ZM58.9521 15.54C59.825 14.9532 60.9997 15.5783 61 16.6299V27.792C60.9999 28.6506 60.3033 29.3467 59.4443 29.3467H48.5459C47.687 29.3466 46.9903 28.6505 46.9902 27.792V24.3594C46.9902 23.842 47.2484 23.3582 47.6777 23.0693L58.9521 15.54Z" fill="#DAFF00"/>',
                "</svg>"
            )
        );
    }

    function generateSVGBody(string memory title, Credential memory cred) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="0" y="83" width="1000px" height="50px" fill="url(#linGrad)"></rect>',
                '<text x="500" y="126" text-anchor="middle" font-family="Georgia" font-size="48" fill="url(#textGrad)">',
                title,
                "</text>",
                '<text x="500" y="226" text-anchor="middle" font-family="Georgia" font-size="25" fill="#f2f2f2">THIS SOULBOUND CREDENTIAL IS HELD BY</text>',
                '<text x="500" y="266" text-anchor="middle" font-family="Georgia" font-size="25" fill="#f2f2f2">',
                investorTypeLabel(cred.investorType),
                "</text>",
                generateDefs(),
                '<rect width="100%" height="100%" fill="url(#grad1)" />',
                '<text x="150" y="360" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">JURISDICTION</text>',
                '<text x="495" y="355" font-family="Georgia" font-size="30" fill="url(#textGrad)">',
                cred.investorJurisdiction,
                "</text>",
                '<rect x="380" y="363" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                bytes(cred.lookThroughJurisdiction).length > 0
                    ? string(
                        abi.encodePacked(
                            '<text x="150" y="405" font-family="Georgia" font-size="26" fill="#f2f2f2" opacity=".6">REGULATORY</text>',
                            '<text x="495" y="405" font-family="Georgia" font-size="30" fill="url(#textGrad)">',
                            cred.lookThroughJurisdiction,
                            "</text>"
                        )
                    )
                    : "",
                '<text x="150" y="450" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">GOOD UNTIL</text>',
                '<text x="495" y="440" font-family="Georgia" font-size="30" fill="url(#textGrad)">',
                timestampToDate(cred.expiryDate),
                "</text>",
                '<rect x="380" y="453" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="325" y="570" font-family="Georgia" font-size="17" fill="#f2f2f2" opacity=".6">Non-transferable. Soul-bound. Verified on-chain.</text>',
                '<text x="210" y="600" font-family="Georgia" font-size="15" fill="#f2f2f2" opacity=".24">',
                bytes32ToHexString(cred.agreementId),
                "</text>"
            )
        );
    }

    function generateDefs() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<defs>",
                '<radialGradient id="grad1" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.07" />',
                '<stop offset="100%" style="stop-color:#191a18; stop-opacity:.07" />',
                "</radialGradient>",
                '<linearGradient id="linGrad">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.4" />',
                '<stop offset="20%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="80%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="100%" style="stop-color:#daff00; stop-opacity:.4" />',
                "</linearGradient>",
                '<linearGradient id="textGrad" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#F2F8CB; stop-opacity:1" />',
                "</linearGradient>",
                "</defs>"
            )
        );
    }

    /// @dev Empty for UNSET — a credential that doesn't assert K_INVESTOR_TYPE states no type.
    function investorTypeLabel(InvestorType investorType) internal pure returns (string memory) {
        if (investorType == InvestorType.INDIVIDUAL) return "Individual";
        if (investorType == InvestorType.ENTITY) return "Entity";
        return "";
    }

    function timestampToDate(uint256 timestamp) internal pure returns (string memory) {
        uint256 day = ((timestamp / 86400) % 31) + 1;
        uint256 month = ((timestamp / 2629743) % 12) + 1;
        uint256 year = (timestamp / 31556926) + 1970;
        return string(
            abi.encodePacked(
                Strings.toString(month), "/", Strings.toString(day), "/", Strings.toString(year)
            )
        );
    }

    function bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = bytes1(
                uint8(uint256(uint8(value[i] >> 4)) + (uint256(uint8(value[i] >> 4)) < 10 ? 48 : 87))
            );
            str[i * 2 + 1] = bytes1(
                uint8(uint256(uint8(value[i] & 0x0f)) + (uint256(uint8(value[i] & 0x0f)) < 10 ? 48 : 87))
            );
        }
        return string(abi.encodePacked("0x", string(str)));
    }
}
