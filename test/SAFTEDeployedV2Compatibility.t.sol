// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";

import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CertificateDetails} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {SAFTEExtensionV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTEExtensionV3, SAFTEResolvedData, SAFTESeriesData} from "../src/storage/extensions/SAFTEExtensionV3.sol";

import {MockCyberCorp, MockIssuanceManager} from "./CyberCertPrinterTest.t.sol";
import {DeployedSAFTEDataV2, DeployedSAFTEExtensionV2} from "./fixtures/DeployedSAFTEExtensionV2.sol";
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SAFTECompatibilityUriBuilder is CertificateUriBuilder {
    constructor() {
        imageBuilder = address(new CertificateImageBuilderContract());
    }
}

/// @notice Source-level compatibility with the user-supplied deployed V2 implementation.
/// Uses actual extension/token proxies and tokenURI, not a mocked extension response.
/// The fixed payload is representative of the deployed ABI, not fetched from a live token.
contract SAFTEDeployedV2CompatibilityTest is Test {
    DeployedSAFTEExtensionV2 internal legacy;
    LedgerEntryToken internal token;
    MockIssuanceManager internal manager;
    address internal constant HOLDER = address(0xCAFE);

    function setUp() public {
        BorgAuth auth = new BorgAuth(address(this));
        legacy = DeployedSAFTEExtensionV2(
            address(
                new ERC1967Proxy(
                    address(new DeployedSAFTEExtensionV2()),
                    abi.encodeCall(DeployedSAFTEExtensionV2.initialize, (address(auth)))
                )
            )
        );
        SAFTECompatibilityUriBuilder builder = new SAFTECompatibilityUriBuilder();
        MockCyberCorp corp = new MockCyberCorp(address(0xDE1), address(0xA0));
        manager = new MockIssuanceManager(address(corp), address(builder));
        token = LedgerEntryToken(
            address(
                new ERC1967Proxy(
                    address(new LedgerEntryToken()),
                    abi.encodeCall(
                        LedgerEntryToken.initialize,
                        (
                            new string[](0),
                            "Legacy SAFTE",
                            "SAFTE",
                            "ipfs://certificate",
                            address(manager),
                            SecurityClass.SAFTE,
                            SecuritySeries.SeriesSeed,
                            address(legacy),
                            bytes("")
                        )
                    )
                )
            )
        );
        vm.warp(1704067200);
        _mint(1, _payload());
    }

    /// @dev Frozen ABI encoding of the deployed SAFTEDataV2 tuple.
    /// Offsets, enum ordinals and field order are literal so changing a development
    /// struct/encoder cannot silently change both the input and expected output.
    function _payload() internal pure returns (bytes memory) {
        return hex"0000000000000000000000000000000000000000000000000000000000000020"
        hex"0000000000000000000000000000000000000000000000000000000000000002"
        hex"0000000000000000000000000000000000000000000000000000000065920080"
        hex"0000000000000000000000000000000000000000000000000000000001e13380"
        hex"000000000000000000000000000000000000000000000000000000000076a700"
        hex"00000000000000000000000000000000000000000000000000000000000009c4"
        hex"0000000000000000000000000000000000000000000000000000000000000004"
        hex"0000000000000000000000000000000000000000000000000000000000000002"
        hex"00000000000000000000000000000000000000000000000000000000000007d0"
        hex"0000000000000000000000000000000000000000000000000000000000002ee0"
        hex"00000000000000000000000000000000000000000014adf4b7320334b9000000"
        hex"0000000000000000000000000000000000000000000000000000000000000160"
        hex"0000000000000000000000000000000000000000000000000000000000000017"
        hex"426f61726420636f6e73656e742072657175697265642e000000000000000000";
    }

    function _mint(uint256 id, bytes memory payload) internal {
        CertificateDetails memory details;
        details.signingOfficerName = "Officer";
        details.signingOfficerTitle = "CEO";
        details.unitsRepresented = 100e18;
        details.investmentAmountUSD = 250_000e18;
        details.extensionData = payload;
        vm.prank(address(manager));
        token.safeMintAndAssign(HOLDER, id, details, "Legacy investor");
    }

    function testFrozenPayloadMatchesDeployedAndDevelopmentV2ABI() public {
        DeployedSAFTEDataV2 memory decoded = legacy.decodeExtensionData(_payload());
        assertEq(uint256(decoded.unlockStartTimeType), 2);
        assertEq(decoded.unlockStartTime, 1704067200);
        assertEq(decoded.unlockingPeriod, 31536000);
        assertEq(decoded.unlockingCliffPeriod, 7776000);
        assertEq(decoded.unlockingCliffPercentage, 2500);
        assertEq(uint256(decoded.unlockingIntervalType), 4);
        assertEq(uint256(decoded.tokenCalculationMethod), 2);
        assertEq(decoded.minCompanyReserve, 2000);
        assertEq(decoded.tokenPremiumMultiplier, 12000);
        assertEq(decoded.protocolUSDValuationAtTimeofInvestment, 25_000_000e18);
        assertEq(decoded.customProvisions, "Board consent required.");
        assertEq(legacy.encodeExtensionData(decoded), _payload());

        SAFTEExtensionV2 development = new SAFTEExtensionV2();
        assertEq(abi.encode(development.decodeExtensionData(_payload())), abi.encode(decoded));
        assertEq(development.encodeExtensionData(development.decodeExtensionData(_payload())), _payload());
    }

    function testTokenUriFallsBackToDeployedV2WithoutResolvedCapability() public {
        assertTrue(legacy.supportsExtensionType(keccak256("SAFTE_V2")));
        assertFalse(legacy.supportsExtensionType(keccak256("SAFTE_V3")));
        (bool ok,) = address(legacy).staticcall(abi.encodeWithSignature("supportsResolvedExtensionData()"));
        assertFalse(ok, "the deployed implementation really lacks the new selector");

        vm.expectCall(address(legacy), abi.encodeWithSignature("supportsResolvedExtensionData()"));
        vm.expectCall(address(legacy), abi.encodeCall(legacy.getExtensionURI, (_payload())));
        string memory json = _json(1);
        _assertSAFTEFields(json);
        assertFalse(vm.keyExistsJson(json, ".SAFTESeriesDetails"));
        assertEq(vm.parseJsonAddress(json, ".currentOwner.ownerAddress"), HOLDER);
        assertEq(token.getActiveCertificateDetails(1).extensionData, _payload());
    }

    function testEmptyLegacyPayloadIsSkipped() public {
        _mint(2, "");
        string memory json = _json(2);
        assertFalse(vm.keyExistsJson(json, ".SAFTEDetails"));
        assertEq(vm.parseJsonAddress(json, ".currentOwner.ownerAddress"), HOLDER);
    }

    /// @notice Current PR rendering propagates invalid extension payload failures.
    /// Do not mistake a missing capability (supported fallback) for corrupt data.
    function testMalformedLegacyPayloadReverts() public {
        _mint(2, hex"1234");
        vm.expectRevert();
        token.tokenURI(2);
    }

    function testUpgradeToV3PreservesLegacyCertificateWithAndWithoutSeries() public {
        legacy.upgradeToAndCall(address(new SAFTEExtensionV3()), "");
        SAFTEExtensionV3 upgraded = SAFTEExtensionV3(address(legacy));
        assertTrue(upgraded.supportsResolvedExtensionData());

        SAFTEResolvedData memory resolved = upgraded.resolveCert(address(token), 1);
        assertEq(abi.encode(resolved.certificate), _payload());
        assertEq(resolved.series.seriesName, "");
        assertEq(resolved.series.governingDocumentURIs.length, 0);
        string memory json = _json(1);
        _assertSAFTEFields(json);
        assertFalse(vm.keyExistsJson(json, ".SAFTESeriesDetails"));

        SAFTESeriesData memory series;
        series.seriesName = "Series Seed";
        series.governingDocumentURIs = new string[](1);
        series.governingDocumentURIs[0] = "ipfs://series-terms";
        series.customProvisions = "Series-wide terms";
        vm.prank(address(manager));
        token.setSeriesData(upgraded.encodeSeriesExtensionData(series));

        resolved = upgraded.resolveCert(address(token), 1);
        assertEq(abi.encode(resolved.certificate), _payload());
        assertEq(abi.encode(resolved.series), abi.encode(series));
        assertEq(token.getActiveCertificateDetails(1).extensionData, _payload());
        json = _json(1);
        _assertSAFTEFields(json);
        assertEq(vm.parseJsonString(json, ".SAFTESeriesDetails.seriesName"), "Series Seed");
        assertEq(vm.parseJsonString(json, ".SAFTESeriesDetails.customProvisions"), "Series-wide terms");
    }

    function _assertSAFTEFields(string memory json) internal pure {
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockStartTimeType"), "setTime");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockStartTime"), "1704067200");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockingPeriod"), "31536000");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockingCliffPeriod"), "7776000");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockingCliffPercentage"), "2500");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.unlockingIntervalType"), "monthly");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.tokenCalculationMethod"), "dollarProRataToProtocolVal");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.minCompanyReserve"), "2000");
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.tokenPremiumMultiplier"), "12000");
        assertEq(
            vm.parseJsonString(json, ".SAFTEDetails.protocolUSDValuationAtTimeofInvestment"),
            "25000000000000000000000000"
        );
        assertEq(vm.parseJsonString(json, ".SAFTEDetails.customProvisions"), "Board consent required.");
    }

    function _json(uint256 id) internal view returns (string memory) {
        bytes memory uri = bytes(token.tokenURI(id));
        bytes memory prefix = bytes("data:application/json;base64,");
        assertGt(uri.length, prefix.length);
        for (uint256 i; i < prefix.length; ++i) {
            assertEq(uri[i], prefix[i]);
        }
        bytes memory decoded = new bytes((uri.length - prefix.length) / 4 * 3);
        uint256 accumulator;
        uint256 bits;
        uint256 cursor;
        for (uint256 i = prefix.length; i < uri.length && uri[i] != "="; ++i) {
            uint256 c = uint8(uri[i]);
            uint256 value = c >= 65 && c <= 90
                ? c - 65
                : c >= 97 && c <= 122 ? c - 71 : c >= 48 && c <= 57 ? c + 4 : c == 43 ? 62 : 63;
            accumulator = (accumulator << 6) | value;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                decoded[cursor++] = bytes1(uint8(accumulator >> bits));
            }
        }
        assembly ("memory-safe") {
            mstore(decoded, cursor)
        }
        return string(decoded);
    }
}
