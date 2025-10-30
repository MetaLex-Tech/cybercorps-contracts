
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./libs/auth.sol";
import "./storage/CyberScripStorage.sol";

contract CyberScrip is Initializable, ERC20Upgradeable, BorgAuthACL {
    using CyberScripStorage for CyberScripStorage.StorageData;
    
    string public constant DEPLOY_VERSION = "1"; // For version-tracking on all deployment and future upgrades

    error RestrictedTransfer(string reason);
    error NotIssuanceManager();
    error ComplianceFeatureDisabled();
    error AccountFrozen(address account);

    event FreezeStatusUpdated(address indexed account, bool frozen);
    event ComplianceFeatureDisabledEvent(string feature);

    modifier onlyIssuanceManager() {
        if (msg.sender != CyberScripStorage.getStorageData().issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
        _disableInitializers();
    }

    function initialize(
        address _certPrinter,
        address _issuanceManager,
        string memory _name,
        string memory _symbol,
        ITransferRestrictionHook[] memory _transferRestrictionHooks,
        bool _enableForceTransfer,
        bool _enableForceBurn,
        bool _enableFreeze
    ) external initializer {
        __ERC20_init(_name, _symbol);

        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        s.certPrinter = _certPrinter;
        s.issuanceManager = _issuanceManager;
        s.transferRestrictionHooks = _transferRestrictionHooks;
        s.canForceTransfer = _enableForceTransfer;
        s.canForceBurn = _enableForceBurn;
        s.canFreeze = _enableFreeze;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        // Enforce freeze checks for normal transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (s.canFreeze) {
                if (s.frozen[from]) revert AccountFrozen(from);
                if (s.frozen[to]) revert AccountFrozen(to);
            }
            // Enforce transfer restriction hooks
            for (uint256 i = 0; i < s.transferRestrictionHooks.length; i++) {
                (bool allowed, string memory reason) = s.transferRestrictionHooks[i].checkTransferRestriction(from, to, amount, "");
                if (!allowed) revert RestrictedTransfer(reason);
            }
        }
        super._update(from, to, amount);
    }

    function burnFrom(address account, uint256 amount) public virtual onlyIssuanceManager {
        super._burn(account, amount);
    }

    function setRestrictionHook(ITransferRestrictionHook[] memory _transferRestrictionHooks) external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        s.transferRestrictionHooks = _transferRestrictionHooks;
    }

    // ========================
    // Compliance functionality
    // ========================

    // Disable features (one-way). Cannot be re-enabled post-initialization
    function disableForceTransfer() external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        if (s.canForceTransfer) {
            s.canForceTransfer = false;
            emit ComplianceFeatureDisabledEvent("forceTransfer");
        }
    }

    function disableForceBurn() external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        if (s.canForceBurn) {
            s.canForceBurn = false;
            emit ComplianceFeatureDisabledEvent("forceBurn");
        }
    }

    function disableFreeze() external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        if (s.canFreeze) {
            s.canFreeze = false;
            emit ComplianceFeatureDisabledEvent("freeze");
        }
    }

    // Freeze/unfreeze an account (only if freezing is enabled)
    function setFrozen(address account, bool isFrozen) external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        if (!s.canFreeze) revert ComplianceFeatureDisabled();
        s.frozen[account] = isFrozen;
        emit FreezeStatusUpdated(account, isFrozen);
    }

    // Force transfer ignoring hooks and freezes (only if feature enabled)
    function forceTransfer(address from, address to, uint256 amount) external onlyIssuanceManager {
        if (!CyberScripStorage.getStorageData().canForceTransfer) revert ComplianceFeatureDisabled();
        require(from != address(0) && to != address(0), "force: zero addr");
        // Bypass our override and hooks by calling the base ERC20 implementation directly
        ERC20Upgradeable._update(from, to, amount);
    }

    // Force burn ignoring hooks and freezes (only if feature enabled)
    function forceBurn(address account, uint256 amount) external onlyIssuanceManager {
        if (!CyberScripStorage.getStorageData().canForceBurn) revert ComplianceFeatureDisabled();
        require(account != address(0), "forceBurn: zero addr");
        ERC20Upgradeable._update(account, address(0), amount);
    }

    // ========================
    // Getter / Setter
    // ========================

    function certPrinter() external returns (address) {
        return CyberScripStorage.getStorageData().certPrinter;
    }

    function issuanceManager() external returns (address) {
        return CyberScripStorage.getStorageData().issuanceManager;
    }

    function transferRestrictionHooks(uint256 i) external returns (ITransferRestrictionHook) {
        return CyberScripStorage.getStorageData().transferRestrictionHooks[i];
    }

    function canForceTransfer() external returns (bool) {
        return CyberScripStorage.getStorageData().canForceTransfer;
    }

    function canForceBurn() external returns (bool) {
        return CyberScripStorage.getStorageData().canForceBurn;
    }

    function canFreeze() external returns (bool) {
        return CyberScripStorage.getStorageData().canFreeze;
    }

    function frozen(address account) external returns (bool) {
        return CyberScripStorage.getStorageData().frozen[account];
    }
}
