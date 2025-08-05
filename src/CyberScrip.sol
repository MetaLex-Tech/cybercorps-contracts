
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITransferRestrictionHook.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./libs/auth.sol";

contract CyberScrip is Initializable, ERC20Upgradeable, BorgAuthACL {
    address public certPrinter;
    uint256 public underlyingTokenId;
    bool public transferable;
    address public IssuanceManager;
    ITransferRestrictionHook[] public typeRestrictionHook;

    error NotTransferable();
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
        ITransferRestrictionHook[] memory _typeRestrictionHook
    ) external initializer {
        __ERC20_init(_name, _symbol);
        certPrinter = _certPrinter;
        IssuanceManager = _issuanceManager;
        typeRestrictionHook = _typeRestrictionHook;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
            if (!transferable) revert NotTransferable();

            for (uint256 i = 0; i < typeRestrictionHook.length; i++) {
                (bool allowed, string memory reason) = typeRestrictionHook[i].checkTransferRestriction(from, to, amount, "");
                if (!allowed) revert RestrictedTransfer(reason);
            }
        }
        super._update(from, to, amount);
    }

    function setRestrictionHook(ITransferRestrictionHook[] memory _typeRestrictionHook) external onlyIssuanceManager {
        typeRestrictionHook = _typeRestrictionHook;
    }

} 