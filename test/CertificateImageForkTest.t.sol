// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console2, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice End-to-end fork test against the deployed CyberCorps V2 stack (deployment-addresses.md):
///         1. upgrades the deployed CertificateUriBuilder proxy to the local implementation and
///            points it at a freshly deployed CertificateImageBuilderContract,
///         2. deploys a CyberCorp with a security offer through the deployed CyberCorpFactory,
///         3. has an investor accept the deal (sign + pay + finalize) minting a CyberCertPrinter NFT,
///         4. prints the tokenURI and verifies every stored field is displayed in the SVG image.
contract CertificateImageForkTest is Test {
    using stdStorage for StdStorage;

    bytes32 internal constant TEMPLATE_ID = keccak256("CertificateImageForkTest.template");

    string internal constant CORP_NAME = "Test CyberCorp, LLC";
    string internal constant OWNER_NAME = "Mr. Prepop";
    string internal constant OFFICER_NAME = "Gabriel Shapiro";

    uint256 internal constant UNITS = 2_500_000e18;
    uint256 internal constant INVESTMENT_USD = 250_000e18; // 0.1 per unit
    uint256 internal constant VALUATION_USD = 25_000_000e18;

    DeploymentConstants.CoreDeployment internal net;
    CyberCorpFactory internal factory;
    CyberAgreementRegistry internal registry;

    uint256 internal founderKey;
    address internal founder;
    uint256 internal investorKey;
    address internal investor;

    function setUp() public {
        vm.createSelectFork("base_sepolia");

        net = DeploymentConstants.coreV2(block.chainid);
        factory = CyberCorpFactory(net.cyberCorpFactory);
        registry = CyberAgreementRegistry(net.cyberAgreementRegistry);

        (founder, founderKey) = makeAddrAndKey("cert-image-founder");
        (investor, investorKey) = makeAddrAndKey("cert-image-investor");

        _upgradeDeployedStack();
        _createTemplate();
    }

    /// @dev Mirrors script/upgrade-core-stack.s.sol on the fork: upgrades the deployed
    ///      CyberCorpFactory + CertificateUriBuilder proxies to the local implementations and
    ///      updates all factory reference implementations, so newly deployed corps run local code.
    function _upgradeDeployedStack() internal {
        address upgrader = makeAddr("cert-image-upgrader");
        CyberCorpSingleFactory singleFactory = CyberCorpSingleFactory(factory.cyberCorpSingleFactory());
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(factory.issuanceManagerFactory());
        DealManagerFactory dmFactory = DealManagerFactory(factory.dealManagerFactory());
        RoundManagerFactory rmFactory = RoundManagerFactory(factory.roundManagerFactory());

        _grantOwnerRole(address(factory.AUTH()), upgrader);
        _grantOwnerRole(address(CertificateUriBuilder(net.uriBuilder).AUTH()), upgrader);
        _grantOwnerRole(address(singleFactory.AUTH()), upgrader);
        _grantOwnerRole(address(imFactory.AUTH()), upgrader);
        _grantOwnerRole(address(dmFactory.AUTH()), upgrader);
        _grantOwnerRole(address(rmFactory.AUTH()), upgrader);

        vm.startPrank(upgrader);

        // Factory + uri builder proxies
        IUUPS(address(factory)).upgradeToAndCall(address(new CyberCorpFactory()), "");
        IUUPS(net.uriBuilder).upgradeToAndCall(address(new CertificateUriBuilder()), "");
        CertificateUriBuilder(net.uriBuilder).setImageBuilder(address(new CertificateImageBuilderContract()));

        // Reference implementations used when deploying a new corp stack
        singleFactory.setRefImplementation(address(new CyberCorp()));
        imFactory.setRefImplementation(address(new IssuanceManager()));
        imFactory.setCyberCertPrinterRefImplementation(address(new CyberCertPrinter()));
        imFactory.setCyberScripRefImplementation(address(new CyberScrip()));
        dmFactory.setRefImplementation(address(new DealManager()));
        rmFactory.setRefImplementation(address(new RoundManager()));

        // Make sure the factory has a stable payment token configured
        if (factory.stable() == address(0)) {
            factory.setStable(DeploymentConstants.deps(block.chainid).usdc);
        }

        vm.stopPrank();
    }

    /// @dev Grants OWNER_ROLE (99) on a BorgAuth instance directly via storage
    function _grantOwnerRole(address auth, address user) internal {
        if (BorgAuth(auth).userRoles(user) >= 99) return;
        stdstore.target(auth).sig("userRoles(address)").with_key(user).checked_write(uint256(99));
    }

    function _createTemplate() internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Jurisdiction";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Name";

        vm.prank(net.metalexSafe);
        registry.createTemplate(
            TEMPLATE_ID,
            "Certificate Image Fork Test Template",
            "ipfs://cert-image-fork-template",
            globalFields,
            partyFields
        );
    }

    function test_ForkDeal_MintsCertAndDisplaysAllFieldsInImage() public {
        // ------------------------------------------------------------------
        // 1. Founder deploys a CyberCorp and creates a Common Stock offer
        // ------------------------------------------------------------------
        string[] memory defaultLegend = new string[](2);
        defaultLegend[0] = "Board Consent Required";
        defaultLegend[1] = "Securities Act Restriction";

        CyberCorpFactory.CyberCertData[] memory certData = new CyberCorpFactory.CyberCertData[](1);
        certData[0] = CyberCorpFactory.CyberCertData({
            name: "Common Stock",
            symbol: "TCC-CS",
            uri: "ipfs://cert-image-fork-cert",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(0),
            defaultLegend: defaultLegend,
            printerExtensionData: hex""
        });

        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        certDetails[0] = CertificateDetails({
            signingOfficerName: OFFICER_NAME,
            signingOfficerTitle: "CEO",
            investmentAmountUSD: INVESTMENT_USD,
            issuerUSDValuationAtTimeOfInvestment: VALUATION_USD,
            unitsRepresented: UNITS,
            legalDetails: "Founder restricted stock purchase",
            extensionData: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "DE";

        address[] memory parties = new address[](2);
        parties[0] = founder;
        parties[1] = investor;

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = OFFICER_NAME;
        partyValues[1] = new string[](1);
        partyValues[1][0] = OWNER_NAME;

        ERC20 stable = ERC20(factory.stable());
        uint256 paymentAmount = 250_000 * (10 ** stable.decimals());
        uint256 dealSalt = uint256(keccak256("CertificateImageForkTest.deal"));
        bytes32 expectedAgreementId = keccak256(abi.encode(TEMPLATE_ID, dealSalt, globalValues, parties));

        (string memory templateUri, , string[] memory globalFields, string[] memory partyFields) =
            registry.getTemplateDetails(TEMPLATE_ID);

        vm.startPrank(founder);
        (
            ,
            ,
            ,
            address dealManagerAddr,
            ,
            address[] memory certPrinters,
            bytes32 agreementId,
            uint256[] memory certIds
        ) = factory.deployCyberCorpAndCreateOffer(
            dealSalt,
            CORP_NAME,
            "Limited Liability Company",
            "DE",
            "contact@testcybercorp.xyz",
            "Arbitration",
            founder,
            CompanyOfficer({eoa: founder, name: OFFICER_NAME, contact: "officer@testcybercorp.xyz", title: "CEO"}),
            certData,
            TEMPLATE_ID,
            globalValues,
            parties,
            paymentAmount,
            partyValues,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                expectedAgreementId,
                templateUri,
                globalFields,
                partyFields,
                globalValues,
                partyValues[0],
                founderKey
            ),
            certDetails,
            new address[](0),
            bytes32(0),
            block.timestamp + 30 days
        );
        vm.stopPrank();

        assertEq(agreementId, expectedAgreementId, "unexpected agreement id");

        // ------------------------------------------------------------------
        // 2. Investor accepts the deal: sign + pay, then finalize
        // ------------------------------------------------------------------
        deal(address(stable), investor, paymentAmount);

        vm.startPrank(investor);
        stable.approve(dealManagerAddr, paymentAmount);
        DealManager(dealManagerAddr).signDealAndPay(
            investor,
            agreementId,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                templateUri,
                globalFields,
                partyFields,
                globalValues,
                partyValues[1],
                investorKey
            ),
            partyValues[1],
            true,
            OWNER_NAME,
            ""
        );
        vm.stopPrank();

        DealManager(dealManagerAddr).finalizeDeal(agreementId);

        CyberCertPrinter printer = CyberCertPrinter(certPrinters[0]);
        uint256 tokenId = certIds[0];
        assertEq(printer.ownerOf(tokenId), investor, "investor should own the certificate NFT");

        // ------------------------------------------------------------------
        // 3. Print the tokenURI and verify all stored fields render in the SVG
        // ------------------------------------------------------------------
        string memory uri = printer.tokenURI(tokenId);
        console2.log("=== tokenURI ===");
        console2.log(uri);

        string memory json = _decodeJsonDataUri(uri);
        string memory svg = _extractSvg(json);
        console2.log("=== decoded SVG ===");
        console2.log(svg);

        // Corp name (header and issuer block)
        assertTrue(_contains(svg, string.concat(">", CORP_NAME, "</text>")), "corp name missing");
        // Token ID
        assertTrue(_contains(svg, string.concat(">#", vm.toString(tokenId), "</text>")), "token id missing");
        // Unit label from securityClass
        assertTrue(_contains(svg, ">Shares</text>"), "base unit label missing");
        // unitsRepresented (header counter + stats panel)
        assertTrue(_contains(svg, ">2,500,000</text>"), "units missing");
        // Consideration = investmentAmountUSD / unitsRepresented for stock
        assertTrue(_contains(svg, ">0.1/sh</text>"), "per-share consideration missing");
        // securityClass + securitySeries
        assertTrue(_contains(svg, ">Common Stock Series Seed</text>"), "class/series missing");
        // Registered owner (name from signDealAndPay + truncated address)
        assertTrue(_contains(svg, string.concat(">", OWNER_NAME, " </text>")), "owner name missing");
        assertTrue(_contains(svg, string.concat(">", _truncatedAddress(investor), "</text>")), "owner address missing");
        // Issuer (cert printer contract) truncated address
        assertTrue(_contains(svg, string.concat(">", _truncatedAddress(address(printer)), "</text>")), "issuer address missing");
        // Signing officer
        assertTrue(_contains(svg, string.concat(">", OFFICER_NAME, "</text>")), "officer name missing");
        // Block number of the render
        assertTrue(_contains(svg, string.concat(">block ", vm.toString(block.number), " | ")), "block number missing");
        // Certificate legend -> transfer restrictions
        assertTrue(_contains(svg, "[1] Board Consent Required"), "restriction 1 missing");
        assertTrue(_contains(svg, "[2] Securities Act Restriction"), "restriction 2 missing");
        // Static chrome
        assertTrue(_contains(svg, ">active</text>"), "status chip missing");
        assertTrue(_contains(svg, "Ledger Entry Token"), "ledger label missing");
        assertTrue(_contains(svg, "Tokenized Stock Ledger pursuant to DGCL"), "footer missing");

        // JSON metadata sanity: all stored numeric fields present
        assertTrue(_contains(json, string.concat('"cyberCORPName": "', CORP_NAME, '"')), "json corp name missing");
        assertTrue(_contains(json, '"signingOfficerName": "Gabriel Shapiro"'), "json officer missing");
        assertTrue(_contains(json, '"investmentAmountUSD": "250000.00"'), "json investment missing");
        assertTrue(_contains(json, '"issuerUSDValuationAtTimeOfInvestment": "25000000.00"'), "json valuation missing");
        assertTrue(_contains(json, '"unitsRepresented": "2500000.00"'), "json units missing");

        // ------------------------------------------------------------------
        // 4. Void the certificate and verify the red "voided" badge renders
        // ------------------------------------------------------------------
        vm.prank(printer.issuanceManager());
        printer.voidCert(tokenId);

        string memory voidedSvg = _extractSvg(_decodeJsonDataUri(printer.tokenURI(tokenId)));
        assertTrue(_contains(voidedSvg, ">voided</text>"), "voided label missing");
        assertTrue(_contains(voidedSvg, 'fill="url(#paint4_linear_void)"'), "voided pill missing");
        assertTrue(_contains(voidedSvg, ">VOIDED</text>"), "VOIDED stamp missing");
        assertFalse(_contains(voidedSvg, ">active</text>"), "active label should be gone");
    }

    // ------------------------------------------------------------------
    // Data URI helpers
    // ------------------------------------------------------------------

    function _decodeJsonDataUri(string memory uri) internal pure returns (string memory) {
        bytes memory u = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        require(u.length > prefix.length, "uri too short");
        for (uint256 i = 0; i < prefix.length; i++) {
            require(u[i] == prefix[i], "unexpected uri prefix");
        }
        return string(_base64Decode(_slice(u, prefix.length, u.length)));
    }

    function _extractSvg(string memory json) internal pure returns (string memory) {
        bytes memory marker = bytes('"image": "data:image/svg+xml;base64,');
        bytes memory j = bytes(json);
        int256 start = _indexOf(j, marker, 0);
        require(start >= 0, "image data uri not found in json");
        uint256 b64Start = uint256(start) + marker.length;
        uint256 b64End = b64Start;
        while (b64End < j.length && j[b64End] != '"') {
            b64End++;
        }
        return string(_base64Decode(_slice(j, b64Start, b64End)));
    }

    function _base64Decode(bytes memory data) internal pure returns (bytes memory) {
        require(data.length % 4 == 0, "invalid base64 length");
        if (data.length == 0) return "";

        uint256 padding = 0;
        if (data[data.length - 1] == "=") padding++;
        if (data[data.length - 2] == "=") padding++;

        uint256 outLen = (data.length / 4) * 3 - padding;
        bytes memory result = new bytes(outLen);
        uint256 outIdx = 0;

        for (uint256 i = 0; i < data.length; i += 4) {
            uint256 chunk = (_base64Value(data[i]) << 18)
                | (_base64Value(data[i + 1]) << 12)
                | (_base64Value(data[i + 2]) << 6)
                | _base64Value(data[i + 3]);
            if (outIdx < outLen) result[outIdx++] = bytes1(uint8(chunk >> 16));
            if (outIdx < outLen) result[outIdx++] = bytes1(uint8(chunk >> 8));
            if (outIdx < outLen) result[outIdx++] = bytes1(uint8(chunk));
        }
        return result;
    }

    function _base64Value(bytes1 c) internal pure returns (uint256) {
        uint8 v = uint8(c);
        if (v >= 65 && v <= 90) return v - 65; // A-Z
        if (v >= 97 && v <= 122) return v - 71; // a-z
        if (v >= 48 && v <= 57) return v + 4; // 0-9
        if (v == 43) return 62; // +
        if (v == 47) return 63; // /
        return 0; // '=' padding
    }

    // ------------------------------------------------------------------
    // String helpers
    // ------------------------------------------------------------------

    /// @dev Mirrors the SVG's truncated address format: 0x + first 8 + "..." + last 10 hex chars (lowercase)
    function _truncatedAddress(address addr) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory full = new bytes(40);
        uint160 value = uint160(addr);
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(value >> (8 * (19 - i)));
            full[i * 2] = hexChars[b >> 4];
            full[i * 2 + 1] = hexChars[b & 0x0f];
        }
        bytes memory head = new bytes(8);
        for (uint256 i = 0; i < 8; i++) {
            head[i] = full[i];
        }
        bytes memory tail = new bytes(10);
        for (uint256 i = 0; i < 10; i++) {
            tail[i] = full[30 + i];
        }
        return string(abi.encodePacked("0x", head, "...", tail));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        return _indexOf(bytes(haystack), bytes(needle), 0) >= 0;
    }

    function _indexOf(bytes memory haystack, bytes memory needle, uint256 from) internal pure returns (int256) {
        if (needle.length == 0) return int256(from);
        if (needle.length > haystack.length) return -1;
        for (uint256 i = from; i <= haystack.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return int256(i);
        }
        return -1;
    }

    function _slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = data[i];
        }
        return result;
    }
}
