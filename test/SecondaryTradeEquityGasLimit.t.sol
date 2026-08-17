// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {ShareLayerLib} from "../src/storage/extensions/ShareLayerLib.sol";
import {ExemptionPathway} from "../src/storage/SecondaryTradeStorage.sol";
import {REAL_WORLD_IPFS_URI, RealWorldShareCert} from "./libs/RealWorldShareCert.sol";
import {SecondaryTradeGasBase} from "./libs/SecondaryTradeGasBase.sol";

/// @notice Secondary-trade gas baseline for **cyberCORP equity**: a resale of preferred stock a cyberCORP
///         issued through cyberRAISE. The printer carries the six real restricted-securities legends and
///         each lot carries the ~13 KB `ShareCertData` payload, both copied from a mainnet issuance.
///
/// This is the heavier of the two baselines, and it is the one to watch. Per `cyberTRADE_spec_v3.55.dev0`
/// §2 the cyberTRADE product trades SPV interests, not equity, so this case arises when a cyberCORP
/// secondary-trades its own stock. The code permits it. The spec does not scope it.
///
/// Its sibling is `SecondaryTradeFundInterestGasLimit.t.sol`. Everything except the printer is identical
/// in both, so the difference between them is the cost of the security's own data.
///
/// Each test asserts gas <= 90% of the EIP-7825 block gas limit (16,777,216).
///
/// Measured baseline. Per-lot data: 13,984-byte payload, 6 legends totalling 3,321 bytes.
/// | pathway           | postOffer | acceptOffer | finalize   | finalize % of limit |
/// |-------------------|-----------|-------------|------------|---------------------|
/// | Rule 144          | 1,362,186 | 2,913,648   | 13,866,077 | 82.6%               |
/// | Section 4(a)(7)   | 1,362,186 | 1,935,090   | 14,666,519 | 87.4%               |
/// | Section 4(a)(1/2) | 1,362,186 | 1,895,299   | 14,647,728 | 87.3%               |
/// | Regulation S      | 1,362,186 | 1,993,343   | 14,813,716 | 88.3%               |
///
/// Posting pinned to Rule 144 costs 2,505,028, because `HoldingPeriodCondition` loads the whole payload
/// looking for a tacking anchor. That load also warms the slots the mint later writes, which is why the
/// Rule 144 finalize is the cheapest of the four.
///
/// Finalize has roughly 285,000 gas of margin under the assertion. A new condition, or a larger payload,
/// can exceed the limit. `SecondaryTradeEquityLayeredGasLimitTest` below is the same trade with the same
/// data, split into layers, and it is the shape a new issuance should use.
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
        sellerTokenId =
            im.createCertAndAssign(address(printer), seller, _baseCertDetails(POSITION_UNITS, _certExtensionData()));
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
/// merges the layers back with `ShareLayerLib.resolve`, and the token URI renders the series sections
/// through `getSeriesExtensionURI`.
///
/// Settlement copies the seller's per-cert payload into a fresh Ledger Entry Token for the buyer, so the
/// size of that payload sets the cost of finalization.
///
/// Measured. Per-lot data: 832-byte payload against 13,984 legacy, the same 6 legends of 3,321 bytes.
/// | pathway           | postOffer | acceptOffer | finalize  | finalize % of limit | finalize vs legacy |
/// |-------------------|-----------|-------------|-----------|---------------------|--------------------|
/// | Rule 144          | 1,362,187 | 1,998,674   | 4,818,413 | 28.7%               | -65.3%             |
/// | Section 4(a)(7)   | 1,362,187 | 1,935,091   | 4,889,830 | 29.1%               | -66.7%             |
/// | Section 4(a)(1/2) | 1,362,187 | 1,895,300   | 4,871,039 | 29.0%               | -66.7%             |
/// | Regulation S      | 1,362,187 | 1,993,344   | 5,037,008 | 30.0%               | -66.0%             |
///
/// Unpinned posting does not read the payload, so postOffer is unchanged. Posting pinned to Rule 144
/// does read it, and costs 1,590,185 against 2,505,028.
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
        assertEq(
            keccak256(abi.encode(ShareLayerLib.resolveCert(address(printer), buyerTokenId))),
            keccak256(abi.encode(RealWorldShareCert.shareCertData())),
            "the layers merge back to the whole ShareCertData"
        );
    }
}
