pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./CyberCorpConstants.sol";
import {Endorsement} from "./interfaces/ICyberCertPrinter.sol";

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
    error EndorsementNotSignedOrInvalid();
    error InvalidEndorsement();
    
    address public issuanceManager;
    SecurityClass securityType; 
    SecuritySeries securitySeries; 
    string public certificateUri;
    string public ledger;
    bool transferable;

    // Mapping from token ID to agreement details
    mapping(uint256 => CertificateDetails) public certificateDetails;
    mapping(uint256 => Endorsement[]) public endorsements;
    mapping(uint256 => OwnerDetails) public owners;
    mapping(uint256 => SecurityStatus) public securityStatus;

    // Mapping for custom restriction hooks by security type
    mapping(uint256 => ITransferRestrictionHook) public restrictionHooksById;
    // Global restriction hook (applies to all tokens)
    ITransferRestrictionHook public globalRestrictionHook;
    
    event CyberCertPrinter_CertificateCreated(uint256 indexed tokenId);
    event CertificateAssigned(uint256 indexed tokenId, address indexed investorAddress, string investorName, string issuerName);
    event CertificateVoided(uint256 indexed tokenId, uint256 timestamp);
    event CertificateEndorsed(uint256 indexed tokenId, address indexed endorser, address endorsee, string endorseeName, address registry, bytes32 agreementId, uint256 index, uint256 timestamp);
    event RestrictionHookSet(uint256 indexed tokenId, address hookAddress);
    event GlobalTransferableSet(bool transferable);
    event GlobalRestrictionHookSet(address hookAddress);
    event CyberCertTransfer(address indexed from, address indexed to, uint256 indexed tokenId);

    modifier onlyIssuanceManager() {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
    }

    // Called by proxy on deployment (if needed)
    function initialize(string memory _ledger, string memory name, string memory ticker, string memory _certificateUri, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external initializer {
        __ERC721_init(name, ticker);
        __ERC721Enumerable_init_unchained();
        __UUPSUpgradeable_init();
        issuanceManager = _issuanceManager;
        ledger = _ledger;
        securityType = _securityType;
        securitySeries = _securitySeries;
        certificateUri = _certificateUri;
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
        emit RestrictionHookSet(_id, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
        globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManager {
        transferable = _transferable;
        emit GlobalTransferableSet(transferable);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        certificateDetails[tokenId] = details;
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
        _safeMint(to, tokenId);
        
        // Store agreement details
        certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(issuanceManager).companyName();
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
        certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(issuanceManager).companyName();
       // _transfer(from, to, tokenId);
        return tokenId;
    }
    
    // Simplified mint for backward compatibility
    function safeMint(address to, uint256 tokenId) external onlyIssuanceManager {
        _safeMint(to, tokenId);
    }

    // Add issuer signature to an agreement
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external onlyIssuanceManager {
        certificateDetails[tokenId].issuerSignatureURI = signatureURI;
    }
    
    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if(msg.sender != issuanceManager && msg.sender != ownerOf(tokenId)) revert InvalidEndorsement();
        endorsements[tokenId].push(newEndorsement);
        emit CertificateEndorsed(tokenId, newEndorsement.endorser, newEndorsement.endorsee, newEndorsement.endorseeName, newEndorsement.registry, newEndorsement.agreementId, endorsements[tokenId].length - 1, block.timestamp);
    }

    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        _transfer(from, to, tokenId);
    }
    
    // Update agreement details (for admin purposes)
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        certificateDetails[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external {
        if (msg.sender != issuanceManager) revert NotIssuanceManager();
        _burn(tokenId);
        
        // Clear agreement details
        delete certificateDetails[tokenId];
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
           // if (!certificateDetails[tokenId].transferable) revert TokenNotTransferable();
            
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

            address ownerAddress = owners[tokenId].ownerAddress;
            //check endorsement and update owners
            if(from == ownerAddress) {
                if(endorsements[tokenId].length > 0) {
                    Endorsement memory endorsement = endorsements[tokenId][endorsements[tokenId].length - 1];
                    if (endorsement.endorsee == to) {
                        // Endorsement exists; ownership will be updated
                        emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(issuanceManager).companyName());
                        owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
                    } 
                } 
                // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
            }
            else if(endorsements[tokenId].length > 0) {
                // Token is not being transferred from the current owner. It can only be transferrred to the latest endorsee, or the current owner
                Endorsement memory endorsement = endorsements[tokenId][endorsements[tokenId].length - 1];
                if(endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();

                emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(issuanceManager).companyName());
                owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
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
        return certificateDetails[tokenId];
    }
    
    // Get endorsement history
    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (
        address endorser,
        string memory endorseeName,
        address registry,
        bytes32 agreementId,
        uint256 timestamp,
        bytes memory signatureHash,
        address endorsee
    ) {
        if (ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        Endorsement memory details = endorsements[tokenId][index];
        return (
            details.endorser,
            details.endorseeName,
            details.registry,
            details.agreementId,
            details.timestamp,
            details.signatureHash,
            details.endorsee
        );
    }

    function voidCert(uint256 tokenId) external onlyIssuanceManager {
        securityStatus[tokenId] = SecurityStatus.Void;
        emit CertificateVoided(tokenId, block.timestamp);
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
