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

import "../interfaces/IRoundManagerFactory.sol";
import "../interfaces/ICyberCorp.sol";
import "../libs/auth.sol";

/// @notice Minimal interface to read a corp's AUTH and issuance manager
interface ICyberCorpAuthReader {
    function AUTH() external view returns (address);
    function issuanceManager() external view returns (address);
}

/// @notice Minimal interface for RoundManager initialization
interface IRoundManagerInit {
    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager,
        address _upgradeFactory
    ) external;
}

/// @title RoundManagerUpgradeHelper
/// @notice Helper to deploy and attach a RoundManager to an existing CyberCorp
/// @dev Caller must be authorized as OWNER in the corp's AUTH; this contract will enforce a role check
contract RoundManagerUpgradeHelper {
    error NotAuthorized();
    error ZeroAddress();
    error RoundManagerAlreadyExists();

    address public immutable registryAddress;
    address public immutable roundManagerFactory;

    event RoundManagerDeployedForCorp(address indexed corp, address indexed roundManager);

    constructor(address _registryAddress, address _roundManagerFactory) {
        if (_registryAddress == address(0) || _roundManagerFactory == address(0)) revert ZeroAddress();
        registryAddress = _registryAddress;
        roundManagerFactory = _roundManagerFactory;
    }

    /// @notice Deploy and wire a RoundManager for an existing CyberCorp
    /// @param corp Address of the existing CyberCorp
    /// @param salt Create2 salt for deterministic RoundManager deployment
    /// @return roundManager Address of the deployed RoundManager proxy
    function upgradeCorp(address corp, bytes32 salt) external returns (address roundManager) {
        if (corp == address(0)) revert ZeroAddress();
        //if corp already has a round manager, revert
        if (ICyberCorp(corp).roundManager() != address(0)) revert RoundManagerAlreadyExists();

        // Read corp's AUTH and ensure the caller is authorized as OWNER
        address auth = ICyberCorpAuthReader(corp).AUTH();
        BorgAuth(auth).onlyRole(BorgAuth(auth).OWNER_ROLE(), msg.sender);

        // Deploy RoundManager via factory
        roundManager = IRoundManagerFactory(roundManagerFactory).deployRoundManager(salt);

        // Initialize RoundManager
        address issuanceMgr = ICyberCorpAuthReader(corp).issuanceManager();
        IRoundManagerInit(roundManager).initialize(
            auth,
            corp,
            registryAddress,
            issuanceMgr,
            roundManagerFactory
        );

        // Grant OWNER role to the newly deployed RoundManager in the corp's AUTH
        BorgAuth(auth).updateRole(roundManager, BorgAuth(auth).OWNER_ROLE());

        // Set RoundManager on the CyberCorp contract
        ICyberCorp(corp).setRoundManager(roundManager);

        emit RoundManagerDeployedForCorp(corp, roundManager);

        BorgAuth(auth).zeroOwner();
    }
}


