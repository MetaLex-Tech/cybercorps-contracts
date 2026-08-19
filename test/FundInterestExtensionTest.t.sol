// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {CertificateDetails} from "../src/interfaces/ILedgerEntryToken.sol";
import {
    FundInterestData,
    FundInterestExtension,
    FundInterestResolvedData,
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
            isAffiliateOrControlPerson: true,
            customProvisions: ""
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
            isAffiliateOrControlPerson: true,
            customProvisions: ""
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
            isAffiliateOrControlPerson: true,
            customProvisions: ""
        });

        bytes memory rewritten = extension.withTackedFrom(abi.encode(data), 1_555_000_000);
        FundInterestData memory decoded = abi.decode(rewritten, (FundInterestData));

        assertEq(decoded.tackedFromAcquisitionDate, 1_555_000_000, "tacking anchor set");
        assertEq(decoded.acquisitionDate, 1_700_000_000, "acquisition date preserved");
        assertTrue(decoded.isAffiliateOrControlPerson, "affiliate flag preserved");
    }

    /// @notice Both scopes render in one section, and `resolveCert` returns them as one typed pair.
    ///         The two scopes hold different fields, so pairing them needs no conflict rule.
    function test_getResolvedExtensionURI_PairsBothScopes() public {
        FundInterestData memory cert = FundInterestData({
            acquisitionDate: 1_780_075_297,
            tackedFromAcquisitionDate: 0,
            isAffiliateOrControlPerson: false,
            customProvisions: "none"
        });
        FundInterestSeriesData memory series;
        series.interestClass = "Class A";
        series.fundEntityType = "Delaware LP";

        address printer = address(new BothScopesPrinterStub(abi.encode(cert), abi.encode(series)));
        string memory json = string.concat("{", _stripSeparator(extension.getResolvedExtensionURI(printer, 1)), "}");
        vm.parseJson(json);

        assertEq(vm.parseJsonString(json, ".FundInterestTokenDetails.acquisitionDate"), "1780075297", "cert scope");
        assertEq(vm.parseJsonString(json, ".FundInterestSeriesDetails.interestClass"), "Class A", "series scope");

        FundInterestResolvedData memory resolved = extension.resolveCert(printer, 1);
        assertEq(resolved.certificate.acquisitionDate, 1_780_075_297, "typed cert half");
        assertEq(resolved.series.interestClass, "Class A", "typed series half");
    }

    /// @dev The render is a fragment that starts with ", " so it can be appended to a larger object.
    function _stripSeparator(string memory fragment) internal pure returns (string memory) {
        bytes memory b = bytes(fragment);
        bytes memory out = new bytes(b.length - 2);
        for (uint256 i = 2; i < b.length; i++) {
            out[i - 2] = b[i];
        }
        return string(out);
    }

    function test_getResolvedExtensionURI_RendersTheSeriesScope() public {
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

        // No cert payload, so the resolved render is the series scope on its own.
        address printer = address(new SeriesOnlyPrinterStub(abi.encode(data)));
        assertEq(
            extension.getResolvedExtensionURI(printer, 1),
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

/// @dev A printer that holds a series payload and no cert payload, so the resolved render shows the
///      series scope alone.
contract SeriesOnlyPrinterStub {
    bytes private seriesPayload;

    constructor(bytes memory payload) {
        seriesPayload = payload;
    }

    function getActiveCertificateDetails(uint256) external pure returns (CertificateDetails memory details) {}

    function getSeriesInfo() external view returns (address, bytes memory) {
        return (address(0), seriesPayload);
    }
}

/// @dev A printer that holds both payloads.
contract BothScopesPrinterStub {
    bytes private certPayload;
    bytes private seriesPayload;

    constructor(bytes memory cert, bytes memory series) {
        certPayload = cert;
        seriesPayload = series;
    }

    function getActiveCertificateDetails(uint256) external view returns (CertificateDetails memory details) {
        details.extensionData = certPayload;
    }

    function getSeriesInfo() external view returns (address, bytes memory) {
        return (address(0), seriesPayload);
    }
}
