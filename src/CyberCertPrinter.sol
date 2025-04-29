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

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./storage/CyberCertPrinterStorage.sol";
import "./interfaces/IUriBuilder.sol";
import "./interfaces/ICyberAgreementRegistry.sol";


contract CyberCertPrinter is Initializable, ERC721EnumerableUpgradeable, UUPSUpgradeable {
    using CyberCertPrinterStorage for CyberCertPrinterStorage.CyberCertStorage;

    // Custom errors
    error NotIssuanceManager();
    error TokenNotTransferable();
    error TokenDoesNotExist();
    error InvalidTokenId();
    error URIQueryForNonexistentToken();
    error URISetForNonexistentToken();
    error ConversionNotImplemented();
    error TransferRestricted(string reason);
    error EndorsementNotSignedOrInvalid();
    error InvalidEndorsement();
    error InvalidLegendIndex();

    //events
    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
    event CertificateEndorsed(
        uint256 indexed tokenId,
        address indexed endorser,
        address indexed endorsee,
        string endorseeName,
        address registry,
        bytes32 agreementId,
        uint256 index,
        uint256 timestamp
    );
    event HookStatusChanged(bool enabled);
    event WhitelistUpdated(address indexed account, bool whitelisted);
    event CyberCertPrinter_CertificateCreated(uint256 indexed tokenId);
    event CyberCertTransfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event CertificateAssigned(uint256 indexed tokenId, address indexed newOwner, string newOwnerName, string issuerName);
    event CertificateVoided(uint256 indexed tokenId, uint256 timestamp);
    event RestrictionHookSet(uint256 indexed id, address indexed hookAddress);
    event GlobalRestrictionHookSet(address indexed hookAddress);
    event GlobalTransferableSet(bool indexed transferable);
    
    
    modifier onlyIssuanceManager() {
        if (msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
        _disableInitializers();
    }

    // Called by proxy on deployment (if needed)
    function initialize(string[] memory _defaultLegend, string memory name, string memory ticker, string memory _certificateUri, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external initializer {
        __ERC721_init(name, ticker);
        __ERC721Enumerable_init_unchained();
        __UUPSUpgradeable_init();
        
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.issuanceManager = _issuanceManager;
        s.defaultLegend = _defaultLegend;
        s.securityType = _securityType;
        s.securitySeries = _securitySeries;
        s.certificateUri = _certificateUri;
        s.endorsementRequired = true;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().issuanceManager = _issuanceManager;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit RestrictionHookSet(_id, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().transferable = _transferable;
        emit GlobalTransferableSet(_transferable);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId] = CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        _safeMint(to, tokenId);
        emit CyberCertPrinter_CertificateCreated(tokenId);
        return tokenId;
    }

    // Restricted minting with full agreement details
    function safeMintAndAssign(
        address to, 
        uint256 tokenId,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId] = CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
        _safeMint(to, tokenId);

        // Store agreement details
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName();
        emit CyberCertPrinter_CertificateCreated(tokenId);
        return tokenId;
    }

    function assignCert(
        address from,
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        if(ownerOf(tokenId) != from) revert InvalidTokenId();
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName();
       // _transfer(from, to, tokenId);
        return tokenId;
    }
    
    // Simplified mint for backward compatibility
    function safeMint(address to, uint256 tokenId) external onlyIssuanceManager {
        _safeMint(to, tokenId);
    }
    
    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if(msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager && msg.sender != ownerOf(tokenId)) revert InvalidEndorsement();
        CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].push(newEndorsement);
        emit CertificateEndorsed(
            tokenId,
            newEndorsement.endorser,
            newEndorsement.endorsee,
            newEndorsement.endorseeName,
            newEndorsement.registry,
            newEndorsement.agreementId,
            CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1,
            block.timestamp
        );
    }

    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        _transfer(from, to, tokenId);
    }
    
    // Update agreement details (for admin purposes)
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external onlyIssuanceManager {
        _burn(tokenId);
        
        // Clear agreement details
        delete CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId];
    }
    
    /**
     * @dev Override _update to enforce transferability restrictions
     * This function is called for all token transfers, mints, and burns
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Skip restriction checks for minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            // This is a transfer, check built-in transferability flag
            if (!CyberCertPrinterStorage.cyberCertStorage().transferable && from != ICyberCorp(IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).CORP()).dealManager()) revert TokenNotTransferable();
            
            // Check security type-specific hook if it exists
            ITransferRestrictionHook typeHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
            
            if (address(typeHook) != address(0)) {
                (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }
            
            // Check global hook if it exists
            if (address(CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook) != address(0)) {
                (bool allowed, string memory reason) = CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }

            address ownerAddress = CyberCertPrinterStorage.cyberCertStorage().owners[tokenId].ownerAddress;
            //check endorsement and update owners
            if(from == ownerAddress) {
                if(!CyberCertPrinterStorage.cyberCertStorage().endorsementRequired) {
                        emit CertificateAssigned(tokenId, to, "", IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName());
                        CyberCertPrinterStorage.cyberCertStorage().owners[tokenId] = OwnerDetails("", to);  
                }
                else if(CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                    Endorsement memory endorsement = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                    if (endorsement.endorsee == to) {
                        // Endorsement exists; ownership will be updated
                        emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName());
                        CyberCertPrinterStorage.cyberCertStorage().owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
                    } 
                } 
            // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
            }
            else if(CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                // Token is not being transferred from the current owner. It can only be transferrred to the latest endorsee, or the current owner
                Endorsement memory endorsement = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                if(endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();

                emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName());
                CyberCertPrinterStorage.cyberCertStorage().owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
            }
            else revert EndorsementNotSignedOrInvalid();

        }
        // Emit custom transfer event for indexing
        emit CyberCertTransfer(
            from,
            to,
            tokenId
        );
        
        // Call the parent implementation to handle the actual transfer
        return super._update(to, tokenId, auth);
    }
    
    // Get full agreement details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId];
    }
    
    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        Endorsement memory details
    ) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
             details = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][index];
    }

    function voidCert(uint256 tokenId) external onlyIssuanceManager {
        CyberCertPrinterStorage.setSecurityStatus(tokenId, SecurityStatus.Void);
        emit CertificateVoided(tokenId, block.timestamp);
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        string[] memory certLegend = s.certLegend[tokenId];
        ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());

        // Get registry and agreementId from first endorsement if it exists
        address registry = address(0);
        bytes32 agreementId = bytes32(0);
        if (s.endorsements[tokenId].length > 0) {
            Endorsement memory firstEndorsement = s.endorsements[tokenId][0];
            registry = firstEndorsement.registry;
            agreementId = firstEndorsement.agreementId;
        }

    return IUriBuilder(IIssuanceManager(s.issuanceManager).uriBuilder()).buildCertificateUri(
            corp.cyberCORPName(),
            corp.cyberCORPType(),
            corp.cyberCORPJurisdiction(),
            corp.cyberCORPContactDetails(),
            s.securityType,
            s.securitySeries,
            s.certificateUri,
            certLegend,
            s.certificateDetails[tokenId],
            s.endorsements[tokenId],
            s.owners[tokenId],
            registry,
            agreementId,
            tokenId,
            address(this)
        );
    }

    // Public getters that directly access storage
    function defaultLegend() public view returns (string[] memory) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
    }

    function certificateUri() public view returns (string memory) {
        return CyberCertPrinterStorage.cyberCertStorage().certificateUri;
    }

    function issuanceManager() public view returns (address) {
        return CyberCertPrinterStorage.cyberCertStorage().issuanceManager;
    }

    function securityType() public view returns (SecurityClass) {
        return CyberCertPrinterStorage.cyberCertStorage().securityType;
    }

    function securitySeries() public view returns (SecuritySeries) {
        return CyberCertPrinterStorage.cyberCertStorage().securitySeries;
    }

    function transferable() public view returns (bool) {
        return CyberCertPrinterStorage.cyberCertStorage().transferable;
    }
    
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function endorsementRequired() public view returns (bool) {
        return CyberCertPrinterStorage.cyberCertStorage().endorsementRequired;
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal override onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyIssuanceManager {}

    function addDefaultLegend(string memory newLegend) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.defaultLegend.push(newLegend);
    }

    function removeDefaultLegendAt(uint256 index) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert InvalidLegendIndex();

        // Move the last element to the index being removed (if it's not the last element)
        // and then pop the last element
        uint256 lastIndex = s.defaultLegend.length - 1;
        if (index != lastIndex) {
            s.defaultLegend[index] = s.defaultLegend[lastIndex];
        }
        s.defaultLegend.pop();
    }

    function getDefaultLegendAt(uint256 index) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert InvalidLegendIndex();
        
        return s.defaultLegend[index];
    }

    function getDefaultLegendCount() external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend.length;
    }

    function addCertLegend(uint256 tokenId, string memory newLegend) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.certLegend[tokenId].push(newLegend);
    }

    function removeCertLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert InvalidLegendIndex();

        // Move the last element to the index being removed (if it's not the last element)
        // and then pop the last element
        uint256 lastIndex = s.certLegend[tokenId].length - 1;
        if (index != lastIndex) {
            s.certLegend[tokenId][index] = s.certLegend[tokenId][lastIndex];
        }
        s.certLegend[tokenId].pop();
    }   

    function getCertLegendAt(uint256 tokenId, uint256 index) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert InvalidLegendIndex();
        
        return s.certLegend[tokenId][index];
    }   

    function getCertLegendCount(uint256 tokenId) external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId].length;
    }
    
}
