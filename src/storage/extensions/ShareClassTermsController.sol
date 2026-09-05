// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../interfaces/ILedgerEntryToken.sol";
import "../../interfaces/IIssuanceManager.sol";
import "../../interfaces/IShareClassTermsController.sol";
import "../../interfaces/IShareClassTermsExtension.sol";
import "../../libs/auth.sol";
import "../LedgerEntryTokenStorage.sol";
import "./ICertificateExtension.sol";

/// @notice Share extension facade and canonical class-terms accounting controller.
/// @dev LedgerEntryToken v4 is already at the EIP-170 size ceiling. This contract
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
            ILedgerEntryToken(certPrinter).totalSupply() != 0
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
            if (ILedgerEntryToken(certPrinter).totalSupply() != 0) {
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

    /// @notice Books the buyer's replacement lot at secondary settlement.
    /// @dev The buyer inherits the seller's terms snapshot: a transfer passes title to shares
    ///      issued under their original terms, it is not a re-issuance under amended ones. So the
    ///      lot's terms must match the canonical hash or the SELLER lot's current snapshot, and
    ///      anything else is a mismatch. Units are cap-checked on increase; the seller-side
    ///      decrement booked in the same transaction keeps the trade issued-units neutral.
    function accountTransferMint(
        address certPrinter,
        uint256 fromTokenId,
        bytes calldata extensionData,
        uint256 units
    ) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();
        _validateClassTermsForUpdate(
            state, extensionData, ILedgerEntryToken(certPrinter).getActiveCertificateDetails(fromTokenId).extensionData
        );
        _increaseIssuedUnits(state, units);
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

        ILedgerEntryToken printer = ILedgerEntryToken(certPrinter);
        CertificateDetails memory current = printer.getActiveCertificateDetails(tokenId);
        _validateClassTermsForUpdate(state, extensionData, current.extensionData);
        // Representation-only updates (changesIssuedUnits = false, e.g. scripify and recert)
        // stop at the relaxed validation: their unit movements are vault-side and already
        // counted, so effective growth there is not issuance.
        if (!changesIssuedUnits) return;

        uint256 oldUnits = _effectiveUnits(certPrinter, tokenId, current.unitsRepresented);
        uint256 newUnits = _effectiveUnits(certPrinter, tokenId, activeUnits);
        if (newUnits > oldUnits) {
            // Growing a lot IS new issuance, and amendments bind new issuance: an increase must
            // carry the CANONICAL terms, or 99 fresh units could ride into an old one-unit lot
            // with grandfathered economic rights. Validated BEFORE the voided early-return: a
            // voided lot can be grown by assignCert and its larger quantity becomes active at
            // unvoid, which cap-checks but deliberately does not validate terms.
            _validateClassTerms(state, extensionData);
        }
        // A voided lot's accounting stays deferred until unvoid restores it (cap-checked there);
        // the growth validation above has already run.
        if (printer.isVoided(tokenId)) return;
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

        ILedgerEntryToken printer = ILedgerEntryToken(certPrinter);
        if (printer.isVoided(tokenId)) revert CertificateAlreadyVoided();
        // Release only the certificate's ACTIVE units. Units represented by still-circulating
        // scrip stay counted against the cap: voiding the certificate does not extinguish the
        // ERC20, so freeing its scripified units would let the class issue past authorization.
        state.issuedUnits -= printer.getActiveCertificateDetails(tokenId).unitsRepresented;
    }

    function restoreCertificateUnits(address certPrinter, uint256 tokenId) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();

        ILedgerEntryToken printer = ILedgerEntryToken(certPrinter);
        if (!printer.isVoided(tokenId)) revert CertificateNotVoided();
        // No terms validation: the certificate's snapshot was validated at issuance, and a later
        // amendment must not make its unvoid revert — amendments bind new issuance, they do not
        // retroactively rewrite certificates issued under the previous terms.
        // Restore only the ACTIVE units, mirroring releaseCertificateUnits: the certificate's
        // scripified units never left issuedUnits.
        _increaseIssuedUnits(state, printer.getActiveCertificateDetails(tokenId).unitsRepresented);
    }

    /// @notice Extinguishes units whose scrip representation was destroyed (force burn).
    /// @dev Scripified units are counted in issuedUnits from original issuance and survive their
    ///      certificate's void, so destroying the ERC20 is the only event that releases them.
    function releaseScripUnits(address certPrinter, uint256 units) external override {
        _requireAuthorizedControllerCall(certPrinter);
        ClassTermsState storage state = classTerms[certPrinter];
        if (!state.configured) revert ClassTermsNotConfigured();
        state.issuedUnits -= units;
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
        ILedgerEntryToken printer = ILedgerEntryToken(certPrinter);
        // The printer itself is an authorized caller: its void/unvoid path syncs the accounting
        // directly (LedgerEntryTokenStorage.syncClassTermsOnVoidStatus), whoever drove the void.
        if (msg.sender != certPrinter && printer.issuanceManager() != msg.sender) {
            revert NotPrinterIssuanceManager();
        }
        if (printer.getExtension(0) != address(this)) {
            revert PrinterUsesDifferentExtension();
        }
    }

    /// @dev KNOWN OPEN SCALE ITEM (P2 follow-up, from Codex review on PR #144): this scan walks
    ///      every certificate in one transaction with several external calls per lot. A legacy
    ///      printer with a large enough cap table cannot complete it within the block gas limit,
    ///      and the one-shot `configured` flag offers no cursor, so such a printer could never
    ///      migrate. Launch-baseline printers hold dozens of lots, far from the limit; a chunked,
    ///      resumable scan is deliberately deferred (it cannot be atomic with the manager upgrade
    ///      by definition, so it needs its own migration mode). Tracked in
    ///      notes/plans/protocol-improvement-plan.md.
    function _calculateOutstandingUnits(address certPrinter) private view returns (uint256 outstandingUnits) {
        ILedgerEntryToken printer = ILedgerEntryToken(certPrinter);
        uint256 supply = printer.totalSupply();
        for (uint256 i = 0; i < supply; ++i) {
            uint256 tokenId = printer.tokenByIndex(i);
            if (!printer.isVoided(tokenId)) {
                outstandingUnits += printer.getActiveCertificateDetails(tokenId).unitsRepresented;
            }
        }
        // Count the scrip vault ONCE, from the manager's exact aggregate. Per-certificate claims
        // each round down against the pool, so summing them undercounts a vault diluted by a
        // socialized withdrawal (e.g. forceScripBurn) and would seed issuedUnits below the actual
        // outstanding amount — letting later issuance breach authorizedShares. The aggregate also
        // captures voided certificates' still-circulating scrip without per-lot special-casing.
        outstandingUnits +=
            IIssuanceManager(ILedgerEntryToken(certPrinter).issuanceManager()).getScripVaultAssets(certPrinter);
    }

    function _effectiveUnits(address certPrinter, uint256 tokenId, uint256 activeUnits) private view returns (uint256) {
        address issuanceManager = ILedgerEntryToken(certPrinter).issuanceManager();
        (, uint256 scripifiedUnits,) = IIssuanceManager(issuanceManager).getCertScripifiedStatus(certPrinter, tokenId);
        return activeUnits + scripifiedUnits;
    }

    function _validateClassTerms(ClassTermsState storage state, bytes memory extensionData) private view {
        (bytes memory termsData,) = _readClassTerms(extensionData);
        if (keccak256(termsData) != state.termsHash) {
            revert ClassTermsMismatch();
        }
    }

    /// @dev An update may carry either the canonical terms or the certificate's own existing terms
    ///      snapshot. Amendments bind new issuance; they do not retroactively rewrite certificates
    ///      issued under the previous terms, so a representation-only update (scripify, recert)
    ///      that echoes the certificate's unchanged snapshot must keep working after an amendment.
    ///      Anything that matches neither is a genuine mismatch.
    function _validateClassTermsForUpdate(
        ClassTermsState storage state,
        bytes memory extensionData,
        bytes memory currentExtensionData
    ) private view {
        (bytes memory termsData,) = _readClassTerms(extensionData);
        bytes32 newHash = keccak256(termsData);
        if (newHash == state.termsHash) return;
        (bytes memory currentTerms,) = _readClassTerms(currentExtensionData);
        if (newHash != keccak256(currentTerms)) revert ClassTermsMismatch();
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
