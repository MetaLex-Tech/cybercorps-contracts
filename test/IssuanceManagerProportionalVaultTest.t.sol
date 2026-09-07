// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {ProportionalVaultMath} from "../src/libs/ProportionalVaultMath.sol";
import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import {VaultEpochHarness} from "./IssuanceManagerVaultEpochTest.t.sol";
import {Test} from "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract ProportionalVaultHarness {
    address internal constant PRINTER = address(1);

    function deposit(uint256 id, uint256 amount) external {
        IssuanceManagerStorage._depositCertScripUnits(PRINTER, id, amount);
    }

    function withdraw(uint256 amount) external {
        IssuanceManagerStorage._withdrawVaultAssets(PRINTER, amount);
    }

    function claim(uint256 id) external view returns (uint256) {
        return IssuanceManagerStorage._assetsOfVaultPosition(PRINTER, id);
    }

    function shares(uint256 id) external view returns (uint256) {
        return IssuanceManagerStorage.getScripPoolSharesById(PRINTER, id);
    }

    function totals() external view returns (uint256, uint256) {
        return IssuanceManagerStorage.getCertScripUnitVault(PRINTER);
    }

    function index() external view returns (uint256, uint256) {
        IssuanceManagerStorage.CertScripUnitPool storage pool =
            IssuanceManagerStorage.issuanceManagerStorage().certScripUnitPools[PRINTER];
        return (pool.lossIndex, pool.lossScale);
    }
}

