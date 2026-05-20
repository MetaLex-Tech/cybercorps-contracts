// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";

contract MockPrinterExtensionData {
    bytes internal data;

    function setPrinterExtensionData(bytes memory newData) external {
        data = newData;
    }

    function getPrinterExtensionData() external view returns (bytes memory) {
        return data;
    }
}

contract MockLegacyCertificateExtension {
    function getExtensionURI(bytes memory certificateExtensionData) external pure returns (string memory) {
        if (certificateExtensionData.length == 0) return "";
        return string.concat(', "legacyCertificateData": "', abi.decode(certificateExtensionData, (string)), '"');
    }
}

contract MockV2CertificateExtension {
    function getExtensionURI(bytes memory certificateExtensionData) external pure returns (string memory) {
        if (certificateExtensionData.length == 0) return "";
        return string.concat(', "legacyCertificateData": "', abi.decode(certificateExtensionData, (string)), '"');
    }

    function getExtensionURI(
        bytes memory printerExtensionData,
        bytes memory certificateExtensionData
    ) external pure returns (string memory) {
        string memory shared = printerExtensionData.length == 0 ? "" : abi.decode(printerExtensionData, (string));
        string memory certificate = certificateExtensionData.length == 0 ? "" : abi.decode(certificateExtensionData, (string));
        return string.concat(
            ', "sharedFields": {',
            '"series": "', shared,
            '", "certificate": "', certificate,
            '"}'
        );
    }
}

contract CertificateExtensionDataTest is Test {
    CertificateUriBuilder internal uriBuilder;
    MockPrinterExtensionData internal printer;
    MockLegacyCertificateExtension internal legacyExtension;
    MockV2CertificateExtension internal v2Extension;

    function setUp() public {
        BorgAuth auth = new BorgAuth(address(this));
        uriBuilder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(auth))
                )
            )
        );
        uriBuilder.setImageBuilder(address(new CertificateImageBuilderContract()));

        printer = new MockPrinterExtensionData();
        legacyExtension = new MockLegacyCertificateExtension();
        v2Extension = new MockV2CertificateExtension();
    }

    function testLegacyExtensionUriUnchangedWhenPrinterDataIsSetButExtensionNotUpgraded() public {
        CertificateUriBuilder.CertificateDetails memory details = _details("certificate-only-data");

        string memory beforePrinterData = _json(details, address(legacyExtension), address(printer));

        printer.setPrinterExtensionData(abi.encode("shared data unavailable to legacy extension"));

        assertEq(_json(details, address(legacyExtension), address(printer)), beforePrinterData);
    }

    function testV2ExtensionUriIncludesSharedPrinterAndCertificateFields() public {
        printer.setPrinterExtensionData(abi.encode("Series A shared terms"));

        string memory json = _json(_details("Certificate 1001 terms"), address(v2Extension), address(printer));

        assertTrue(_contains(json, '"sharedFields": {'));
        assertTrue(_contains(json, '"series": "Series A shared terms"'));
        assertTrue(_contains(json, '"certificate": "Certificate 1001 terms"'));
    }

    function testV2ExtensionUriIncludesSharedFieldsWhenCertificateDataIsEmpty() public {
        printer.setPrinterExtensionData(abi.encode("Series A shared terms"));

        string memory json = _json(_detailsBytes(hex""), address(v2Extension), address(printer));

        assertTrue(_contains(json, '"sharedFields": {'));
        assertTrue(_contains(json, '"series": "Series A shared terms"'));
        assertTrue(_contains(json, '"certificate": ""'));
    }

    function _json(
        CertificateUriBuilder.CertificateDetails memory details,
        address extension,
        address printerAddress
    ) internal view returns (string memory) {
        string[] memory legend = new string[](1);
        legend[0] = "Legend";
        CertificateUriBuilder.Endorsement[] memory endorsements = new CertificateUriBuilder.Endorsement[](0);
        CertificateUriBuilder.OwnerDetails memory owner =
            CertificateUriBuilder.OwnerDetails({name: "Investor", ownerAddress: address(0xB0B)});

        return uriBuilder.buildCertificateUriNotEncoded(
            "Test CyberCorp",
            "corporation",
            "DE",
            "contact@test.com",
            SecurityClass.PreferredStock,
            SecuritySeries.SeriesA,
            "ipfs://series-a-cert",
            legend,
            details,
            endorsements,
            owner,
            address(0),
            bytes32(0),
            1,
            printerAddress,
            extension
        );
    }

    function _details(string memory extensionData) internal pure returns (CertificateUriBuilder.CertificateDetails memory) {
        return _detailsBytes(abi.encode(extensionData));
    }

    function _detailsBytes(bytes memory extensionData) internal pure returns (CertificateUriBuilder.CertificateDetails memory) {
        return CertificateUriBuilder.CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100_000e18,
            issuerUSDValuationAtTimeOfInvestment: 25_000_000e18,
            unitsRepresented: 10_000e18,
            legalDetails: "Legal details",
            extensionData: extensionData
        });
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0) return true;
        if (n.length > h.length) return false;

        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }

        return false;
    }
}
