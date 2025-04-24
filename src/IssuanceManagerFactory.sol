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

import "./IssuanceManager.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./libs/auth.sol";

contract IssuanceManagerFactory is BorgAuthACL {
    error InvalidSalt();
    error DeploymentFailed();
    error ZeroAddress();
    
    UpgradeableBeacon public beacon;

    event IssuanceManagerDeployed(address issuanceManager);

    constructor(address _auth) {
        // Deploy the implementation contract and beacon
        beacon = new UpgradeableBeacon(address(new IssuanceManager()), address(this));
        initialize(_auth);
    }

    function initialize(address _auth) public initializer {
        // Initialize BorgAuthACL
        __BorgAuthACL_init(_auth);
    }

    function deployIssuanceManager(bytes32 _salt) public returns (address) {
        if (_salt == bytes32(0)) revert InvalidSalt();
        
        // Create proxy deployment bytecode
        bytes memory proxyBytecode = _getBytecode();
        
        // Deploy using CREATE2
        address issuanceManagerProxy = Create2.deploy(0, _salt, proxyBytecode);
        
        if(issuanceManagerProxy == address(0)) revert DeploymentFailed();
        
        emit IssuanceManagerDeployed(issuanceManagerProxy);
        return issuanceManagerProxy;
    }

    /// @notice Computes the deterministic address for an IssuanceManagerBeaconProxy
    /// @param _salt Salt used for CREATE2
    /// @return computedAddress The precomputed address of the proxy
    function computeIssuanceManagerAddress(bytes32 _salt) external view returns (address) {
        bytes memory proxyBytecode = _getBytecode();
        return Create2.computeAddress(_salt, keccak256(proxyBytecode));
    }

    /// @notice Gets the bytecode for creating new IssuanceManager proxies
    /// @dev Internal function used by deployIssuanceManager
    /// @return bytecode The proxy contract creation bytecode
    function _getBytecode() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(beacon, ""));
    }

    /// @notice Upgrades the implementation contract
    /// @dev Only callable by addresses with the admin role
    /// @param _newImplementation Address of the new implementation
    function upgradeImplementation(address _newImplementation) external onlyOwner {
        UpgradeableBeacon(beacon).upgradeTo(_newImplementation);
    }

    /// @notice Gets the current implementation address
    /// @return The address of the current implementation contract
    function getBeaconImplementation() external view returns (address) {
        return UpgradeableBeacon(beacon).implementation();
    }

    /// @notice Upgrades the implementation of the certificate printer
    /// @dev Only callable by upgrader role
    /// @param _newImplementation Address of the new implementation
    function upgradePrinterBeaconAt(address issuanceManager, address _newImplementation) external onlyOwner {
        IssuanceManager(issuanceManager).upgradeBeaconImplementation(_newImplementation);
    }
}