contract IssuanceManagerProportionalVaultTest is Test {
    ProportionalVaultHarness internal vault;

    function setUp() public {
        vault = new ProportionalVaultHarness();
    }

    function test_ThreeActors_1000_100_Redeem750() public {
        vault.deposit(0, 1000e18);
        vault.deposit(1, 100e18);
        vault.withdraw(750e18);
        _assertTotals(350e18);
        assertApproxEqAbs(vault.claim(0), Math.mulDiv(1000e18, 350, 1100), 1);
        assertApproxEqAbs(vault.claim(1), Math.mulDiv(100e18, 350, 1100), 1);
        assertEq(vault.shares(0), vault.claim(0));
        assertEq(vault.shares(1), vault.claim(1));
        assertLe(vault.claim(0) + vault.claim(1), 350e18);

        uint256 firstBefore = vault.claim(0);
        uint256 secondBefore = vault.claim(1);
        vault.deposit(2, 750e18);
        _assertTotals(1100e18);
        assertEq(vault.claim(2), 750e18);
        assertEq(vault.claim(0), firstBefore, "deposit cannot steal prior backing");
        assertEq(vault.claim(1), secondBefore);
    }

    function test_OriginalAttack_RepeatedCrossCertificateCycles() public {
        vault.deposit(0, 100e18);
        for (uint256 i; i < 200; ++i) {
            vault.deposit(1, 900e18);
            _assertTotals(1000e18);
            vault.withdraw(900e18);
            _assertTotals(100e18);
            assertLe(vault.claim(0) + vault.claim(1), 100e18);
        }
        (, uint256 scale) = vault.index();
        assertGt(scale, 256, "exercise multiple index normalizations beyond uint256 precision");
        assertEq(vault.claim(0), 0, "sub-wei historical attribution does not revive");
        vault.deposit(2, 900e18);
        assertEq(vault.claim(2), 900e18, "new deposit remains live at a very old index");
    }

    function test_DustCanBeRedeemedEvenWhenAllClaimsRoundToZero() public {
        vault.deposit(0, 1);
        vault.deposit(1, 1);
        vault.withdraw(1);
        assertEq(vault.claim(0), 0);
        assertEq(vault.claim(1), 0);
        _assertTotals(1);
        vault.withdraw(1);
        _assertTotals(0);
        vault.deposit(1, 10);
        assertEq(vault.claim(0), 0);
        assertEq(vault.claim(1), 10);
    }

    function test_MaxUintDepositAndOneWeiResidualDoNotOverflowOrUnderflow() public {
        vault.deposit(0, type(uint256).max);
        vault.withdraw(type(uint256).max - 1);
        _assertTotals(1);
        assertLe(vault.claim(0), 1);
        (uint256 mantissa,) = vault.index();
        assertGe(mantissa, uint256(1) << 255);
        vault.deposit(1, type(uint256).max - 1);
        _assertTotals(type(uint256).max);
        vault.withdraw(type(uint256).max);
        assertEq(vault.claim(0), 0);
        assertEq(vault.claim(1), 0);
    }

    function test_FreshPoolInitializesOnFirstDeposit() public {
        _assertTotals(0);
        assertEq(vault.claim(0), 0);
        assertEq(vault.shares(0), 0);
        (uint256 indexBefore, uint256 scaleBefore) = vault.index();
        assertEq(indexBefore, 0);
        assertEq(scaleBefore, 0);

        vault.deposit(0, 100);
        _assertTotals(100);
        (uint256 indexAfter, uint256 scaleAfter) = vault.index();
        assertEq(indexAfter, ProportionalVaultMath.ONE);
        assertEq(scaleAfter, 0);
        assertEq(vault.claim(0), 100);
        assertEq(vault.claim(1), 0);
    }

    function test_NewPositionUsesCurrentIndexAfterWithdrawal() public {
        vault.deposit(0, 1000);
        vault.withdraw(900);
        uint256 firstClaim = vault.claim(0);
        assertEq(vault.claim(1), 0);
        vault.deposit(1, 100);
        _assertTotals(200);
        assertEq(vault.claim(0), firstClaim);
        assertEq(vault.claim(1), 100);
        vault.withdraw(100);
        assertApproxEqAbs(vault.claim(0), 50, 1);
        assertApproxEqAbs(vault.claim(1), 50, 1);
    }

    function test_InvalidWithdrawalsAndZeroDeposit() public {
        vm.expectRevert(IssuanceManagerStorage.EmptyVault.selector);
        vault.withdraw(1);
        vm.expectRevert(IssuanceManagerStorage.ZeroSharesMinted.selector);
        vault.deposit(0, 0);
        vault.deposit(0, 10);
        vm.expectRevert(IssuanceManagerStorage.VaultWithdrawalExceedsAssets.selector);
        vault.withdraw(11);
        vault.withdraw(0);
        _assertTotals(10);
        assertEq(vault.claim(0), 10);
    }

    function test_PartialWithdrawalGasDoesNotScaleWithLivePositions() public {
        uint256 small = _withdrawalGas(2);
        uint256 large = _withdrawalGas(128);
        assertApproxEqAbs(large, small, 1000, "no per-position term in withdrawal cost");
    }

    function _withdrawalGas(uint256 count) internal returns (uint256 used) {
        ProportionalVaultHarness instance = new ProportionalVaultHarness();
        for (uint256 i; i < count; ++i) {
            instance.deposit(i, 100e18);
        }
        uint256 beforeGas = gasleft();
        instance.withdraw(count * 50e18);
        used = beforeGas - gasleft();
    }

    function testFuzz_WithdrawalMatchesProportionalAllocation(uint128 a, uint128 b, uint256 out) public {
        uint256 first = uint256(a) + 1;
        uint256 second = uint256(b) + 1;
        uint256 total = first + second;
        out = bound(out, 0, total);
        vault.deposit(0, first);
        vault.deposit(1, second);
        vault.withdraw(out);
        uint256 remaining = total - out;
        _assertTotals(remaining);
        uint256 expectedFirst = Math.mulDiv(first, remaining, total);
        uint256 expectedSecond = Math.mulDiv(second, remaining, total);
        assertLe(vault.claim(0), expectedFirst);
        assertLe(vault.claim(1), expectedSecond);
        assertApproxEqAbs(vault.claim(0), expectedFirst, 1);
        assertApproxEqAbs(vault.claim(1), expectedSecond, 1);
    }

    function testFuzz_StatefulConservation(bytes32 seed) public {
        uint256[4] memory upperClaims;
        uint256 expectedAssets;
        // An independently rounded-up allocation bounds every computed claim after arbitrary sequences.
        for (uint256 i; i < 80; ++i) {
            seed = keccak256(abi.encode(seed, i));
            uint256 id = uint256(seed) % 4;
            if (expectedAssets == 0 || uint256(seed) & 4 == 0) {
                uint256 amount = uint256(seed) % 1e24 + 1;
                vault.deposit(id, amount);
                upperClaims[id] += amount;
                expectedAssets += amount;
            } else {
                uint256 amount = uint256(seed) % expectedAssets + 1;
                uint256 remaining = expectedAssets - amount;
                for (uint256 j; j < 4; ++j) {
                    upperClaims[j] = Math.mulDiv(upperClaims[j], remaining, expectedAssets, Math.Rounding.Ceil);
                }
                vault.withdraw(amount);
                expectedAssets = remaining;
            }
            _assertTotals(expectedAssets);
            uint256 sum;
            for (uint256 j; j < 4; ++j) {
                uint256 claim = vault.claim(j);
                assertLe(claim, upperClaims[j]);
                // At these magnitudes index error is below one wei per step; checkpoint/floor error
                // remains bounded by the number of operations, never an unbounded percentage loss.
                assertApproxEqAbs(claim, upperClaims[j], 2 * (i + 1));
                sum += claim;
            }
            assertLe(sum, expectedAssets, "attribution must never exceed backing");
        }
    }

    function _assertTotals(uint256 expected) internal view {
        (uint256 assets, uint256 shares) = vault.totals();
        assertEq(assets, expected);
        assertEq(shares, expected, "share count is bounded by current backing");
    }
}

