
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
 import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
 import "./interfaces/IIssuanceManager.sol";
 import "./interfaces/ITransferRestrictionHook.sol";
 import "./storage/CyberSharesStorage.sol";
 import "./interfaces/ICyberCertPrinter.sol";
 import "./interfaces/IUriBuilder.sol";
 import "./CyberCorpConstants.sol";
 import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
 import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
 import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
 import "./storage/CyberCertPrinterStorage.sol"; // for types
 import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
 
 contract CyberShares is Initializable, ERC20Upgradeable {
     using CyberSharesStorage for CyberSharesStorage.CyberSharesStorageData;
 
     // Custom errors
     error NotIssuanceManager();
     error InsufficientShares();
     error TransferRestricted(string reason);
     error InvalidAmount();
     error TokenNotTransferable();
     error NotOwner();
     error TokenDoesNotExist();
 
     // Events
     event SharesMinted(address indexed to, uint256 amount);
     event SharesBurned(address indexed from, uint256 amount);
     event CertificateFormed(uint256 indexed certId, uint256 sharesBurned);
     event SharesFromCertificate(uint256 indexed certId, uint256 sharesMinted);
     event GlobalRestrictionHookSet(address indexed hookAddress);
     event TransferableSet(bool transferable);
     event CertThresholdSet(uint256 threshold);
     event SharesFromVoidedCertificate(uint256 indexed certId, uint256 sharesMinted);
     event CertificateTransfer(address indexed from, address indexed to, uint256 indexed tokenId);
     event CertificateApproval(address indexed owner, address indexed approved, uint256 indexed tokenId);
     event CertificateApprovalForAll(address indexed owner, address indexed operator, bool approved);
 
     modifier onlyIssuanceManager() {
         if (msg.sender != CyberSharesStorage.getIssuanceManager()) revert NotIssuanceManager();
         _;
     }
 
     constructor() {
         _disableInitializers();
     }
 
     function initialize(
         string memory name,
         string memory symbol,
         uint256 _decimals,
         string memory _sharesUri,
         address _issuanceManager,
         SecurityClass _securityType,
         SecuritySeries _securitySeries,
         uint256 _certThreshold,
         string[] memory _defaultLegend
     ) external initializer {
         __ERC20_init(name, symbol);
 
         CyberSharesStorage.setIssuanceManager(_issuanceManager);
         CyberSharesStorage.setSecurityType(_securityType);
         CyberSharesStorage.setSecuritySeries(_securitySeries);
         CyberSharesStorage.setSharesUri(_sharesUri);
         CyberSharesStorage.setDefaultLegend(_defaultLegend);
         CyberSharesStorage.setTransferable(true);
         CyberSharesStorage.setDecimals(_decimals);
         CyberSharesStorage.setCertThreshold(_certThreshold);
         CyberSharesStorage.setNextCertId(1);
     }
 
     // ERC20 overrides with restrictions
     function transfer(address to, uint256 amount) public virtual override returns (bool) {
         _checkTransferRestrictions(msg.sender, to, amount);
         return super.transfer(to, amount);
     }
 
     function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
         _checkTransferRestrictions(from, to, amount);
         return super.transferFrom(from, to, amount);
     }
 
     function _checkTransferRestrictions(address from, address to, uint256 amount) internal view {
         if (!CyberSharesStorage.isTransferable()) revert TokenNotTransferable();
 
         ITransferRestrictionHook globalHook = CyberSharesStorage.getGlobalRestrictionHook();
         if (address(globalHook) != address(0)) {
             (bool allowed, string memory reason) = globalHook.checkTransferRestriction(
                 from, to, amount, ""
             );
             if (!allowed) revert TransferRestricted(reason);
         }
     }
 
     // Mint shares
     function mint(address to, uint256 amount) external onlyIssuanceManager {
         _mint(to, amount);
         emit SharesMinted(to, amount);
     }
 
     // Burn shares
     function burn(address from, uint256 amount) external onlyIssuanceManager {
         _burn(from, amount);
         emit SharesBurned(from, amount);
     }
 
     // Burn certificate to shares
     function voidToShares(uint256 certId) external {
        //check that msg.sender is the owner of the certificate
        if (msg.sender != certificateOwnerOf(certId)) revert NotOwner();
         
         // Get certificate details
         SharesCertificateDetails memory details = CyberSharesStorage.getSharesCertificateDetails(certId);
         
         // Calculate share amount (units * 10^decimals)
         uint256 shareAmount = details.unitsRepresented * (10 ** CyberSharesStorage.getDecimals());
         address owner = certificateOwnerOf(certId);
         
         // Void the certificate
         voidCert(certId);
         CyberSharesStorage.setVoidedCertificate(certId, true);
         
         // Mint shares to the certificate owner
         _mint(owner, shareAmount);
         
         emit SharesFromVoidedCertificate(certId, shareAmount);
     }

     function voidCert(uint256 certId) internal {
        cyberSharesStorage().SharesCertificateDetails[certId].voided = true;
     }
 
     // Form certificate from shares
     function formCertificateFromShares(uint256 amount, CertificateDetails memory details) external {
         uint256 threshold = CyberSharesStorage.getCertThreshold();
         if (amount < threshold) revert InsufficientShares();
         if (amount % (10 ** CyberSharesStorage.getDecimals()) != 0) revert InvalidAmount();
         
         uint256 units = amount / (10 ** CyberSharesStorage.getDecimals());
         
         // Burn shares
         _burn(msg.sender, amount);
         
         // Create certificate via IssuanceManager
         uint256 certId = CyberSharesStorage.getNextCertId();
         //safeMint(certId, msg.sender, details);
         CyberSharesStorage.setNextCertId(certId + 1);
         
         emit CertificateFormed(certId, amount);
     }
 
     // Configuration setters
     function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
         CyberSharesStorage.setGlobalRestrictionHook(ITransferRestrictionHook(hookAddress));
         emit GlobalRestrictionHookSet(hookAddress);
     }
 
     function setTransferable(bool _transferable) external onlyIssuanceManager {
         CyberSharesStorage.setTransferable(_transferable);
         emit TransferableSet(_transferable);
     }
 
     function setCertThreshold(uint256 _threshold) external onlyIssuanceManager {
         CyberSharesStorage.setCertThreshold(_threshold);
         emit CertThresholdSet(_threshold);
     }
 
     // View functions
     function decimals() public view virtual override returns (uint8) {
         return uint8(CyberSharesStorage.getDecimals());
     }
 
     function certThreshold() public view returns (uint256) {
         return CyberSharesStorage.getCertThreshold();
     }
 
     function sharesUri() public view returns (string memory) {
         return CyberSharesStorage.getSharesUri();
     }
 
     // ERC721 overrides
     function certificateOwnerOf(uint256 tokenId) public view returns (address) {
         address owner = CyberSharesStorage.getTokenOwner(tokenId);
         if (owner == address(0)) revert TokenDoesNotExist();
         return owner;
     }

     function certificateTransferFrom(address from, address to, uint256 tokenId) public {
         // implementation
         emit CertificateTransfer(from, to, tokenId);
     }

     function certificateApprove(address to, uint256 tokenId) public {
         address owner = certificateOwnerOf(tokenId);
         require(to != owner, "ERC721: approval to current owner");
         require(msg.sender == owner || certificateIsApprovedForAll(owner, msg.sender), "ERC721: approve caller is not owner nor approved for all");
         CyberSharesStorage.setTokenApproval(tokenId, to);
         emit CertificateApproval(owner, to, tokenId);
     }

     function certificateGetApproved(uint256 tokenId) public view returns (address) {
         return CyberSharesStorage.getApproved(tokenId);
     }

     function certificateSetApprovalForAll(address operator, bool _approved) public {
         require(operator != msg.sender, "ERC721: approve to caller");
         CyberSharesStorage.setApprovalForAll(msg.sender, operator, _approved);
         emit CertificateApprovalForAll(msg.sender, operator, _approved);
     }

     function certificateIsApprovedForAll(address owner, address operator) public view returns (bool) {
         return CyberSharesStorage.isApprovedForAll(owner, operator);
     }

     function certificateSafeTransferFrom(address from, address to, uint256 tokenId) public {
         certificateSafeTransferFrom(from, to, tokenId, "");
     }

     function certificateSafeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
         require(_isApprovedOrOwner(msg.sender, tokenId), "ERC721: transfer caller is not owner nor approved");
         CyberSharesStorage._transfer(from, to, tokenId);
         _checkOnERC721Received(from, to, tokenId, _data);
         emit CertificateTransfer(from, to, tokenId);
     }

     function certificateTokenURI(uint256 tokenId) public view returns (string memory) {
         /*require(CyberSharesStorage.exists(tokenId), "URI query for nonexistent token");
         // Adapt from LedgerEntryToken
         string[] memory certLegend = CyberSharesStorage.getCertLegend(tokenId);
         // Get corp details, perhaps from issuanceManager
         address issuanceManager = CyberSharesStorage.getIssuanceManager();
         ICyberCorp corp = ICyberCorp(IIssuanceManager(issuanceManager).CORP());
         // Get registry and agreementId from first endorsement if exists
         address registry = address(0);
         bytes32 agreementId = bytes32(0);
         SharesEndorsement[] memory endorsements = CyberSharesStorage.getSharesEndorsements(tokenId);
         if (endorsements.length > 0) {
             registry = endorsements[0].registry;
             agreementId = endorsements[0].agreementId;
         }
         return IUriBuilder(CyberSharesStorage.uriBuilder).buildCertificateUri(
             corp.cyberCORPName(), corp.cyberCORPType(), corp.cyberCORPJurisdiction(), corp.cyberCORPContactDetails(),
             CyberSharesStorage.getSecurityType(), CyberSharesStorage.getSecuritySeries(), CyberSharesStorage.getCertificateUri(),
             certLegend, CyberSharesStorage.getSharesCertificateDetails(tokenId), endorsements, CyberSharesStorage.getOwners(tokenId),
             registry, agreementId, tokenId, address(this), CyberSharesStorage.getExtension()
         );
         */
         return "";
     }


     function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
         address owner = certificateOwnerOf(tokenId);
         return (spender == owner || certificateGetApproved(tokenId) == spender || certificateIsApprovedForAll(owner, spender));
     }
 
     // Internal storage accessor
     function cyberSharesStorage() internal pure returns (CyberSharesStorage.CyberSharesStorageData storage) {
         return CyberSharesStorage.cyberSharesStorage();
     }

     function safeMint(uint256 tokenId, address to, SharesCertificateDetails memory details) internal {
      /*   // mint logic: setTokenOwner(tokenId, to), increment balances, add to arrays, emit Transfer(0, to, tokenId);
         CyberSharesStorage.setSharesCertificateDetails(tokenId, CertificateDetails({
             signingOfficerName: details.signingOfficerName,
             signingOfficerTitle: details.signingOfficerTitle,
             investmentAmountUSD: details.investmentAmountUSD,
             issuerUSDValuationAtTimeOfInvestment: details.issuerUSDValuationAtTimeOfInvestment,
             unitsRepresented: details.unitsRepresented
         }));
         CyberSharesStorage.setTokenOwner(tokenId, to);
         CyberSharesStorage.incrementBalance(to);
         CyberSharesStorage.addTokenToOwnerEnumeration(to, tokenId);
         CyberSharesStorage.addTokenToAllTokensEnumeration(tokenId);
         emit CertificateTransfer(address(0), to, tokenId);
         */
     }

     function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {

             try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                 require(retval == IERC721Receiver.onERC721Received.selector, "ERC721: transfer to non ERC721Receiver implementer");
             } catch (bytes memory reason) {
                 if (reason.length == 0) {
                     revert("ERC721: transfer to non ERC721Receiver implementer");
                 } else {
                     assembly {
                         revert(add(32, reason), mload(reason))
                     }
                 }
             }
         
     }
 }

