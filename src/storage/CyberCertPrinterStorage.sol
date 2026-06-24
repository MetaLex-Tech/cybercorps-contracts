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
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictiveLegend,
    RestrictionType
} from "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICyberCorp.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/IUriBuilder.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import "./extensions/ICertificateExtension.sol";

library CyberCertPrinterStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.cert.printer.storage.v1");

    // Mirrors of the printer's error/event signatures; identical selectors/topics,
    // so reverts and logs surface exactly as if they came from the printer (delegatecall).
    error TokenNotTransferable();
    error TransferRestricted(string reason);
    error EndorsementNotSignedOrInvalid();
    error InvalidLegendIndex();
    error ExceedsAvailableUnits();
    error ExceedsReservedUnits();

    event CertificateAssigned(uint256 indexed tokenId, address indexed newOwner, string newOwnerName, string issuerName);
    event CyberCertPrinter_CertificateCreated(uint256 indexed tokenId);
    event UnitsReservedUpdated(uint256 indexed tokenId, uint256 unitsReserved);
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

    // Main storage layout struct
    struct CyberCertStorage {
        // Token data
        mapping(uint256 => CertificateDetails) certificateDetails;
        mapping(uint256 => Endorsement[]) endorsements;
        mapping(uint256 => OwnerDetails) owners;
        mapping(uint256 => SecurityStatus) securityStatus;
        mapping(uint256 => string[]) certLegend;
        // Restriction hooks
        mapping(uint256 => ITransferRestrictionHook) restrictionHooksById;
        ITransferRestrictionHook globalRestrictionHook;
        address extension;
        // Contract configuration - making these public
        address issuanceManager;
        SecurityClass securityType;
        SecuritySeries securitySeries;
        string certificateUri;
        string[] defaultLegend;
        bool transferable;
        bool endorsementRequired;
        // New variables must be appended below to preserve storage layout for upgrades
        mapping(uint256 => bool) tokenTransferable;
        mapping(uint256 => bytes[]) issuerSignatures;
        // Units locked in a pending deal/loan; always <= certificateDetails[tokenId].unitsRepresented
        mapping(uint256 => uint256) unitsReserved;
        mapping(uint256 => RestrictiveLegend[]) certLegendsV2;
        RestrictiveLegend[] defaultLegendsV2;
        mapping(address => uint256) holderTokenCount;
        uint256 uniqueHolderCount;
        
    }

    // Returns the storage layout
    function cyberCertStorage() internal pure returns (CyberCertStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    // URI storage functionality
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = cyberCertStorage();
        RestrictiveLegend[] memory certLegend = getEffectiveRestrictiveLegends(tokenId);
        ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());
        CertificateDetails memory effectiveDetails = getCertificateDetails(
            tokenId
        );

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
            effectiveDetails,
            s.endorsements[tokenId],
            s.owners[tokenId],
            registry,
            agreementId,
            tokenId,
            address(this),
            address(s.extension)
        );
    }

    /// @dev Transfer-time restriction and endorsement logic, extracted from
    /// CyberCertPrinter._update to reduce the printer's bytecode size.
    /// External so it runs via delegatecall against this deployed library.
    /// Only called for true transfers (from != 0 && to != 0).
    function processTransfer(address from, address to, uint256 tokenId) external {
        CyberCertStorage storage s = cyberCertStorage();

        // Check built-in transferability flag and per-token override
        if (!s.transferable && !s.tokenTransferable[tokenId]) {
            ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());
            if (from != corp.dealManager() && from != corp.roundManager()) revert TokenNotTransferable();
        }

        // Check global hook if it exists
        if (address(s.globalRestrictionHook) != address(0)) {
            (bool allowed, string memory reason) = s.globalRestrictionHook.checkTransferRestriction(
                from, to, tokenId, ""
            );
            if (!allowed) revert TransferRestricted(reason);
        }

        ITransferRestrictionHook typeHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
            
        if (address(typeHook) != address(0)) {
            (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                from, to, tokenId, ""
            );
            if (!allowed) revert TransferRestricted(reason);
        }

        address ownerAddress = s.owners[tokenId].ownerAddress;
        uint256 endorsementCount = s.endorsements[tokenId].length;
        //check endorsement and update owners
        if (from == ownerAddress) {
            if (!s.endorsementRequired) {
                emit CertificateAssigned(tokenId, to, "", IIssuanceManager(s.issuanceManager).companyName());
                s.owners[tokenId] = OwnerDetails("", to);
            }
            else if (endorsementCount > 0) {
                Endorsement memory endorsement = s.endorsements[tokenId][endorsementCount - 1];
                if (endorsement.endorsee == to) {
                    // Endorsement exists; ownership will be updated
                    emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(s.issuanceManager).companyName());
                    s.owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
                }
            }
        // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
        }
        else if (endorsementCount > 0) {
            // Token is not being transferred from the current owner. It can only be transferrred to the latest endorsee, or the current owner
            Endorsement memory endorsement = s.endorsements[tokenId][endorsementCount - 1];
            if (endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();

            emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(s.issuanceManager).companyName());
            s.owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
        }
        else revert EndorsementNotSignedOrInvalid();
    }

    /// @dev Post-mint bookkeeping for CyberCertPrinter.safeMint (the _safeMint itself stays in the printer).
    function recordMint(uint256 tokenId, address to, CertificateDetails memory details) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certLegend[tokenId] = s.defaultLegend;
        copyDefaultRestrictiveLegendsToCert(s, tokenId);
        s.certificateDetails[tokenId] = details;
        s.owners[tokenId] = OwnerDetails("", to);
        emit CyberCertPrinter_CertificateCreated(tokenId);
    }

    /// @dev Post-mint bookkeeping for CyberCertPrinter.safeMintAndAssign.
    function recordMintAndAssign(
        uint256 tokenId,
        address to,
        CertificateDetails memory details,
        string memory investorName
    ) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certLegend[tokenId] = s.defaultLegend;
        copyDefaultRestrictiveLegendsToCert(s, tokenId);
        s.certificateDetails[tokenId] = details;
        s.owners[tokenId] = OwnerDetails(investorName, to);
        emit CertificateAssigned(tokenId, to, investorName, IIssuanceManager(s.issuanceManager).companyName());
        emit CyberCertPrinter_CertificateCreated(tokenId);
    }

    /// @dev Bookkeeping for CyberCertPrinter.assignCert (the ownerOf check stays in the printer).
    function recordAssign(uint256 tokenId, address to, CertificateDetails memory details) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.certificateDetails[tokenId] = details;
        s.owners[tokenId] = OwnerDetails("", to);
        emit CertificateAssigned(tokenId, to, "", IIssuanceManager(s.issuanceManager).companyName());
    }

    /// @dev Endorsement push + event for CyberCertPrinter.addEndorsement (the auth check stays in the printer).
    function recordEndorsement(uint256 tokenId, Endorsement memory newEndorsement) external {
        CyberCertStorage storage s = cyberCertStorage();
        s.endorsements[tokenId].push(newEndorsement);
        emit CertificateEndorsed(
            tokenId,
            newEndorsement.endorser,
            newEndorsement.endorsee,
            newEndorsement.endorseeName,
            newEndorsement.registry,
            newEndorsement.agreementId,
            s.endorsements[tokenId].length - 1,
            block.timestamp
        );
    }

    /// @dev Reserve units against a pending deal/loan. Reverts if the total reserved
    /// would exceed the certificate's units.
    function increaseUnitsReserved(uint256 tokenId, uint256 amount) external {
        CyberCertStorage storage s = cyberCertStorage();
        uint256 newReserved = s.unitsReserved[tokenId] + amount;
        if (newReserved > s.certificateDetails[tokenId].unitsRepresented) revert ExceedsAvailableUnits();
        s.unitsReserved[tokenId] = newReserved;
        emit UnitsReservedUpdated(tokenId, newReserved);
    }

    /// @dev Release previously reserved units. Reverts if releasing more than is reserved.
    function decreaseUnitsReserved(uint256 tokenId, uint256 amount) external {
        CyberCertStorage storage s = cyberCertStorage();
        uint256 reserved = s.unitsReserved[tokenId];
        if (amount > reserved) revert ExceedsReservedUnits();
        uint256 newReserved;
        unchecked { newReserved = reserved - amount; }
        s.unitsReserved[tokenId] = newReserved;
        emit UnitsReservedUpdated(tokenId, newReserved);
    }

    function getUnitsReserved(uint256 tokenId) internal view returns (uint256) {
        return cyberCertStorage().unitsReserved[tokenId];
    }

    function recordHolderChange(address from, address to) internal {
        CyberCertStorage storage s = cyberCertStorage();

        if (from == to) return;

        if (from != address(0)) {
            uint256 fromBalance = s.holderTokenCount[from] - 1;
            s.holderTokenCount[from] = fromBalance;
            if (fromBalance == 0) {
                s.uniqueHolderCount--;
            }
        }

        if (to != address(0)) {
            uint256 toBalance = s.holderTokenCount[to];
            if (toBalance == 0) {
                s.uniqueHolderCount++;
            }
            s.holderTokenCount[to] = toBalance + 1;
        }
    }

    function getHolderCount() internal view returns (uint256) {
        return cyberCertStorage().uniqueHolderCount;
    }

    // Legend management; isDefault selects the defaultLegend array (tokenId ignored) vs a cert's legend
    function _legendArray(uint256 tokenId, bool isDefault) private view returns (string[] storage) {
        CyberCertStorage storage s = cyberCertStorage();
        if (isDefault) return s.defaultLegend;
        return s.certLegend[tokenId];
    }

    function addLegend(uint256 tokenId, bool isDefault, string memory newLegend) external {
        _legendArray(tokenId, isDefault).push(newLegend);
    }

    function removeLegendAt(uint256 tokenId, bool isDefault, uint256 index) external {
        string[] storage arr = _legendArray(tokenId, isDefault);
        uint256 len = arr.length;
        if (index >= len) revert InvalidLegendIndex();

        // Move the last element to the index being removed (if it's not the last element)
        // and then pop the last element
        uint256 lastIndex = len - 1;
        if (index != lastIndex) {
            string memory lastLegend = arr[lastIndex];
            arr[index] = lastLegend;
        }
        arr.pop();
    }

    function _restrictiveLegendArray(uint256 tokenId, bool isDefault) private view returns (RestrictiveLegend[] storage) {
        CyberCertStorage storage s = cyberCertStorage();
        if (isDefault) return s.defaultLegendsV2;
        return s.certLegendsV2[tokenId];
    }

    function copyDefaultRestrictiveLegendsToCert(CyberCertStorage storage s, uint256 tokenId) private {
        delete s.certLegendsV2[tokenId];
        RestrictiveLegend[] storage certLegends = s.certLegendsV2[tokenId];
        for (uint256 i = 0; i < s.defaultLegendsV2.length; i++) {
            RestrictiveLegend memory legend = s.defaultLegendsV2[i];
            certLegends.push(legend);
        }
    }

    function addRestrictiveLegend(uint256 tokenId, bool isDefault, RestrictiveLegend memory newLegend) external {
        _restrictiveLegendArray(tokenId, isDefault).push(newLegend);
    }

    function removeRestrictiveLegendAt(uint256 tokenId, bool isDefault, uint256 index) external {
        RestrictiveLegend[] storage arr = _restrictiveLegendArray(tokenId, isDefault);
        uint256 len = arr.length;
        if (index >= len) revert InvalidLegendIndex();

        uint256 lastIndex = len - 1;
        if (index != lastIndex) {
            arr[index] = arr[lastIndex];
        }
        arr.pop();
    }

    function getEffectiveRestrictiveLegends(uint256 tokenId) internal view returns (RestrictiveLegend[] memory legends) {
        CyberCertStorage storage s = cyberCertStorage();
        if (s.certLegendsV2[tokenId].length > 0) {
            RestrictiveLegend[] storage storedLegends = s.certLegendsV2[tokenId];
            legends = new RestrictiveLegend[](storedLegends.length);
            for (uint256 i = 0; i < storedLegends.length; i++) {
                legends[i] = storedLegends[i];
            }
        } else {
            string[] storage legacyLegends = s.certLegend[tokenId];
            legends = new RestrictiveLegend[](legacyLegends.length);
            for (uint256 i = 0; i < legacyLegends.length; i++) {
                legends[i] = RestrictiveLegend({
                    restrictionType: RestrictionType.Custom,
                    title: "",
                    text: legacyLegends[i],
                    jurisdiction: "",
                    referenceId: bytes32(0),
                    effectiveTimestamp: 0,
                    expirationTimestamp: 0,
                    active: true,
                    data: ""
                });
            }
        }
    }

    // Internal getters for complex types
    function getStoredCertificateDetails(uint256 tokenId) internal view returns (CertificateDetails storage) {
        return cyberCertStorage().certificateDetails[tokenId];
    }

    function getActiveCertificateDetails(
        uint256 tokenId
    ) internal view returns (CertificateDetails memory details) {
        details = cyberCertStorage().certificateDetails[tokenId];
    }

    function getCertificateDetails(
        uint256 tokenId
    ) internal view returns (CertificateDetails memory details) {
        CyberCertStorage storage s = cyberCertStorage();
        details = getActiveCertificateDetails(tokenId);

        (
            bool isScripified,
            uint256 scripifiedUnits,
            uint256 _maxUnitsRepresented
        ) = IIssuanceManager(s.issuanceManager).getCertScripifiedStatus(
                address(this),
                tokenId
            );

        if (isScripified) {
            details.unitsRepresented = details.unitsRepresented + scripifiedUnits;
        }
    }

    function getEndorsements(uint256 tokenId) internal view returns (Endorsement[] storage) {
        return cyberCertStorage().endorsements[tokenId];
    }

    function getOwnerDetails(uint256 tokenId) internal view returns (OwnerDetails storage) {
        return cyberCertStorage().owners[tokenId];
    }

    function getSecurityStatus(uint256 tokenId) internal view returns (SecurityStatus) {
        return cyberCertStorage().securityStatus[tokenId];
    }

    // Setters
    function setCertificateDetails(uint256 tokenId, CertificateDetails memory details) internal {
        cyberCertStorage().certificateDetails[tokenId] = details;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory endorsement) internal {
        cyberCertStorage().endorsements[tokenId].push(endorsement);
    }

    function setOwnerDetails(uint256 tokenId, OwnerDetails memory details) internal {
        cyberCertStorage().owners[tokenId] = details;
    }

    function setSecurityStatus(uint256 tokenId, SecurityStatus status) internal {
        cyberCertStorage().securityStatus[tokenId] = status;
    }

    // Configuration setters
    function setIssuanceManager(address _issuanceManager) internal {
        cyberCertStorage().issuanceManager = _issuanceManager;
    }

    function setCertificateUri(string memory _certificateUri) internal {
        cyberCertStorage().certificateUri = _certificateUri;
    }

    function setTransferable(bool _transferable) internal {
        cyberCertStorage().transferable = _transferable;
    }

    function setTokenTransferable(uint256 tokenId, bool value) internal {
        cyberCertStorage().tokenTransferable[tokenId] = value;
    }

    function isTokenTransferable(uint256 tokenId) internal view returns (bool) {
        return cyberCertStorage().tokenTransferable[tokenId];
    }

    function setRestrictionHook(uint256 tokenId, ITransferRestrictionHook hook) internal {
        cyberCertStorage().restrictionHooksById[tokenId] = hook;
    }

    function setGlobalRestrictionHook(ITransferRestrictionHook hook) internal {
        cyberCertStorage().globalRestrictionHook = hook;
    }

    // Update the getter/setter for defaultLegend
    function getDefaultLegend() internal view returns (string[] memory) {
        return cyberCertStorage().defaultLegend;
    }

    function setDefaultLegend(string[] memory _defaultLegend) internal {
        cyberCertStorage().defaultLegend = _defaultLegend;
    }

    // Extension management
    function setExtension(uint256 tokenId, address extension) internal {
        cyberCertStorage().extension = extension;
    }

    function getExtension(uint256 tokenId) internal view returns (address) {
        return cyberCertStorage().extension;
    }

    function _getExtensionData(uint256 tokenId) internal view returns (bytes memory) {
        return cyberCertStorage().certificateDetails[tokenId].extensionData;
    }

} 