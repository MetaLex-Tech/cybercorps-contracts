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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IAuthAdapter.sol";

/// @title  BorgAuth
/// @author MetaLeX Labs, Inc.
/// @notice ACL with extensibility for different role hierarchies and custom adapters
contract BorgAuth is Initializable {
    //constants built-in roles, authority works as a hierarchy
    uint256 public constant OWNER_ROLE = 99;
    uint256 public constant ADMIN_ROLE = 98;
    uint256 public constant PRIVILEGED_ROLE = 97;
    uint256 public constant UPGRADER_ROLE = 96;
    address public constant UPGRADER_ADDRESS = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    address public pendingOwner;

    //mappings and events
    mapping(address => uint256) public userRoles;
    mapping(uint256 => address) public roleAdapters;

    event RoleUpdated(address indexed user, uint256 role);
    event AdapterUpdated(uint256 indexed role, address adapter);

    /// @dev user not authorized with given role
    error BorgAuth_NotAuthorized(uint256 role, address user);
    error BorgAuth_SetAnotherOwner();
    error BorgAuth_ZeroAddress();

    /// @notice Empty constructor for implementation contract
    constructor() {
    }

    /// @notice Initializer replacing the constructor - sets the deployer/initializer as owner
    /// @dev Use this instead of constructor when deployed behind a proxy
    function initialize() external initializer {
        _updateRole(msg.sender, OWNER_ROLE);
        if(UPGRADER_ADDRESS != msg.sender)
            _updateRole(UPGRADER_ADDRESS, UPGRADER_ROLE);
    }

    /// @notice update role for user
    /// @param user address of user
    /// @param role role to update
    function updateRole(
        address user,
        uint256 role
    ) external {
         if(role == UPGRADER_ROLE && msg.sender != address(this)) revert BorgAuth_SetAnotherOwner();
         onlyRole(OWNER_ROLE, msg.sender);
         if(user == msg.sender && role < OWNER_ROLE) revert BorgAuth_SetAnotherOwner();
        _updateRole(user, role);
    }
    
    /// @notice initialize ownership transfer
    /// @param newOwner address of new owner
    function initTransferOwnership(address newOwner) external {
        if (newOwner == address(0) || newOwner == msg.sender) revert BorgAuth_ZeroAddress();
        onlyRole(OWNER_ROLE, msg.sender);
        pendingOwner = newOwner;
    }

    /// @notice accept ownership transfer
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert BorgAuth_NotAuthorized(OWNER_ROLE, msg.sender);
        _updateRole(pendingOwner, OWNER_ROLE);
        pendingOwner = address(0);
        emit RoleUpdated(pendingOwner, OWNER_ROLE);
    }

    /// @notice function to purposefully revoke all roles from owner, rendering subsequent role updates impossible
    /// @dev this function is intended for use to remove admin controls from subsequent contracts using this auth
    function zeroOwner() external {
        onlyRole(OWNER_ROLE, msg.sender);
        _updateRole(msg.sender, 0);
    }

    /// @notice set adapter for role
    /// @param _role role to set adapter for
    /// @param _adapter address of adapter
    function setRoleAdapter(uint256 _role, address _adapter) external {
        onlyRole(OWNER_ROLE, msg.sender);
        roleAdapters[_role] = _adapter;
        emit AdapterUpdated(_role, _adapter);
    }

    /// @notice check role for user, revert if not authorized
    /// @param user address of user
    /// @param role of user
    function onlyRole(uint256 role, address user) public view {
        uint256 authorized = userRoles[user];

        if (authorized < role) {
            address adapter = roleAdapters[role];
            if (adapter != address(0)) 
                if (IAuthAdapter(adapter).isAuthorized(user) >= role) 
                    return;
            revert BorgAuth_NotAuthorized(role, user);
        }
    }

    /// @notice check role for user, revert if not authorized
    /// @param user address of user
    /// @param role of user
    function matchRole(uint256 role, address user) public view {
        uint256 authorized = userRoles[user];

        if (authorized != role) {
            address adapter = roleAdapters[role];
            if (adapter != address(0)) 
                if (IAuthAdapter(adapter).isAuthorized(user) == role) 
                    return;
            revert BorgAuth_NotAuthorized(role, user);
        }
    }

    /// @notice internal function to add a role to a user
    /// @param role role to update
    /// @param user address of user
    function _updateRole(
        address user,
        uint256 role
    ) internal {
        userRoles[user] = role;
        emit RoleUpdated(user, role);
    }
}

/// @title BorgAuthACL
/// @notice ACL with modifiers for different roles
abstract contract BorgAuthACL is Initializable {
    //BorgAuth instance
    BorgAuth public AUTH;

    // @dev zero address error
    error BorgAuthACL_ZeroAddress();

    /// @notice Empty constructor for implementation contract
    constructor() {
    }

    /// @notice Initializer for BorgAuthACL
    /// @param _auth Address of the BorgAuth contract
    function __BorgAuthACL_init(address _auth) internal onlyInitializing {
        if(_auth == address(0)) revert BorgAuthACL_ZeroAddress();
        AUTH = BorgAuth(_auth);
    }

    function userRoles(address user) public view returns (uint256) {
        return AUTH.userRoles(user);
    }

    //common modifiers and general access control onlyRole
    modifier onlyOwner() {
        AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        _;
    }

    modifier onlyAdmin() {
        AUTH.onlyRole(AUTH.ADMIN_ROLE(), msg.sender);
        _;
    }

    modifier onlyPriv() {
        AUTH.onlyRole(AUTH.PRIVILEGED_ROLE(), msg.sender);
        _;
    }

    modifier onlyUpgrader() {
        AUTH.matchRole(AUTH.UPGRADER_ROLE(), msg.sender);
        _;
    }

    modifier onlyRole(uint256 _role) {
        AUTH.onlyRole(_role, msg.sender);
        _;
    }

    modifier matchRole(uint256 _role) {
        AUTH.matchRole(_role, msg.sender);
        _;
    }
}