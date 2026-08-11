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

import "./libs/auth.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./storage/extensions/ICyberCorpExtension.sol";

/// @title CyberCorp
/// @notice Main contract representing a corporation's on-chain presence and management
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract CyberCorp is Initializable, BorgAuthACL, UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "5"; // For version-tracking on all deployment and future upgrades

    // cyberCORP details
    /// @notice Legal name of the entity, including designation (e.g., "Inc." or "LLC")
    string public cyberCORPName;
    /// @notice Legal entity type (e.g., "corporation" or "limited liability company")
    string public cyberCORPType;
    /// @notice Jurisdiction of incorporation (e.g., "Delaware")
    string public cyberCORPJurisdiction;
    /// @notice Contact information for the corporation
    string public cyberCORPContactDetails;
    /// @notice Default dispute resolution mechanism for agreements
    string public defaultDisputeResolution;
    /// @notice Address that can receive payments on behalf of the company
    address public companyPayable;
    /// @notice Address of the issuance manager contract
    address public issuanceManager;
    /// @notice Address of the deal manager contract
    address public dealManager;
    /// @notice Implementation address for the LedgerEntryToken contract
    address public cyberCertPrinterImplementation;

    address public upgradeFactory;
    /// @notice Array of company officers with their roles and details
    CompanyOfficer[] public companyOfficers;

    /// @notice Address of the round manager contract
    address public roundManager;
    /// @notice Escrowed officer signatures that can be applied to certificates
    bytes[] public escrowedOfficerSignatures;
    /// @notice Extension contract that interprets `extensionData`
    address public extension;
    /// @notice Type selector for the active extension schema
    bytes32 public extensionType;
    /// @notice Raw extension payload interpreted by the active extension contract
    bytes public extensionData;
    /// @notice Board state is appended after the extension fields for proxy
    /// storage compatibility (extension fields are the released layout).
    CompanyDirector[] public companyDirectors;
    mapping(address => bool) public boardMembers;
    mapping(address => bool) public officerMembers;
    bool public boardGovernanceEnforced;

    event CyberCORPDetailsUpdated(string cyberCORPName, string cyberCORPType, string cyberCORPJurisdiction, string cyberCORPContactDetails, string defaultDisputeResolution);
    event OfficerAdded(address indexed officer, uint256 index);
    event OfficerRemoved(address indexed officer, uint256 index);
    event CompanyPayableUpdated(address indexed companyPayable, address indexed oldCompanyPayable);
    event EscrowedOfficerSignatureAdded(uint256 indexed index, address indexed officer);
    event EscrowedOfficerSignatureUpdated(uint256 indexed index, address indexed officer);
    event CyberCORPExtensionSet(address indexed extension, bytes32 indexed extensionType);
    event CyberCORPExtensionDataUpdated(bytes32 indexed extensionType, bytes extensionData);
    event DirectorAdded(address indexed director, uint256 index);
    event DirectorRemoved(address indexed director, uint256 index);
    event BoardGovernanceActivated(address indexed initialDirector);
    event BoardAuthorityAdapterUpdated(address indexed adapter);

    error NotRefImplementation();
    error SignatureRequired();
    error InvalidEscrowSignatureIndex();
    error InvalidExtension();
    error ExtensionTypeNotSupported();
    error ExtensionNotConfigured();
    error BoardGovernanceNotEnforced();
    error BoardGovernanceAlreadyEnforced();
    error RoleManagerNotCyberCorp();
    error InvalidOfficer();
    error InvalidDirector();
    error DuplicateOfficer();
    error DuplicateDirector();
    error LastOfficer();
    error LastDirector();

    /// @dev Modifier bodies are inlined at every use site; sharing one private function keeps
    /// this contract under the EIP-170 runtime size limit (same pattern as IssuanceManager).
    function _requireBoardAuthority() private view {
        if (boardGovernanceEnforced) {
            AUTH.onlyRole(AUTH.BOARD_ROLE(), msg.sender);
        } else {
            // Explicit legacy compatibility. This is not described as Board
            // enforcement by the app or plans.
            AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        }
    }

    function _requireEnforcedBoard() private view {
        if (!boardGovernanceEnforced) {
            revert BoardGovernanceNotEnforced();
        }
        AUTH.onlyRole(AUTH.BOARD_ROLE(), msg.sender);
    }

    modifier onlyBoardAuthority() {
        _requireBoardAuthority();
        _;
    }

    modifier onlyEnforcedBoard() {
        _requireEnforcedBoard();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the CyberCorp contract with essential details
    /// @param _auth Address of the BorgAuth ACL contract
    /// @param _cyberCORPName Legal name of the entity
    /// @param _cyberCORPType Legal type of the entity
    /// @param _cyberCORPJurisdiction Jurisdiction of incorporation
    /// @param _cyberCORPContactDetails Contact information
    /// @param _defaultDisputeResolution Default dispute resolution mechanism
    /// @param _issuanceManager Address of the issuance manager
    /// @param _companyPayable Address for receiving payments
    /// @param _officer Initial company officer details
    function initialize(
        address _auth,
        string memory _cyberCORPName,
        string memory _cyberCORPType,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution,
        address _issuanceManager,
        address _companyPayable,
        CompanyOfficer memory _officer,
        address _upgradeFactory,
        address _roundManager
    ) public initializer {
        __BorgAuthACL_init(_auth);

        cyberCORPName = _cyberCORPName;
        cyberCORPType = _cyberCORPType;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        issuanceManager = _issuanceManager;
        companyPayable = _companyPayable;
        companyOfficers.push(_officer);
        officerMembers[_officer.eoa] = true;
        companyDirectors.push(
            CompanyDirector({
                eoa: _officer.eoa,
                name: _officer.name,
                contact: _officer.contact
            })
        );
        boardMembers[_officer.eoa] = true;
        upgradeFactory = _upgradeFactory;
        roundManager = _roundManager;
    }

    /// @notice Finalizes the one-way BorgAuth role-manager handoff for a newly
    ///         deployed corp and promotes the founder to the Board role.
    /// @dev Permissionless to call because it can only succeed after BorgAuth
    ///      has irrevocably selected this CyberCorp as its role manager.
    function activateBoardGovernance() external {
        if (boardGovernanceEnforced) {
            revert BoardGovernanceAlreadyEnforced();
        }
        if (AUTH.roleManager() != address(this)) {
            revert RoleManagerNotCyberCorp();
        }
        if (companyDirectors.length == 0) revert LastDirector();

        address initialDirector = companyDirectors[0].eoa;
        AUTH.updateRole(initialDirector, AUTH.BOARD_ROLE());
        boardGovernanceEnforced = true;
        emit BoardGovernanceActivated(initialDirector);
    }

    /// @notice Updates the corporation's basic details
    /// @dev Only callable by owner
    /// @param _cyberCORPName New legal name
    /// @param _cyberCORPType New entity type
    /// @param _cyberCORPJurisdiction New jurisdiction
    /// @param _cyberCORPContactDetails New contact details
    /// @param _defaultDisputeResolution New dispute resolution mechanism
    function setcyberCORPDetails(
        string memory _cyberCORPName,
        string memory _cyberCORPType,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution
    ) external onlyBoardAuthority {
        cyberCORPName = _cyberCORPName;
        cyberCORPType = _cyberCORPType;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;

        emit CyberCORPDetailsUpdated(cyberCORPName, cyberCORPType, cyberCORPJurisdiction, cyberCORPContactDetails, defaultDisputeResolution);
    }

    /// @notice Updates the issuance manager address
    /// @dev Only callable by owner
    /// @param _issuanceManager New issuance manager contract address
    function setIssuanceManager(
        address _issuanceManager
    ) external onlyBoardAuthority {
        address previous = issuanceManager;
        issuanceManager = _issuanceManager;
        _rotateManagerRole(previous, _issuanceManager);
    }

    /// @notice Updates the deal manager address
    /// @dev Only callable by owner
    /// @param _dealManager New deal manager contract address
    function setDealManager(address _dealManager) external onlyBoardAuthority {
        address previous = dealManager;
        dealManager = _dealManager;
        _rotateManagerRole(previous, _dealManager);
    }

    /// @notice Updates the round manager address
    /// @dev Only callable by owner
    /// @param _roundManager New round manager contract address
    function setRoundManager(
        address _roundManager
    ) external onlyBoardAuthority {
        address previous = roundManager;
        roundManager = _roundManager;
        _rotateManagerRole(previous, _roundManager);
    }

    /// @dev On a corp that is BorgAuth's role manager, swapping a manager pointer must rotate
    ///      the AUTH role with it: the factory granted the original managers OWNER_ROLE and then
    ///      irreversibly locked role mutation to this corp, so without rotation a replacement
    ///      manager cannot make owner-gated cross-manager calls while the superseded one stays
    ///      privileged forever. Runs after the pointer update so the still-referenced check sees
    ///      the new state — an address that still serves as another manager keeps its role
    ///      (tests and early corps have pointed two slots at one contract). Legacy corps without
    ///      the role-manager lock keep their historical behavior: BorgAuth's owner rotates roles
    ///      directly.
    function _rotateManagerRole(address previousManager, address newManager) private {
        if (AUTH.roleManager() != address(this)) return;
        if (previousManager == newManager) return;
        if (
            previousManager != address(0) && previousManager != issuanceManager
                && previousManager != dealManager && previousManager != roundManager
        ) {
            // Restore the roster-derived role rather than zeroing: a superseded manager address
            // that also holds a director or officer seat keeps that seat's authority.
            AUTH.updateRole(
                previousManager,
                boardMembers[previousManager]
                    ? AUTH.BOARD_ROLE()
                    : officerMembers[previousManager] ? AUTH.OFFICER_ROLE() : 0
            );
        }
        // Grant only when the address does not already satisfy the owner threshold. BorgAuth
        // stores a single role per user and officers (200) / directors (300) already clear the
        // numeric owner gate (99), so overwriting would demote a roster seat — a sole director
        // pointing a manager slot at themselves must not lose Board authority.
        if (newManager != address(0) && AUTH.userRoles(newManager) < AUTH.OWNER_ROLE()) {
            AUTH.updateRole(newManager, AUTH.OWNER_ROLE());
        }
    }

    /// @notice Checks if an address belongs to a company officer
    /// @param _address Address to check
    /// @return bool True if the address belongs to an officer
    function isCyberCORPOfficer(address _address) external view returns (bool) {
        if (!boardGovernanceEnforced) {
            return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
        }
        return officerMembers[_address];
    }

    function isCyberCORPDirector(address account) external view returns (bool) {
        return boardMembers[account];
    }

    function getCompanyOfficerCount() external view returns (uint256) {
        return companyOfficers.length;
    }

    function getCompanyDirectorCount() external view returns (uint256) {
        return companyDirectors.length;
    }

    /// @notice Adds a new officer to the company
    /// @dev Only callable by owner, sets officer role to 200
    /// @param _officer Officer details including address and role
    function addOfficer(CompanyOfficer memory _officer) external onlyBoardAuthority {
        if (_officer.eoa == address(0)) revert InvalidOfficer();
        if (officerMembers[_officer.eoa]) revert DuplicateOfficer();
        companyOfficers.push(_officer);
        officerMembers[_officer.eoa] = true;
        if (!boardMembers[_officer.eoa]) {
            AUTH.updateRole(_officer.eoa, AUTH.OFFICER_ROLE());
        }
        emit OfficerAdded(_officer.eoa, companyOfficers.length - 1);
    }

    /// @notice Removes an officer by their address
    /// @dev Only callable by owner, revokes officer role
    /// @param _address Address of the officer to remove
    function removeOfficer(address _address) external onlyBoardAuthority {
        if (!officerMembers[_address]) revert InvalidOfficer();
        if (companyOfficers.length == 1) revert LastOfficer();
        for (uint256 i = 0; i < companyOfficers.length; i++) {
            if (companyOfficers[i].eoa == _address) {
                companyOfficers[i] = companyOfficers[companyOfficers.length - 1];
                companyOfficers.pop();
                officerMembers[_address] = false;
                AUTH.updateRole(
                    _address,
                    boardMembers[_address] ? AUTH.BOARD_ROLE() : 0
                );
                emit OfficerRemoved(_address, i);
                return;
            }
        }
        revert InvalidOfficer();
    }

    /// @notice Removes an officer by their index in the officers array
    /// @dev Only callable by owner, revokes officer role
    /// @param _index Index of the officer to remove
    function removeOfficerAt(uint256 _index) external onlyBoardAuthority {
        if (_index >= companyOfficers.length) revert InvalidOfficer();
        if (companyOfficers.length == 1) revert LastOfficer();
        address officerEOA = companyOfficers[_index].eoa;
        companyOfficers[_index] = companyOfficers[companyOfficers.length - 1];
        companyOfficers.pop();
        officerMembers[officerEOA] = false;
        AUTH.updateRole(
            officerEOA,
            boardMembers[officerEOA] ? AUTH.BOARD_ROLE() : 0
        );
        emit OfficerRemoved(officerEOA, _index);
    }

    function addDirector(
        CompanyDirector calldata director
    ) external onlyEnforcedBoard {
        if (director.eoa == address(0)) revert InvalidDirector();
        if (boardMembers[director.eoa]) revert DuplicateDirector();
        companyDirectors.push(director);
        boardMembers[director.eoa] = true;
        AUTH.updateRole(director.eoa, AUTH.BOARD_ROLE());
        emit DirectorAdded(director.eoa, companyDirectors.length - 1);
    }

    function removeDirector(address director) external onlyEnforcedBoard {
        if (!boardMembers[director]) revert InvalidDirector();
        if (companyDirectors.length == 1) revert LastDirector();
        for (uint256 i = 0; i < companyDirectors.length; i++) {
            if (companyDirectors[i].eoa == director) {
                companyDirectors[i] =
                    companyDirectors[companyDirectors.length - 1];
                companyDirectors.pop();
                boardMembers[director] = false;
                AUTH.updateRole(
                    director,
                    officerMembers[director] ? AUTH.OFFICER_ROLE() : 0
                );
                emit DirectorRemoved(director, i);
                return;
            }
        }
        revert InvalidDirector();
    }

    function removeDirectorAt(uint256 index) external onlyEnforcedBoard {
        if (index >= companyDirectors.length) revert InvalidDirector();
        if (companyDirectors.length == 1) revert LastDirector();
        address director = companyDirectors[index].eoa;
        companyDirectors[index] =
            companyDirectors[companyDirectors.length - 1];
        companyDirectors.pop();
        boardMembers[director] = false;
        AUTH.updateRole(
            director,
            officerMembers[director] ? AUTH.OFFICER_ROLE() : 0
        );
        emit DirectorRemoved(director, index);
    }

    /// @notice Connects a stockholder-governance executor (or other
    ///         IAuthAdapter) to Board authority.
    function setBoardAuthorityAdapter(
        address adapter
    ) external onlyEnforcedBoard {
        AUTH.setRoleAdapter(AUTH.BOARD_ROLE(), adapter);
        emit BoardAuthorityAdapterUpdated(adapter);
    }

    /// @notice Board-gated wrapper for the BorgAuth ownership handoff.
    function initTransferAuthOwnership(
        address newOwner
    ) external onlyEnforcedBoard {
        AUTH.initTransferOwnership(newOwner);
    }

    function setCompanyPayable(
        address _companyPayable
    ) external onlyBoardAuthority {
        address oldCompanyPayable = companyPayable;
        companyPayable = _companyPayable;
        emit CompanyPayableUpdated(companyPayable, oldCompanyPayable);
    }

    /// @notice Adds a reusable escrowed officer signature
    /// @dev Officer role (200+) required
    function addEscrowedOfficerSignature(bytes calldata signature) external onlyRole(200) {
        if (signature.length == 0) revert SignatureRequired();
        escrowedOfficerSignatures.push(signature);
        emit EscrowedOfficerSignatureAdded(
            escrowedOfficerSignatures.length - 1,
            msg.sender
        );
    }

    /// @notice Updates an existing reusable escrowed officer signature
    /// @dev Officer role (200+) required
    function setEscrowedOfficerSignature(
        uint256 index,
        bytes calldata signature
    ) external onlyRole(200) {
        if (index >= escrowedOfficerSignatures.length) revert InvalidEscrowSignatureIndex();
        if (signature.length == 0) revert SignatureRequired();
        escrowedOfficerSignatures[index] = signature;
        emit EscrowedOfficerSignatureUpdated(index, msg.sender);
    }

    /// @notice Reads an escrowed officer signature by index
    function getEscrowedOfficerSignature(
        uint256 index
    ) external view returns (bytes memory) {
        if (index >= escrowedOfficerSignatures.length) revert InvalidEscrowSignatureIndex();
        return escrowedOfficerSignatures[index];
    }

    /// @notice Gets total escrowed officer signature count
    function getEscrowedOfficerSignatureCount() external view returns (uint256) {
        return escrowedOfficerSignatures.length;
    }

    /// @notice Set or replace the active CyberCorp extension contract and schema type
    /// @dev Setting a new extension clears any previously stored extension data
    function setExtension(
        address _extension,
        bytes32 _extensionType
    ) external onlyBoardAuthority {
        if (_extension == address(0)) {
            if (_extensionType != bytes32(0)) revert InvalidExtension();
            extension = address(0);
            extensionType = bytes32(0);
            delete extensionData;
            emit CyberCORPExtensionSet(address(0), bytes32(0));
            emit CyberCORPExtensionDataUpdated(bytes32(0), "");
            return;
        }

        if (
            !ICyberCorpExtension(_extension).supportsExtensionType(_extensionType)
        ) revert ExtensionTypeNotSupported();

        extension = _extension;
        extensionType = _extensionType;
        delete extensionData;

        emit CyberCORPExtensionSet(_extension, _extensionType);
        emit CyberCORPExtensionDataUpdated(_extensionType, "");
    }

    /// @notice Update the raw extension payload for the active CyberCorp extension
    function setExtensionData(bytes calldata _extensionData) external onlyBoardAuthority {
        if (extension == address(0)) revert ExtensionNotConfigured();
        extensionData = _extensionData;
        emit CyberCORPExtensionDataUpdated(extensionType, _extensionData);
    }

    /// @notice Clear the active CyberCorp extension and any stored extension data
    function clearExtension() external onlyBoardAuthority {
        extension = address(0);
        extensionType = bytes32(0);
        delete extensionData;
        emit CyberCORPExtensionSet(address(0), bytes32(0));
        emit CyberCORPExtensionDataUpdated(bytes32(0), "");
    }

    /// @notice Returns the extension-provided JSON fragment for the current extension payload
    function getExtensionURI() external view returns (string memory) {
        if (extension == address(0) || extensionData.length == 0) return "";
        return ICyberCorpExtension(extension).getExtensionURI(extensionData);
    }

    // ========================
    // UUPSUpgradeable
    // ========================

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyBoardAuthority {
        if(
            ICyberCorpSingleFactory(upgradeFactory).getRefImplementation() != newImplementation) {
            revert NotRefImplementation();
        }
    }
}
