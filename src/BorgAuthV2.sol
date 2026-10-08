// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CorporateAuth, IBorgAuthReleaseRegistry} from "./libs/CorporateAuth.sol";
import {BorgAuth} from "./libs/auth.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice New-deployment authority. Legacy numeric APIs are retained but cannot authorize anything.
contract BorgAuthV2 is BorgAuth, UUPSUpgradeable {
    address public rootAuthority;
    address public pendingRootAuthority;
    address public releaseRegistry;
    address public officerController;
    bool public setupComplete;
    mapping(address => uint256) public memberships;

    error Unauthorized();
    error ZeroAddress();
    error NotContract(address account);
    error AddressIsComponent(address account);
    error SetupNotComplete();
    error SetupAlreadyComplete();
    error UnknownRoles(uint256 roles);
    error OfficerBitMismatch(address account);
    error NomineeIsRoot();
    error LegacyAPIUnavailable();
    error ImplementationMismatch(address approved, address implementation);
    error PermissionDenied(bytes32 permission, address account);

    event MembershipChanged(address indexed account, uint256 roles);
    event RootTransferProposed(address indexed nominee);
    event RootTransferred(address indexed previousRoot, address indexed newRoot);
    event SetupCompleted(address indexed root, address indexed board, address indexed corp);

    constructor() BorgAuth(address(this)) {
        _disableInitializers();
    }

    function initializeCorporate(address bootstrap, address registry) external initializer {
        if (bootstrap == address(0)) revert ZeroAddress();
        _requireContract(registry);
        __UUPSUpgradeable_init();
        rootAuthority = bootstrap;
        releaseRegistry = registry;
    }

    modifier onlyRoot() {
        if (msg.sender != rootAuthority) revert Unauthorized();
        _;
    }

    function supportsCorporateAuth() external pure returns (bool) {
        return true;
    }

    /// @notice Called once by the deploying factory before it returns the new stack.
    function completeSetup(
        address root,
        address board,
        address corp,
        address officer,
        address issuance,
        address deal,
        address round
    ) external onlyRoot {
        if (setupComplete) revert SetupAlreadyComplete();
        if (root == address(0) || officer == address(0)) revert ZeroAddress();
        _requireContract(board);
        _requireContract(corp);
        _requireContract(issuance);
        _requireContract(deal);
        _requireContract(round);
        // Root and the board act for the company. They must not be one of its components.
        _requireNotComponent(board, corp, issuance, deal, round);
        _requireNotComponent(root, corp, issuance, deal, round);
        setupComplete = true;
        officerController = corp;
        _grant(board, CorporateAuth.BOARD_EXECUTOR);
        _grant(officer, CorporateAuth.OFFICER);
        _grant(issuance, CorporateAuth.ISSUANCE_MANAGER);
        _grant(deal, CorporateAuth.DEAL_MANAGER);
        _grant(round, CorporateAuth.ROUND_MANAGER);
        rootAuthority = root;
        emit SetupCompleted(root, board, corp);
    }

    /// @notice Root administers non-officer memberships. Officer changes go through the company roster.
    function setMembership(address account, uint256 roles) external onlyRoot {
        if (!setupComplete) revert SetupNotComplete();
        if (account == address(0)) revert ZeroAddress();
        if (roles & ~CorporateAuth.ALL_ROLES != 0) revert UnknownRoles(roles);
        if ((memberships[account] ^ roles) & CorporateAuth.OFFICER != 0) revert OfficerBitMismatch(account);
        if (roles & CorporateAuth.BOARD_EXECUTOR != 0) _requireContract(account);
        memberships[account] = roles;
        emit MembershipChanged(account, roles);
    }

    function setOfficerMembership(address account, bool enabled) external {
        if (!setupComplete) revert SetupNotComplete();
        if (msg.sender != officerController) revert Unauthorized();
        if (account == address(0)) revert ZeroAddress();
        uint256 roles = memberships[account];
        memberships[account] = enabled ? roles | CorporateAuth.OFFICER : roles & ~CorporateAuth.OFFICER;
        emit MembershipChanged(account, memberships[account]);
    }

    function hasRole(address account, uint256 role) public view returns (bool) {
        return role != 0 && role & ~CorporateAuth.ALL_ROLES == 0 && memberships[account] & role == role;
    }

    /// @notice Permission table. Note this is static until upgrading to a new implementation
    ///
    /// | Permission              | Root | Board | Officer | Deal Mgr | Round Mgr |
    /// |-------------------------|------|-------|---------|----------|-----------|
    /// | CONFIGURE_PROTOCOL      | yes  |       |         |          |           |
    /// | APPROVE_UPGRADE         | yes  |       |         |          |           |
    /// | MANAGE_OFFICERS         | yes  | yes   |         |          |           |
    /// | SIGN_AS_OFFICER         |      |       | yes     |          |           |
    /// | COMPANY_OPERATIONS      |      |       | yes     |          |           |
    /// | MANAGE_DEALS            |      |       | yes     |          |           |
    /// | MANAGE_ROUNDS           |      |       | yes     |          |           |
    /// | TRANSFER_POLICY         |      |       | yes     |          |           |
    /// | MANAGE_SECURITY_CLASSES |      |       | yes     | yes      | yes       |
    /// | ISSUE_SECURITIES        |      |       | yes     | yes      | yes       |
    /// | ADMINISTER_CERTIFICATES |      |       | yes     | yes      | yes       |
    ///
    /// - The Root column is in hasPermission, not here. Root is an address, not a real role.
    /// - DIRECTOR and ISSUANCE_MANAGER give no permission.
    function rolesForPermission(bytes32 permission) public pure returns (uint256) {
        if (permission == CorporateAuth.MANAGE_OFFICERS) return CorporateAuth.BOARD_EXECUTOR;
        if (
            permission == CorporateAuth.SIGN_AS_OFFICER || permission == CorporateAuth.COMPANY_OPERATIONS
                || permission == CorporateAuth.MANAGE_DEALS || permission == CorporateAuth.MANAGE_ROUNDS
                || permission == CorporateAuth.TRANSFER_POLICY
        ) return CorporateAuth.OFFICER;
        if (
            permission == CorporateAuth.MANAGE_SECURITY_CLASSES || permission == CorporateAuth.ISSUE_SECURITIES
                || permission == CorporateAuth.ADMINISTER_CERTIFICATES
        ) {
            return CorporateAuth.OFFICER | CorporateAuth.DEAL_MANAGER | CorporateAuth.ROUND_MANAGER;
        }
        return 0;
    }

    /// @notice Root alone holds CONFIGURE_PROTOCOL and APPROVE_UPGRADE, also during setup.
    /// After setup, root also holds MANAGE_OFFICERS. All other permissions come from roles.
    function hasPermission(bytes32 permission, address account) public view returns (bool) {
        if (permission == CorporateAuth.CONFIGURE_PROTOCOL || permission == CorporateAuth.APPROVE_UPGRADE) {
            return account == rootAuthority;
        }
        if (!setupComplete) return false;
        if (permission == CorporateAuth.MANAGE_OFFICERS && account == rootAuthority) return true;
        return memberships[account] & rolesForPermission(permission) != 0;
    }

    function requirePermission(bytes32 permission, address account) external view {
        if (!hasPermission(permission, account)) revert PermissionDenied(permission, account);
    }

    /// @notice A zero nominee cancels an outstanding proposal; root itself is never set to zero.
    function proposeRootTransfer(address nominee) external onlyRoot {
        if (!setupComplete) revert SetupNotComplete();
        if (nominee == rootAuthority) revert NomineeIsRoot();
        pendingRootAuthority = nominee;
        emit RootTransferProposed(nominee);
    }

    function acceptRootTransfer() external {
        if (msg.sender == address(0) || msg.sender != pendingRootAuthority) revert Unauthorized();
        address oldRoot = rootAuthority;
        rootAuthority = msg.sender;
        pendingRootAuthority = address(0);
        emit RootTransferred(oldRoot, msg.sender);
    }

    function _requireContract(address account) private view {
        if (account.code.length == 0) revert NotContract(account);
    }

    function _requireNotComponent(address account, address corp, address issuance, address deal, address round)
        private
        pure
    {
        if (account == corp || account == issuance || account == deal || account == round) {
            revert AddressIsComponent(account);
        }
    }

    function _grant(address account, uint256 role) private {
        memberships[account] |= role;
        emit MembershipChanged(account, memberships[account]);
    }

    function _authorizeUpgrade(address implementation) internal override onlyRoot {
        if (!setupComplete) revert SetupNotComplete();
        address approved = IBorgAuthReleaseRegistry(releaseRegistry).borgAuthImplementation();
        if (approved != implementation) revert ImplementationMismatch(approved, implementation);
    }

    function updateRole(address, uint256) external override {
        revert LegacyAPIUnavailable();
    }

    function initTransferOwnership(address) external override {
        revert LegacyAPIUnavailable();
    }

    function acceptOwnership() external override {
        revert LegacyAPIUnavailable();
    }

    function zeroOwner() external override {
        revert LegacyAPIUnavailable();
    }

    function setRoleAdapter(uint256, address) external override {
        revert LegacyAPIUnavailable();
    }

    function onlyRole(uint256, address) public pure override {
        revert LegacyAPIUnavailable();
    }

    function matchRole(uint256, address) public pure override {
        revert LegacyAPIUnavailable();
    }
}
