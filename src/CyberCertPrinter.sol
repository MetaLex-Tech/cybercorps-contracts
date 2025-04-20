// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./CyberCorpConstants.sol";
import "./storage/CyberCertPrinterStorage.sol";
import "./interfaces/IUriBuilder.sol";
import "./interfaces/ICyberAgreementRegistry.sol";

contract CyberCertPrinter is Initializable, ERC721EnumerableUpgradeable, UUPSUpgradeable {
    using CyberCertPrinterStorage for CyberCertPrinterStorage.CyberCertStorage;

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

    //events
    event CertificateCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 cap);
    event Converted(uint256 indexed oldTokenId, uint256 indexed newTokenId);
    event CertificateSigned(uint256 indexed tokenId, string signatureURI);
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
    event CyberCertPrinter_CertificateCreated(uint256 indexed tokenId);
    event CyberCertTransfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event CertificateAssigned(uint256 indexed tokenId, address indexed newOwner, string newOwnerName, string issuerName);
    event CertificateVoided(uint256 indexed tokenId, uint256 timestamp);
    event RestrictionHookSet(uint256 indexed id, address indexed hookAddress);
    event GlobalRestrictionHookSet(address indexed hookAddress);
    event GlobalTransferableSet(bool indexed transferable);
    
    
    modifier onlyIssuanceManager() {
        if (msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
    }

    // Called by proxy on deployment (if needed)
    function initialize(string[] memory _defaultLegend, string memory name, string memory ticker, string memory _certificateUri, address _issuanceManager, SecurityClass _securityType, SecuritySeries _securitySeries) external initializer {
        __ERC721_init(name, ticker);
        __ERC721Enumerable_init_unchained();
        __UUPSUpgradeable_init();
        
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.issuanceManager = _issuanceManager;
        s.defaultLegend = _defaultLegend;
        s.securityType = _securityType;
        s.securitySeries = _securitySeries;
        s.certificateUri = _certificateUri;
    }

    function updateIssuanceManager(address _issuanceManager) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().issuanceManager = _issuanceManager;
    }

    // Set a restriction hook for a specific security type
    function setRestrictionHook(uint256 _id, address _hookAddress) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[_id] = ITransferRestrictionHook(_hookAddress);
        emit RestrictionHookSet(_id, _hookAddress);
    }
    
    // Set a global restriction hook that applies to all tokens
    function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook = ITransferRestrictionHook(hookAddress);
        emit GlobalRestrictionHookSet(hookAddress);
    }

    function setGlobalTransferable(bool _transferable) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().transferable = _transferable;
        emit GlobalTransferableSet(_transferable);
    }

    function safeMint(
        uint256 tokenId,
        address to,
        CertificateDetails memory details
    ) external onlyIssuanceManager returns (uint256) {
        CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId] = CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
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
        CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId] = CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
        _safeMint(to, tokenId);

        // Store agreement details
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName();
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
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
        string memory issuerName = IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName();
       // _transfer(from, to, tokenId);
        return tokenId;
    }
    
    // Simplified mint for backward compatibility
    function safeMint(address to, uint256 tokenId) external onlyIssuanceManager {
        _safeMint(to, tokenId);
    }

    // Add issuer signature to an agreement
    function addIssuerSignature(uint256 tokenId, string calldata signatureURI) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.certificateDetails[tokenId].issuerSignatureURI = signatureURI;
    }
    
    // Add endorsement (for transfers in secondary market)
    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        if(msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager && msg.sender != ownerOf(tokenId)) revert InvalidEndorsement();
        CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].push(newEndorsement);
        emit CertificateEndorsed(
            tokenId,
            newEndorsement.endorser,
            newEndorsement.endorsee,
            newEndorsement.endorseeName,
            newEndorsement.registry,
            newEndorsement.agreementId,
            CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1,
            block.timestamp
        );
    }

    function endorseAndTransfer(uint256 tokenId, Endorsement memory newEndorsement, address from, address to) external {
        addEndorsement(tokenId, newEndorsement);
        _transfer(from, to, tokenId);
    }
    
    // Update agreement details (for admin purposes)
    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external onlyIssuanceManager {
        CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId] = details;
    }

    // Restricted burning
    function burn(uint256 tokenId) external onlyIssuanceManager {
        _burn(tokenId);
        
        // Clear agreement details
        delete CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId];
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
            ITransferRestrictionHook typeHook = CyberCertPrinterStorage.cyberCertStorage().restrictionHooksById[tokenId];
            
            if (address(typeHook) != address(0)) {
                (bool allowed, string memory reason) = typeHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }
            
            // Check global hook if it exists
            if (address(CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook) != address(0)) {
                (bool allowed, string memory reason) = CyberCertPrinterStorage.cyberCertStorage().globalRestrictionHook.checkTransferRestriction(
                    from, to, tokenId, ""
                );
                if (!allowed) revert TransferRestricted(reason);
            }

            address ownerAddress = CyberCertPrinterStorage.cyberCertStorage().owners[tokenId].ownerAddress;
            //check endorsement and update owners
            if(from == ownerAddress) {
                if(CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                    Endorsement memory endorsement = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                    if (endorsement.endorsee == to) {
                        // Endorsement exists; ownership will be updated
                        emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName());
                        CyberCertPrinterStorage.cyberCertStorage().owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
                    } 
                } 
                // NOTE: we don't revert in this block: Owner is able to transfer to another address without an endorsement, but it does not update the owner
            }
            else if(CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length > 0) {
                // Token is not being transferred from the current owner. It can only be transferrred to the latest endorsee, or the current owner
                Endorsement memory endorsement = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId].length - 1];
                if(endorsement.endorsee != to && ownerAddress != to) revert EndorsementNotSignedOrInvalid();

                emit CertificateAssigned(tokenId, to, endorsement.endorseeName, IIssuanceManager(CyberCertPrinterStorage.cyberCertStorage().issuanceManager).companyName());
                CyberCertPrinterStorage.cyberCertStorage().owners[tokenId] = OwnerDetails(endorsement.endorseeName, endorsement.endorsee);
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
        return CyberCertPrinterStorage.cyberCertStorage().certificateDetails[tokenId];
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
        Endorsement memory details = CyberCertPrinterStorage.cyberCertStorage().endorsements[tokenId][index];
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
        CyberCertPrinterStorage.cyberCertStorage().securityStatus[tokenId] = SecurityStatus.Void;
        emit CertificateVoided(tokenId, block.timestamp);
    }
    
    // URI storage functionality
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        CertificateDetails memory details = s.certificateDetails[tokenId];
        OwnerDetails memory owner = s.owners[tokenId];
        string[] memory certLegend = s.certLegend[tokenId];
        ICyberCorp corp = ICyberCorp(IIssuanceManager(s.issuanceManager).CORP());

        // Convert storage endorsements to memory array for the builder
        Endorsement[] memory endorsementsArray = new Endorsement[](s.endorsements[tokenId].length);
        string[] memory globalFields;
        string[] memory globalValues;

        // If there are endorsements, get the global fields and values from the agreement registry
        if (s.endorsements[tokenId].length > 0) {
            Endorsement memory firstEndorsement = s.endorsements[tokenId][0];
            if (firstEndorsement.registry != address(0) && firstEndorsement.agreementId != bytes32(0)) {
                ICyberAgreementRegistry registry = ICyberAgreementRegistry(firstEndorsement.registry);
                (
                    ,  // bytes32 templateId
                    ,  // string memory legalContractUri
                    globalFields,  // string[] memory globalFields
                    ,  // string[] memory partyFields
                    globalValues,  // string[] memory globalValues
                    ,  // address[] memory parties
                    ,  // string[][] memory partyValues
                    ,  // uint256[] memory signedAt
                    ,  // uint256 numSignatures
                    ,  // bool isComplete
                ) = registry.getContractDetails(firstEndorsement.agreementId);
            } else {
                globalFields = new string[](0);
                globalValues = new string[](0);
            }
        }

        for (uint256 i = 0; i < s.endorsements[tokenId].length; i++) {
            endorsementsArray[i] = s.endorsements[tokenId][i];
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
            details,
            endorsementsArray,
            owner,
            globalFields,
            globalValues,
            tokenId,
            address(this)
        );
    }

    // Helper function to convert SecurityClass enum to string
    function _securityClassToString(SecurityClass _class) internal pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "SAFE";
        if (_class == SecurityClass.SAFT) return "SAFT";
        if (_class == SecurityClass.SAFTE) return "SAFTE";
        if (_class == SecurityClass.TokenPurchaseAgreement) return "TokenPurchaseAgreement";
        if (_class == SecurityClass.TokenWarrant) return "TokenWarrant";
        if (_class == SecurityClass.ConvertibleNote) return "ConvertibleNote";
        if (_class == SecurityClass.CommonStock) return "CommonStock";
        if (_class == SecurityClass.StockOption) return "StockOption";
        if (_class == SecurityClass.PreferredStock) return "PreferredStock";
        if (_class == SecurityClass.RestrictedStockPurchaseAgreement) return "RestrictedStockPurchaseAgreement";
        if (_class == SecurityClass.RestrictedStockUnit) return "RestrictedStockUnit";
        if (_class == SecurityClass.RestrictedTokenPurchaseAgreement) return "RestrictedTokenPurchaseAgreement";
        if (_class == SecurityClass.RestrictedTokenUnit) return "RestrictedTokenUnit";
        return "Unknown";
    }

    // Helper function to convert SecuritySeries enum to string
    function _securitySeriesToString(SecuritySeries _series) internal pure returns (string memory) {
        if (_series == SecuritySeries.SeriesPreSeed) return "SeriesPreSeed";
        if (_series == SecuritySeries.SeriesSeed) return "SeriesSeed";
        if (_series == SecuritySeries.SeriesA) return "SeriesA";
        if (_series == SecuritySeries.SeriesB) return "SeriesB";
        if (_series == SecuritySeries.SeriesC) return "SeriesC";
        if (_series == SecuritySeries.SeriesD) return "SeriesD";
        if (_series == SecuritySeries.SeriesE) return "SeriesE";
        if (_series == SecuritySeries.SeriesF) return "SeriesF";
        if (_series == SecuritySeries.NA) return "NA";
        return "Unknown";
    }

    // Helper function to convert string array to JSON array string with numbered legends
    function _arrayToJsonString(string[] memory arr) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < arr.length; i++) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, '{"id": ', _uint256ToString(i + 1), ', "legend": "', arr[i], '"}');
        }
        return string.concat(json, "]");
    }

    // Helper function to convert address to string
    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint160(_addr) >> (8 * (19 - i))));
            uint8 hi = uint8(b) >> 4;
            uint8 lo = uint8(b) & 0x0f;
            s[2*i] = bytes1(hi + (hi < 10 ? 48 : 87));
            s[2*i+1] = bytes1(lo + (lo < 10 ? 48 : 87));
        }
        return string(abi.encodePacked("0x", s));
    }

    // Helper function to convert uint256 to string
    function _uint256ToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // Helper function to convert bytes32 to string
    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(uint8(bytes1(bytes32(_bytes32) >> (8 * (31 - i)))));
            bytesArray[i*2] = bytes1(uint8(b/16 + (b/16 < 10 ? 48 : 87)));
            bytesArray[i*2+1] = bytes1(uint8(b%16 + (b%16 < 10 ? 48 : 87)));
        }
        return string(bytesArray);
    }

    // Public getters that directly access storage
    function defaultLegend() public view returns (string[] memory) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend;
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

    function addLegend(string memory newLegend) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.defaultLegend.push(newLegend);
    }

    function removeLegendAt(uint256 index) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert InvalidLegendIndex();

        // Move the last element to the index being removed (if it's not the last element)
        // and then pop the last element
        uint256 lastIndex = s.defaultLegend.length - 1;
        if (index != lastIndex) {
            s.defaultLegend[index] = s.defaultLegend[lastIndex];
        }
        s.defaultLegend.pop();
    }

    function getLegendAt(uint256 index) external view returns (string memory) {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.defaultLegend.length) revert InvalidLegendIndex();
        
        return s.defaultLegend[index];
    }

    function getLegendCount() external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().defaultLegend.length;
    }

    function addCertLegend(uint256 tokenId, string memory newLegend) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        s.certLegend[tokenId].push(newLegend);
    }

    function removeCertLegendAt(uint256 tokenId, uint256 index) external onlyIssuanceManager {
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
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
        CyberCertPrinterStorage.CyberCertStorage storage s = CyberCertPrinterStorage.cyberCertStorage();
        if (index >= s.certLegend[tokenId].length) revert InvalidLegendIndex();
        
        return s.certLegend[tokenId][index];
    }   

    function getCertLegendCount(uint256 tokenId) external view returns (uint256) {
        return CyberCertPrinterStorage.cyberCertStorage().certLegend[tokenId].length;
    }
    
}
