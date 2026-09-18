pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./ITransferRestrictionHook.sol";

interface ICyberScrip is IERC20 {
    error NotTransferable();
    error RestrictedTransfer(string reason);
    error HolderLimitExceeded(uint256 limit);

    function initialize(
        address _auth,
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
    function issuanceManager() external view returns (address);
    function transferRestrictionHooks(uint256 index) external view returns (ITransferRestrictionHook);
    function transferRestrictionHooksLength() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function disableForceTransfer() external;
    function disableForceBurn() external;
    function disableFreeze() external;
    function setFrozen(address account, bool isFrozen) external;
    function canFreeze() external view returns (bool);
    function frozen(address account) external view returns (bool);
    function forceTransfer(address from, address to, uint256 amount) external;
    function forceBurn(address account, uint256 amount) external;
    function holderCount() external view returns (uint256);
    function maxHolderCount() external view returns (uint256);
    function setMaxHolderCount(uint256 maxHolders) external;
}