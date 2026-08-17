// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
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
/// | Rule 144          | 1,362,186 | 2,913,663   | 13,866,092 | 82.6%               |
/// | Section 4(a)(7)   | 1,362,186 | 1,935,090   | 14,666,519 | 87.4%               |
/// | Section 4(a)(1/2) | 1,362,186 | 1,895,299   | 14,647,728 | 87.3%               |
/// | Regulation S      | 1,362,186 | 1,993,344   | 14,813,716 | 88.3%               |
///
/// Posting pinned to Rule 144 costs 2,505,043, because `HoldingPeriodCondition` loads the whole payload
/// looking for a tacking anchor. That load also warms the slots the mint later writes, which is why the
/// Rule 144 finalize is the cheapest of the four.
///
/// Finalize has roughly 285,000 gas of margin under the assertion. A new condition, or a larger payload,
/// can exceed the limit.
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
                    address(new ShareExtension()),
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
                bytes("")
            )
        );
        LedgerEntryToken(address(printer)).setLookThroughBadge(address(badge));
        sellerTokenId = im.createCertAndAssign(
            address(printer), seller, _baseCertDetails(POSITION_UNITS, RealWorldShareCert.encodedShareCertData())
        );
    }
}
