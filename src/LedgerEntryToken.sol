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
import "./storage/LedgerEntryTokenStorage.sol";
import "./interfaces/ILedgerEntryToken.sol";
import "./interfaces/IUriBuilder.sol";
import "./interfaces/ICyberAgreementRegistry.sol";


/// @title LedgerEntryToken (formerly CyberCertPrinter)
/// @dev Renamed from CyberCertPrinter. The rename is source-level only: this implementation must remain
/// ABI- and storage-compatible with the CyberCertPrinter BeaconProxy instances already deployed, so
/// the ILedgerEntryToken interface members (functions, errors, and events — including
/// CyberCertPrinter_CertificateCreated), the LedgerEntryTokenStorage library and its
/// "cybercorp.cert.printer.storage.v1" slot, and all external signatures are intentionally unchanged.
/// Do NOT rename any of those without treating it as a breaking ABI change.
contract LedgerEntryToken is Initializable, ERC721EnumerableUpgradeable {
    using LedgerEntryTokenStorage for LedgerEntryTokenStorage.CyberCertStorage;

    string public constant DEPLOY_VERSION = "5"; // For version-tracking on all deployment and future upgrades

    modifier onlyIssuanceManager() {
        if (msg.sender != LedgerEntryTokenStorage.cyberCertStorage().issuanceManager) revert ILedgerEntryToken.NotIssuanceManager();
        _;
    }

    function _requireIssuanceManagerOrAdmin() private view {
        LedgerEntryTokenStorage.requireManagerOrAdmin();
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
        
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        s.issuanceManager = _issuanceManager;
        s.defaultLegend = _defaultLegend;
        s.securityType = _securityType;
        s.securitySeries = _securitySeries;
        s.certificateUri = _certificateUri;
        s.endorsementRequired = true;
        // `transferable` and `legalTransferable` both stay false on purpose. A new printer issues freely
        // (issuance skips both gates), but holders cannot move the certificate and the register cannot
        // change until an admin opens each one. Secondary trading is therefore an explicit act per SPV.
        s.extension = _extension;
        s.seriesData = _seriesData;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().issuanceManager = _issuanceManager;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.cyberCertStorage().restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit ILedgerEntryToken.RestrictionHookSet(_id, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.cyberCertStorage().globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit ILedgerEntryToken.GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.cyberCertStorage().transferable = _transferable;
        emit ILedgerEntryToken.GlobalTransferableSet(_transferable);
    }

    /// @notice Stop-transfer on the books: whether the holder of record may change at all.
    /// Governs registration, not delivery. Original issuance is never gated by it.
    function setGlobalLegalTransferable(bool value) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.setLegalTransferable(value);
        emit ILedgerEntryToken.GlobalLegalTransferableSet(value);
    }

    /// @notice Per-lot override of the stop-transfer on the books; either flag being on permits registration.
    function setTokenLegalTransferable(uint256 tokenId, bool value) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.setTokenLegalTransferable(tokenId, value);
        emit ILedgerEntryToken.TokenLegalTransferableSet(tokenId, value);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {

        _safeMint(to, tokenId);
        LedgerEntryTokenStorage.recordMint(tokenId, to, details);
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
        LedgerEntryTokenStorage.recordMintAndAssign(tokenId, to, details, investorName);
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
        LedgerEntryTokenStorage.recordMintAndAssign(tokenId, owner, details, ownerName);
        return tokenId;
    }

    /// @notice Mints the buyer's lot in a secondary trade. Names the lot the title came from.
    /// @dev A reissue moves title, but it is a mint. Nothing on the new lot shows that.
    /// `sourceTokenId` gives the register gate the seller, so the gate sees a transfer.
    /// @param sourceTokenId The seller's lot. Supplies the outgoing holder of record.
    /// @param to Takes possession. The custodian under administered hosting, else the buyer.
    /// @param owner The buyer. Goes on the register.
    /// @param tokenId ID for the new lot
    /// @param details Certificate details, copied from the seller's lot
    /// @param ownerName Buyer's legal name for the register
    function safeMintFromAndAssign(
        uint256 sourceTokenId,
        address to,
        address owner,
        uint256 tokenId,
        CertificateDetails memory details,
        string memory ownerName
    ) external onlyIssuanceManager returns (uint256) {
        _safeMint(to, tokenId);
        LedgerEntryTokenStorage.recordMintFromAndAssign(sourceTokenId, tokenId, owner, details, ownerName);
        return tokenId;
    }

    /// @notice Re-registers a lot to a new holder of record.
    /// @dev This moves the register, so it checks the register. `from` is the holder of record.
    /// It is not the possessor. A lot with reserved units is committed to a deal and cannot move.
    /// @param from Current holder of record
    /// @param tokenId ID of the lot
    /// @param to Incoming holder of record
    /// @param details Updated certificate details
    /// @param name Incoming holder's legal name for the register
    function assignCert(
        address from,
        uint256 tokenId,
        address to,
        CertificateDetails memory details,
        string memory name
    ) external onlyIssuanceManager returns (uint256) {
        if(legalOwnerOf(tokenId) != from) revert ILedgerEntryToken.InvalidTokenId();
        // Reserved units are escrowed for a pending deal; legal ownership can't be reassigned while on escrow.
        if (LedgerEntryTokenStorage.getUnitsReserved(tokenId) > 0) revert ILedgerEntryToken.CertificateReserved();
        LedgerEntryTokenStorage.recordAssign(tokenId, to, details, name);
        return tokenId;
    }
    
    // Add endorsement (for transfers in secondary market)
    // Only the holder of record may endorse their own cert; possession alone does not authorize it, or a
    // custodian could endorse a cert to itself and take legal title on delivery. The IssuanceManager endorses
    // as registrar, on the owner's signature carried in the endorsement.
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if(msg.sender != LedgerEntryTokenStorage.cyberCertStorage().issuanceManager && msg.sender != legalOwnerOf(tokenId)) revert ILedgerEntryToken.InvalidEndorsement();
        LedgerEntryTokenStorage.recordEndorsement(tokenId, newEndorsement);
    }

    function addIssuerSignature(
        uint256 tokenId,
        bytes calldata signature
    ) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        if (signature.length == 0) revert ILedgerEntryToken.SignatureRequired();
        LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId].push(signature);
        emit ILedgerEntryToken.CertificateSigned(tokenId, signature);
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
        LedgerEntryTokenStorage.endorseCertificate(tokenId, endorser, signature, agreementId);
    }

    /// @notice Overrides a certificate's Rule 144(d)(3) tacking anchor (tackedFromAcquisitionDate).
    /// @dev Rewrites only that field in the cert's FundInterestData; other fields are preserved.
    function updateCertificateTackedFromAcquisitionDate(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.updateTackedFromAcquisitionDate(tokenId, ts);
    }

    /// @dev Goes through _update with msg.sender as the authorizer, so moving someone else's possession needs
    /// their ERC-721 approval. A pledgee's or custodian's possession is not revocable by the holder of record.
    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        if (to == address(0)) revert ILedgerEntryToken.InvalidTokenId();
        address previousOwner = _update(to, tokenId, msg.sender);
        if (previousOwner != from) revert ILedgerEntryToken.InvalidTokenId();
    }
    
    // Update agreement details
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        // Enforce the reserved-units invariant at the single write chokepoint: raw unitsRepresented may never
        // drop below the units locked in pending deals. Guards against a caller writing back an effective
        // (scripified-inflated) or otherwise under-counted balance.
        if (details.unitsRepresented < LedgerEntryTokenStorage.getUnitsReserved(tokenId)) revert ILedgerEntryToken.ExceedsAvailableUnits();
        LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId] = details;
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
            if (LedgerEntryTokenStorage.getUnitsReserved(tokenId) > 0) revert ILedgerEntryToken.CertificateReserved();
            // Restriction + endorsement logic lives in the external library (delegatecall)
            // to keep this contract under the bytecode size limit
            LedgerEntryTokenStorage.processTransfer(from, to, tokenId);
        }
        // Emit custom transfer event for indexing
        emit ILedgerEntryToken.CyberCertTransfer(
            from,
            to,
            tokenId
        );
        LedgerEntryTokenStorage.recordHolderChange(from, to);
        
        // Call the parent implementation to handle the actual transfer
        return super._update(to, tokenId, auth);
    }
    
    /// @notice `CertificateDetails.unitsRepresented` is re-purposed to `details.unitsRepresented + scripifiedUnits` in this case
    ///         If you need raw `unitsRepresented`, use `getActiveCertificateDetails()` instead
    // Get full agreement details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert ILedgerEntryToken.TokenDoesNotExist();
        return LedgerEntryTokenStorage.getCertificateDetails(tokenId);
    }

    function getActiveCertificateDetails(
        uint256 tokenId
    ) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert ILedgerEntryToken.TokenDoesNotExist();
        return LedgerEntryTokenStorage.getActiveCertificateDetails(tokenId);
    }

    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        Endorsement memory details
    ) {
        if (ownerOf(tokenId) == address(0)) revert ILedgerEntryToken.TokenDoesNotExist();
             details = LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId][index];
    }

    function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId].length;
    }

    function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes memory) {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId][index];
    }

    // Note voiding a cert does not impact legal owner accounting (the legal-owner enumeration keeps the
    // voided lot; that is why `_removeFromLegalOwnerEnumeration()` is not called here). It DOES impact the
    // look-through holder tally: a fully-voided lot no longer counts its owner as a live holder, so the
    // tally is decremented via `recordVoidLegalOwner` (after the status flip).
    function voidCert(uint256 tokenId) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        // Class-terms accounting runs first: it reads the pre-void active units (P1 review fix)
        LedgerEntryTokenStorage.syncClassTermsOnVoidStatus(tokenId, true);
        LedgerEntryTokenStorage.setSecurityStatus(tokenId, SecurityStatus.Void);
        LedgerEntryTokenStorage.recordVoidLegalOwner(tokenId);
        emit ILedgerEntryToken.CertificateVoided(tokenId, block.timestamp);
    }

    // As explained in `voidCert()`. Un-voiding restores the lot's contribution to the look-through tally,
    // so `recordUnvoidLegalOwner` runs after the status is set back to Assigned.
    function unvoidCert(uint256 tokenId) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        // Class-terms accounting runs first (lot must still read voided); a restore that would
        // breach authorizedShares reverts the unvoid rather than bypassing the cap
        LedgerEntryTokenStorage.syncClassTermsOnVoidStatus(tokenId, false);
        LedgerEntryTokenStorage.setSecurityStatus(tokenId, SecurityStatus.Assigned);
        LedgerEntryTokenStorage.recordUnvoidLegalOwner(tokenId);
        emit ILedgerEntryToken.CertificateUnvoided(tokenId, block.timestamp);
    }

    function isVoided(uint256 tokenId) external view returns (bool) {
        if (ownerOf(tokenId) == address(0)) revert ILedgerEntryToken.TokenDoesNotExist();
        return
            LedgerEntryTokenStorage.getSecurityStatus(tokenId) ==
            SecurityStatus.Void;
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert ILedgerEntryToken.URIQueryForNonexistentToken();
        return LedgerEntryTokenStorage.tokenURI(tokenId);
    }

   /* // URI storage functionality
    function tokenURIJson(uint256 tokenId) public view virtual returns (string memory) {
        if (!_exists(tokenId)) revert ILedgerEntryToken.URIQueryForNonexistentToken();

        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
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
        return LedgerEntryTokenStorage.cyberCertStorage().defaultLegend;
    }

    function defaultRestrictiveLegends() public view returns (RestrictiveLegend[] memory) {
        return LedgerEntryTokenStorage.cyberCertStorage().defaultLegendsV2;
    }

    function certificateUri() public view returns (string memory) {
        return LedgerEntryTokenStorage.cyberCertStorage().certificateUri;
    }

    function issuanceManager() public view returns (address) {
        return LedgerEntryTokenStorage.cyberCertStorage().issuanceManager;
    }

    function securityType() public view returns (SecurityClass) {
        return LedgerEntryTokenStorage.cyberCertStorage().securityType;
    }

    function securitySeries() public view returns (SecuritySeries) {
        return LedgerEntryTokenStorage.cyberCertStorage().securitySeries;
    }

    function transferable() public view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().transferable;
    }

    function legalTransferable() public view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().legalTransferable;
    }

    function isTokenLegalTransferable(uint256 tokenId) external view returns (bool) {
        return LedgerEntryTokenStorage.isTokenLegalTransferable(tokenId);
    }

    /// @notice Distinct wallets that hold a lot of this series, counted on delivery.
    /// @dev This counts possession, not the register. For the holder-of-record count that the §3(c)(1) cap
    /// reads, use `lookThroughHolderCount()`.
    function holderCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.getHolderCount();
    }

    /// @notice §3(c)(1)(A) look-through holder count: Σ over live holders of max(beneficialOwnerCount, 1).
    function lookThroughHolderCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.getLookThroughHolderCount();
    }

    /// @notice The U.S.-resident subset of `lookThroughHolderCount` (Touche Remnant counting). Past
    /// `usTallyExpiry` this reports the full look-through count instead, because a non-US booking may
    /// have lapsed into US unobserved.
    function usLookThroughHolderCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.getUsLookThroughHolderCount();
    }

    /// @notice When the U.S. subtotal stops being trusted: the earliest credential expiry among holders
    /// booked non-US, or 0 when none constrains it. Keepers resync those holders before it passes.
    function usTallyExpiry() external view returns (uint64) {
        return LedgerEntryTokenStorage.getUsTallyExpiry();
    }

    /// @notice True when `owner` currently holds at least one live (non-void) lot of record.
    function isLegalHolder(address owner) external view returns (bool) {
        return LedgerEntryTokenStorage.isLegalHolder(owner);
    }

    /// @notice The LeXcheXBadge the look-through tally samples for beneficial-owner counts and US residency.
    function lookThroughBadge() external view returns (address) {
        return LedgerEntryTokenStorage.getLookThroughBadge();
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function endorsementRequired() public view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().endorsementRequired;
    }

    function addDefaultLegend(string memory newLegend) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.addLegend(0, true, newLegend);
    }

    function removeDefaultLegendAt(uint256 index) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.removeLegendAt(0, true, index);
    }

    function getDefaultLegendAt(uint256 index) external view returns (string memory) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert ILedgerEntryToken.InvalidLegendIndex();
        
        return s.defaultLegend[index];
    }

    function getDefaultLegendCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().defaultLegend.length;
    }

    function addDefaultRestrictiveLegend(RestrictiveLegend memory newLegend) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.addRestrictiveLegend(0, true, newLegend);
    }

    function removeDefaultRestrictiveLegendAt(uint256 index) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.removeRestrictiveLegendAt(0, true, index);
    }

    function getDefaultRestrictiveLegendAt(uint256 index) external view returns (RestrictiveLegend memory) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.defaultLegendsV2.length) revert ILedgerEntryToken.InvalidLegendIndex();

        return s.defaultLegendsV2[index];
    }

    function getDefaultRestrictiveLegendCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().defaultLegendsV2.length;
    }

    function addCertLegend(uint256 tokenId, string memory newLegend) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.addLegend(tokenId, false, newLegend);
    }

    function removeCertLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.removeLegendAt(tokenId, false, index);
    }   

    function getCertLegendAt(uint256 tokenId, uint256 index) external view returns (string memory) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert ILedgerEntryToken.InvalidLegendIndex();
        
        return s.certLegend[tokenId][index];
    }   

    function getCertLegendCount(uint256 tokenId) external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().certLegend[tokenId].length;
    }

    function addCertRestrictiveLegend(uint256 tokenId, RestrictiveLegend memory newLegend) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.addRestrictiveLegend(tokenId, false, newLegend);
    }

    function removeCertRestrictiveLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.removeRestrictiveLegendAt(tokenId, false, index);
    }

    function getCertRestrictiveLegendAt(uint256 tokenId, uint256 index) external view returns (RestrictiveLegend memory) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.certLegendsV2[tokenId].length) revert ILedgerEntryToken.InvalidLegendIndex();

        return s.certLegendsV2[tokenId][index];
    }

    function getCertRestrictiveLegendCount(uint256 tokenId) external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().certLegendsV2[tokenId].length;
    }

    function getExtension(uint256 tokenId) external view returns (address) {
        return LedgerEntryTokenStorage.cyberCertStorage().extension;
    }

    function getExtensionData(uint256 tokenId) external view returns (bytes memory) {
        return LedgerEntryTokenStorage._getExtensionData(tokenId);
    }

    function setExtension(uint256 tokenId, address extension) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().extension = extension;
    }

    /// @notice Sets the series-scope extension data (this printer is the series scope).
    /// Same pattern as per-cert extensionData; both payloads are decoded/rendered by the printer's
    /// single `extension` contract (ICertificateExtensionV3-capable extensions handle the series section).
    function setSeriesData(bytes memory _seriesData) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        s.seriesData = _seriesData;
        emit ILedgerEntryToken.SeriesDataSet(s.extension);
    }

    /// @notice Series-scope extension data: the shared extension contract and opaque payload.
    function getSeriesInfo()
        external
        view
        returns (address extension, bytes memory seriesData)
    {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        return (s.extension, s.seriesData);
    }

    function setTokenTransferable(uint256 tokenId, bool value) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.cyberCertStorage().tokenTransferable[tokenId] = value;
    }

    /// @notice Reserve units of a certificate against a pending deal/loan; cannot exceed the cert's units
    function increaseUnitsReserved(uint256 tokenId, uint256 amount) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        LedgerEntryTokenStorage.increaseUnitsReserved(tokenId, amount);
    }

    /// @notice Release previously reserved units; cannot release more than is reserved
    function decreaseUnitsReserved(uint256 tokenId, uint256 amount) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        LedgerEntryTokenStorage.decreaseUnitsReserved(tokenId, amount);
    }

    function unitsReserved(uint256 tokenId) public view returns (uint256) {
        return LedgerEntryTokenStorage.getUnitsReserved(tokenId);
    }

    /// @notice Timestamp the certificate was issued (set at mint; admin-overridable via setIssueTimestamp).
    function issueTimestamp(uint256 tokenId) external view returns (uint64) {
        return LedgerEntryTokenStorage.getIssueTimestamp(tokenId);
    }

    /// @notice Admin override of a cert's issue timestamp (for off-chain-issued positions).
    function setIssueTimestamp(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        LedgerEntryTokenStorage.setIssueTimestamp(tokenId, ts);
    }

    /// @notice Timestamp the current legal owner acquired the certificate; (re)stamped on each legal-owner change.
    function acquisitionTimestamp(uint256 tokenId) external view returns (uint64) {
        return LedgerEntryTokenStorage.getAcquisitionTimestamp(tokenId);
    }

    /// @notice Admin override of a cert's acquisition timestamp (e.g. to seed a seasoned migrated position).
    function setAcquisitionTimestamp(uint256 tokenId, uint64 ts) external onlyIssuanceManagerOrAdmin {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        LedgerEntryTokenStorage.setAcquisitionTimestamp(tokenId, ts);
    }

    function isTokenTransferable(uint256 tokenId) external view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().tokenTransferable[tokenId];
    }

    function legalOwnerOf(uint256 tokenId) public view returns (address) {
        if (!_exists(tokenId)) revert ILedgerEntryToken.TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId].ownerAddress;
    }

    /// @notice Number of certificates `owner` is the legal owner of record for (distinct from ERC-721 custody).
    function balanceOfLegalOwner(address owner) external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().legalOwnerTokenCount[owner];
    }

    /// @notice The `index`-th certificate `owner` is the legal owner of record for. Enumerates by legal owner,
    /// so it lists a holder's certs even when a custodian (e.g. an admin multisig) holds the NFTs.
    function tokenOfLegalOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.legalOwnerTokenCount[owner]) revert ILedgerEntryToken.LegalOwnerIndexOutOfBounds();
        return s.legalOwnedTokens[owner][index];
    }

    /// @notice Backfill the legal-owner enumeration for tokens in [startIndex, startIndex+count) of the supply.
    /// For printers deployed before the enumeration existed: permissionless and idempotent (already-tracked
    /// tokens are skipped), call in batches over [0, totalSupply()) after a beacon upgrade. New printers need it
    /// only if you want to (harmlessly) re-run it.
    function backfillLegalOwners(uint256 startIndex, uint256 count) external {
        LedgerEntryTokenStorage.backfillLegalOwnerEnumeration(startIndex, count);
    }

    /// @notice Backfill the base acquisitionTimestamp from FundInterestExtension data. Permissionless and
    /// idempotent; batch over the supply. See LedgerEntryTokenStorage.backfillAcquisitionTimestamp.
    function backfillAcquisitionTimestamps(uint256 startIndex, uint256 count) external {
        LedgerEntryTokenStorage.backfillAcquisitionTimestamp(startIndex, count);
    }

    /// @notice Wire the LeXcheXBadge the look-through tally samples. Set before the first mint on a new
    /// printer. If holders were already counted without it, run `backfillLookThroughTally` over the supply
    /// afterwards to re-read them off the badge.
    function setLookThroughBadge(address badge) external onlyIssuanceManagerOrAdmin {
        LedgerEntryTokenStorage.setLookThroughBadge(badge);
        emit ILedgerEntryToken.LookThroughBadgeSet(badge);
    }

    /// @notice Re-read the badge and reconcile a live holder's look-through contribution (e.g. after a
    /// re-credential). Permissionless: it can only pull the tally toward authoritative badge state.
    function resyncHolder(address owner) external {
        LedgerEntryTokenStorage.resyncHolder(owner);
    }

    function resyncHolders(address[] calldata owners) external {
        LedgerEntryTokenStorage.resyncHolders(owners);
    }

    /// @notice Backfill the look-through tally for tokens in [startIndex, startIndex+count) after a beacon
    /// upgrade, or after wiring the badge late. Permissionless and idempotent: an already-counted token is
    /// re-read off the badge. Batch over [0, totalSupply()).
    function backfillLookThroughTally(uint256 startIndex, uint256 count) external {
        LedgerEntryTokenStorage.backfillLookThroughTally(startIndex, count);
    }

}
