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

import "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./storage/CyberCertPrinterStorage.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/IUriBuilder.sol";
import "./interfaces/ICyberAgreementRegistry.sol";


contract CyberCertPrinter is Initializable, ERC721EnumerableUpgradeable {
    using CyberCertPrinterStorage for CyberCertPrinterStorage.CyberCertStorage;

    string public constant DEPLOY_VERSION = "4"; // For version-tracking on all deployment and future upgrades

    modifier onlyIssuanceManager() {
        if (msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager) revert ICyberCertPrinter.NotIssuanceManager();
        _;
    }

    function _requireIssuanceManagerOrAdmin() private view {
        CyberCertPrinterStorage.requireManagerOrAdmin();
    }

    modifier onlyIssuanceManagerOrAdmin() {
        // routed through a single private helper (not inlined per call site) to save sapce
        _requireIssuanceManagerOrAdmin();
        _;
    }

    constructor()  {
        _disableInitializers();
    }

    // Called by proxy on deployment (if needed)
    function initialize(
        string[] memory _defaultLegend,
        string memory name,
        string memory ticker,
        string memory _certificateUri,
        address _issuanceManager,
        SecurityClass _securityType,
        SecuritySeries _securitySeries,
        address _extension,
        bytes memory _seriesData
    ) external initializer {
        __ERC721_init(name, ticker);
        __ERC721Enumerable_init_unchained();
        
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.issuanceManager = _issuanceManager;
        s.defaultLegend = _defaultLegend;
        s.securityType = _securityType;
        s.securitySeries = _securitySeries;
        s.certificateUri = _certificateUri;
        s.endorsementRequired = true;
        s.extension = _extension;
        s.seriesData = _seriesData;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().issuanceManager = _issuanceManager;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit ICyberCertPrinter.RestrictionHookSet(_id, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit ICyberCertPrinter.GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.cyberCertStorage().transferable = _transferable;
        emit ICyberCertPrinter.GlobalTransferableSet(_transferable);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {

        _safeMint(to, tokenId);
        CyberCertPrinterStorage.recordMint(tokenId, to, details);
        return tokenId;
    }

    // Restricted minting with full agreement details
    function safeMintAndAssign(
        address to,
        uint256 tokenId,
        CertificateDetails memory details,
        string memory investorName
    ) external onlyIssuanceManager returns (uint256) {
        _safeMint(to, tokenId);
        CyberCertPrinterStorage.recordMintAndAssign(tokenId, to, details, investorName);
        return tokenId;
    }

    // Overload: allowing separation of custodian `to` vs legal owner `owner`
    // This way we can support administered hosting (to != owner) in addition to direct hosting (owner == to)
    function safeMintAndAssign(
        address to, // custodian
        address owner, // legal owner
        uint256 tokenId,
        CertificateDetails memory details,
        string memory ownerName
    ) external onlyIssuanceManager returns (uint256) {
        _safeMint(to, tokenId);
        CyberCertPrinterStorage.recordMintAndAssign(tokenId, owner, details, ownerName);
        return tokenId;
    }

    function assignCert(
        address from,
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        if(ownerOf(tokenId) != from) revert ICyberCertPrinter.InvalidTokenId();
        // Reserved units are escrowed for a pending deal; legal ownership can't be reassigned while on escrow.
        if (CyberCertPrinterStorage.getUnitsReserved(tokenId) > 0) revert ICyberCertPrinter.CertificateReserved();
        CyberCertPrinterStorage.recordAssign(tokenId, to, details);
        return tokenId;
    }
    
    // Add endorsement (for transfers in secondary market)
    // Only the holder of record may endorse their own cert; possession alone does not authorize it, or a
    // custodian could endorse a cert to itself and take legal title on delivery. The IssuanceManager endorses
    // as registrar, on the owner's signature carried in the endorsement.
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if(msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager && msg.sender != legalOwnerOf(tokenId)) revert ICyberCertPrinter.InvalidEndorsement();
        CyberCertPrinterStorage.recordEndorsement(tokenId, newEndorsement);
    }

    function addIssuerSignature(
        uint256 tokenId,
        bytes calldata signature
    ) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        if (signature.length == 0) revert ICyberCertPrinter.SignatureRequired();
        CyberCertPrinterStorage.cyberCertStorage().issuerSignatures[tokenId].push(signature);
        emit ICyberCertPrinter.CertificateSigned(tokenId, signature);
    }

    /// @notice Records a secondary-market endorsement, assembling the endorsement tuple on-chain.
    /// @dev Admin/manager entrypoint (endorsee/name blank, registry cleared); addEndorsement covers the
    /// manager/token-owner path with a caller-supplied Endorsement.
    function endorseCertificate(
        uint256 tokenId,
        address endorser,
        bytes memory signature,
        bytes32 agreementId
    ) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.endorseCertificate(tokenId, endorser, signature, agreementId);
    }

    /// @notice Overrides a certificate's Rule 144(d)(3) tacking anchor (tackedFromAcquisitionDate).
    /// @dev Rewrites only that field in the cert's FundInterestData; other fields are preserved.
    function updateCertificateTackedFromAcquisitionDate(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.updateTackedFromAcquisitionDate(tokenId, ts);
    }

    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        _transfer(from, to, tokenId);
    }
    
    // Update agreement details
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        // Enforce the reserved-units invariant at the single write chokepoint: raw unitsRepresented may never
        // drop below the units locked in pending deals. Guards against a caller writing back an effective
        // (scripified-inflated) or otherwise under-counted balance.
        if (details.unitsRepresented < CyberCertPrinterStorage.getUnitsReserved(tokenId)) revert ICyberCertPrinter.ExceedsAvailableUnits();
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
    }

    /**
     * @dev Override _update to enforce transferability restrictions
     * This function is called for all token transfers, mints, and burns
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Skip restriction checks for minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            // A cert with reserved units is escrowed for a pending deal/loan: its legal ownership is frozen
            // until the reservation is released at settlement or void. Blocks the transfer vector; assignCert
            // guards the reassignment vector.
            if (CyberCertPrinterStorage.getUnitsReserved(tokenId) > 0) revert ICyberCertPrinter.CertificateReserved();
            // Restriction + endorsement logic lives in the external library (delegatecall)
            // to keep this contract under the bytecode size limit
            CyberCertPrinterStorage.processTransfer(from, to, tokenId);
        }
        // Emit custom transfer event for indexing
        emit ICyberCertPrinter.CyberCertTransfer(
            from,
            to,
            tokenId
        );
        CyberCertPrinterStorage.recordHolderChange(from, to);
        
        // Call the parent implementation to handle the actual transfer
        return super._update(to, tokenId, auth);
    }
    
    /// @notice `CertificateDetails.unitsRepresented` is re-purposed to `details.unitsRepresented + scripifiedUnits` in this case
    ///         If you need raw `unitsRepresented`, use `getActiveCertificateDetails()` instead
    // Get full agreement details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert ICyberCertPrinter.TokenDoesNotExist();
        return CyberCertPrinterStorage.getCertificateDetails(tokenId);
    }

    function getActiveCertificateDetails(
        uint256 tokenId
    ) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert ICyberCertPrinter.TokenDoesNotExist();
        return CyberCertPrinterStorage.getActiveCertificateDetails(tokenId);
    }

    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        Endorsement memory details
    ) {
        if (ownerOf(tokenId) == address(0)) revert ICyberCertPrinter.TokenDoesNotExist();
             details = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][index];
    }

    function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        return CyberCertPrinterStorage.cyberCertStorage().issuerSignatures[tokenId].length;
    }

    function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes memory) {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        return CyberCertPrinterStorage.cyberCertStorage().issuerSignatures[tokenId][index];
    }

    // Note voiding a cert does not impact legal owner accounting (the legal-owner enumeration keeps the
    // voided lot; that is why `_removeFromLegalOwnerEnumeration()` is not called here). It DOES impact the
    // look-through holder tally: a fully-voided lot no longer counts its owner as a live holder, so the
    // tally is decremented via `recordVoidLegalOwner` (after the status flip).
    function voidCert(uint256 tokenId) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.setSecurityStatus(tokenId, SecurityStatus.Void);
        CyberCertPrinterStorage.recordVoidLegalOwner(tokenId);
        emit ICyberCertPrinter.CertificateVoided(tokenId, block.timestamp);
    }

    // As explained in `voidCert()`. Un-voiding restores the lot's contribution to the look-through tally,
    // so `recordUnvoidLegalOwner` runs after the status is set back to Assigned.
    function unvoidCert(uint256 tokenId) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        CyberCertPrinterStorage.setSecurityStatus(tokenId, SecurityStatus.Assigned);
        CyberCertPrinterStorage.recordUnvoidLegalOwner(tokenId);
        emit ICyberCertPrinter.CertificateUnvoided(tokenId, block.timestamp);
    }

    function isVoided(uint256 tokenId) external view returns (bool) {
        if (ownerOf(tokenId) == address(0)) revert ICyberCertPrinter.TokenDoesNotExist();
        return
            CyberCertPrinterStorage.getSecurityStatus(tokenId) ==
            SecurityStatus.Void;
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert ICyberCertPrinter.URIQueryForNonexistentToken();
        return CyberCertPrinterStorage.tokenURI(tokenId);
    }

   /* // URI storage functionality
    function tokenURIJson(uint256 tokenId) public view virtual returns (string memory) {
        if (!_exists(tokenId)) revert ICyberCertPrinter.URIQueryForNonexistentToken();

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

    return IUriBuilder(IIssuanceManager(s.issuanceManager).uriBuilder()).buildCertificateUriNotEncoded(   
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
            address(this),
            address(s.extension)
        );
    }*/

    // Public getters that directly access storage
    function defaultLegend() public view returns (string[] memory) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
    }

    function defaultRestrictiveLegends() public view returns (RestrictiveLegend[] memory) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegendsV2;
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

    function holderCount() external view returns (uint256) {
        return CyberCertPrinterStorage.getHolderCount();
    }

    /// @notice §3(c)(1)(A) look-through holder count: Σ over live holders of max(beneficialOwnerCount, 1).
    function lookThroughHolderCount() external view returns (uint256) {
        return CyberCertPrinterStorage.getLookThroughHolderCount();
    }

    /// @notice The U.S.-resident subset of `lookThroughHolderCount` (Touche Remnant counting).
    function usLookThroughHolderCount() external view returns (uint256) {
        return CyberCertPrinterStorage.getUsLookThroughHolderCount();
    }

    /// @notice True when `owner` currently holds at least one live (non-void) lot of record.
    function isLegalHolder(address owner) external view returns (bool) {
        return CyberCertPrinterStorage.isLegalHolder(owner);
    }

    /// @notice The LeXcheXBadge the look-through tally samples for beneficial-owner counts and US residency.
    function lookThroughBadge() external view returns (address) {
        return CyberCertPrinterStorage.getLookThroughBadge();
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function endorsementRequired() public view returns (bool) {
        return CyberCertPrinterStorage.cyberCertStorage().endorsementRequired;
    }

    function addDefaultLegend(string memory newLegend) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.addLegend(0, true, newLegend);
    }

    function removeDefaultLegendAt(uint256 index) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.removeLegendAt(0, true, index);
    }

    function getDefaultLegendAt(uint256 index) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert ICyberCertPrinter.InvalidLegendIndex();
        
        return s.defaultLegend[index];
    }

    function getDefaultLegendCount() external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend.length;
    }

    function addDefaultRestrictiveLegend(RestrictiveLegend memory newLegend) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.addRestrictiveLegend(0, true, newLegend);
    }

    function removeDefaultRestrictiveLegendAt(uint256 index) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.removeRestrictiveLegendAt(0, true, index);
    }

    function getDefaultRestrictiveLegendAt(uint256 index) external view returns (RestrictiveLegend memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegendsV2.length) revert ICyberCertPrinter.InvalidLegendIndex();

        return s.defaultLegendsV2[index];
    }

    function getDefaultRestrictiveLegendCount() external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegendsV2.length;
    }

    function addCertLegend(uint256 tokenId, string memory newLegend) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.addLegend(tokenId, false, newLegend);
    }

    function removeCertLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.removeLegendAt(tokenId, false, index);
    }   

    function getCertLegendAt(uint256 tokenId, uint256 index) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert ICyberCertPrinter.InvalidLegendIndex();
        
        return s.certLegend[tokenId][index];
    }   

    function getCertLegendCount(uint256 tokenId) external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId].length;
    }

    function addCertRestrictiveLegend(uint256 tokenId, RestrictiveLegend memory newLegend) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.addRestrictiveLegend(tokenId, false, newLegend);
    }

    function removeCertRestrictiveLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.removeRestrictiveLegendAt(tokenId, false, index);
    }

    function getCertRestrictiveLegendAt(uint256 tokenId, uint256 index) external view returns (RestrictiveLegend memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.certLegendsV2[tokenId].length) revert ICyberCertPrinter.InvalidLegendIndex();

        return s.certLegendsV2[tokenId][index];
    }

    function getCertRestrictiveLegendCount(uint256 tokenId) external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().certLegendsV2[tokenId].length;
    }

    function getExtension(uint256 tokenId) external view returns (address) {
        return CyberCertPrinterStorage.cyberCertStorage().extension;
    }

    function getExtensionData(uint256 tokenId) external view returns (bytes memory) {
        return CyberCertPrinterStorage._getExtensionData(tokenId);
    }

    function setExtension(uint256 tokenId, address extension) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().extension = extension;
    }

    /// @notice Sets the series-scope extension data (this printer is the series scope).
    /// Same pattern as per-cert extensionData; both payloads are decoded/rendered by the printer's
    /// single `extension` contract (ICertificateExtensionV3-capable extensions handle the series section).
    function setSeriesData(bytes memory _seriesData) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.seriesData = _seriesData;
        emit ICyberCertPrinter.SeriesDataSet(s.extension);
    }

    /// @notice Series-scope extension data: the shared extension contract and opaque payload.
    function getSeriesInfo()
        external
        view
        returns (address extension, bytes memory seriesData)
    {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        return (s.extension, s.seriesData);
    }

    function setTokenTransferable(uint256 tokenId, bool value) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.cyberCertStorage().tokenTransferable[tokenId] = value;
    }

    /// @notice Reserve units of a certificate against a pending deal/loan; cannot exceed the cert's units
    function increaseUnitsReserved(uint256 tokenId, uint256 amount) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        CyberCertPrinterStorage.increaseUnitsReserved(tokenId, amount);
    }

    /// @notice Release previously reserved units; cannot release more than is reserved
    function decreaseUnitsReserved(uint256 tokenId, uint256 amount) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        CyberCertPrinterStorage.decreaseUnitsReserved(tokenId, amount);
    }

    function unitsReserved(uint256 tokenId) public view returns (uint256) {
        return CyberCertPrinterStorage.getUnitsReserved(tokenId);
    }

    /// @notice Timestamp the certificate was issued (set at mint; admin-overridable via setIssueTimestamp).
    function issueTimestamp(uint256 tokenId) external view returns (uint64) {
        return CyberCertPrinterStorage.getIssueTimestamp(tokenId);
    }

    /// @notice Admin override of a cert's issue timestamp (for off-chain-issued positions).
    function setIssueTimestamp(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        CyberCertPrinterStorage.setIssueTimestamp(tokenId, ts);
    }

    /// @notice Timestamp the current legal owner acquired the certificate; (re)stamped on each legal-owner change.
    function acquisitionTimestamp(uint256 tokenId) external view returns (uint64) {
        return CyberCertPrinterStorage.getAcquisitionTimestamp(tokenId);
    }

    /// @notice Admin override of a cert's acquisition timestamp (e.g. to seed a seasoned migrated position).
    function setAcquisitionTimestamp(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        CyberCertPrinterStorage.setAcquisitionTimestamp(tokenId, ts);
    }

    function isTokenTransferable(uint256 tokenId) external view returns (bool) {
        return CyberCertPrinterStorage.cyberCertStorage().tokenTransferable[tokenId];
    }

    function legalOwnerOf(uint256 tokenId) public view returns (address) {
        if (!_exists(tokenId)) revert ICyberCertPrinter.TokenDoesNotExist();
        return CyberCertPrinterStorage.cyberCertStorage().owners[tokenId].ownerAddress;
    }

    /// @notice Number of certificates `owner` is the legal owner of record for (distinct from ERC-721 custody).
    function balanceOfLegalOwner(address owner) external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().legalOwnerTokenCount[owner];
    }

    /// @notice The `index`-th certificate `owner` is the legal owner of record for. Enumerates by legal owner,
    /// so it lists a holder's certs even when a custodian (e.g. an admin multisig) holds the NFTs.
    function tokenOfLegalOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.legalOwnerTokenCount[owner]) revert ICyberCertPrinter.LegalOwnerIndexOutOfBounds();
        return s.legalOwnedTokens[owner][index];
    }

    /// @notice Backfill the legal-owner enumeration for tokens in [startIndex, startIndex+count) of the supply.
    /// For printers deployed before the enumeration existed: permissionless and idempotent (already-tracked
    /// tokens are skipped), call in batches over [0, totalSupply()) after a beacon upgrade. New printers need it
    /// only if you want to (harmlessly) re-run it.
    function backfillLegalOwners(uint256 startIndex, uint256 count) external {
        CyberCertPrinterStorage.backfillLegalOwnerEnumeration(startIndex, count);
    }

    /// @notice Backfill the base acquisitionTimestamp from FundInterestExtension data. Permissionless and
    /// idempotent; batch over the supply. See CyberCertPrinterStorage.backfillAcquisitionTimestamp.
    function backfillAcquisitionTimestamps(uint256 startIndex, uint256 count) external {
        CyberCertPrinterStorage.backfillAcquisitionTimestamp(startIndex, count);
    }

    /// @notice Wire the LeXcheXBadge the look-through tally samples. Set before the first mint on a new
    /// printer (and before `backfillLookThroughTally` on an upgraded one).
    function setLookThroughBadge(address badge) external onlyIssuanceManagerOrAdmin {
        CyberCertPrinterStorage.setLookThroughBadge(badge);
        emit ICyberCertPrinter.LookThroughBadgeSet(badge);
    }

    /// @notice Re-read the badge and reconcile a live holder's look-through contribution (e.g. after a
    /// re-credential). Permissionless: it can only pull the tally toward authoritative badge state.
    function resyncHolder(address owner) external {
        CyberCertPrinterStorage.resyncHolder(owner);
    }

    function resyncHolders(address[] calldata owners) external {
        CyberCertPrinterStorage.resyncHolders(owners);
    }

    /// @notice Backfill the look-through tally for tokens in [startIndex, startIndex+count) after a beacon
    /// upgrade. Set the badge first; permissionless and idempotent. Batch over [0, totalSupply()).
    function backfillLookThroughTally(uint256 startIndex, uint256 count) external {
        CyberCertPrinterStorage.backfillLookThroughTally(startIndex, count);
    }

}
