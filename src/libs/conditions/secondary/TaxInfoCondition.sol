// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  TaxInfoCondition - blocks acceptance until tax information is on file
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition backing K-1 readiness and the §1446(f) withholding posture.
/// Acts as the dedicated tax-form registry: the credentialing-layer admin records each account's
/// W-9 / W-8BEN(-E) file (the form itself stays offchain; the hash is the audit anchor).
/// Fails when the buyer's form is not recorded. The seller's record (which should exist from primary
/// issuance) is readable here for the §1446(f) determination but does not gate the trade.
contract TaxInfoCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    enum TaxFormType {
        NONE,
        W9,
        W8BEN,
        W8BENE
    }

    struct TaxFormRecord {
        TaxFormType formType;
        bytes32 evidenceHash;   // hash of the offchain form/file
        uint64 recordedAt;
    }

    error InvalidAccount();

    event TaxFormRecorded(address indexed account, TaxFormType formType, bytes32 evidenceHash);
    event TaxFormCleared(address indexed account);

    mapping(address => TaxFormRecord) public taxForms;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function setTaxForm(address account, TaxFormType formType, bytes32 evidenceHash) external onlyAdmin {
        if (account == address(0)) revert InvalidAccount();
        taxForms[account] = TaxFormRecord({
            formType: formType,
            evidenceHash: evidenceHash,
            recordedAt: uint64(block.timestamp)
        });
        emit TaxFormRecorded(account, formType, evidenceHash);
    }

    function clearTaxForm(address account) external onlyAdmin {
        delete taxForms[account];
        emit TaxFormCleared(account);
    }

    function hasTaxFormOnFile(address account) public view returns (bool) {
        return taxForms[account].formType != TaxFormType.NONE;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // No buyer yet (posting context) — nothing to gate
        if (buyer == address(0)) return true;

        // TODO do we need to gate tax form types by buyer status?
        return hasTaxFormOnFile(buyer);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
