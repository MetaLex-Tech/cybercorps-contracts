
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Interface for transfer restriction hooks
interface ITransferRestrictionHook {
    function checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external view returns (bool allowed, string memory reason);
}

contract CyberCorpsCertificate is ERC721 {
    // Custom errors
    error NotIssuanceManager();
    error TokenNotTransferable();
    error TokenDoesNotExist();
    error URIQueryForNonexistentToken();
    error URISetForNonexistentToken();
    error ConversionNotImplemented();
    error TransferRestricted(string reason);
    
    address public issuanceManager;
    
    // Certificate details
    struct CertificateDetails {
        string issuerName;
        string investorName;
        string securityType;
        uint256 purchaseAmount;
        uint256 postMoneyValuationCap;
        string safeTextURI;
        bool transferable;
        string legend;
        
        // Additional legal details
        string governingJurisdiction;
        string contactDetails;
        string disputeResolutionMethod;
        
        // Signature and endorsement tracking
        string issuerSignatureURI;
        address[] endorsementSigners;
        string[] endorsementSignatureURIs;
        uint256[] endorsementTimestamps;
    }
    
    // Mapping from token ID to certificate details
    mapping(uint256 => CertificateDetails) public certificates;
    // Mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;
    // Mapping for custom restriction hooks by security type
    mapping(string => ITransferRestrictionHook) public restrictionHooks;
    // Global restriction hook (applies to all tokens)
    ITransferRestrictionHook public globalRestrictionHook;
    
    event CertificateCreated(uint256 indexed tokenId, string issuerName, string investorName);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI, uint256 timestamp);
    event RestrictionHookSet(string indexed securityType, address hookAddress);
    event GlobalRestrictionHookSet(address hookAddress);

    constructor() ERC721("CyberCorpsCertificate", "CCA") {
        issuanceManager = msg.sender; // Set by IM or deployer
    }

    // Called by proxy on deployment (if needed)
    function initialize() external {
        // Placeholder for initialization logic
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(string calldata securityType, address hookAddress) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        restrictionHooks[securityType] = ITransferRestrictionHook(hookAddress);
        emit RestrictionHookSet(securityType, hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    // Restricted minting with full certificate details
    function safeMint(
        address to, 
        uint256 tokenId,
        CertificateDetails memory details
    ) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _safeMint(to, tokenId);
        
        // Store certificate details
        certificates[tokenId] = details;
        
        emit CertificateCreated(tokenId, details.issuerName, details.investorName);
    }
    
    // Simplified mint for backward compatibility
    function safeMint(address to, uint256 tokenId) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _safeMint(to, tokenId);
    }

    // Add issuer signature to an certificate
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        certificates[tokenId].issuerSignatureURI = signatureURI;
    }
    
    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, address endorser, string calldata signatureURI) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        
        CertificateDetails storage details = certificates[tokenId];
        details.endorsementSigners.push(endorser);
        details.endorsementSignatureURIs.push(signatureURI);
        details.endorsementTimestamps.push(block.timestamp);
        
        emit CertificateEndorsed(tokenId, endorser, signatureURI, block.timestamp);
    }
    
    // Update certificate details (for admin purposes)
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        certificates[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _burn(tokenId);
        
        // Clear certificate details
        delete certificates[tokenId];
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
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
            if (!certificates[tokenId].transferable) revert TokenNotTransferable();
            
            // Check security type-specific hook if it exists
            string memory securityType = certificates[tokenId].securityType;
            ITransferRestrictionHook typeHook = restrictionHooks[securityType];
            
            if (address(typeHook) != address(0)) {
                (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }
            
            // Check global hook if it exists
            if (address(globalRestrictionHook) != address(0)) {
                (bool allowed, string memory reason) = globalRestrictionHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }
        }
        
        // Call the parent implementation to handle the actual transfer
        return super._update(to, tokenId, auth);
    }
    
    // Get full certificate details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return certificates[tokenId];
    }
    
    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId) external view returns (
        address[] memory signers,
        string[] memory signatureURIs,
        uint256[] memory timestamps
    ) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        CertificateDetails memory details = certificates[tokenId];
        
        return (
            details.endorsementSigners,
            details.endorsementSignatureURIs,
            details.endorsementTimestamps
        );
    }

    // Placeholder for SAFE/stock-specific logic (upgradable)
    function convert(uint256 tokenId) external virtual {
        revert ConversionNotImplemented();
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }
    
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        if (!_exists(tokenId)) revert URISetForNonexistentToken();
        _tokenURIs[tokenId] = _tokenURI;
    }
    
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
