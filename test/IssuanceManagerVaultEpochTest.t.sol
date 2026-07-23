// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/LedgerEntryToken.sol";
import "../src/CyberScrip.sol";
import "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import "../src/libs/auth.sol";
import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockCyberCorpForIM, MockUriBuilderForIM} from "./IssuanceManagerTest.t.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Scenario matrix — scrip-unit vault epoch reset
//
// The vault empties whenever pool.totalAssetsWad hits exactly 0, at which point _resetVaultPositions bumps
// pool.vaultEpoch instead of walking the printer's token supply. Two things must hold on every path there:
// the reset is O(1), and every outstanding position is retired so it cannot claim shares in the pool funded
// next. Layer 1 is which call empties the vault; layer 2 is what happens afterwards.
//
// Emptying trigger                    | Reached via                    | Test
// ------------------------------------|--------------------------------|-------------------------------------
// Redeem down to zero                 | convertScripToCert, units <=   | CostIsFlatInTotalSupply
//                                     | the converter's own claim      | InvalidatesPositionsAcrossAnEmptying
// Socialized withdrawal to zero       | convertScripToCert, units >    | EmptyingViaWithdrawal_
//                                     | claim: redeem then dilute      | RetiresOtherParticipant
// Admin burn to zero                  | forceScripBurn                 | EmptyingViaForceScripBurn_
//                                     |                                | RetiresPositions
// Not triggered (dust left)           | convertScripToCert, balance-1  | FullAndPartialConversion_
//                                     |                                | CostAboutTheSame
//
// Post-reset behaviour                                        | Test
// ------------------------------------------------------------|--------------------------------------------
// Refill by a cert that never participated                    | InvalidatesPositionsAcrossAnEmptying
// Refill by the cert whose position was just retired          | RetiredCertCanScripifyAgain
// Refill after the refiller's position was diluted away       | EmptyingViaWithdrawal_RetiresOtherParticipant
// Repeated empty/refill cycles (epoch keeps advancing)        | SurvivesRepeatedEmptyRefillCycles
//
// Printer supply is the axis the old implementation scaled on: 8/128/256 in CostIsFlatInTotalSupply, and
// 6,500 in the Adhoc contract, which is the size that used to exceed a block.
// ─────────────────────────────────────────────────────────────────────────────

/// @title VaultEpochHarness
/// @notice Shared fixture for the scenario matrix above: a real IssuanceManager over a real
/// LedgerEntryToken printer, with helpers to build a printer of arbitrary supply, empty its vault, and check
/// what survives.
abstract contract VaultEpochHarness is Test {
    bytes32 constant SALT = bytes32(keccak256("IssuanceManagerVaultEpochTest"));
    uint256 constant BLOCK_GAS_LIMIT = 30_000_000;
    uint256 constant UNITS = 100;

    IssuanceManager public issuanceManager;
    BorgAuth public auth;
    address public holder;
    address public otherHolder;
    /// @dev Scrip deployed for the printer built by the most recent `_setUpVaultWithSupply`.
    ICyberScrip public scrip;

    function setUp() public {
        holder = makeAddr("holder");
        otherHolder = makeAddr("otherHolder");
        auth = new BorgAuth(address(this));

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new IssuanceManagerFactory{salt: SALT}()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        new IssuanceManager(),
                        new LedgerEntryToken(),
                        new CyberScrip()
                    )
                )
            )
        );

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(new MockCyberCorpForIM()),
            address(new MockUriBuilderForIM()),
            address(imFactory)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Gas for the conversion that drives the pool to exactly zero, on a printer with `supply` certificates.
    function _measureFinalConversionGas(uint256 supply) internal returns (uint256 gasUsed) {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(supply);

        vm.prank(holder);
        uint256 gasBefore = gasleft();
        issuanceManager.convertScripToCert(address(cert), scripBalance);
        gasUsed = gasBefore - gasleft();

        (uint256 totalAssetsWad,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(totalAssetsWad, 0, "conversion emptied the vault");
    }

    /// Deploys a printer holding `supply` certificates and scripifies token 0, so the vault has exactly one
    /// participant regardless of supply. Returns the holder's scrip balance.
    function _setUpVaultWithSupply(uint256 supply)
        internal
        returns (ICyberCertPrinter cert, uint256 scripBalance)
    {
        cert = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Cert",
                "CERT",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );

        for (uint256 i = 0; i < supply; i++) {
            issuanceManager.createCertAndAssign(address(cert), holder, _details(UNITS));
        }
        assertEq(IERC721Enumerable(address(cert)).totalSupply(), supply, "printer supply");

        scrip = ICyberScrip(_deployScrip(address(cert)));

        vm.prank(holder);
        issuanceManager.scripifyCert(address(cert), 0, UNITS, address(0));

        scripBalance = scrip.balanceOf(holder);
        assertGt(scripBalance, 0, "holder funded the vault");
    }

    /// Asserts the pool is empty and that no certificate in [0, supply) still claims shares or underlying.
    function _assertVaultEmptyAndPositionsRetired(ICyberCertPrinter cert, uint256 supply) internal view {
        (uint256 assets, uint256 shares) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 0, "pool emptied");
        assertEq(shares, 0, "pool shares zeroed");
        for (uint256 i = 0; i < supply; i++) {
            assertEq(issuanceManager.getScripPoolSharesById(address(cert), i), 0, "position retired");
            assertEq(issuanceManager.getScripPoolAmountById(address(cert), i), 0, "claim retired");
        }
    }

    /// Scripifies `tokenId` into the freshly emptied pool and asserts it owns the whole thing, which fails if
    /// any retired position carried into the new epoch.
    function _assertRefillOwnsWholePool(ICyberCertPrinter cert, uint256 tokenId, uint256 units) internal {
        vm.prank(cert.legalOwnerOf(tokenId));
        issuanceManager.scripifyCert(address(cert), tokenId, units, address(0));

        (uint256 assets, uint256 shares) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(
            issuanceManager.getScripPoolSharesById(address(cert), tokenId),
            shares,
            "refilling cert owns the whole new pool"
        );
        assertEq(
            issuanceManager.getScripPoolAmountById(address(cert), tokenId),
            assets,
            "and claims all of its underlying"
        );
    }

    function _details(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: bytes("")
        });
    }

    function _deployScrip(address cert) internal returns (address) {
        return issuanceManager.deployCyberScrip(
            cert,
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, // scripToCertMinimum
            1, // ratio numerator
            1, // ratio denominator
            new uint256[](0),
            false, // whitelist disabled
            true,
            true,
            true
        );
    }
}


