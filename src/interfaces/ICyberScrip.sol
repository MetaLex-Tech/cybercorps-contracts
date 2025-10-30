pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./ITransferRestrictionHook.sol";

interface ICyberScrip is IERC20 {
    error NotTransferable();
    error RestrictedTransfer(string reason);

    function initialize(
        address _certPrinter,
        address _issuanceManager,
        string calldata _name,
        string calldata _symbol,
        ITransferRestrictionHook[] calldata _typeRestrictionHook,
        // TODO TBD: not sure if final design yet
        bool _enableForceTransfer,
        bool _enableForceBurn,
        bool _enableFreeze
    ) external;

    function setRestrictionHook(ITransferRestrictionHook[] calldata _typeRestrictionHook) external;
    function certPrinter() external view returns (address);
    function IssuanceManager() external view returns (address);
    function transferRestrictionHooks(uint256 index) external view returns (ITransferRestrictionHook);
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
} 