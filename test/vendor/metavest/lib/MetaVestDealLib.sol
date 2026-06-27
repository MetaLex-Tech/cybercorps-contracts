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

import {BaseAllocation} from "../BaseAllocation.sol";

enum MetaVestType { Vesting, TokenOption, RestrictedTokenAward }

struct MetaVestDeal {
    bytes32 agreementId;
    MetaVestType metavestType;
    address grantee;
    address paymentToken;
    uint256 exercisePrice;
    uint256 shortStopDuration;
    BaseAllocation.Allocation allocation;
    BaseAllocation.Milestone[] milestones;
    address metavest;
}

library MetaVestDealLib {
    function draft() internal pure returns (MetaVestDeal memory) {
        MetaVestDeal memory deal; // all default values
        return deal;
    }

    /// @notice Partially fill the given deal struct
    /// @dev Beware of which fields are not filled and using default values
    function setVesting(
        MetaVestDeal memory deal,
        address grantee,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones
    ) internal pure returns (MetaVestDeal memory) {
        deal.metavestType = MetaVestType.Vesting;
        deal.grantee = grantee;
        deal.allocation = allocation;
        deal.milestones = milestones;
        return deal;
    }

    /// @notice Partially fill the given deal struct
    /// @dev Beware of which fields are not filled and using default values
    function setTokenOption(
        MetaVestDeal memory deal,
        address grantee,
        address paymentToken,
        uint256 exercisePrice,
        uint256 shortStopDuration,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones
    ) internal pure returns (MetaVestDeal memory) {
        deal.metavestType = MetaVestType.TokenOption;
        deal.grantee = grantee;
        deal.paymentToken = paymentToken;
        deal.exercisePrice = exercisePrice;
        deal.shortStopDuration = shortStopDuration;
        deal.allocation = allocation;
        deal.milestones = milestones;
        return deal;
    }

    /// @notice Partially fill the given deal struct
    /// @dev Beware of which fields are not filled and using default values
    function setRestrictedToken(
        MetaVestDeal memory deal,
        address grantee,
        address paymentToken,
        uint256 exercisePrice,
        uint256 shortStopDuration,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones
    ) internal pure returns (MetaVestDeal memory) {
        deal.metavestType = MetaVestType.RestrictedTokenAward;
        deal.grantee = grantee;
        deal.paymentToken = paymentToken;
        deal.exercisePrice = exercisePrice;
        deal.shortStopDuration = shortStopDuration;
        deal.allocation = allocation;
        deal.milestones = milestones;
        return deal;
    }
}
