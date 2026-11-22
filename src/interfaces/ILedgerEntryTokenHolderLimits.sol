// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title  ILedgerEntryTokenHolderLimits - the functions of the LedgerEntryTokenHolderLimits library
/// @author MetaLeX Labs, Inc.
/// @notice Encode calls against this interface and send them through the printer's forwarder:
/// `ILedgerEntryToken(printer).holderLimits(abi.encodeCall(ILedgerEntryTokenHolderLimits.fn, (...)))`, then
/// `abi.decode` the returned bytes. Use a static call for the views. The selectors are the library's own:
/// every parameter is an elementary type, so they equal these. Do not call the printer at this interface
/// directly; it has none of these functions.
interface ILedgerEntryTokenHolderLimits {
    // Any caller: recompute from the printer's records; only moves the totals to their correct value
    function syncHolder(address owner) external;
    function syncLot(uint256 tokenId) external;

    // Issuance manager, or an admin of its AUTH
    function setPlanSecurity(uint256 tokenId, bool value) external;
    function setNotAccreditedMark(address account, bool marked) external;

    // Views
    function nonAccreditedLookThroughHolderCount() external view returns (uint256);
    function lookThroughHolderCountExcludingPlan() external view returns (uint256);
    function nonAccreditedLookThroughHolderCountExcludingPlan() external view returns (uint256);
    function holderLimitTotals() external view returns (uint256 accredited, uint256 planOnly, uint256 planOnlyAccredited);
    function isAccredited(address account) external view returns (bool);
    function isPlanOnlyHolder(address owner) external view returns (bool);
    function isPlanSecurity(uint256 tokenId) external view returns (bool);
    function notAccreditedMark(address account) external view returns (bool);
    function holderLimitAccount(address owner)
        external
        view
        returns (bool accredited, uint32 planLots, uint256 credentialId);
}
