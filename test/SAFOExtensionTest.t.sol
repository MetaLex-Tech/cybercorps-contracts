// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParams, SecurityClass, SecuritySeries, UnlockStartTimeType, UnlockingIntervalType} from "../src/CyberCorpConstants.sol";
import {CertificateDetails, Endorsement, OwnerDetails} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth, BorgAuthACL} from "../src/libs/auth.sol";
import {SAFOData, SAFOExtension} from "../src/storage/extensions/SAFOExtension.sol";
import {StaticCertificateImageBuilder} from "./CertificateUriBuilderJsonEscapingTest.t.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

// Any attempted series/class resolution fails. The base extension needs neither.
contract SAFOBaseContext {
    function unitsReserved(uint256) external pure returns (uint256) {
        return 0;
    }

    function issuanceManager() external view returns (address) {
        return address(this);
    }

    function CORP() external pure returns (address) {
        return address(0);
    }

    fallback() external {
        revert("Unexpected scoped read");
    }
}

contract SAFOExtensionNext is SAFOExtension {
    function revision() external pure returns (uint256) {
        return 2;
    }
}

contract SAFOExtensionTest is Test {
    SAFOExtension internal extension;
    SAFOExtension internal implementation;
    BorgAuth internal auth;

    function setUp() public {
        auth = new BorgAuth(address(this));
        implementation = new SAFOExtension();
        extension = SAFOExtension(
            address(
                new ERC1967Proxy(address(implementation), abi.encodeCall(SAFOExtension.initialize, (address(auth))))
            )
        );
    }

    function _terms() internal pure returns (SAFOData memory d) {
        d.schemaVersion = 1;
        d.minProjectReserve = 200_000; // 20%, no implicit 18-decimal scaling.
        d.maxUnlockingCliffPeriod = 365 days;
        d.maxUnlockingPeriod = 4 * 365 days;
        d.requiresTokenholderGovernance = true;
        d.outsideDateEnabled = true;
        d.outsideDate = 3;
        d.hasUnlockParameters = true;
        d.unlockStartTimeType = UnlockStartTimeType.setTime;
        d.unlockStartTime = 1_900_000_000;
        d.unlockingPeriod = 48;
        d.unlockingCliffPeriod = 12;
        d.unlockingCliffPercentage = 250_000;
        d.unlockingIntervalType = UnlockingIntervalType.monthly;
        d.customProvisions = unicode'Quote " \\ newline\n tab\t café and 雪';
    }

    function _json(SAFOData memory d) internal view returns (string memory) {
        return string.concat('{"instrument":"SAFO"', extension.getExtensionURI(abi.encode(d)), "}");
    }

    function test_RoundTripAndJsonKeepUnitsBooleansAndEscapedText() public view {
        SAFOData memory d = _terms();
        bytes memory encoded = extension.encodeExtensionData(d);
        assertEq(abi.encode(extension.decodeExtensionData(encoded)), abi.encode(d));
        assertTrue(extension.validateExtensionData(encoded));
        assertTrue(extension.supportsExtensionType(keccak256("SAFO")));
        assertFalse(extension.supportsExtensionType(keccak256("SAFTE")));
        string memory json = _json(d);
        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".SAFODetails.minProjectReserve"), "200000");
        assertEq(vm.parseJsonString(json, ".SAFODetails.maxUnlockingPeriod"), "126144000");
        assertEq(vm.parseJsonString(json, ".SAFODetails.outsideDate"), "3");
        assertTrue(vm.parseJsonBool(json, ".SAFODetails.requiresTokenholderGovernance"));
        assertTrue(vm.parseJsonBool(json, ".SAFODetails.outsideDateEnabled"));
        assertTrue(vm.parseJsonBool(json, ".SAFODetails.hasUnlockParameters"));
        assertEq(vm.parseJsonString(json, ".SAFODetails.unlockingCliffPercentage"), "250000");
        assertEq(vm.parseJsonString(json, ".SAFODetails.unlockingIntervalType"), "monthly");
        assertEq(vm.parseJsonString(json, ".SAFODetails.customProvisions"), d.customProvisions);
    }

    function test_DisabledOptionsAndZeroValuesRemainDistinctFromEnabledZero() public view {
        SAFOData memory d;
        d.schemaVersion = 1;
        string memory json = _json(d);
        assertFalse(vm.parseJsonBool(json, ".SAFODetails.outsideDateEnabled"));
        assertFalse(vm.parseJsonBool(json, ".SAFODetails.requiresTokenholderGovernance"));
        assertFalse(vm.parseJsonBool(json, ".SAFODetails.hasUnlockParameters"));
        assertFalse(vm.keyExistsJson(json, ".SAFODetails.outsideDate"));
        assertFalse(vm.keyExistsJson(json, ".SAFODetails.unlockingPeriod"));
        d.outsideDateEnabled = true;
        d.hasUnlockParameters = true;
        json = _json(d);
        assertEq(vm.parseJsonString(json, ".SAFODetails.outsideDate"), "0");
        assertEq(vm.parseJsonString(json, ".SAFODetails.unlockingPeriod"), "0");
        assertEq(vm.parseJsonString(json, ".SAFODetails.unlockStartTimeType"), "agreementExecutionTime");
    }

    function testFuzz_ValidPayloadRoundTripsWithoutEconomicArithmetic(
        uint256 reserve,
        uint256 cliff,
        uint256 period,
        bool governance,
        bool outsideEnabled,
        uint256 yearsAfterIssue,
        bytes memory custom
    ) public view {
        SAFOData memory d;
        d.schemaVersion = 1;
        d.minProjectReserve = bound(reserve, 0, 1_000_000);
        d.maxUnlockingCliffPeriod = cliff;
        d.maxUnlockingPeriod = period;
        d.requiresTokenholderGovernance = governance;
        d.outsideDateEnabled = outsideEnabled;
        d.outsideDate = outsideEnabled ? yearsAfterIssue : 0;
        d.customProvisions = string(custom);
        bytes memory encoded = extension.encodeExtensionData(d);
        assertEq(abi.encode(extension.decodeExtensionData(encoded)), abi.encode(d));
        vm.parseJson(_json(d));
    }

    function test_AllScheduleEnumsRender() public view {
        SAFOData memory d = _terms();
        d.unlockStartTime = 0;
        for (uint8 start; start < 3; start++) {
            d.unlockStartTimeType = UnlockStartTimeType(start);
            for (uint8 interval; interval < 5; interval++) {
                d.unlockingIntervalType = UnlockingIntervalType(interval);
                vm.parseJson(_json(d));
            }
        }
    }

    function test_RejectMalformedWrongVersionAndImpossiblePercentages() public {
        vm.expectRevert();
        extension.decodeExtensionData("");
        vm.expectRevert();
        extension.decodeExtensionData(hex"123456");
        SAFOData memory d = _terms();
        d.schemaVersion = 2;
        vm.expectRevert(abi.encodeWithSelector(SAFOExtension.UnsupportedSchemaVersion.selector, 2));
        extension.decodeExtensionData(abi.encode(d));
        d.schemaVersion = 1;
        d.minProjectReserve = 1_000_001;
        vm.expectRevert(abi.encodeWithSelector(SAFOExtension.InvalidPercentage.selector, 1_000_001));
        extension.encodeExtensionData(d);
        d.minProjectReserve = 1_000_000;
        d.unlockingCliffPercentage = 1_000_001;
        vm.expectRevert(abi.encodeWithSelector(SAFOExtension.InvalidPercentage.selector, 1_000_001));
        extension.validateExtensionData(abi.encode(d));
    }

    function test_RejectInactiveFieldsWithNonzeroValues() public {
        SAFOData memory d = _terms();
        d.outsideDateEnabled = false;
        vm.expectRevert(SAFOExtension.UnexpectedOutsideDate.selector);
        extension.encodeExtensionData(d);
        d.outsideDate = 0;
        d.hasUnlockParameters = false;
        vm.expectRevert(SAFOExtension.UnexpectedUnlockParameters.selector);
        extension.encodeExtensionData(d);
        d.hasUnlockParameters = true;
        d.unlockStartTimeType = UnlockStartTimeType.tgeTime;
        vm.expectRevert(SAFOExtension.UnexpectedUnlockStartTime.selector);
        extension.encodeExtensionData(d);
    }

    function test_InitializersAndUpgradeAuthority() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(auth));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        extension.initialize(address(auth));
        vm.expectRevert(BorgAuthACL.BorgAuthACL_ZeroAddress.selector);
        new ERC1967Proxy(address(implementation), abi.encodeCall(SAFOExtension.initialize, (address(0))));
        SAFOExtensionNext next = new SAFOExtensionNext();
        address outsider = address(0xBAD);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, outsider));
        extension.upgradeToAndCall(address(next), "");
        bytes memory encoded = extension.encodeExtensionData(_terms());
        extension.upgradeToAndCall(address(next), "");
        assertEq(SAFOExtensionNext(address(extension)).revision(), 2);
        assertEq(address(extension.AUTH()), address(auth));
        assertEq(abi.encode(extension.decodeExtensionData(encoded)), abi.encode(_terms()));
    }

    function test_CurrentUriBuilderUsesBasePayloadWithoutScopedReads() public {
        CertificateUriBuilder builder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeCall(CertificateUriBuilder.initialize, (address(auth)))
                )
            )
        );
        builder.setImageBuilder(address(new StaticCertificateImageBuilder()));
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "President",
            investmentAmountUSD: 1000 ether,
            issuerUSDValuationAtTimeOfInvestment: 100_000 ether,
            unitsRepresented: 0,
            legalDetails: "Governing law: Delaware",
            extensionData: extension.encodeExtensionData(_terms())
        });
        string memory json = builder.buildCertificateUriNotEncoded(
            "Test Corp",
            "C-Corp",
            "DE",
            "",
            SecurityClass.SAFO,
            SecuritySeries.SeriesA,
            "",
            new string[](0),
            details,
            new Endorsement[](0),
            OwnerDetails("Investor", address(0xA11CE)),
            address(0),
            bytes32(0),
            1,
            address(new SAFOBaseContext()),
            address(extension)
        );
        vm.parseJson(json);
        assertEq(builder.securityClassToString(SecurityClass.SAFO), "SAFO");
        assertEq(builder.securityClassToUnit(SecurityClass.SAFO), "Dollars");
        assertEq(vm.parseJsonString(json, ".SAFODetails.minProjectReserve"), "200000");
        assertEq(vm.parseJsonString(json, ".SAFODetails.customProvisions"), _terms().customProvisions);
    }

    function test_NativeImageShowsOneSAFOAndTotalConsideration() public {
        CertificateSVGParams memory params;
        params.corpName = "Test Corp";
        params.securityType = SecurityClass.SAFO;
        params.securitySeries = SecuritySeries.NA;
        params.units = 1500 ether;
        params.consideration = 1500 ether;
        params.considerationKnown = true;
        params.ownerName = "Investor";
        params.officerName = "Officer";
        params.officerTitle = "President";
        params.transferRestrictions = new string[](0);
        string memory svg = new CertificateImageBuilderContract().buildCertificateSVG(params, 1_900_000_000);
        assertTrue(_contains(svg, ">SAFO</text>"));
        assertTrue(_contains(svg, ">Instruments</text>"));
        assertTrue(_contains(svg, ">1</text>"));
        assertFalse(_contains(svg, "/unit"));
        assertFalse(_contains(svg, "/sh"));
    }

    function _contains(string memory text, string memory part) private pure returns (bool) {
        bytes memory a = bytes(text);
        bytes memory b = bytes(part);
        if (b.length > a.length) return false;
        for (uint256 i; i <= a.length - b.length; ++i) {
            bool matches = true;
            for (uint256 j; j < b.length; ++j) {
                if (a[i + j] != b[j]) { matches = false; break; }
            }
            if (matches) return true;
        }
        return false;
    }
}
