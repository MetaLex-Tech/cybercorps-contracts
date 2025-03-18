pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/ITransferRestrictionHook.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/CyberCorpConstants.sol";

contract CyberCertPrinter is Initializable, ERC721EnumerableUpgradeable, UUPSUpgradeable {
    // Custom errors
    error NotIssuanceManager();
    error TokenNotTransferable();
    error TokenDoesNotExist();
    error InvalidTokenId();
    error URIQueryForNonexistentToken();
    error URISetForNonexistentToken();
    error ConversionNotImplemented();
    error TransferRestricted(string reason);
    
    address public issuanceManager;
    SecurityClass securityType; 
    SecuritySeries securitySeries; 
    string ledger;

    struct endorsement {
        address endorser;
        string signatureURI;
        uint256 timestamp;
    }

    // Mapping from token ID to agreement details
    mapping(uint256 => CertificateDetails) public agreements;
    mapping(uint256 => endorsement[]) public endorsements;

    // Mapping for custom restriction hooks by security type
    mapping(uint256 => ITransferRestrictionHook) public restrictionHooksById;
    // Global restriction hook (applies to all tokens)
    ITransferRestrictionHook public globalRestrictionHook;
    
    event CertCreated(uint256 indexed tokenId);
    event CertAssigned(uint256 indexed tokenId, string issuerName, string investorName);
    event AgreementEndorsed(uint256 indexed tokenId, address indexed endorser, string signatureURI, uint256 timestamp);
    event RestrictionHookSet(SecurityClass securityType, address hookAddress);
    event GlobalRestrictionHookSet(address hookAddress);

    modifier onlyIssuanceManager() {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
    }

    // Called by proxy on deployment (if needed)
    function initialize(string memory _ledger, string memory name, string memory ticker, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external initializer {
        __ERC721_init(name, ticker);
        __ERC721Enumerable_init_unchained();
        __UUPSUpgradeable_init();
        issuanceManager = _issuanceManager;
        ledger = _ledger;
        securityType = _securityType;
        securitySeries = _securitySeries;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        issuanceManager = _issuanceManager;
    }

    function updateLedger(string memory _ledger) external onlyIssuanceManager {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        ledger = _ledger;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManager {
        restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit RestrictionHookSet(securityType, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
        globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        agreements[tokenId] = details;
        _safeMint(to, tokenId);
        emit CertCreated(tokenId);
        return tokenId;
    }

    // Restricted minting with full agreement details
    function safeMintAndAssign(
        address to, 
        uint256 tokenId,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        _safeMint(to, tokenId);
        
        // Store agreement details
        agreements[tokenId] = details;
        string memory issuerName = IIssuanceManager(issuanceManager).companyName();
        emit CertCreated(tokenId);
        emit CertAssigned(tokenId, issuerName, details.investorName);
        return tokenId;
    }

    function assignCert(
        address from,
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        if(ownerOf(tokenId) != from) revert InvalidTokenId();
        agreements[tokenId] = details;
        string memory issuerName = IIssuanceManager(issuanceManager).companyName();
       // _transfer(from, to, tokenId);
        emit CertAssigned(tokenId, issuerName, details.investorName);
        return tokenId;
    }
    
    // Simplified mint for backward compatibility
    function safeMint(address to, uint256 tokenId) external onlyIssuanceManager {
        _safeMint(to, tokenId);
    }

    // Add issuer signature to an agreement
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external onlyIssuanceManager {
        agreements[tokenId].issuerSignatureURI = signatureURI;
    }
    
    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, address endorser, string calldata signatureURI) external {
        
        endorsement memory newEndorsement = endorsement(endorser, signatureURI, block.timestamp);
        endorsements[tokenId].push(newEndorsement);
        
        emit AgreementEndorsed(tokenId, endorser, signatureURI, block.timestamp);
    }
    
    // Update agreement details (for admin purposes)
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        agreements[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _burn(tokenId);
        
        // Clear agreement details
        delete agreements[tokenId];
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
            if (!agreements[tokenId].transferable) revert TokenNotTransferable();
            
            // Check security type-specific hook if it exists

            ITransferRestrictionHook typeHook = restrictionHooksById[tokenId];
            
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
    
    // Get full agreement details
    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return agreements[tokenId];
    }
    
    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        address endorser,
        string memory signatureURI,
        uint256 timestamp
    ) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        endorsement memory details = endorsements[tokenId][index];
        return (
            details.endorser,
            details.signatureURI,
            details.timestamp
        );
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        return super.tokenURI(tokenId);
    }
    
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
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
}
