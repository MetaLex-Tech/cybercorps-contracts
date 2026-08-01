// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../../auth.sol";
import "../../../interfaces/ILexChexBadge.sol";

/// @title  BadgeScopedCondition - picks which credential registry judges an SPV's parties
/// @author MetaLeX Labs, Inc.
/// @notice Shared by the conditions that read credentials. A platform default covers every SPV, and an
/// operator running its own LeXcheXBadge layer gets its SPVs pointed at that instead. Both are admin-set:
/// the registry decides who counts as accredited, and the SPV is the party being checked, so it does not
/// choose its own checker. HolderCapCondition is the exception — its count has to match the printer's
/// tally, so it reads the registry off the printer.
abstract contract BadgeScopedCondition is BorgAuthACL {
    struct BadgeScopedStorage {
        ILexChexBadge defaultBadge;                 // registry for any SPV without an override; never zero
        mapping(address => ILexChexBadge) spvBadge; // per-SPV override; zero means use the default
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.badge-scoped.storage.v1");

    error InvalidBadge();
    error InvalidBadgeSpv();

    event DefaultBadgeUpdated(address badge);
    event SpvBadgeUpdated(address indexed spv, address badge);

    function __BadgeScopedCondition_init(address _defaultBadge) internal onlyInitializing {
        _setDefaultBadge(_defaultBadge);
    }

    function updateDefaultBadge(address _badge) external onlyAdmin {
        _setDefaultBadge(_badge);
    }

    /// @notice Points one SPV at a registry other than the default; zero restores the default
    function setSpvBadge(address spv, address _badge) external onlyAdmin {
        if (spv == address(0)) revert InvalidBadgeSpv();
        _badgeScopedStorage().spvBadge[spv] = ILexChexBadge(_badge);
        emit SpvBadgeUpdated(spv, _badge);
    }

    /// @notice Registry for any SPV without an override
    function defaultBadge() public view returns (ILexChexBadge) {
        return _badgeScopedStorage().defaultBadge;
    }

    /// @notice An SPV's override, or zero when it uses the default
    function spvBadge(address spv) public view returns (ILexChexBadge) {
        return _badgeScopedStorage().spvBadge[spv];
    }

    /// @notice The registry that judges `spv`'s parties. Never zero — the default is required at initialize.
    function badgeFor(address spv) public view returns (ILexChexBadge) {
        BadgeScopedStorage storage $ = _badgeScopedStorage();
        ILexChexBadge badge = $.spvBadge[spv];
        return address(badge) != address(0) ? badge : $.defaultBadge;
    }

    function _setDefaultBadge(address _badge) private {
        if (_badge == address(0)) revert InvalidBadge();
        _badgeScopedStorage().defaultBadge = ILexChexBadge(_badge);
        emit DefaultBadgeUpdated(_badge);
    }

    function _badgeScopedStorage() private pure returns (BadgeScopedStorage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }
}
