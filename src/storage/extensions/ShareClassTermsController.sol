// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../interfaces/ICyberCertPrinter.sol";
import "../../interfaces/IIssuanceManager.sol";
import "../../interfaces/IShareClassTermsController.sol";
import "../../interfaces/IShareClassTermsExtension.sol";
import "../../libs/auth.sol";
import "../CyberCertPrinterStorage.sol";
import "./ICertificateExtension.sol";

/// @notice Share extension facade and canonical class-terms accounting controller.
/// @dev CyberCertPrinter v4 is already at the EIP-170 size ceiling. This contract
///      keeps enforcement in a separately upgradeable component while the
///      IssuanceManager remains the only mutating path into a printer.
contract ShareClassTermsController is
    UUPSUpgradeable,
    ICertificateExtension,
    IShareClassTermsExtension,
    IShareClassTermsController,
    BorgAuthACL
{
    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    string public constant DEPLOY_VERSION = "1";

    error NotPrinterIssuanceManager();
    error PrinterUsesDifferentExtension();
    error InvalidRenderer();
    error InvalidShareExtensionData();
    error ClassTermsNotConfigured();
    error ClassTermsAlreadyConfigured();
    error ClassTermsMismatch();
    error AuthorizedSharesExceeded(uint256 authorizedShares, uint256 attemptedIssuedUnits);
    error AuthorizedSharesBelowIssued(uint256 authorizedShares, uint256 issuedUnits);
    error CertificateAlreadyVoided();
    error CertificateNotVoided();

    event RendererSet(address indexed renderer);
    event ClassTermsConfigured(
        address indexed certPrinter,
        bytes32 indexed termsHash,
        uint256 authorizedShares,
        uint256 issuedUnits,
        bool migrated
    );
    event ClassTermsAmended(
        address indexed certPrinter,
        bytes32 indexed previousTermsHash,
        bytes32 indexed newTermsHash,
        uint256 authorizedShares
    );

    struct ClassTermsState {
        bytes termsData;
        bytes32 termsHash;
        uint256 authorizedShares;
        uint256 issuedUnits;
        bool configured;
    }

    address public renderer;
    mapping(address certPrinter => ClassTermsState) private classTerms;
    uint256[48] private __gap;

    constructor() {
        _disableInitializers();
    }

    function initialize(address auth, address renderer_) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(auth);
        _setRenderer(renderer_);
    }

    function setRenderer(address renderer_) external onlyOwner {
        _setRenderer(renderer_);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        return ICertificateExtension(renderer).getExtensionURI(data);
    }

    function getSeriesTermsData(bytes calldata extensionData)
        external
        view
        override
        returns (bytes memory termsData, uint256 authorizedShares)
    {
        return IShareClassTermsExtension(renderer).getSeriesTermsData(extensionData);
    }

    function configureClassTerms(address certPrinter, bytes calldata extensionData) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (state.configured) revert ClassTermsAlreadyConfigured();

        (bytes memory termsData, uint256 authorizedShares) = _readClassTerms(extensionData);
        uint256 issuedUnits = _calculateOutstandingUnits(certPrinter);
        if (issuedUnits > authorizedShares) {
            revert AuthorizedSharesExceeded(authorizedShares, issuedUnits);
        }

        _storeClassTerms(state, termsData, authorizedShares);
        state.issuedUnits = issuedUnits;
        emit ClassTermsConfigured(
            certPrinter,
            state.termsHash,
            authorizedShares,
            issuedUnits,
            ICyberCertPrinter(certPrinter).totalSupply() != 0
        );
    }

    function amendClassTerms(address certPrinter, bytes calldata extensionData) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();

        (bytes memory termsData, uint256 authorizedShares) = _readClassTerms(extensionData);
        if (authorizedShares < state.issuedUnits) {
            revert AuthorizedSharesBelowIssued(authorizedShares, state.issuedUnits);
        }

        bytes32 previousTermsHash = state.termsHash;
        _storeClassTerms(state, termsData, authorizedShares);
        emit ClassTermsAmended(certPrinter, previousTermsHash, state.termsHash, authorizedShares);
    }

    function accountNewIssuance(
        address certPrinter,
        bytes calldata extensionData,
        uint256 units,
        bool increasesIssuedUnits
    ) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];

        if (!state.configured) {
            if (ICyberCertPrinter(certPrinter).totalSupply() != 0) {
                revert ClassTermsNotConfigured();
            }
            (bytes memory termsData, uint256 authorizedShares) = _readClassTerms(extensionData);
            _storeClassTerms(state, termsData, authorizedShares);
            emit ClassTermsConfigured(certPrinter, state.termsHash, authorizedShares, 0, false);
        } else {
            _validateClassTerms(state, extensionData);
        }

        if (increasesIssuedUnits) {
            _increaseIssuedUnits(state, units);
        }
    }

    function accountCertificateUpdate(
        address certPrinter,
        uint256 tokenId,
        bytes calldata extensionData,
        uint256 activeUnits,
        bool changesIssuedUnits
    ) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();
        _validateClassTerms(state, extensionData);

        ICyberCertPrinter printer = ICyberCertPrinter(certPrinter);
        if (!changesIssuedUnits || printer.isVoided(tokenId)) return;

        uint256 oldUnits =
            _effectiveUnits(certPrinter, tokenId, printer.getActiveCertificateDetails(tokenId).unitsRepresented);
        uint256 newUnits = _effectiveUnits(certPrinter, tokenId, activeUnits);
        if (newUnits > oldUnits) {
            _increaseIssuedUnits(state, newUnits - oldUnits);
        } else if (oldUnits > newUnits) {
            state.issuedUnits -= oldUnits - newUnits;
        }
    }

    function releaseCertificateUnits(address certPrinter, uint256 tokenId) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();

        ICyberCertPrinter printer = ICyberCertPrinter(certPrinter);
        if (printer.isVoided(tokenId)) revert CertificateAlreadyVoided();
        state.issuedUnits -= _effectiveUnits(
            certPrinter, tokenId, printer.getActiveCertificateDetails(tokenId).unitsRepresented
        );
    }

    function restoreCertificateUnits(address certPrinter, uint256 tokenId) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();

        ICyberCertPrinter printer = ICyberCertPrinter(certPrinter);
        if (!printer.isVoided(tokenId)) revert CertificateNotVoided();
        CertificateDetails memory details = printer.getActiveCertificateDetails(tokenId);
        _validateClassTerms(state, details.extensionData);
        _increaseIssuedUnits(state, _effectiveUnits(certPrinter, tokenId, details.unitsRepresented));
    }

    function getClassTerms(address certPrinter)
        external
        view
        override
        returns (
            bytes memory termsData,
            bytes32 termsHash,
            uint256 authorizedShares,
            uint256 issuedUnits,
            bool configured
        )
    {
        ClassTermsState storage state = classTerms[certPrinter];
        return (state.termsData, state.termsHash, state.authorizedShares, state.issuedUnits, state.configured);
    }

    function _requireAuthorizedControllerCall(address certPrinter) private view {
        ICyberCertPrinter printer = ICyberCertPrinter(certPrinter);
        if (printer.issuanceManager() != msg.sender) {
            revert NotPrinterIssuanceManager();
        }
        if (printer.getExtension(0) != address(this)) {
            revert PrinterUsesDifferentExtension();
        }
    }

    function _calculateOutstandingUnits(address certPrinter) private view returns (uint256 outstandingUnits) {
        ICyberCertPrinter printer = ICyberCertPrinter(certPrinter);
        uint256 supply = printer.totalSupply();
        for (uint256 i = 0; i < supply; ++i) {
            uint256 tokenId = printer.tokenByIndex(i);
            if (!printer.isVoided(tokenId)) {
                outstandingUnits += _effectiveUnits(
                    certPrinter, tokenId, printer.getActiveCertificateDetails(tokenId).unitsRepresented
                );
            }
        }
    }

    function _effectiveUnits(address certPrinter, uint256 tokenId, uint256 activeUnits) private view returns (uint256) {
        address issuanceManager = ICyberCertPrinter(certPrinter).issuanceManager();
        (, uint256 scripifiedUnits,) = IIssuanceManager(issuanceManager).getCertScripifiedStatus(certPrinter, tokenId);
        return activeUnits + scripifiedUnits;
    }

    function _validateClassTerms(ClassTermsState storage state, bytes memory extensionData) private view {
        (bytes memory termsData,) = _readClassTerms(extensionData);
        if (keccak256(termsData) != state.termsHash) {
            revert ClassTermsMismatch();
        }
    }

    function _increaseIssuedUnits(ClassTermsState storage state, uint256 units) private {
        uint256 attemptedIssuedUnits = state.issuedUnits + units;
        if (attemptedIssuedUnits > state.authorizedShares) {
            revert AuthorizedSharesExceeded(state.authorizedShares, attemptedIssuedUnits);
        }
        state.issuedUnits = attemptedIssuedUnits;
    }

    function _storeClassTerms(ClassTermsState storage state, bytes memory termsData, uint256 authorizedShares) private {
        state.termsData = termsData;
        state.termsHash = keccak256(termsData);
        state.authorizedShares = authorizedShares;
        state.configured = true;
    }

    function _readClassTerms(bytes memory extensionData)
        private
        view
        returns (bytes memory termsData, uint256 authorizedShares)
    {
        if (extensionData.length == 0) revert InvalidShareExtensionData();
        try IShareClassTermsExtension(renderer).getSeriesTermsData(extensionData) returns (
            bytes memory extractedTerms, uint256 extractedAuthorized
        ) {
            if (extractedTerms.length == 0) {
                revert InvalidShareExtensionData();
            }
            return (extractedTerms, extractedAuthorized);
        } catch {
            revert InvalidShareExtensionData();
        }
    }

    function _setRenderer(address renderer_) private {
        if (renderer_.code.length == 0) revert InvalidRenderer();
        renderer = renderer_;
        emit RendererSet(renderer_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
