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
    error InvalidConfiguration();
    error LegacyAPIUnavailable();
    error UnapprovedImplementation();
    error PermissionDenied(bytes32 permission, address account);

    event MembershipChanged(address indexed account, uint256 roles);
    event RootTransferProposed(address indexed nominee);
    event RootTransferred(address indexed previousRoot, address indexed newRoot);
    event SetupCompleted(address indexed root, address indexed board, address indexed corp);

    constructor() BorgAuth(address(this)) {
        _disableInitializers();
    }

    function initializeCorporate(address bootstrap, address registry) external initializer {
        if (bootstrap == address(0) || registry.code.length == 0) revert InvalidConfiguration();
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
        if (
            setupComplete || root == address(0) || board.code.length == 0 || corp.code.length == 0
                || officer == address(0) || issuance.code.length == 0 || deal.code.length == 0 || round.code.length == 0
                || board == corp || board == issuance || board == deal || board == round || root == corp || root == issuance
                || root == deal || root == round
        ) {
            revert InvalidConfiguration();
        }
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
        if (
            !setupComplete || account == address(0) || roles & ~CorporateAuth.ALL_ROLES != 0
                || (memberships[account] ^ roles) & CorporateAuth.OFFICER != 0
                || (roles & CorporateAuth.BOARD_EXECUTOR != 0 && account.code.length == 0)
        ) {
            revert InvalidConfiguration();
        }
        memberships[account] = roles;
        emit MembershipChanged(account, roles);
    }

    function setOfficerMembership(address account, bool enabled) external {
        if (!setupComplete || msg.sender != officerController || account == address(0)) revert Unauthorized();
        uint256 roles = memberships[account];
        memberships[account] = enabled ? roles | CorporateAuth.OFFICER : roles & ~CorporateAuth.OFFICER;
        emit MembershipChanged(account, memberships[account]);
    }

    function hasRole(address account, uint256 role) public view returns (bool) {
        return role != 0 && role & ~CorporateAuth.ALL_ROLES == 0 && memberships[account] & role == role;
    }

    function rolesForPermission(bytes32 permission) public pure returns (uint256) {
        if (permission == CorporateAuth.MANAGE_OFFICERS) return CorporateAuth.BOARD_EXECUTOR;
        if (
            permission == CorporateAuth.SIGN_AS_OFFICER || permission == CorporateAuth.COMPANY_OPERATIONS
                || permission == CorporateAuth.MANAGE_DEALS || permission == CorporateAuth.MANAGE_ROUNDS
                || permission == CorporateAuth.TRANSFER_POLICY
        ) return CorporateAuth.OFFICER;
        if (permission == CorporateAuth.MANAGE_SECURITY_CLASSES) {
            return CorporateAuth.OFFICER | CorporateAuth.ROUND_MANAGER;
        }
        if (permission == CorporateAuth.ISSUE_SECURITIES || permission == CorporateAuth.ADMINISTER_CERTIFICATES) {
            return CorporateAuth.OFFICER | CorporateAuth.DEAL_MANAGER | CorporateAuth.ROUND_MANAGER;
        }
        return 0;
    }

    function hasPermission(bytes32 permission, address account) public view returns (bool) {
        if (
            permission == CorporateAuth.CONFIGURE_PROTOCOL || permission == CorporateAuth.APPROVE_UPGRADE
                || permission == CorporateAuth.MANAGE_OFFICERS && setupComplete && account == rootAuthority
        ) {
            return account == rootAuthority;
        }
        return setupComplete && memberships[account] & rolesForPermission(permission) != 0;
    }

    function requirePermission(bytes32 permission, address account) external view {
        if (!hasPermission(permission, account)) revert PermissionDenied(permission, account);
    }

    /// @notice A zero nominee cancels an outstanding proposal; root itself is never set to zero.
    function proposeRootTransfer(address nominee) external onlyRoot {
        if (!setupComplete || nominee == rootAuthority) revert InvalidConfiguration();
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

    function _grant(address account, uint256 role) private {
        memberships[account] |= role;
        emit MembershipChanged(account, memberships[account]);
    }

    function _authorizeUpgrade(address implementation) internal override onlyRoot {
        if (!setupComplete || IBorgAuthReleaseRegistry(releaseRegistry).borgAuthImplementation() != implementation) {
            revert UnapprovedImplementation();
        }
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
