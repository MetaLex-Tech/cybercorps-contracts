// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";

import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import {SecurityClass, SecuritySeries} from "../src/storage/LedgerEntryTokenStorage.sol";
import {VaultEpochHarness} from "./IssuanceManagerVaultEpochTest.t.sol";

contract AuditEconomicsScripVoidTest is VaultEpochHarness {
    function test_AuditEconomics_OneUnitRedemptionCanVoidAnotherScripHolder() public {
        ILedgerEntryToken cert = _prepare(1, 1);
        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 1);
        _proveVoidBlocksRedemption(cert, 1);
    }

    function test_AuditEconomics_RepeatedCyclesBlockFullSizePosition() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        for (uint256 i; i < 22; ++i) {
            vm.prank(otherHolder);
            issuanceManager.convertScripToCert(address(cert), 900e18);
            if (i != 21) {
                vm.prank(otherHolder);
                issuanceManager.scripifyCert(address(cert), 1, 900e18, address(0));
            }
        }
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 900e18);
        _proveVoidBlocksRedemption(cert, 100e18);
    }

    function _prepare(uint256 victimUnits, uint256 attackerUnits) internal returns (ILedgerEntryToken cert) {
        cert = ILedgerEntryToken(
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
        issuanceManager.createCertAndAssign(address(cert), holder, _details(victimUnits));
        issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(attackerUnits));
        scrip = ICyberScrip(_deployScrip(address(cert)));
        vm.prank(holder);
        issuanceManager.scripifyCert(address(cert), 0, victimUnits, address(0));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), 1, attackerUnits, address(0));
    }

    function _proveVoidBlocksRedemption(ILedgerEntryToken cert, uint256 victimBalance) internal {
        assertEq(scrip.balanceOf(holder), victimBalance);
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 0);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 0), 0);
        (uint256 assets,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, victimBalance, "victim's fungible balance is still fully backed");

        uint256 snapshot = vm.snapshotState();
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), victimBalance);
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, victimBalance);
        assertTrue(vm.revertToState(snapshot));

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.prank(otherHolder);
        issuanceManager.voidEmptyCerts(address(cert), ids);
        assertTrue(cert.isVoided(0));
        assertFalse(cert.isLegalHolder(holder));
        vm.expectRevert(IssuanceManagerStorage.RecertificationApprovalRequired.selector);
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), victimBalance);
        assertEq(scrip.balanceOf(holder), victimBalance);
    }
}