/// @title IssuanceManagerVaultEpochTest
/// @notice Regression suite for the vault-epoch reset. Emptying the scrip vault must cost the same no matter
/// how many certificates the printer has ever minted, and must still leave no position able to claim shares
/// in the pool that gets funded next.
contract IssuanceManagerVaultEpochTest is VaultEpochHarness {
    /// The vault has exactly one participant in every case; only the printer's totalSupply() differs. Before
    /// the epoch reset this walked every token id and grew ~4,933 gas per certificate, crossing a 30M block
    /// at ~6,100 certificates. It must now be flat.
    function test_VaultEmptyingConversion_CostIsFlatInTotalSupply() public {
        uint256 gasAt8 = _measureFinalConversionGas(8);
        uint256 gasAt128 = _measureFinalConversionGas(128);
        uint256 gasAt256 = _measureFinalConversionGas(256);

        emit log_named_uint("supply   8 - final conversion gas", gasAt8);
        emit log_named_uint("supply 128 - final conversion gas", gasAt128);
        emit log_named_uint("supply 256 - final conversion gas", gasAt256);

        // A 32x supply increase must not move the cost: any per-certificate term would blow this out.
        assertApproxEqRel(gasAt256, gasAt8, 0.02e18, "emptying cost must not scale with totalSupply");
        assertApproxEqRel(gasAt128, gasAt8, 0.02e18, "emptying cost must not scale with totalSupply");
    }

    /// Emptying the vault and converting all but a dust amount now cost about the same: neither path walks
    /// the token supply, so a holder is no longer pushed into leaving dust behind to keep the call cheap.
    function test_FullAndPartialConversion_CostAboutTheSame() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(256);

        uint256 gasBefore = gasleft();
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), scripBalance - 1);
        uint256 dustGas = gasBefore - gasleft();

        (uint256 totalAssetsWad,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(totalAssetsWad, 1, "one unit of dust keeps the pool non-empty");

        uint256 emptyingGas = _measureFinalConversionGas(256);
        emit log_named_uint("convert all-but-dust", dustGas);
        emit log_named_uint("convert to zero     ", emptyingGas);
        assertApproxEqRel(emptyingGas, dustGas, 0.5e18, "emptying is no longer the expensive path");
    }

    /// The epoch bump must invalidate outstanding positions, not merely skip clearing them: the deposit path
    /// mints 1:1 into an empty pool and adds to the stored share count, so a position surviving into the next
    /// epoch would let its holder claim more than the whole refilled pool.
    function test_VaultEpoch_InvalidatesPositionsAcrossAnEmptying() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(8);

        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), scripBalance);
        _assertVaultEmptyAndPositionsRetired(cert, 8);

        // Refill from a different certificate: token 0's retired position must not carry into the new pool.
        _assertRefillOwnsWholePool(cert, 1, 40);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 0), 0, "retired position stays retired");
    }

    /// A certificate that held a retired position must be able to scripify again in the new epoch: the write
    /// path clears the stale value first, so it starts from zero rather than accumulating onto dead shares.
    function test_VaultEpoch_RetiredCertCanScripifyAgain() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(8);

        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), scripBalance);

        // Same certificate, new epoch: it funds the pool alone, so it must own exactly all of it.
        _assertRefillOwnsWholePool(cert, 0, 40);
    }

    /// Emptying via the socialized-withdrawal path: converting more units than the converter's own claim
    /// redeems that claim and then dilutes the rest of the pool away, so the OTHER participant's position is
    /// what the epoch bump has to retire.
    function test_VaultEpoch_EmptyingViaWithdrawal_RetiresOtherParticipant() public {
        (ICyberCertPrinter cert,) = _setUpVaultWithSupply(8);

        uint256 otherTokenId = IERC721Enumerable(address(cert)).totalSupply();
        issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(UNITS));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), otherTokenId, UNITS, address(0));

        // The holder buys out the other participant's scrip, then converts more than their own cert's claim.
        uint256 otherScrip = scrip.balanceOf(otherHolder);
        vm.prank(otherHolder);
        scrip.transfer(holder, otherScrip);
        assertGt(
            issuanceManager.getScripPoolSharesById(address(cert), otherTokenId),
            0,
            "other participant holds a position going in"
        );

        uint256 holderScrip = scrip.balanceOf(holder);
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), holderScrip);

        _assertVaultEmptyAndPositionsRetired(cert, otherTokenId + 1);
        // Refill from an untouched certificate: the other participant's diluted-away position is retired, so
        // it must not resurface as a claim on the new pool.
        _assertRefillOwnsWholePool(cert, 1, 40);
    }

    /// Emptying via an admin force-burn reaches _resetVaultPositions through executeForceScripBurn rather
    /// than through a conversion, so it must retire positions the same way.
    function test_VaultEpoch_EmptyingViaForceScripBurn_RetiresPositions() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(8);

        issuanceManager.forceScripBurn(address(cert), holder, scripBalance);

        _assertVaultEmptyAndPositionsRetired(cert, 8);
        _assertRefillOwnsWholePool(cert, 1, 40);
    }

    /// Repeated empty/refill cycles must keep working -- each bump retires only the epoch it ended.
    function test_VaultEpoch_SurvivesRepeatedEmptyRefillCycles() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(8);

        for (uint256 cycle = 0; cycle < 3; cycle++) {
            vm.prank(holder);
            issuanceManager.convertScripToCert(address(cert), scripBalance);
            (uint256 assets, uint256 shares) = issuanceManager.getCertScripUnitVault(address(cert));
            assertEq(assets, 0, "pool emptied");
            assertEq(shares, 0, "pool shares zeroed");

            vm.prank(holder);
            issuanceManager.scripifyCert(address(cert), 0, UNITS, address(0));
            assertEq(
                issuanceManager.getScripPoolSharesById(address(cert), 0),
                UNITS,
                "refilling cert owns the new pool outright"
            );
        }
    }
}

