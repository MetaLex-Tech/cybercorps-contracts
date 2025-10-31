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

import {SecurityClass, SecuritySeries} from "../CyberCorpConstants.sol";

enum RoundType {
    FCFS,
    FounderApproved
}

struct Round {
    bytes32 id;
    SecuritySeries seriesType;
    uint256 raiseCap;
    uint256 minTicket;
    uint256 maxTicket;
    RoundType roundType;
    uint256 startTime;
    uint256 endTime;
    bytes32 templateId;
    address[] certPrinter;
    address paymentToken;
    uint256 pricePerUnit;
    uint256 valuation;
    uint256 raised;
    address[] roundConditions;
    // Normalized round price and primary security sold to new money
    uint256 roundPricePerShare; // normalized to priceDecimals
    uint8 roundPriceDecimals;
    SecurityClass primarySecurityClass;
    SecuritySeries primarySecuritySeries;
    address authorityOfficer;
    string officerName;
    string officerTitle;
    string[] legalDetails;
    bytes[] extensionData;
    string[] roundPartyValues;
    bytes escrowedSignature;
    bool publicRound;
    bool allowTimedOffers; // if false, ignore EOI expiries and use round end
}

library RoundLib {
    function draft() internal pure returns (Round memory) {
        Round memory round; // all default values
        return round;
    }

    /// @notice Partially fill the given Round struct (ticket-related parameters)
    /// @dev Beware of which fields are not filled and using default values
    /// @param seriesType The series type (e.g., Series A)
    /// @param roundType FCFS or FounderApproved
    /// @param publicRound Indicate public round
    /// @param raiseCap The maximum amount to raise
    /// @param minTicket Minimum investment per EOI
    /// @param maxTicket Maximum investment per EOI
    /// @param paymentToken Payment token address
    /// @param pricePerUnit Price per unit in payment token decimals
    /// @param valuation Valuation in USD
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @return Partially filled Round struct
    function setTickets(
        Round memory round,
        SecuritySeries seriesType,
        RoundType roundType,
        bool publicRound,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        uint256 startTime,
        uint256 endTime
    ) internal pure returns (Round memory) {
        round.seriesType = seriesType;
        round.roundType = roundType;
        round.publicRound = publicRound;
        round.raiseCap = raiseCap;
        round.minTicket = minTicket;
        round.maxTicket = maxTicket;
        round.paymentToken = paymentToken;
        round.pricePerUnit = pricePerUnit;
        round.roundPricePerShare = pricePerUnit; // default value
        round.roundPriceDecimals = 18; // default value
        round.valuation = valuation;
        round.startTime = startTime;
        round.endTime = endTime;
        return round;
    }

    /// @notice Partially fill the given Round struct (agreement-related parameters)
    /// @dev Beware of which fields are not filled and using default values
    /// @param templateId Agreement template ID
    /// @param roundPartyValues Round party values
    /// @param escrowedSignature Escrowed signature
    /// @return Partially filled Round struct
    function setAgreement(
        Round memory round,
        bytes32 templateId,
        address authorityOfficer,
        string memory officerName,
        string memory officerTitle,
        string[] memory legalDetails,
        string[] memory roundPartyValues,
        bytes[] memory extensionData,
        address[] memory roundConditions,
        bytes memory escrowedSignature
    ) internal pure returns (Round memory) {
        round.templateId = templateId;
        round.authorityOfficer = authorityOfficer;
        round.officerName = officerName;
        round.officerTitle = officerTitle;
        round.legalDetails = legalDetails;
        round.roundPartyValues = roundPartyValues;
        round.extensionData = extensionData;
        round.roundConditions = roundConditions;
        round.escrowedSignature = escrowedSignature;
        return round;
    }
}
