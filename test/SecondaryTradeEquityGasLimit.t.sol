// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CertificateDetails, ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
import {ShareCertDataLayerLib} from "../src/storage/extensions/ShareCertDataLayerLib.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {ExemptionPathway} from "../src/storage/SecondaryTradeStorage.sol";
import {REAL_WORLD_IPFS_URI, RealWorldShareCert} from "./libs/RealWorldShareCert.sol";
import {SecondaryTradeGasBase} from "./libs/SecondaryTradeGasBase.sol";

/// @notice Secondary-trade gas baseline for **cyberCORP equity**: a resale of preferred stock a cyberCORP
///         issued through cyberRAISE. The printer carries the six real restricted-securities legends and
///         each lot carries the ~13 KB `ShareCertData` payload, both copied from a mainnet issuance.
///
/// This is the guard for printers bound to the legacy `ShareExtension`, which keeps the whole payload on
/// every cert. Layering does not change a payload that is already stored, so those lots keep this cost
/// and can still be secondary-traded. Per `cyberTRADE_spec_v3.55.dev0` §2 the cyberTRADE product trades
/// SPV interests, not equity, so this case arises when a cyberCORP secondary-trades its own stock. The
/// code permits it. The spec does not scope it.
///
/// Its sibling is `SecondaryTradeFundInterestGasLimit.t.sol`. Everything except the printer is identical
/// in both, so the difference between them is the cost of the security's own data.
///
/// Each test checks the Glamsterdam limits in `GasBudget`: execution gas <= 90% of the EIP-7825 cap, and
/// total gas <= 90% of the expected block gas limit (200,000,000).
///
/// Measured baseline, Glamsterdam gas. Per-lot data: 13,984-byte payload, 6 legends totalling 3,321 bytes.
/// | pathway           | postOffer | acceptOffer | finalize   | finalize execution | finalize % of limit |
/// |-------------------|-----------|-------------|------------|--------------------|---------------------|
/// | Rule 144          | 5,104,626 | 8,078,859   | 64,687,512 | 9,748,793          | 32.3%               |
/// | Section 4(a)(7)   | 5,104,638 | 7,083,111   | 64,623,564 | 9,684,845          | 32.3%               |
/// | Section 4(a)(1/2) | 5,104,626 | 7,052,210   | 64,570,663 | 9,631,944          | 32.3%               |
/// | Regulation S      | 5,104,638 | 7,493,530   | 65,371,220 | 9,747,061          | 32.7%               |
///
/// Posting pinned to Rule 144 costs 6,342,643, because `HoldingPeriodCondition` reads the whole payload
/// into memory before it tests the extension type. An equity printer is not a fund printer, so the
/// condition then discards the payload. That load also warms the slots the mint later writes.
///
/// `SecondaryTradeEquityLayeredGasLimitTest` below is the same trade with the same data, split into
/// layers, and it is the shape a new issuance must use.
/// forge-config: default.isolate = true
contract SecondaryTradeEquityGasLimitTest is SecondaryTradeGasBase {
    ShareExtension internal shareExtension;

    function setUp() public {
        _setUpGasScenario();
    }

    function _securityDescription() internal pure override returns (string memory) {
        return "Series Seed 2 Preferred Stock - MetaLeX Labs, Inc.";
    }

    function _deployPrinter() internal override {
        BorgAuth shareAuth = new BorgAuth(address(this));
        shareExtension = ShareExtension(
            address(
                new ERC1967Proxy(
                    _extensionImplementation(),
                    abi.encodeWithSelector(ShareExtension.initialize.selector, address(shareAuth))
                )
            )
        );

        printer = ILedgerEntryToken(
            im.createCertPrinter(
                RealWorldShareCert.legends(),
                "Seed Preferred Stock - MetaLeX Labs, Inc.",
                "MLI-SEED-PREFSTCK",
                REAL_WORLD_IPFS_URI,
                SecurityClass.PreferredStock,
                SecuritySeries.SeriesSeed,
                address(shareExtension),
                _seriesData()
            )
        );
        LedgerEntryToken(address(printer)).setLookThroughBadge(address(badge));
        CertificateDetails memory sellerCert = _baseCertDetails(POSITION_UNITS, _certExtensionData());
        sellerTokenId = im.createCertAndAssign(address(printer), seller, sellerCert);
    }

    /// @dev The legacy shape: no series payload, the whole `ShareCertData` on every cert.
    function _extensionImplementation() internal virtual returns (address) {
        return address(new ShareExtension());
    }

    function _seriesData() internal pure virtual returns (bytes memory) {
        return bytes("");
    }

    function _certExtensionData() internal pure virtual returns (bytes memory) {
        return RealWorldShareCert.encodedShareCertData();
    }
}

