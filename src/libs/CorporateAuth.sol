// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

library CorporateAuth {
    uint256 internal constant DIRECTOR = 1;
    uint256 internal constant OFFICER = 1 << 1;
    uint256 internal constant BOARD_EXECUTOR = 1 << 2;
    uint256 internal constant ISSUANCE_MANAGER = 1 << 3;
    uint256 internal constant DEAL_MANAGER = 1 << 4;
    uint256 internal constant ROUND_MANAGER = 1 << 5;
    uint256 internal constant ALL_ROLES = (1 << 6) - 1;

    bytes32 internal constant MANAGE_OFFICERS = keccak256("MANAGE_OFFICERS");
    bytes32 internal constant SIGN_AS_OFFICER = keccak256("SIGN_AS_OFFICER");
    bytes32 internal constant COMPANY_OPERATIONS = keccak256("COMPANY_OPERATIONS");
    bytes32 internal constant CONFIGURE_PROTOCOL = keccak256("CONFIGURE_PROTOCOL");
    bytes32 internal constant APPROVE_UPGRADE = keccak256("APPROVE_UPGRADE");
    bytes32 internal constant MANAGE_SECURITY_CLASSES = keccak256("MANAGE_SECURITY_CLASSES");
    bytes32 internal constant ISSUE_SECURITIES = keccak256("ISSUE_SECURITIES");
    bytes32 internal constant ADMINISTER_CERTIFICATES = keccak256("ADMINISTER_CERTIFICATES");
    bytes32 internal constant MANAGE_DEALS = keccak256("MANAGE_DEALS");
    bytes32 internal constant MANAGE_ROUNDS = keccak256("MANAGE_ROUNDS");
    bytes32 internal constant TRANSFER_POLICY = keccak256("TRANSFER_POLICY");
}

interface ICorporateAuth {
    function supportsCorporateAuth() external pure returns (bool);
    function rootAuthority() external view returns (address);
    function hasRole(address account, uint256 role) external view returns (bool);
    function requirePermission(bytes32 permission, address account) external view;
    function setOfficerMembership(address account, bool enabled) external;
}

interface IBorgAuthReleaseRegistry {
    function borgAuthImplementation() external view returns (address);
}
