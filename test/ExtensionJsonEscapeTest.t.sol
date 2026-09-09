// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ACESAFEExtension, ACESAFEData} from "../src/storage/extensions/ACESAFEExtension.sol";
import {ACESAFEExtensionV3, ACESAFESeriesData} from "../src/storage/extensions/ACESAFEExtensionV3.sol";
import {
    CyberCorpComplianceExtension,
    CyberCorpComplianceData,
    FeeDetail
} from "../src/storage/extensions/CyberCorpComplianceExtension.sol";
import {CyberCorpExtension, CyberCorpData} from "../src/storage/extensions/CyberCorpExtension.sol";
import {CyberCorpExtensionV2, CyberCorpDataV2} from "../src/storage/extensions/CyberCorpExtensionV2.sol";
import {
    CyberCorpFundExtension,
    CyberCorpFundData,
    PortfolioHolding
} from "../src/storage/extensions/CyberCorpFundExtension.sol";
import {
    FundInterestExtension,
    FundInterestSeriesData,
    SecurityIdentification
} from "../src/storage/extensions/FundInterestExtension.sol";
import {SAFEExtension, SAFEData} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFEExtensionV3, SAFESeriesData} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {SAFTEExtensionV2, SAFTEDataV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTEExtensionV3, SAFTESeriesData} from "../src/storage/extensions/SAFTEExtensionV3.sol";
import {SAFTExtensionV2, SAFTDataV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {SAFTExtensionV3, SAFTSeriesData} from "../src/storage/extensions/SAFTExtensionV3.sol";
import {TokenWarrantExtensionV2, TokenWarrantDataV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";
import {
    TokenWarrantExtensionV3,
    TokenWarrantSeriesData
} from "../src/storage/extensions/TokenWarrantExtensionV3.sol";

/// @dev Every extension returns a finished JSON fragment. CertificateUriBuilder joins the fragments.
/// At that point the builder cannot tell a structural quote from a data quote. Each extension must
/// therefore escape its own strings. This suite gives each one a string that holds a quote, a
/// backslash and a control byte, then checks that the fragment is still valid JSON and that the
/// value comes back unchanged.
contract ExtensionJsonEscapeTest is Test {
    string internal constant POISON = "\"a\\b\x07c\", \"injected\": \"1";

    /// @dev Fragments start with a comma. Put one field in front to make a parsable object.
    function _wrap(string memory fragment) private pure returns (string memory) {
        return string.concat('{"pad": 0', fragment, "}");
    }

    function _assertField(string memory fragment, string memory path) private view {
        assertEq(vm.parseJsonString(_wrap(fragment), path), POISON);
    }

    function _assertFirstOfArray(string memory fragment, string memory path) private view {
        assertEq(vm.parseJsonStringArray(_wrap(fragment), path)[0], POISON);
    }

    function _poisonedUris() private pure returns (string[] memory uris) {
        uris = new string[](1);
        uris[0] = POISON;
    }

    function test_ACESAFEExtension() public {
        ACESAFEData memory data;
        data.denominationToken = POISON;
        data.customProvisions = POISON;

        string memory json = new ACESAFEExtension().getExtensionURI(abi.encode(data));
        _assertField(json, ".ACESAFEDetails.denominationToken");
        _assertField(json, ".ACESAFEDetails.customProvisions");
    }

    function test_ACESAFEExtensionV3() public {
        ACESAFESeriesData memory data;
        data.seriesName = POISON;
        data.denominationToken = POISON;
        data.governingDocumentURIs = _poisonedUris();
        data.customProvisions = POISON;

        string memory json = new ACESAFEExtensionV3().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".ACESAFESeriesDetails.seriesName");
        _assertField(json, ".ACESAFESeriesDetails.denominationToken");
        _assertFirstOfArray(json, ".ACESAFESeriesDetails.governingDocumentURIs");
        _assertField(json, ".ACESAFESeriesDetails.customProvisions");
    }

    function test_CyberCorpComplianceExtension() public {
        FeeDetail[] memory fees = new FeeDetail[](1);
        fees[0].feeName = POISON;
        fees[0].feeToken = POISON;
        fees[0].notes = POISON;

        CyberCorpComplianceData memory data;
        data.holderRestrictions = _poisonedUris();
        data.feeDetails = fees;

        string memory json = new CyberCorpComplianceExtension().getExtensionURI(abi.encode(data));
        _assertFirstOfArray(json, ".CyberCorpCompliance.holderRestrictions");
        _assertField(json, ".CyberCorpCompliance.feeDetails[0].feeName");
        _assertField(json, ".CyberCorpCompliance.feeDetails[0].feeToken");
        _assertField(json, ".CyberCorpCompliance.feeDetails[0].notes");
    }

    function test_CyberCorpExtension() public {
        CyberCorpData memory data = CyberCorpData(POISON, POISON, POISON, POISON);

        string memory json = new CyberCorpExtension().getExtensionURI(abi.encode(data));
        _assertField(json, ".CyberCorpDetails.website");
        _assertField(json, ".CyberCorpDetails.primaryBusinessLine");
        _assertField(json, ".CyberCorpDetails.entityId");
        _assertField(json, ".CyberCorpDetails.metadataURI");
    }

    function test_CyberCorpExtensionV2() public {
        CyberCorpDataV2 memory data = CyberCorpDataV2(POISON, POISON, POISON, POISON, POISON, POISON);

        string memory json = new CyberCorpExtensionV2().getExtensionURI(abi.encode(data));
        _assertField(json, ".CyberCorpDetails.website");
        _assertField(json, ".CyberCorpDetails.primaryBusinessLine");
        _assertField(json, ".CyberCorpDetails.entityId");
        _assertField(json, ".CyberCorpDetails.metadataURI");
        _assertField(json, ".CyberCorpDetails.investorRelationsURI");
        _assertField(json, ".CyberCorpDetails.transferAgent");
    }

    function test_CyberCorpFundExtension() public {
        PortfolioHolding[] memory holdings = new PortfolioHolding[](1);
        holdings[0].portfolioCompany = POISON;
        holdings[0].securityKind = POISON;

        CyberCorpFundData memory data;
        data.fundEntityType = POISON;
        data.icaExceptionRelied = POISON;
        data.portfolioHoldings = holdings;
        data.documentRegistryURI = POISON;
        data.governingDocumentURIs = _poisonedUris();
        data.metadataURI = POISON;

        string memory json = new CyberCorpFundExtension().getExtensionURI(abi.encode(data));
        _assertField(json, ".CyberCorpFundDetails.fundEntityType");
        _assertField(json, ".CyberCorpFundDetails.icaExceptionRelied");
        _assertField(json, ".CyberCorpFundDetails.portfolioHoldings[0].portfolioCompany");
        _assertField(json, ".CyberCorpFundDetails.portfolioHoldings[0].securityKind");
        _assertField(json, ".CyberCorpFundDetails.documentRegistryURI");
        _assertFirstOfArray(json, ".CyberCorpFundDetails.governingDocumentURIs");
        _assertField(json, ".CyberCorpFundDetails.metadataURI");
    }

    function test_FundInterestExtension() public {
        FundInterestSeriesData memory data;
        data.interestClass = POISON;
        data.fundEntityType = POISON;
        data.icaExceptionRelied = POISON;
        data.distributionWaterfallPosition = POISON;
        data.governingDocumentURIs = _poisonedUris();
        data.securityIdentification = SecurityIdentification(POISON, POISON, POISON, POISON, POISON);

        string memory json = new FundInterestExtension().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".FundInterestSeriesDetails.interestClass");
        _assertField(json, ".FundInterestSeriesDetails.fundEntityType");
        _assertField(json, ".FundInterestSeriesDetails.icaExceptionRelied");
        _assertField(json, ".FundInterestSeriesDetails.distributionWaterfallPosition");
        _assertFirstOfArray(json, ".FundInterestSeriesDetails.governingDocumentURIs");
        _assertField(json, ".FundInterestSeriesDetails.securityIdentification.securityID");
        _assertField(json, ".FundInterestSeriesDetails.securityIdentification.securityIDSource");
        _assertField(json, ".FundInterestSeriesDetails.securityIdentification.securityType");
        _assertField(json, ".FundInterestSeriesDetails.securityIdentification.securityDesc");
        _assertField(json, ".FundInterestSeriesDetails.securityIdentification.issuer");
    }

    function test_SAFEExtension() public {
        SAFEData memory data = SAFEData(POISON);

        string memory json = new SAFEExtension().getExtensionURI(abi.encode(data));
        _assertField(json, ".SAFEDetails.customProvisions");
    }

    function test_SAFEExtensionV3() public {
        SAFESeriesData memory data;
        data.seriesName = POISON;
        data.governingDocumentURIs = _poisonedUris();
        data.customProvisions = POISON;

        string memory json = new SAFEExtensionV3().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".SAFESeriesDetails.seriesName");
        _assertFirstOfArray(json, ".SAFESeriesDetails.governingDocumentURIs");
        _assertField(json, ".SAFESeriesDetails.customProvisions");
    }

    function test_SAFTEExtensionV2() public {
        SAFTEDataV2 memory data;
        data.customProvisions = POISON;

        string memory json = new SAFTEExtensionV2().getExtensionURI(abi.encode(data));
        _assertField(json, ".SAFTEDetails.customProvisions");
    }

    function test_SAFTEExtensionV3() public {
        SAFTESeriesData memory data;
        data.seriesName = POISON;
        data.customProvisions = POISON;

        string memory json = new SAFTEExtensionV3().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".SAFTESeriesDetails.seriesName");
        _assertField(json, ".SAFTESeriesDetails.customProvisions");
    }

    function test_SAFTExtensionV2() public {
        SAFTDataV2 memory data;
        data.customProvisions = POISON;

        string memory json = new SAFTExtensionV2().getExtensionURI(abi.encode(data));
        _assertField(json, ".SAFTDetails.customProvisions");
    }

    function test_SAFTExtensionV3() public {
        SAFTSeriesData memory data;
        data.seriesName = POISON;
        data.customProvisions = POISON;

        string memory json = new SAFTExtensionV3().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".SAFTSeriesDetails.seriesName");
        _assertField(json, ".SAFTSeriesDetails.customProvisions");
    }

    function test_TokenWarrantExtensionV2() public {
        TokenWarrantDataV2 memory data;
        data.customProvisions = POISON;

        string memory json = new TokenWarrantExtensionV2().getExtensionURI(abi.encode(data));
        _assertField(json, ".warrantDetails.customProvisions");
    }

    function test_TokenWarrantExtensionV3() public {
        TokenWarrantSeriesData memory data;
        data.seriesName = POISON;
        data.underlyingTokenDescription = POISON;
        data.customProvisions = POISON;

        string memory json = new TokenWarrantExtensionV3().getSeriesExtensionURI(abi.encode(data));
        _assertField(json, ".TokenWarrantSeriesDetails.seriesName");
        _assertField(json, ".TokenWarrantSeriesDetails.underlyingTokenDescription");
        _assertField(json, ".TokenWarrantSeriesDetails.customProvisions");
    }
}