contract ProportionalVaultMathTest is Test {
    function test_FullWidthBigIntegerReferenceVectors() public view {
        string memory json = vm.readFile("test/res/proportional-vault-vectors.json");
        for (uint256 i; i < 64; ++i) {
            uint256[] memory row = vm.parseJsonUintArray(json, string.concat(".vectors[", vm.toString(i), "]"));
            assertEq(ProportionalVaultMath.balance(row[0], row[1], row[2], row[3]), row[4]);
        }
    }

    function test_257BitIntermediateQuotient() public pure {
        uint256 one = uint256(1) << 255;
        assertEq(ProportionalVaultMath.balance(type(uint256).max, type(uint256).max, one, 1), type(uint256).max - 1);
        assertEq(ProportionalVaultMath.balance(type(uint256).max, type(uint256).max, one, 256), 1);
        assertEq(ProportionalVaultMath.balance(type(uint256).max, type(uint256).max, one, 257), 0);
    }

    function testFuzz_BalanceMatchesFullPrecision(uint256 amount, uint256 current, uint256 snapshot, uint16 scale)
        public
        pure
    {
        current |= uint256(1) << 255;
        snapshot |= uint256(1) << 255;
        amount >>= 1; // Independent reference quotient fits; full-width overflow vectors are above.
        uint256 shift = uint256(scale) % 300;
        uint256 expected = Math.mulDiv(amount, current, snapshot) >> shift;
        assertEq(ProportionalVaultMath.balance(amount, current, snapshot, shift), expected);
    }

    function testFuzz_ReductionIsNormalizedAndConservative(uint256 mantissa, uint256 total, uint256 remaining)
        public
        pure
    {
        mantissa |= uint256(1) << 255;
        total = bound(total, 1, type(uint256).max);
        remaining = bound(remaining, 1, total);
        (uint256 next, uint256 scale) = ProportionalVaultMath.reduce(mantissa, 0, remaining, total);
        assertGe(next, uint256(1) << 255);
        // Exact expected balance for a position equal to the entire old pool is remaining.
        uint256 actual = ProportionalVaultMath.balance(total, next, mantissa, scale);
        assertLe(actual, remaining);
        assertApproxEqAbs(actual, remaining, 8, "full-uint256 index rounding bound");
    }
}

contract IssuanceManagerProportionalConversionTest is VaultEpochHarness {
    function test_ExistingCertificateConversionSocializesItsOwnClaimToo() public {
        (ILedgerEntryToken cert,) = _setUpVaultWithSupply(2);
        uint256 otherId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(100));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), otherId, 100, address(0));
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), 50);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), 0), 75);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), otherId), 75);
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 50);
        assertEq(scrip.balanceOf(holder), 50);
        assertEq(scrip.balanceOf(otherHolder), 100);
    }

    function test_SingleCertificateCyclesStayLiveThroughManyNormalizations() public {
        (ILedgerEntryToken cert,) = _setUpVaultWithSupply(1);
        uint256 otherId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(900));
        for (uint256 i; i < 100; ++i) {
            vm.startPrank(otherHolder);
            issuanceManager.scripifyCert(address(cert), otherId, 900, address(0));
            issuanceManager.convertScripToCert(address(cert), 900);
            vm.stopPrank();
            (uint256 assets, uint256 shares) = issuanceManager.getCertScripUnitVault(address(cert));
            assertEq(assets, 100);
            assertEq(shares, 100);
            assertEq(scrip.totalSupply(), 100);
            assertEq(cert.getActiveCertificateDetails(otherId).unitsRepresented, 900);
            cert.getCertificateDetails(otherId); // Previously overflowing claim/detail path stays live.
        }
    }

    function test_NewCertificateThreeActorConversion() public {
        (ILedgerEntryToken cert,) = _setUpVaultWithSupply(1); // A has scripified 100 units.
        uint256 otherId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(1000));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), otherId, 1000, address(0));
        address buyer = makeAddr("buyer");
        vm.prank(otherHolder);
        scrip.transfer(buyer, 750);
        issuanceManager.setRecertificationApproval(address(cert), buyer, "Buyer", _details(0), bytes("signature"));
        vm.prank(buyer);
        issuanceManager.convertScripToCert(address(cert), 750);
        uint256 buyerId = cert.tokenOfLegalOwnerByIndex(buyer, 0);
        assertEq(cert.getActiveCertificateDetails(buyerId).unitsRepresented, 750);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), buyerId), 0);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), 0), 31);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), otherId), 318);
        assertEq(scrip.totalSupply(), 350);
        assertEq(scrip.balanceOf(holder), 100);
        assertEq(scrip.balanceOf(otherHolder), 250);
        assertEq(scrip.balanceOf(buyer), 0);
    }

    function test_ForceBurnSocializesBothPositions() public {
        (ILedgerEntryToken cert,) = _setUpVaultWithSupply(1);
        uint256 otherId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(100));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), otherId, 100, address(0));
        issuanceManager.forceScripBurn(address(cert), holder, 50);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), 0), 75);
        assertEq(issuanceManager.getScripPoolAmountById(address(cert), otherId), 75);
        (uint256 assets, uint256 shares) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 150);
        assertEq(shares, 150);
    }
}