/// @notice The same equity trade, the same real payload, stored as layers instead of one blob per cert.
///
/// The five series-wide sections of `ShareCertData` move to the printer's `seriesData`, where one copy
/// serves every cert of the series. Only `certificateData` stays on the cert. Nothing is lost: a reader
/// merges the layers back with `ShareCertDataLayerLib.resolve`, and the token URI renders the series sections
/// through `getResolvedExtensionURI`.
///
/// Settlement copies the seller's per-cert payload into a fresh Ledger Entry Token for the buyer, so the
/// size of that payload sets the cost of finalization.
///
/// Measured, Glamsterdam gas. Per-lot data: 928-byte payload against 13,984 legacy, the same 6 legends of
/// 3,321 bytes.
/// | pathway           | postOffer | acceptOffer | finalize   | finalize execution | finalize % of limit | finalize vs legacy |
/// |-------------------|-----------|-------------|------------|--------------------|---------------------|--------------------|
/// | Rule 144          | 5,104,628 | 7,170,565   | 20,608,884 | 3,761,045          | 10.3%               | -68.1%             |
/// | Section 4(a)(7)   | 5,104,640 | 7,083,111   | 20,637,230 | 3,789,391          | 10.3%               | -68.1%             |
/// | Section 4(a)(1/2) | 5,104,628 | 7,052,210   | 20,584,329 | 3,736,490          | 10.3%               | -68.1%             |
/// | Regulation S      | 5,104,640 | 7,493,531   | 21,384,865 | 3,851,586          | 10.7%               | -67.3%             |
///
/// Unpinned posting does not read the payload, so postOffer is unchanged. Posting pinned to Rule 144
/// does read it, and costs 5,434,481 against 6,342,643.
/// forge-config: default.isolate = true
contract SecondaryTradeEquityLayeredGasLimitTest is SecondaryTradeEquityGasLimitTest {
    function _extensionImplementation() internal override returns (address) {
        return address(new ShareExtensionV3());
    }

    function _seriesData() internal pure override returns (bytes memory) {
        return RealWorldShareCert.encodedSeriesLayer();
    }

    function _certExtensionData() internal pure override returns (bytes memory) {
        return RealWorldShareCert.encodedCertLayer();
    }

    /// @notice The resolved render shows the series terms, which the cert payload does not carry. The
    ///         per-scope render of the same cert payload does not, which is why the builder prefers the
    ///         resolved path.
    function test_resolvedUri_showsTermsTheCertPayloadDoesNotCarry() public view {
        ShareExtensionV3 v3 = ShareExtensionV3(address(shareExtension));
        assertTrue(v3.supportsResolvedExtensionData(), "V3 advertises the resolved path");

        string memory resolved = _asObject(v3.getResolvedExtensionURI(address(printer), sellerTokenId));
        string memory perScope =
            _asObject(v3.getExtensionURI(printer.getActiveCertificateDetails(sellerTokenId).extensionData));

        assertEq(
            vm.parseJsonString(resolved, ".shareDetails.terms.seriesName"),
            "Series Seed 2",
            "the resolved render carries the series terms"
        );
        assertEq(vm.parseJsonString(perScope, ".shareDetails.terms.seriesName"), "", "the cert scope alone carries none");
    }

    /// @dev Both renders return a fragment that starts with ", " so it can be appended to a larger
    ///      object. Wrap it to get parseable JSON.
    function _asObject(string memory fragment) internal pure returns (string memory) {
        bytes memory b = bytes(fragment);
        bytes memory out = new bytes(b.length - 2);
        for (uint256 i = 2; i < b.length; i++) {
            out[i - 2] = b[i];
        }
        return string.concat("{", string(out), "}");
    }

    /// @notice The lean lot a settlement mints still reads back as the whole security. The buyer's fresh
    ///         Ledger Entry Token carries `certificateData` alone; every other section resolves from the
    ///         printer, so the acquirer holds the same terms the seller held.
    function test_layeredLot_resolvesToTheWholeSecurity() public {
        _lifecycle("Rule 144 resale", ExemptionPathway.RULE_144, buyer, buyerKey);

        uint256 buyerTokenId = printer.tokenOfLegalOwnerByIndex(buyer, 0);
        assertEq(
            printer.getActiveCertificateDetails(buyerTokenId).extensionData.length,
            RealWorldShareCert.encodedCertLayer().length,
            "the minted lot carries the lean payload"
        );
        // One `ShareCertData` per statement. Two in one statement exceed the solc 0.8.28 stack limit.
        bytes32 resolved = keccak256(abi.encode(ShareCertDataLayerLib.resolveCert(address(printer), buyerTokenId)));
        bytes32 whole = keccak256(abi.encode(RealWorldShareCert.shareCertData()));
        assertEq(resolved, whole, "the layers merge back to the whole ShareCertData");
    }
}
