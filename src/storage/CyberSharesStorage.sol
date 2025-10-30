
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
 
 import "../CyberCorpConstants.sol";
 import "../interfaces/ITransferRestrictionHook.sol";
 
 struct ShareDetails {
     uint256 totalSupply;
     mapping(address => uint256) balances;
     // Other share-specific details if needed
 }

 struct SharesCertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmountUSD;
    uint256 issuerUSDValuationAtTimeOfInvestment;
    uint256 unitsRepresented;
    bool voided;
 }

 struct SharesEndorsement {
    address endorser;
    uint256 timestamp;
    bytes signatureHash;
    address registry;  //optional
    bytes32 agreementId; //optional
    address endorsee;
    string endorseeName;
}

struct ShareOwnerDetails {
    string name;
    address ownerAddress;
}
 
 library CyberSharesStorage {
     // Storage slot for our struct
     bytes32 constant STORAGE_POSITION = keccak256("cybercorp.shares.storage.v1");
 
     // Main storage layout struct
     struct CyberSharesStorageData {
         // Contract configuration
         address issuanceManager;
         SecurityClass securityType;
         SecuritySeries securitySeries;
         string sharesUri;
         string[] defaultLegend;
         bool transferable;
         uint256 decimals;
         uint256 certThreshold; // Minimum shares to form a certificate
         mapping(uint256 => bool) voidedCertificates;
         // Restriction hooks
         ITransferRestrictionHook globalRestrictionHook;
         // Share data
         ShareDetails shares;
         // ERC721 storage
         mapping(uint256 => address) tokenOwners;
         mapping(address => uint256) nftBalances;
         mapping(uint256 => address) tokenApprovals;
         mapping(address => mapping(address => bool)) operatorApprovals;
         // Enumerable storage
         mapping(address => mapping(uint256 => uint256)) ownedTokens;
         mapping(uint256 => uint256) ownedTokensIndex;
         uint256[] allTokens;
         mapping(uint256 => uint256) allTokensIndex;
         // Certificate storage
         mapping(uint256 => SharesCertificateDetails) SharesCertificateDetails;
         mapping(uint256 => SharesEndorsement[]) endorsements;
         mapping(uint256 => ShareOwnerDetails) owners;
         mapping(uint256 => SecurityStatus) securityStatus;
         mapping(uint256 => string[]) certLegend;
         mapping(uint256 => ITransferRestrictionHook) restrictionHooksById;
         // Existing globalRestrictionHook is already there
         address extension;
         string certificateUri;
         bool endorsementRequired;
         uint256 nextCertId;
     }
 
     // Returns the storage layout
     function cyberSharesStorage() internal pure returns (CyberSharesStorageData storage s) {
         bytes32 position = STORAGE_POSITION;
         assembly {
             s.slot := position
         }
     }
 
     // Getters for configuration
     function getIssuanceManager() internal view returns (address) {
         return cyberSharesStorage().issuanceManager;
     }
 
     function getSecurityType() internal view returns (SecurityClass) {
         return cyberSharesStorage().securityType;
     }
 
     function getSecuritySeries() internal view returns (SecuritySeries) {
         return cyberSharesStorage().securitySeries;
     }
 
     function getSharesUri() internal view returns (string memory) {
         return cyberSharesStorage().sharesUri;
     }
 
     function getDefaultLegend() internal view returns (string[] memory) {
         return cyberSharesStorage().defaultLegend;
     }
 
     function isTransferable() internal view returns (bool) {
         return cyberSharesStorage().transferable;
     }
 
     function getDecimals() internal view returns (uint256) {
         return cyberSharesStorage().decimals;
     }
 
     function getCertThreshold() internal view returns (uint256) {
         return cyberSharesStorage().certThreshold;
     }
 
     function getGlobalRestrictionHook() internal view returns (ITransferRestrictionHook) {
         return cyberSharesStorage().globalRestrictionHook;
     }
 
     // Share data getters
     function getTotalSupply() internal view returns (uint256) {
         return cyberSharesStorage().shares.totalSupply;
     }
 
     function getBalance(address account) internal view returns (uint256) {
         return cyberSharesStorage().shares.balances[account];
     }
 
     // Setters
     function setIssuanceManager(address _issuanceManager) internal {
         cyberSharesStorage().issuanceManager = _issuanceManager;
     }
 
     function setSecurityType(SecurityClass _type) internal {
         cyberSharesStorage().securityType = _type;
     }
 
     function setSecuritySeries(SecuritySeries _series) internal {
         cyberSharesStorage().securitySeries = _series;
     }
 
     function setSharesUri(string memory _uri) internal {
         cyberSharesStorage().sharesUri = _uri;
     }
 
     function setDefaultLegend(string[] memory _legend) internal {
         cyberSharesStorage().defaultLegend = _legend;
     }
 
     function setTransferable(bool _transferable) internal {
         cyberSharesStorage().transferable = _transferable;
     }
 
     function setDecimals(uint256 _decimals) internal {
         cyberSharesStorage().decimals = _decimals;
     }
 
     function setCertThreshold(uint256 _threshold) internal {
         cyberSharesStorage().certThreshold = _threshold;
     }
 
     function setGlobalRestrictionHook(ITransferRestrictionHook _hook) internal {
         cyberSharesStorage().globalRestrictionHook = _hook;
     }
 
     // Share data setters
     function setTotalSupply(uint256 _totalSupply) internal {
         cyberSharesStorage().shares.totalSupply = _totalSupply;
     }
 
     function setBalance(address account, uint256 balance) internal {
         cyberSharesStorage().shares.balances[account] = balance;
     }
 
     function addBalance(address account, uint256 amount) internal {
         cyberSharesStorage().shares.balances[account] += amount;
         cyberSharesStorage().shares.totalSupply += amount;
     }
 
     function subtractBalance(address account, uint256 amount) internal {
         cyberSharesStorage().shares.balances[account] -= amount;
         cyberSharesStorage().shares.totalSupply -= amount;
     }
 
     function isVoidedCertificate(uint256 certId) internal view returns (bool) {
         return cyberSharesStorage().voidedCertificates[certId];
     }
 
     function setVoidedCertificate(uint256 certId, bool voided) internal {
         cyberSharesStorage().voidedCertificates[certId] = voided;
     }

    function exists(uint256 tokenId) internal view returns (bool) {
         //check if the tokenId is in the allTokens array
         return CyberSharesStorage.getAllTokens().length > tokenId;
     }

     function getTokenOwner(uint256 tokenId) internal view returns (address) {
         return cyberSharesStorage().tokenOwners[tokenId];
     }

     function setTokenOwner(uint256 tokenId, address owner) internal {
         cyberSharesStorage().tokenOwners[tokenId] = owner;
     }

     function getNftBalance(address account) internal view returns (uint256) {
         return cyberSharesStorage().nftBalances[account];
     }

     function setNftBalance(address account, uint256 balance) internal {
         cyberSharesStorage().nftBalances[account] = balance;
     }

     function getTokenApproval(uint256 tokenId) internal view returns (address) {
         return cyberSharesStorage().tokenApprovals[tokenId];
     }

     function setTokenApproval(uint256 tokenId, address operator) internal {
         cyberSharesStorage().tokenApprovals[tokenId] = operator;
     }

     function getApproved(uint256 tokenId) internal view returns (address) {
         return cyberSharesStorage().tokenApprovals[tokenId];
     }

     function isApprovedForAll(address owner, address operator) internal view returns (bool) {
         return cyberSharesStorage().operatorApprovals[owner][operator];
     }

     function setApprovalForAll(address owner, address operator, bool approved) internal {
         cyberSharesStorage().operatorApprovals[owner][operator] = approved;
     }

     function getOwnedTokens(address owner) internal view returns (uint256[] memory) {
         uint256 balance = getNftBalance(owner);
         uint256[] memory tokens = new uint256[](balance);
         for (uint256 i = 0; i < balance; i++) {
             tokens[i] = cyberSharesStorage().ownedTokens[owner][i];
         }
         return tokens;
     }

     function getOwnedTokenIndex(uint256 tokenId) internal view returns (uint256) {
         return cyberSharesStorage().ownedTokensIndex[tokenId];
     }

     function setOwnedTokenIndex(uint256 tokenId, uint256 index) internal {
         cyberSharesStorage().ownedTokensIndex[tokenId] = index;
     }

     function getAllTokens() internal view returns (uint256[] memory) {
         return cyberSharesStorage().allTokens;
     }

     function getTokenIndex(uint256 tokenId) internal view returns (uint256) {
         return cyberSharesStorage().allTokensIndex[tokenId];
     }

     function setTokenIndex(uint256 tokenId, uint256 index) internal {
         cyberSharesStorage().allTokensIndex[tokenId] = index;
     }

     function getSharesCertificateDetails(uint256 certId) internal view returns (SharesCertificateDetails memory) {
         return cyberSharesStorage().SharesCertificateDetails[certId];
     }

    function setSharesCertificateDetails(uint256 certId, SharesCertificateDetails memory details) internal {
         cyberSharesStorage().SharesCertificateDetails[certId] = details;
     }

     function getSharesEndorsements(uint256 certId) internal view returns (SharesEndorsement[] memory) {
         return cyberSharesStorage().endorsements[certId];
     }

     function setSharesEndorsements(uint256 certId, SharesEndorsement[] memory endorsements) internal {
         cyberSharesStorage().endorsements[certId] = endorsements;
     }

     function getOwners(uint256 certId) internal view returns (ShareOwnerDetails memory) {
         return cyberSharesStorage().owners[certId];
     }

     function setOwners(uint256 certId, ShareOwnerDetails memory owners) internal {
         cyberSharesStorage().owners[certId] = owners;
     }
     
     function getCertLegend(uint256 certId) internal view returns (string[] memory) {
         return cyberSharesStorage().certLegend[certId];
     }

     function setCertLegend(uint256 certId, string[] memory legend) internal {
         cyberSharesStorage().certLegend[certId] = legend;
     }

     function getRestrictionHookById(uint256 certId) internal view returns (ITransferRestrictionHook) {
         return cyberSharesStorage().restrictionHooksById[certId];
     }

     function setRestrictionHookById(uint256 certId, ITransferRestrictionHook hook) internal {
         cyberSharesStorage().restrictionHooksById[certId] = hook;
     }

     function getExtension() internal view returns (address) {
         return cyberSharesStorage().extension;
     }

     function setExtension(address _extension) internal {
         cyberSharesStorage().extension = _extension;
     }

     function getCertificateUri() internal view returns (string memory) {
         return cyberSharesStorage().certificateUri;
     }

     function setCertificateUri(string memory _uri) internal {
         cyberSharesStorage().certificateUri = _uri;
     }

     function isEndorsementRequired() internal view returns (bool) {
         return cyberSharesStorage().endorsementRequired;
     }

     function setEndorsementRequired(bool _required) internal {
         cyberSharesStorage().endorsementRequired = _required;
     }

     function getVoided(uint256 certId) internal view returns (bool) {
         return cyberSharesStorage().SharesCertificateDetails[certId].voided;
     }
     function setVoided(uint256 certId, bool voided) internal {
         cyberSharesStorage().SharesCertificateDetails[certId].voided = voided;
     }

     function getSecurityStatus(uint256 certId) internal view returns (SecurityStatus) {
         return cyberSharesStorage().securityStatus[certId];
     }
     function setSecurityStatus(uint256 certId, SecurityStatus status) internal {
         cyberSharesStorage().securityStatus[certId] = status;
     }

     function getNextCertId() internal view returns (uint256) {
         return cyberSharesStorage().nextCertId;
     }
     function setNextCertId(uint256 id) internal {
         cyberSharesStorage().nextCertId = id;
     }
     function incrementBalance(address owner) internal {
         cyberSharesStorage().nftBalances[owner]++;
     }
     function addTokenToOwnerEnumeration(address to, uint256 tokenId) internal {
         uint256 length = cyberSharesStorage().nftBalances[to];
         cyberSharesStorage().ownedTokens[to][length] = tokenId;
         cyberSharesStorage().ownedTokensIndex[tokenId] = length;
     }
     function addTokenToAllTokensEnumeration(uint256 tokenId) internal {
         cyberSharesStorage().allTokensIndex[tokenId] = cyberSharesStorage().allTokens.length;
         cyberSharesStorage().allTokens.push(tokenId);
     }

     function _transfer(address from, address to, uint256 tokenId) internal {
         require(cyberSharesStorage().tokenOwners[tokenId] == from, "ERC721: transfer from incorrect owner");
         require(to != address(0), "ERC721: transfer to the zero address");
         // Clear approval
         cyberSharesStorage().tokenApprovals[tokenId] = address(0);
         // Update balances
         cyberSharesStorage().nftBalances[from]--;
         cyberSharesStorage().nftBalances[to]++;
         // Update owner
         cyberSharesStorage().tokenOwners[tokenId] = to;
         // Update enumerations
         // Remove from from's list
         uint256 lastTokenIndex = cyberSharesStorage().nftBalances[from];
         uint256 tokenIndex = cyberSharesStorage().ownedTokensIndex[tokenId];
         if (tokenIndex != lastTokenIndex) {
             uint256 lastTokenId = cyberSharesStorage().ownedTokens[from][lastTokenIndex];
             cyberSharesStorage().ownedTokens[from][tokenIndex] = lastTokenId;
             cyberSharesStorage().ownedTokensIndex[lastTokenId] = tokenIndex;
         }
         // Add to to's list
         cyberSharesStorage().ownedTokens[to][cyberSharesStorage().nftBalances[to]] = tokenId;
         cyberSharesStorage().ownedTokensIndex[tokenId] = cyberSharesStorage().nftBalances[to];
     }
 }

