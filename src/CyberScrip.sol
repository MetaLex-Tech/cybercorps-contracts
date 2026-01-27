
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./libs/auth.sol";
import "./storage/CyberScripStorage.sol";

contract CyberScrip is Initializable, ERC20Upgradeable, BorgAuthACL {
    using CyberScripStorage for CyberScripStorage.StorageData;
    
    string public constant DEPLOY_VERSION = "3"; // For version-tracking on all deployment and future upgrades

    error RestrictedTransfer(string reason);
    error NotIssuanceManager();
    error ComplianceFeatureDisabled();
    error AccountFrozen(address account);
    error HolderLimitExceeded(uint256 limit);

    event FreezeStatusUpdated(address indexed account, bool frozen);
    event ComplianceFeatureDisabledEvent(string feature);
    event ForceTransfer(address indexed from, address indexed to, uint256 amount);
    event ForceBurn(address indexed account, uint256 amount);
    event MaxHolderCountUpdated(uint256 maxHolderCount);

    modifier onlyIssuanceManager() {
        if (msg.sender != CyberScripStorage.getStorageData().issuanceManager) revert NotIssuanceManager();
        _;
    }

    constructor()  {
        _disableInitializers();
    }

    function initialize(
        address _auth,
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
        __BorgAuthACL_init(_auth);

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
        uint256 fromBalanceBefore = 0;
        uint256 toBalanceBefore = 0;

        if (from != address(0)) {
            fromBalanceBefore = balanceOf(from);
        }
        if (to != address(0)) {
            toBalanceBefore = balanceOf(to);
        }

        // Enforce freeze checks for normal transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (s.canFreeze) {
                if (s.frozen[from]) revert AccountFrozen(from);
                if (s.frozen[to]) revert AccountFrozen(to);
            }
            // Enforce transfer restriction hooks
            uint256 length = s.transferRestrictionHooks.length;
            for (uint256 i = 0; i < length; i++) {
                (bool allowed, string memory reason) = s.transferRestrictionHooks[i].checkTransferRestriction(from, to, amount, "");
                if (!allowed) revert RestrictedTransfer(reason);
            }
        }

        if (amount > 0 && from != to) {
            uint256 holderDelta = s.holderCount;
            bool decrementHolder = from != address(0) && fromBalanceBefore == amount;
            bool incrementHolder = to != address(0) && toBalanceBefore == 0;

            if (decrementHolder) {
                holderDelta -= 1;
            }
            if (incrementHolder) {
                holderDelta += 1;
            }

            if (s.maxHolderCount > 0 && holderDelta > s.maxHolderCount) {
                revert HolderLimitExceeded(s.maxHolderCount);
            }
        }

        super._update(from, to, amount);

        if (amount > 0 && from != to) {
            bool decrementHolder = from != address(0) && fromBalanceBefore == amount;
            bool incrementHolder = to != address(0) && toBalanceBefore == 0;
            if (decrementHolder) {
                s.holderCount -= 1;
            }
            if (incrementHolder) {
                s.holderCount += 1;
            }
        }
    }

    function mint(address to, uint256 amount) public virtual onlyIssuanceManager {
        super._mint(to, amount);
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

    function setMaxHolderCount(uint256 maxHolders) external onlyIssuanceManager {
        CyberScripStorage.StorageData storage s = CyberScripStorage.getStorageData();
        s.maxHolderCount = maxHolders;
        emit MaxHolderCountUpdated(maxHolders);
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
        emit ForceTransfer(from, to, amount);
    }

    // Force burn ignoring hooks and freezes (only if feature enabled)
    function forceBurn(address account, uint256 amount) external onlyIssuanceManager {
        if (!CyberScripStorage.getStorageData().canForceBurn) revert ComplianceFeatureDisabled();
        require(account != address(0), "forceBurn: zero addr");
        ERC20Upgradeable._update(account, address(0), amount);
        emit ForceBurn(account, amount);
    }

    // ========================
    // Getter / Setter
    // ========================

    function certPrinter() external view returns (address) {
        return CyberScripStorage.getStorageData().certPrinter;
    }

    function issuanceManager() external view returns (address) {
        return CyberScripStorage.getStorageData().issuanceManager;
    }

    function transferRestrictionHooks(uint256 i) external view returns (ITransferRestrictionHook) {
        return CyberScripStorage.getStorageData().transferRestrictionHooks[i];
    }

    function transferRestrictionHooksLength() external view returns (uint256) {
        return CyberScripStorage.getStorageData().transferRestrictionHooks.length;
    }

    function canForceTransfer() external view returns (bool) {
        return CyberScripStorage.getStorageData().canForceTransfer;
    }

    function canForceBurn() external view returns (bool) {
        return CyberScripStorage.getStorageData().canForceBurn;
    }

    function canFreeze() external view returns (bool) {
        return CyberScripStorage.getStorageData().canFreeze;
    }

    function frozen(address account) external view returns (bool) {
        return CyberScripStorage.getStorageData().frozen[account];
    }

    function holderCount() external view returns (uint256) {
        return CyberScripStorage.getStorageData().holderCount;
    }

    function maxHolderCount() external view returns (uint256) {
        return CyberScripStorage.getStorageData().maxHolderCount;
    }

    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool) {
        CyberScripStorage.StorageData storage s = CyberScripStorage
            .getStorageData();
        if (amount == 0 || from == to) {
            return true;
        }
        if (from == address(0) || to == address(0)) {
            return true;
        }
        if (s.canFreeze) {
            if (s.frozen[from]) return false;
            if (s.frozen[to]) return false;
        }
        uint256 length = s.transferRestrictionHooks.length;
        for (uint256 i = 0; i < length; i++) {
            (bool allowed, ) = s.transferRestrictionHooks[i]
                .checkTransferRestriction(from, to, amount, "");
            if (!allowed) return false;
        }

        uint256 fromBalanceBefore = balanceOf(from);
        uint256 toBalanceBefore = balanceOf(to);
        uint256 holderDelta = s.holderCount;
        bool decrementHolder = fromBalanceBefore == amount;
        bool incrementHolder = toBalanceBefore == 0;
        if (decrementHolder) {
            holderDelta -= 1;
        }
        if (incrementHolder) {
            holderDelta += 1;
        }
        if (s.maxHolderCount > 0 && holderDelta > s.maxHolderCount) {
            return false;
        }
        return true;
    }

    function willCreateNewHolder(
        address to,
        uint256 amount
    ) external view returns (bool) {
        if (amount == 0 || to == address(0)) {
            return false;
        }
        return balanceOf(to) == 0;
    }

    function currentHolderCount() external view returns (uint256) {
        return CyberScripStorage.getStorageData().holderCount;
    }

    function remainingSlots() external view returns (uint256) {
        CyberScripStorage.StorageData storage s = CyberScripStorage
            .getStorageData();
        if (s.maxHolderCount == 0) {
            return type(uint256).max;
        }
        if (s.holderCount >= s.maxHolderCount) {
            return 0;
        }
        return s.maxHolderCount - s.holderCount;
    }
}