/// @title IssuanceManagerVaultEpochAdhocTest
/// @notice End-to-end check at the supply that used to brick the vault: the emptying conversion must fit in
/// a block with room to spare.
/// @dev Adhoc (excluded from CI): building a 6,500-certificate printer costs more than Foundry's default
/// per-test gas budget, so run it with
/// `forge test --match-contract IssuanceManagerVaultEpochAdhocTest --gas-limit 100000000000 -vv`.
contract IssuanceManagerVaultEpochAdhocTest is VaultEpochHarness {
    /// At 6,500 certificates the old O(totalSupply()) reset burned 32.2M gas and reverted out-of-gas under a
    /// 30M budget, stranding the scrip and its underlying units.
    function test_VaultEmptyingConversion_FitsInABlockAtLargeSupply() public {
        (ICyberCertPrinter cert, uint256 scripBalance) = _setUpVaultWithSupply(6_500);

        vm.prank(holder);
        uint256 gasBefore = gasleft();
        issuanceManager.convertScripToCert{gas: BLOCK_GAS_LIMIT}(address(cert), scripBalance);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("supply 6500 - final conversion gas", gasUsed);
        assertLt(gasUsed, BLOCK_GAS_LIMIT / 10, "emptying must be nowhere near a block");

        (uint256 totalAssetsWad,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(totalAssetsWad, 0, "vault emptied");
    }
}
