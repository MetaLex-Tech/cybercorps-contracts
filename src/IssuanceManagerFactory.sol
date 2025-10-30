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

import "openzeppelin-contracts/utils/Create2.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./IssuanceManager.sol";
import "./CyberCertPrinter.sol";
import "./CyberScrip.sol";
import "./libs/auth.sol";
import "./storage/IssuanceManagerFactoryStorage.sol";

contract IssuanceManagerFactory is BorgAuthACL, UUPSUpgradeable {
    error InvalidSalt();
    error DeploymentFailed();
    error ZeroAddress();

    event IssuanceManagerDeployed(address issuanceManager);
    event RefImplementationSet(address refImplementation, string version);
    event CyberCertPrinterRefImplementationSet(address refImplementation, string version);
    event CyberScripRefImplementationSet(address refImplementation, string version);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address refImplementation,
        address cyberCertPrinterRefImplementation,
        address cyberScripRefImplementation
    ) public initializer {
        // Initialize BorgAuthACL
        __BorgAuthACL_init(_auth);

        IssuanceManagerFactoryStorage.getStorageData().refImplementation = refImplementation;
        IssuanceManagerFactoryStorage.getStorageData().cyberCertPrinterRefImplementation = cyberCertPrinterRefImplementation;
        IssuanceManagerFactoryStorage.getStorageData().cyberScripRefImplementation = cyberScripRefImplementation;
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
        bytes memory sourceCodeBytes = type(ERC1967Proxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(IssuanceManagerFactoryStorage.getStorageData().refImplementation, ""));
    }

    /// @notice Get the reference implementation contract for the next deployments
    /// @return Current reference implementation contract address
    function getRefImplementation() public view returns(address) {
        return IssuanceManagerFactoryStorage.getStorageData().refImplementation;
    }

    /// @notice Set the reference implementation contract for the next deployments
    /// @dev Only callable by addresses with the admin role
    /// @param _newImplementation Address of the new implementation
    function setRefImplementation(address _newImplementation) public onlyOwner {
        IssuanceManagerFactoryStorage.getStorageData().refImplementation = _newImplementation;
        emit RefImplementationSet(_newImplementation, IssuanceManager(_newImplementation).DEPLOY_VERSION());
    }

    /// @notice Get the reference implementation contract for the next `CyberCertPrinter` deployments
    /// @return Current reference implementation contract address
    function getCyberCertPrinterRefImplementation() external view returns(address) {
        return IssuanceManagerFactoryStorage.getStorageData().cyberCertPrinterRefImplementation;
    }

    /// @notice Set the reference implementation contract for the next `CyberCertPrinter` deployments
    /// @dev Only callable by addresses with the admin role
    /// @param _newImplementation Address of the new implementation
    function setCyberCertPrinterRefImplementation(address _newImplementation) public onlyOwner {
        IssuanceManagerFactoryStorage.getStorageData().cyberCertPrinterRefImplementation = _newImplementation;
        emit CyberCertPrinterRefImplementationSet(_newImplementation, CyberCertPrinter(_newImplementation).DEPLOY_VERSION());
    }

    /// @notice Get the reference implementation contract for the next `CyberScrip` deployments
    /// @return Current reference implementation contract address
    function getCyberScripRefImplementation() external view returns(address) {
        return IssuanceManagerFactoryStorage.getStorageData().cyberScripRefImplementation;
    }

    /// @notice Set the reference implementation contract for the next `CyberScrip` deployments
    /// @dev Only callable by addresses with the admin role
    /// @param _newImplementation Address of the new implementation
    function setCyberScripRefImplementation(address _newImplementation) public onlyOwner {
        IssuanceManagerFactoryStorage.getStorageData().cyberScripRefImplementation = _newImplementation;
        emit CyberScripRefImplementationSet(_newImplementation, CyberScrip(_newImplementation).DEPLOY_VERSION());
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
