
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./libs/auth.sol";

contract CyberScrip is Initializable, ERC20Upgradeable, BorgAuthACL {
    address public certPrinter;
    address public IssuanceManager;
    ITransferRestrictionHook[] public transferRestrictionHooks;

    // Compliance feature toggles
    bool public canForceTransfer;
    bool public canForceBurn;
    bool public canFreeze;

    // Per-account freeze registry
    mapping(address => bool) public frozen;

    error RestrictedTransfer(string reason);
    error NotIssuanceManager();
    error ComplianceFeatureDisabled();
    error AccountFrozen(address account);

    event FreezeStatusUpdated(address indexed account, bool frozen);
    event ComplianceFeatureDisabledEvent(string feature);

    modifier onlyIssuanceManager() {
        if (msg.sender != IssuanceManager) revert NotIssuanceManager();
        _;
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
        certPrinter = _certPrinter;
        IssuanceManager = _issuanceManager;
        transferRestrictionHooks = _transferRestrictionHooks;
        canForceTransfer = _enableForceTransfer;
        canForceBurn = _enableForceBurn;
        canFreeze = _enableFreeze;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        // Enforce freeze checks for normal transfers (not mint/burn)
        if (from != address(0) && to != address(0)) {
            if (canFreeze) {
                if (frozen[from]) revert AccountFrozen(from);
                if (frozen[to]) revert AccountFrozen(to);
            }
            // Enforce transfer restriction hooks
            for (uint256 i = 0; i < transferRestrictionHooks.length; i++) {
                (bool allowed, string memory reason) = transferRestrictionHooks[i].checkTransferRestriction(from, to, amount, "");
                if (!allowed) revert RestrictedTransfer(reason);
            }
        }
        super._update(from, to, amount);
    }

    function burnFrom(address account, uint256 amount) public virtual onlyIssuanceManager {
        super._burn(account, amount);
    }

    function setRestrictionHook(ITransferRestrictionHook[] memory _transferRestrictionHooks) external onlyIssuanceManager {
        transferRestrictionHooks = _transferRestrictionHooks;
    }

    // ========================
    // Compliance functionality
    // ========================

    // Disable features (one-way). Cannot be re-enabled post-initialization
    function disableForceTransfer() external onlyIssuanceManager {
        if (canForceTransfer) {
            canForceTransfer = false;
            emit ComplianceFeatureDisabledEvent("forceTransfer");
        }
    }

    function disableForceBurn() external onlyIssuanceManager {
        if (canForceBurn) {
            canForceBurn = false;
            emit ComplianceFeatureDisabledEvent("forceBurn");
        }
    }

    function disableFreeze() external onlyIssuanceManager {
        if (canFreeze) {
            canFreeze = false;
            emit ComplianceFeatureDisabledEvent("freeze");
        }
    }

    // Freeze/unfreeze an account (only if freezing is enabled)
    function setFrozen(address account, bool isFrozen) external onlyIssuanceManager {
        if (!canFreeze) revert ComplianceFeatureDisabled();
        frozen[account] = isFrozen;
        emit FreezeStatusUpdated(account, isFrozen);
    }

    // Force transfer ignoring hooks and freezes (only if feature enabled)
    function forceTransfer(address from, address to, uint256 amount) external onlyIssuanceManager {
        if (!canForceTransfer) revert ComplianceFeatureDisabled();
        require(from != address(0) && to != address(0), "force: zero addr");
        // Bypass our override and hooks by calling the base ERC20 implementation directly
        ERC20Upgradeable._update(from, to, amount);
    }

    // Force burn ignoring hooks and freezes (only if feature enabled)
    function forceBurn(address account, uint256 amount) external onlyIssuanceManager {
        if (!canForceBurn) revert ComplianceFeatureDisabled();
        require(account != address(0), "forceBurn: zero addr");
        ERC20Upgradeable._update(account, address(0), amount);
    }

} 