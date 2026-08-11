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

import "./interfaces/ICyberAgreementRegistry.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/IUriBuilder.sol";
import "./storage/LedgerEntryTokenStorage.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract LedgerEntryToken is Initializable, ERC721EnumerableUpgradeable {
    using LedgerEntryTokenStorage for LedgerEntryTokenStorage.CyberCertStorage;

    string public constant DEPLOY_VERSION = "4"; // For version-tracking on all deployment and future upgrades

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
    error SignatureRequired();

    //events
    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CertificateSigned(uint256 indexed tokenId, bytes signature);
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
    event LedgerEntryToken_CertificateCreated(uint256 indexed tokenId);
    event CyberCertTransfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event CertificateAssigned(
        uint256 indexed tokenId, address indexed newOwner, string newOwnerName, string issuerName
    );
    event CertificateVoided(uint256 indexed tokenId, uint256 timestamp);
    event CertificateUnvoided(uint256 indexed tokenId, uint256 timestamp);
    event RestrictionHookSet(uint256 indexed id, address indexed hookAddress);
    event GlobalRestrictionHookSet(address indexed hookAddress);
    event GlobalTransferableSet(bool indexed transferable);

    modifier onlyIssuanceManager() {
        if (msg.sender != LedgerEntryTokenStorage.cyberCertStorage().issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor() {
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
        address _extension
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
        s.extension = _extension;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().issuanceManager = _issuanceManager;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit RestrictionHookSet(_id, _hookAddress);
    }

    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().transferable = _transferable;
        emit GlobalTransferableSet(_transferable);
    }

    function safeMint(uint256 tokenId, address to, CertificateDetails memory details)
        external
        onlyIssuanceManager
        returns (uint256)
    {
        _safeMint(to, tokenId);
        LedgerEntryTokenStorage.cyberCertStorage().certLegend[tokenId] =
        LedgerEntryTokenStorage.cyberCertStorage().defaultLegend;
        LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] = OwnerDetails("", to);
        emit LedgerEntryToken_CertificateCreated(tokenId);
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
        LedgerEntryTokenStorage.cyberCertStorage().certLegend[tokenId] =
        LedgerEntryTokenStorage.cyberCertStorage().defaultLegend;
        // Store agreement details
        LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] = OwnerDetails(investorName, to);
        string memory issuerName =
            IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).companyName();
        emit CertificateAssigned(tokenId, to, investorName, issuerName);
        emit LedgerEntryToken_CertificateCreated(tokenId);
        return tokenId;
    }

    function assignCert(address from, uint256 tokenId, address to, CertificateDetails memory details)
        external
        onlyIssuanceManager
        returns (uint256)
    {
        if (ownerOf(tokenId) != from) revert InvalidTokenId();
        LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] = OwnerDetails("", to);
        string memory issuerName =
            IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).companyName();
        emit CertificateAssigned(tokenId, to, "", issuerName);
        return tokenId;
    }

    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if (msg.sender != LedgerEntryTokenStorage.cyberCertStorage().issuanceManager && msg.sender != ownerOf(tokenId)) revert InvalidEndorsement();
        LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].push(newEndorsement);
        emit CertificateEndorsed(
            tokenId,
            newEndorsement.endorser,
            newEndorsement.endorsee,
            newEndorsement.endorseeName,
            newEndorsement.registry,
            newEndorsement.agreementId,
            LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].length - 1,
            block.timestamp
        );
    }

    function addIssuerSignature(uint256 tokenId, bytes calldata signature) external onlyIssuanceManager {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        if (signature.length == 0) revert SignatureRequired();
        LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId].push(signature);
        emit CertificateSigned(tokenId, signature);
    }

    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        _transfer(from, to, tokenId);
    }

    // Update agreement details
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details)
        external
        onlyIssuanceManager
    {
        LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external onlyIssuanceManager {
        _burn(tokenId);

        // Clear agreement details
        delete LedgerEntryTokenStorage.cyberCertStorage().certificateDetails[tokenId];
        delete LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId];
    }

    /**
     * @dev Override _update to enforce transferability restrictions
     * This function is called for all token transfers, mints, and burns
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);

        // Skip restriction checks for minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            // This is a transfer, check built-in transferability flag and per-token override
            bool globalTransferable = LedgerEntryTokenStorage.cyberCertStorage().transferable;
            bool tokenTransferable = LedgerEntryTokenStorage.isTokenTransferable(tokenId);
            if (
                !globalTransferable && !tokenTransferable
                    && from
                        != ICyberCorp(
                                IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).CORP()
                            ).dealManager()
                    && from
                        != ICyberCorp(
                                IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).CORP()
                            ).roundManager()
            ) revert TokenNotTransferable();

            // Check security type-specific hook if it exists
            /*  ITransferRestrictionHook typeHook = LedgerEntryTokenStorage.cyberCertStorage().restrictionHooksById[tokenId];

              if (address(typeHook) != address(0)) {
                  (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                      from, to, tokenId, ""
                  );
                  if (!allowed) revert TransferRestricted(reason);
              }*/

            // Check global hook if it exists
            if (address(LedgerEntryTokenStorage.cyberCertStorage().globalRestrictionHook) != address(0)) {
                (bool allowed, string memory reason) = LedgerEntryTokenStorage.cyberCertStorage().globalRestrictionHook
                    .checkTransferRestriction(from, to, tokenId, "");
                if (!allowed) revert TransferRestricted(reason);
            }

            address ownerAddress = LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId].ownerAddress;
            //check endorsement and update owners
            if (from == ownerAddress) {
                if (!LedgerEntryTokenStorage.cyberCertStorage().endorsementRequired) {
                    emit CertificateAssigned(
                        tokenId,
                        to,
                        "",
                        IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).companyName()
                    );
                    LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] = OwnerDetails("", to);
                } else if (LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                    Endorsement memory endorsement = LedgerEntryTokenStorage.cyberCertStorage()
                    .endorsements[tokenId][LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                    if (endorsement.endorsee == to) {
                        // Endorsement exists; ownership will be updated
                        emit CertificateAssigned(
                            tokenId,
                            to,
                            endorsement.endorseeName,
                            IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).companyName()
                        );
                        LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] =
                            OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
                    }
                }
                // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
            } else if (LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                // Token is not being transferred from the current owner. It can only be transferrred to the latest endorsee, or the current owner
                Endorsement memory endorsement = LedgerEntryTokenStorage.cyberCertStorage()
                .endorsements[tokenId][LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                if (endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();

                emit CertificateAssigned(
                    tokenId,
                    to,
                    endorsement.endorseeName,
                    IIssuanceManager(LedgerEntryTokenStorage.cyberCertStorage().issuanceManager).companyName()
                );
                LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId] =
                    OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
            } else {
                revert EndorsementNotSignedOrInvalid();
            }
        }
        // Emit custom transfer event for indexing
        emit CyberCertTransfer(from, to, tokenId);

        // Call the parent implementation to handle the actual transfer
        return super._update(to, tokenId, auth);
    }

    // Get full agreement details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.getCertificateDetails(tokenId);
    }

    function getActiveCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.getActiveCertificateDetails(tokenId);
    }

    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (Endorsement memory details) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        details = LedgerEntryTokenStorage.cyberCertStorage().endorsements[tokenId][index];
    }

    function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId].length;
    }

    function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().issuerSignatures[tokenId][index];
    }

    function voidCert(uint256 tokenId) external onlyIssuanceManager {
        LedgerEntryTokenStorage.setSecurityStatus(tokenId, SecurityStatus.Void);
        emit CertificateVoided(tokenId, block.timestamp);
    }

    function unvoidCert(uint256 tokenId) external onlyIssuanceManager {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        LedgerEntryTokenStorage.setSecurityStatus(tokenId, SecurityStatus.Assigned);
        emit CertificateUnvoided(tokenId, block.timestamp);
    }

    function isVoided(uint256 tokenId) external view returns (bool) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.getSecurityStatus(tokenId) == SecurityStatus.Void;
    }

    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        return LedgerEntryTokenStorage.tokenURI(tokenId);
    }

    /* // URI storage functionality
     function tokenURIJson(uint256 tokenId) public view virtual returns (string memory) {
         if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

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

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function endorsementRequired() public view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().endorsementRequired;
    }

    function addDefaultLegend(string memory newLegend) external onlyIssuanceManager {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        s.defaultLegend.push(newLegend);
    }

    function removeDefaultLegendAt(uint256 index) external onlyIssuanceManager {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
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
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert InvalidLegendIndex();

        return s.defaultLegend[index];
    }

    function getDefaultLegendCount() external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().defaultLegend.length;
    }

    function addCertLegend(uint256 tokenId, string memory newLegend) external onlyIssuanceManager {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        s.certLegend[tokenId].push(newLegend);
    }

    function removeCertLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManager {
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
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
        LedgerEntryTokenStorage.CyberCertStorage storage s = LedgerEntryTokenStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert InvalidLegendIndex();

        return s.certLegend[tokenId][index];
    }

    function getCertLegendCount(uint256 tokenId) external view returns (uint256) {
        return LedgerEntryTokenStorage.cyberCertStorage().certLegend[tokenId].length;
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

    function setTokenTransferable(uint256 tokenId, bool value) external onlyIssuanceManager {
        LedgerEntryTokenStorage.cyberCertStorage().tokenTransferable[tokenId] = value;
    }

    function isTokenTransferable(uint256 tokenId) external view returns (bool) {
        return LedgerEntryTokenStorage.cyberCertStorage().tokenTransferable[tokenId];
    }

    function legalOwnerOf(uint256 tokenId) external view returns (address) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        return LedgerEntryTokenStorage.cyberCertStorage().owners[tokenId].ownerAddress;
    }
}
