// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../../interfaces/IIssuanceManager.sol";
import "../../interfaces/ICyberScrip.sol";
import "../../interfaces/ICondition.sol";
import "../auth.sol";
import "./baseCondition.sol";

interface ICertWithIssuanceManager {
    function issuanceManager() external view returns (address);
}

/// @title IssuerApprovalRecertificationCondition
/// @notice Requires issuer admin approval before scrip-to-cert conversion.
/// @dev This contract is intended to be deployed once and reused as a singleton condition.
contract IssuerApprovalRecertificationCondition is BaseCondition {
    error InvalidContractAddress();
    error InvalidInvestor();

    event InvestorApprovalUpdated(
        address indexed certAddress,
        address indexed investor,
        bool approved,
        address indexed approver
    );

    bytes4 private constant _CONVERT_SCRIP_TO_CERT_SELECTOR =
        bytes4(keccak256("convertScripToCert(address,uint256)"));

    mapping(address => mapping(address => bool)) private _investorApprovals;

    function setInvestorApproval(
        address certOrScrip,
        address investor,
        bool approved
    ) external {
        if (certOrScrip == address(0)) revert InvalidContractAddress();
        if (investor == address(0)) revert InvalidInvestor();

        address certAddress = _resolveCertAddress(certOrScrip);
        address issuanceManager = ICertWithIssuanceManager(certAddress)
            .issuanceManager();
        _requireAdmin(issuanceManager);

        _investorApprovals[certAddress][investor] = approved;
        emit InvestorApprovalUpdated(certAddress, investor, approved, msg.sender);
    }

    function isInvestorApproved(
        address certOrScrip,
        address investor
    ) external view returns (bool) {
        address certAddress = _resolveCertAddress(certOrScrip);
        return _investorApprovals[certAddress][investor];
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) public view override returns (bool) {
        if (_functionSignature != _CONVERT_SCRIP_TO_CERT_SELECTOR) {
            return false;
        }

        address certAddress = _resolveCertAddress(_contract);
        address investor = _resolveInvestor(data);

        if (investor == address(0)) return false;
        return _investorApprovals[certAddress][investor];
    }

    function _resolveInvestor(bytes memory data) internal view returns (address) {
            (, address investor) = abi.decode(data, (uint256, address));
            return investor;
    }

    function _resolveCertAddress(
        address certOrScrip
    ) internal view returns (address certAddress) {
        certAddress = certOrScrip;
        try ICyberScrip(certOrScrip).certPrinter() returns (address fromScrip) {
            if (fromScrip != address(0)) {
                certAddress = fromScrip;
            }
        } catch {}
    }

    function _requireAdmin(address issuanceManager) internal view {
        if (issuanceManager == address(0)) revert InvalidContractAddress();
        BorgAuth auth = BorgAuth(IIssuanceManager(issuanceManager).AUTH());
        auth.onlyRole(auth.ADMIN_ROLE(), msg.sender);
    }
}
