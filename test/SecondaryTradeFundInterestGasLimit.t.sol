// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {ExemptionPathway, PostOfferParams} from "../src/storage/SecondaryTradeStorage.sol";
import {
    FundInterestData,
    FundInterestExtension,
    FundInterestSeriesData,
    SecurityIdentification
} from "../src/storage/extensions/FundInterestExtension.sol";
import {SecondaryTradeGasBase} from "./libs/SecondaryTradeGasBase.sol";
import {console2} from "forge-std/Test.sol";

/// @notice Secondary-trade gas baseline for an **SPV fund interest**, which is the cyberTRADE product case.
///         Per `cyberTRADE_spec_v3.55.dev0` §2 the traded security is an LLC or LP interest in a
///         single-asset SPV that holds equity in a private company. The portfolio company is not on the
///         protocol, so only the interest is tokenized.
///
/// The SPV here is a Delaware LLC holding Series C preferred of one portfolio company, relying on ICA
/// §3(c)(1). The printer carries the four legends an SPV operating agreement produces, and each lot
/// carries a `FundInterestData` payload. The printer's `seriesData` carries `FundInterestSeriesData`;
/// this is the only test in the repository that populates the series-scope payload.
///
/// Its sibling is `SecondaryTradeEquityGasLimit.t.sol`. Everything except the printer is identical in
/// both, so the difference between them is the cost of the security's own data.
///
/// Each test asserts gas <= 90% of the EIP-7825 block gas limit (16,777,216).
///
/// Measured baseline. Per-lot data: 288-byte payload, 4 legends totalling 867 bytes. The series payload
/// is 1,632 bytes and is written once for the printer, so it never appears in a settlement.
/// | pathway           | postOffer | acceptOffer | finalize  | finalize % of limit |
/// |-------------------|-----------|-------------|-----------|---------------------|
/// | Rule 144          | 1,362,193 | 1,963,981   | 2,608,952 | 15.6%               |
/// | Section 4(a)(7)   | 1,362,193 | 1,935,095   | 2,647,066 | 15.8%               |
/// | Section 4(a)(1/2) | 1,362,193 | 1,895,304   | 2,628,275 | 15.7%               |
/// | Regulation S      | 1,362,193 | 1,993,348   | 2,794,241 | 16.7%               |
///
/// Posting pinned to Rule 144 costs 1,555,496.
///
/// Settlement costs about one fifth of the equity case: 2.79 M against 14.81 M in the worst pathway.
/// Posting and acceptance are within a few percent of each other, because neither depends much on payload
/// size. The whole difference is at finalize, where the acquirer's lot is minted.
///
/// Note when reading the tacked-anchor tests: they call the tacking setter during the test, which warms
/// the certificate's storage slots. Their posting figures are therefore lower than the plain ones, and
/// that difference is warm-slot accounting, not a real saving.
contract SecondaryTradeFundInterestGasLimitTest is SecondaryTradeGasBase {
    FundInterestExtension internal fundExtension;

    /// @dev In-kind distributions let an SPV member tack under Rule 144(d)(3), so a fund lot can carry an
    /// anchor earlier than its own acquisition. Only a FundInterest printer can express this. The anchor
    /// must be earlier than the lot's own acquisition, or the condition discards it.
    uint64 internal constant TACKED_FROM_OFFSET = 200 days;

    /// @dev The tacking anchor for the seller's lot: `SEASONING` days before the lot was acquired, so it
    /// really is the governing anchor. The baseline seasons the lot past the hold anyway, so this measures
    /// the cost of the branch. `HoldingPeriodCondition.t.sol` covers the behaviour, where the base anchor is
    /// short of the hold and only the tacked anchor clears it.
    function _tackedAnchor() internal view returns (uint64) {
        return printer.acquisitionTimestamp(sellerTokenId) - TACKED_FROM_OFFSET;
    }

    function setUp() public {
        _setUpGasScenario();
    }

    function _securityDescription() internal pure override returns (string memory) {
        return "Class A Member Interest - Blue Harbour SPV I, LLC";
    }

    /// @dev The legends an SPV operating agreement produces. Shorter and fewer than an equity charter's,
    /// which is most of why this baseline settles for less.
    function _spvLegends() internal pure returns (string[] memory legend) {
        legend = new string[](4);
        legend[0] = "RESTRICTED SECURITIES LEGEND. THE MEMBER INTERESTS REPRESENTED HEREBY ARE \"RESTRICTED "
            "SECURITIES\" AS DEFINED IN SEC RULE 144 AND HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF "
            "1933, AS AMENDED.";
        legend[1] = "INVESTMENT COMPANY ACT LEGEND. THE COMPANY IS NOT REGISTERED UNDER THE INVESTMENT COMPANY ACT "
            "OF 1940 IN RELIANCE ON SECTION 3(c)(1). TRANSFERS THAT WOULD CAUSE THE COMPANY TO EXCEED THE "
            "PERMITTED NUMBER OF BENEFICIAL OWNERS ARE VOID.";
        legend[2] = "OPERATING AGREEMENT TRANSFER RESTRICTION LEGEND. THE MEMBER INTERESTS MAY NOT BE TRANSFERRED, "
            "PLEDGED OR HYPOTHECATED WITHOUT THE PRIOR WRITTEN CONSENT OF THE MANAGING MEMBER, AND ARE SUBJECT "
            "TO THE RIGHT OF FIRST REFUSAL SET OUT IN THE OPERATING AGREEMENT.";
        legend[3] = "NO PUBLIC MARKET LEGEND. THERE IS NO PUBLIC MARKET FOR THE MEMBER INTERESTS AND NONE IS "
            "EXPECTED TO DEVELOP. THE COMPANY IS UNDER NO OBLIGATION TO REGISTER THE MEMBER INTERESTS.";
    }

    /// @dev Series-scope payload: the terms every lot of this printer shares. Written once, never copied.
    function _seriesData() internal pure returns (bytes memory) {
        string[] memory docs = new string[](3);
        docs[0] = "ipfs://bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";
        docs[1] = "ipfs://bafybeigd7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";
        docs[2] = "ipfs://bafybeihk9knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

        return abi.encode(
            FundInterestSeriesData({
                interestClass: "Class A Member Interest",
                fundEntityType: "Delaware limited liability company",
                icaExceptionRelied: "Section 3(c)(1)",
                managementFeeRateBps: 200,
                carriedInterestRateBps: 2_000,
                distributionWaterfallPosition: "Pro rata after return of capital and preferred return",
                governingDocumentURIs: docs,
                securityIdentification: SecurityIdentification({
                    securityID: "88-1234567",
                    securityIDSource: "EIN",
                    securityType: "FUND",
                    securityDesc: "Class A Member Interest in Blue Harbour SPV I, LLC",
                    issuer: "Blue Harbour SPV I, LLC"
                })
            })
        );
    }

    /// @dev Per-lot payload. The acquisition and tacking anchors are left zero here: the base
    /// `acquisitionTimestamp` mapping is the authoritative anchor, and the tacking anchor is written
    /// through the printer's admin setter, not through this payload.
    function _lotData() internal pure returns (bytes memory) {
        FundInterestData memory fid;
        fid.customProvisions = "Side letter: quarterly reporting; no transfer to a competing fund manager.";
        return abi.encode(fid);
    }

    function _deployPrinter() internal override {
        fundExtension = FundInterestExtension(
            _proxy(
                address(new FundInterestExtension()), abi.encodeCall(FundInterestExtension.initialize, (address(auth)))
            )
        );

        // SecurityClass has no member-interest or LP-interest entry, so a fund printer must borrow one of
        // the equity entries. See specs/analysis/cert-payload-and-tacking-conflicts.md.
        printer = ILedgerEntryToken(
            im.createCertPrinter(
                _spvLegends(),
                "Class A Member Interest - Blue Harbour SPV I, LLC",
                "BH-SPV-I-A",
                "ipfs://bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(fundExtension),
                _seriesData()
            )
        );
        LedgerEntryToken(address(printer)).setLookThroughBadge(address(badge));
        sellerTokenId = im.createCertAndAssign(address(printer), seller, _baseCertDetails(POSITION_UNITS, _lotData()));
    }

    // ── Fund-only path ────────────────────────────────────────────────────────

    /// @notice A lot whose Rule 144 anchor was tacked from an earlier in-kind distribution. Only a
    ///         FundInterest printer reaches this branch: `HoldingPeriodCondition` decodes the payload for
    ///         the tacking anchor only when the extension advertises `FUND_INTEREST`.
    function test_gasLimit_lifecycle_rule144_withTackedAnchor() public {
        LedgerEntryToken(address(printer)).updateCertificateTackedFromAcquisitionDate(sellerTokenId, _tackedAnchor());
        _lifecycle("Rule 144 resale, tacked anchor", ExemptionPathway.RULE_144, buyer, buyerKey);
    }

    /// @notice Posting pinned to Rule 144 with a tacked anchor, which is the read that touches the payload
    ///         at posting time.
    function test_gasLimit_postOffer_pinnedToRule144_withTackedAnchor() public {
        LedgerEntryToken(address(printer)).updateCertificateTackedFromAcquisitionDate(sellerTokenId, _tackedAnchor());
        PostOfferParams memory p = _sellParams(ExemptionPathway.RULE_144, POSITION_UNITS, "pinned tacked offer");
        (, uint256 gasUsed) = _measurePost(p);
        _assertUnderLimit("postOffer (pinned Rule 144, tacked) gas:", gasUsed);
    }

    /// @notice Reports the series-scope payload size alongside the per-lot sizes. It is written once for
    ///         the whole printer, so it never appears in a settlement.
    function test_report_seriesDataSize() public view {
        (, bytes memory seriesData) = LedgerEntryToken(address(printer)).getSeriesInfo();
        console2.log("series payload bytes (written once per printer):", seriesData.length);
    }
}
