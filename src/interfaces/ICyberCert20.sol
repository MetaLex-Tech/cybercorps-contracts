pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./ITransferRestrictionHook.sol";

interface ICyberCert20 is IERC20 {
    error NotTransferable();
    error RestrictedTransfer(string reason);

    function initialize(
        address _certPrinter,
        address _issuanceManager,
        string calldata _name,
        string calldata _symbol,
        ITransferRestrictionHook[] calldata _typeRestrictionHook
    ) external;

    function setRestrictionHook(ITransferRestrictionHook[] calldata _typeRestrictionHook) external;

    function certPrinter() external view returns (address);
    function underlyingTokenId() external view returns (uint256);
    function transferable() external view returns (bool);
    function IssuanceManager() external view returns (address);
    function typeRestrictionHook(uint256 index) external view returns (ITransferRestrictionHook);

    function mint(address to, uint256 amount) external;
} 