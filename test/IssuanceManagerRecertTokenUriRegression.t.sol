// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IUriBuilder} from "../src/interfaces/IUriBuilder.sol";
import {
    CertificateDetails,
    Endorsement,
    OwnerDetails,
    RestrictiveLegend,
    SecurityClass,
    SecuritySeries
} from "../src/storage/CyberCertPrinterStorage.sol";
import {ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerConversionTest} from "./IssuanceManagerConversionTest.t.sol";

contract UriBuilderWithUnits is IUriBuilder {
    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory details,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return
            string.concat(
                '{"unitsRepresented":"',
                Strings.toString(details.unitsRepresented / 1e18),
                '"}'
            );
    }

    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory,
        CertificateDetails memory details,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return
            string.concat(
                '{"unitsRepresented":"',
                Strings.toString(details.unitsRepresented / 1e18),
                '"}'
            );
    }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory details,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return
            string.concat(
                '{"unitsRepresented":"',
                Strings.toString(details.unitsRepresented / 1e18),
                '"}'
            );
    }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory,
        CertificateDetails memory details,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return
            string.concat(
                '{"unitsRepresented":"',
                Strings.toString(details.unitsRepresented / 1e18),
                '"}'
            );
    }
}

contract IssuanceManagerRecertTokenUriRegressionTest is
    IssuanceManagerConversionTest
{
    function test_ReCertBackToOriginalCert_TokenURIShowsInflatedUnits() public {
        UriBuilderWithUnits uriBuilder = new UriBuilderWithUnits();
        issuanceManager.setUriBuilder(address(uriBuilder));

        ICyberCertPrinter certPrinter = _deployPrinter("Regression Cert", "REG");
        uint256 originalCertId = _mintCert(certPrinter, investor, 100);
        address investor2 = otherInvestor;

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            100, // 1 unit => 100 scrips
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            originalCertId,
            100 * 1e18,
            address(0)
        );
        assertEq(certPrinter.getActiveCertificateDetails(0).unitsRepresented, 0);
        // ratio is 100:1, so 100 units become 10,000 nominal scrip in pool amount.
        assertEq(
            IssuanceManager(issuanceManager).getScripPoolAmountById(
                address(certPrinter),
                0
            ),
            10_000 * 1e18
        );
        assertEq(IssuanceManager(issuanceManager).getScripPoolSharesById(address(certPrinter), 0), 100 * 1e18);

        vm.prank(investor);
        ICyberScrip(scrip).transfer(investor2, 1000 * 1e18);

        _stageRecertificationApproval(
            certPrinter,
            investor2,
            "Investor 2",
            10,
            "recert to #1",
            bytes("first")
        );
        vm.prank(investor2);
        issuanceManager.convertScripToCert(address(certPrinter), 1000 * 1e18);

        CertificateDetails memory certOneDetails = certPrinter
            .getActiveCertificateDetails(1);
        assertEq(certOneDetails.unitsRepresented, 10 * 1e18);
        assertEq(certPrinter.ownerOf(1), investor2);

        vm.expectEmit(true, true, true, true);
        emit IssuanceManager.ScripAddedToExistingCert(
            address(certPrinter),
            investor,
            0,
            5000 * 1e18,
            90 * 1e18,
            40 * 1e18
        );
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 5000 * 1e18);

        // Repro: event says 50 on cert #0, but tokenURI uses getCertificateDetails and reports 90.
        string memory certZeroUri = certPrinter.tokenURI(0);
        assertEq(certPrinter.getActiveCertificateDetails(0).unitsRepresented, 50 * 1e18);
        assertEq(certPrinter.getCertificateDetails(0).unitsRepresented, 90 * 1e18);
        assertTrue(_contains(certZeroUri, '"unitsRepresented":"90"'));
    }

    function test_HolderOneScripify50ThenRecertify25() public {
        UriBuilderWithUnits uriBuilder = new UriBuilderWithUnits();
        issuanceManager.setUriBuilder(address(uriBuilder));

        ICyberCertPrinter certPrinter = _deployPrinter("Regression Cert", "REG");
        uint256 certId = _mintCert(certPrinter, investor, 100);

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            100, // 1 unit => 100 scrips
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            certId,
            50 * 1e18,
            address(0)
        );

        assertEq(certPrinter.getActiveCertificateDetails(certId).unitsRepresented, 50 * 1e18);
        assertEq(certPrinter.getCertificateDetails(certId).unitsRepresented, 100 * 1e18);

        vm.expectEmit(true, true, true, true);
        emit IssuanceManager.ScripAddedToExistingCert(
            address(certPrinter),
            investor,
            certId,
            2500 * 1e18,
            100 * 1e18,
            25 * 1e18
        );
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 2500 * 1e18);

        assertEq(certPrinter.getActiveCertificateDetails(certId).unitsRepresented, 75 * 1e18);
        assertEq(certPrinter.getCertificateDetails(certId).unitsRepresented, 100 * 1e18);
        assertTrue(_contains(certPrinter.tokenURI(certId), '"unitsRepresented":"100"'));
    }

    function _contains(
        string memory haystack,
        string memory needle
    ) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (n.length > h.length) return false;

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool matchFound = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) return true;
        }

        return false;
    }
}
