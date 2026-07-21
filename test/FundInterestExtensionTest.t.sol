// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {
    FundInterestData,
    FundInterestExtension,
    FundInterestSeriesData,
    SecurityIdentification
} from "../src/storage/extensions/FundInterestExtension.sol";

contract FundInterestExtensionTest is Test {
    FundInterestExtension internal extension;

    function setUp() public {
        extension = new FundInterestExtension();
    }

    function test_getExtensionURI_RendersTokenData() public view {
        FundInterestData memory data = FundInterestData({
            acquisitionDate: 1_700_000_000,
            tackedFromAcquisitionDate: 1_600_000_000,
            isAffiliateOrControlPerson: true
        });

        assertEq(
            extension.getExtensionURI(abi.encode(data)),
            ', "FundInterestTokenDetails": {"acquisitionDate": "1700000000", '
            '"tackedFromAcquisitionDate": "1600000000", "isAffiliateOrControlPerson": true}'
        );
    }

    function test_typedAccessors_ReadFields() public view {
        FundInterestData memory data = FundInterestData({
            acquisitionDate: 1_700_000_000,
            tackedFromAcquisitionDate: 1_600_000_000,
            isAffiliateOrControlPerson: true
        });
        bytes memory encoded = abi.encode(data);

        assertEq(extension.acquisitionDate(encoded), 1_700_000_000);
        assertEq(extension.tackedFromAcquisitionDate(encoded), 1_600_000_000);
    }

    function test_typedAccessors_EmptyPayloadReverts() public {
        // Empty/malformed data is not silently defaulted; callers guard the "no extension data" case.
        vm.expectRevert();
        extension.acquisitionDate("");
        vm.expectRevert();
        extension.tackedFromAcquisitionDate("");
    }

    function test_withTackedFrom_RewritesOnlyTackingAnchor() public view {
        FundInterestData memory data = FundInterestData({
            acquisitionDate: 1_700_000_000,
            tackedFromAcquisitionDate: 0,
            isAffiliateOrControlPerson: true
        });

        bytes memory rewritten = extension.withTackedFrom(abi.encode(data), 1_555_000_000);
        FundInterestData memory decoded = abi.decode(rewritten, (FundInterestData));

        assertEq(decoded.tackedFromAcquisitionDate, 1_555_000_000, "tacking anchor set");
        assertEq(decoded.acquisitionDate, 1_700_000_000, "acquisition date preserved");
        assertTrue(decoded.isAffiliateOrControlPerson, "affiliate flag preserved");
    }

    function test_getSeriesExtensionURI_RendersCurrentSeriesData() public view {
        string[] memory documents = new string[](2);
        documents[0] = "ipfs://operating-agreement";
        documents[1] = "ipfs://ppm";
        FundInterestSeriesData memory data = FundInterestSeriesData({
            interestClass: "Class A",
            fundEntityType: "Delaware LP",
            icaExceptionRelied: "3(c)(7)",
            managementFeeRateBps: 200,
            carriedInterestRateBps: 2_000,
            distributionWaterfallPosition: "After return of capital",
            governingDocumentURIs: documents,
            securityIdentification: SecurityIdentification({
                securityID: "549300TEST",
                securityIDSource: "LEI",
                securityType: "FUND",
                securityDesc: "Class A member interest",
                issuer: "Example Fund LP"
            })
        });

        assertEq(
            extension.getSeriesExtensionURI(abi.encode(data)),
            ', "FundInterestSeriesDetails": {"interestClass": "Class A", '
            '"fundEntityType": "Delaware LP", "icaExceptionRelied": "3(c)(7)", '
            '"managementFeeRateBps": 200, "carriedInterestRateBps": 2000, '
            '"distributionWaterfallPosition": "After return of capital", '
            '"governingDocumentURIs": ["ipfs://operating-agreement", "ipfs://ppm"], '
            '"securityIdentification": {"securityID": "549300TEST", "securityIDSource": "LEI", '
            '"securityType": "FUND", "securityDesc": "Class A member interest", '
            '"issuer": "Example Fund LP"}}'
        );
    }
}
