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

pragma solidity 0.8.28;

import {OfferSide} from "../storage/SecondaryTradeStorage.sol";

/// @title ISecondaryTradeStorage
/// @notice Events/errors owned by the SecondaryTradeStorage library — the single source of truth.
/// @dev SecondaryTradeStorage emits/reverts these via the qualified ISecondaryTradeStorage.X form, and
/// any manager that links the library (e.g. DealManager) inherits this interface so the selectors/topics
/// appear in its ABI for off-chain decoding.
interface ISecondaryTradeStorage {
    event OfferPosted(bytes32 indexed offerId, address indexed offeror, OfferSide side, uint256 units, uint256 consideration);
    event OfferCancelled(bytes32 indexed offerId, address indexed offeror);
    event OfferAccepted(bytes32 indexed offerId, bytes32 indexed settlementAgreementId, address indexed acceptor, uint256 units);
    event SecondaryDealFinalized(bytes32 indexed agreementId, address seller, address buyer, uint256 consideration);

    error OfferNotAvailable();
    error OfferExpired();
    /// @notice A trade's units or consideration is below the admin-set minimum-ticket threshold;
    /// enforced on the whole offer at postOffer and on each lot at acceptOffer
    error BelowMinTradeThreshold();
    error IntegratorNotWhitelisted();
    error UnitsExceedOffer();
    error NotOfferor();
    error MissingCertPrinter();
    error NotPartyToAgreement();
    error OfferAlreadyExists();
    /// @notice Caller is not the signer they claim to be (signer must equal msg.sender)
    error NotSigner();
}
