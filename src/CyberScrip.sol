
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

    error RestrictedTransfer(string reason);
    error NotIssuanceManager();

    modifier onlyIssuanceManager() {
        if (msg.sender != CyberCertPrinterStorage.cyberCertStorage().issuanceManager) revert NotIssuanceManager();
        _;
    }

    function initialize(
        address _certPrinter,
        address _issuanceManager,
        string memory _name,
        string memory _symbol,
        ITransferRestrictionHook[] memory _transferRestrictionHooks
    ) external initializer {
        __ERC20_init(_name, _symbol);
        certPrinter = _certPrinter;
        IssuanceManager = _issuanceManager;
        transferRestrictionHooks = _transferRestrictionHooks;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
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

} 