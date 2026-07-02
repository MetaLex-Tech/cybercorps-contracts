// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts/interfaces/IERC165.sol";
import "../../interfaces/IDealManager.sol";

/// @title  ISecondaryTradingCondition - Strongly-typed condition interface for the secondary-trading path
/// @author MetaLeX Labs, Inc.
/// @notice Unlike the generic ICondition (opaque `bytes` payload requiring abi.decode), the caller hands the
/// condition the DealManager and the two ids it needs, so implementations resolve offer/escrow state through
/// IDealManager.getOffer / getSecondaryEscrow with compile-time-checked arguments.
interface ISecondaryTradingCondition is IERC165 {
    /// @param dealManager       DealManager evaluating the condition; source of offer/escrow state
    /// @param functionSignature msg.sig of the gated DealManager entrypoint (post/accept/finalize).
    ///                          Note since most of DealManager's functions are from external libraries,
    ///                          msg.sig will reflect external library's instead of DealManager's.
    ///                          Moreover, the input argument struct's name will be used literally instead of the underlying tuples
    ///                          for computing an external library's function (ex. bytes4(keccak256("postOffer(PostOfferParams)"))
    /// @param offerId           offer key under evaluation
    /// @param agreementId       settlement agreement id; bytes32(0) at postOffer (no settlement yet)
    function checkCondition(
        IDealManager dealManager,
        bytes4 functionSignature,
        bytes32 offerId,
        bytes32 agreementId
    ) external view returns (bool);
}

/// @title  BaseSecondaryTradingCondition - Base for secondary-trading conditions
/// @author MetaLeX Labs, Inc.
/// @notice Specialized counterpart of BaseCondition for the typed ISecondaryTradingCondition family, letting
/// SecondaryTradeStorage (1) validate an attached condition via ERC-165 supportsInterface before wiring it in,
/// and (2) call checkCondition with typed arguments instead of an abi-encoded blob.
abstract contract BaseSecondaryTradingCondition is ISecondaryTradingCondition {
    function checkCondition(
        IDealManager dealManager,
        bytes4 functionSignature,
        bytes32 offerId,
        bytes32 agreementId
    ) external view virtual returns (bool);

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(ISecondaryTradingCondition).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
