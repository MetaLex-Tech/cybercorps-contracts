// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

import "../CyberCorpConstants.sol";
import "../interfaces/ITransferRestrictionHook.sol";
import "../interfaces/IIssuanceManager.sol";

struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmount;
    uint256 issuerUSDValuationAtTimeofInvestment;
    uint256 unitsRepresented;
    string legalDetails;
    string issuerSignatureURI;
}

struct Endorsement {
    address endorser;
    uint256 timestamp;
    bytes signatureHash;
    address registry;  //optional
    bytes32 agreementId; //optional
    address endorsee;
    string endorseeName;
}

struct OwnerDetails {
    string name;
    address ownerAddress;
}

library CyberCertPrinterStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.cert.printer.storage.v1");

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
        
        // Contract configuration - making these public
        address issuanceManager;
        SecurityClass securityType;
        SecuritySeries securitySeries;
        string certificateUri;
        string[] defaultLegend;
        bool transferable;
    }

    // Returns the storage layout
    function cyberCertStorage() internal pure returns (CyberCertStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // Internal getters for complex types
    function getCertificateDetails(uint256 tokenId) internal view returns (CertificateDetails storage) {
        return cyberCertStorage().certificateDetails[tokenId];
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

    function setSecurityType(SecurityClass _securityType) internal {
        cyberCertStorage().securityType = _securityType;
    }

    function setSecuritySeries(SecuritySeries _securitySeries) internal {
        cyberCertStorage().securitySeries = _securitySeries;
    }

    function setCertificateUri(string memory _certificateUri) internal {
        cyberCertStorage().certificateUri = _certificateUri;
    }

    function setTransferable(bool _transferable) internal {
        cyberCertStorage().transferable = _transferable;
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
} 