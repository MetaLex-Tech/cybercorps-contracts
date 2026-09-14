// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";

import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import {SecurityClass, SecuritySeries} from "../src/storage/LedgerEntryTokenStorage.sol";
import {VaultEpochHarness} from "./IssuanceManagerVaultEpochTest.t.sol";

contract AuditEconomicsScripVoidTest is VaultEpochHarness {
    function test_AuditEconomics_NewHolderRedemptionCanStillRoundAttributionToZero() public {
        ILedgerEntryToken cert = _prepare(1, 1);
        address buyer = makeAddr("buyer");
        vm.prank(otherHolder);
        scrip.transfer(buyer, 1);
        issuanceManager.setRecertificationApproval(address(cert), buyer, "Buyer", _details(0), bytes("signature"));
        vm.prank(buyer);
        issuanceManager.convertScripToCert(address(cert), 1);
        _proveVoidBlocksRedemption(cert, 1);
    }

    function test_AuditEconomics_RepeatedMemberCyclesCannotMakeVictimSweepable() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        _runRepeatedCycles(cert);
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 900e18);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert(IssuanceManagerStorage.CertNotEmpty.selector);
        vm.prank(otherHolder);
        issuanceManager.voidEmptyCerts(address(cert), ids);
        assertFalse(cert.isVoided(0));
    }

    function test_AuditEconomics_VictimRedeemsOriginalUnitsAfterMemberCycles() public {
        uint256 originalUnitsRepresented = 100e18;
        ILedgerEntryToken cert = _prepare(originalUnitsRepresented, 900e18);
        _runRepeatedCycles(cert);

        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 0), originalUnitsRepresented);
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 0);
        assertFalse(cert.isVoided(0));
        assertEq(scrip.balanceOf(holder), originalUnitsRepresented);

        // No sweep or new approval: the victim redeems against the shared backing.
        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), originalUnitsRepresented);

        assertEq(
            cert.getActiveCertificateDetails(0).unitsRepresented,
            originalUnitsRepresented,
            "victim must recover all original certificate units"
        );
        assertEq(scrip.balanceOf(holder), 0, "victim scrip must be burned");
        (uint256 assets,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 0, "victim must recover the remaining pool backing");
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 900e18);
        assertEq(scrip.balanceOf(otherHolder), 0);
    }

    function test_AuditEconomics_MultipleMemberCertificatesPreserveVictimAttribution() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        uint256 secondMemberId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(900e18));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), secondMemberId, 900e18, address(0));
        assertEq(scrip.balanceOf(otherHolder), 1800e18);

        // Both member positions must be consumed before touching the victim's attribution.
        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 1800e18);

        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 1800e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 1), 0);
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 100e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), secondMemberId), 0);
        assertEq(scrip.balanceOf(otherHolder), 0);
        assertEq(scrip.balanceOf(holder), 100e18);
        (uint256 assets,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 100e18, "victim backing and attribution must remain intact");

        vm.prank(holder);
        issuanceManager.convertScripToCert(address(cert), 100e18);
        assertEq(cert.getActiveCertificateDetails(0).unitsRepresented, 100e18);
        assertEq(scrip.totalSupply(), 0);
        (assets,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 0);
    }

    function test_AuditEconomics_PartialRedemptionAcrossMemberCertificatesPreservesOtherHolders() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        uint256 secondId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(900e18));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), secondId, 900e18, address(0));

        // Swap custody without changing legal ownership. Attribution must follow the legal holder.
        cert.setTokenTransferable(secondId, true);
        vm.prank(otherHolder);
        cert.transferFrom(otherHolder, holder, secondId);
        cert.setTokenTransferable(0, true);
        vm.prank(holder);
        cert.transferFrom(holder, otherHolder, 0);
        assertEq(cert.legalOwnerOf(secondId), otherHolder);
        assertEq(cert.legalOwnerOf(0), holder);

        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 1200e18);
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 1200e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 1), 0);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), secondId), 600e18);
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 100e18);

        // The receiving certificate now has no pool attribution, but the second still does.
        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 600e18);
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 1800e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), secondId), 0);
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 100e18);
    }

    function test_AuditEconomics_DirectRedemptionSkipsVoidedMemberPositions() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        uint256 secondId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(900e18));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), secondId, 900e18, address(0));
        cert.voidCert(1);

        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 900e18);
        assertEq(cert.getActiveCertificateDetails(secondId).unitsRepresented, 900e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), secondId), 0);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 1), 900e18);
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 100e18);
        assertEq(scrip.balanceOf(otherHolder), 900e18);
    }

    function test_AuditEconomics_OnlyExcessBeyondAllMemberPositionsIsProportional() public {
        ILedgerEntryToken cert = _prepare(100e18, 900e18);
        uint256 secondId = issuanceManager.createCertAndAssign(address(cert), otherHolder, _details(900e18));
        vm.prank(otherHolder);
        issuanceManager.scripifyCert(address(cert), secondId, 900e18, address(0));
        vm.prank(holder);
        scrip.transfer(otherHolder, 50e18);

        vm.prank(otherHolder);
        issuanceManager.convertScripToCert(address(cert), 1850e18);
        assertEq(cert.getActiveCertificateDetails(1).unitsRepresented, 1850e18);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), 1), 0);
        assertEq(issuanceManager.getScripPoolSharesById(address(cert), secondId), 0);
        assertEq(cert.getCertificateDetails(0).unitsRepresented, 50e18);
        assertEq(scrip.balanceOf(holder), 50e18);
        assertEq(scrip.balanceOf(otherHolder), 0);
        (uint256 assets,) = issuanceManager.getCertScripUnitVault(address(cert));
        assertEq(assets, 50e18);
    }

    function _runRepeatedCycles(ILedgerEntryToken cert) internal {
        for (uint256 i; i < 22; ++i) {
            vm.prank(otherHolder);
            issuanceManager.convertScripToCert(address(cert), 900e18);
            assertEq(cert.getCertificateDetails(0).unitsRepresented, 100e18, "victim attribution must not dilute");
            assertEq(
                cert.getCertificateDetails(1).unitsRepresented, 900e18, "redeemer must not retain extra attribution"
            );
            assertEq(issuanceManager.getScripPoolSharesById(address(cert), 1), 0);
            if (i != 21) {
                vm.prank(otherHolder);
                issuanceManager.scripifyCert(address(cert), 1, 900e18, address(0));
            }
        }
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
