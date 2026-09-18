// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateImageBuilder} from "../src/CertificateImageBuilder.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";
import {Test} from "forge-std/Test.sol";

contract TimestampToDateHarness is LeXcheX {
    function lexCheXDate(uint256 timestamp) external pure returns (string memory) {
        return timestampToDate(timestamp);
    }

    function certificateImage(uint256 timestamp) external pure returns (string memory) {
        Accreditation memory accreditation;
        accreditation.expiryDate = timestamp;
        return CertificateImageBuilder.buildLexChexSVG(accreditation);
    }
}

contract TimestampToDateTest is Test {
    TimestampToDateHarness internal harness;

    function setUp() public {
        harness = new TimestampToDateHarness();
    }

    function test_LeXcheX_RendersGregorianCalendarDates() public view {
        assertEq(harness.lexCheXDate(1_786_147_200), "8/8/2026");
        assertEq(harness.lexCheXDate(1_709_164_800), "2/29/2024");
        assertEq(harness.lexCheXDate(1_798_675_200), "12/31/2026");
    }

    function test_CertificateImageBuilder_RendersGregorianCalendarDate() public {
        assertTrue(vm.contains(harness.certificateImage(1_786_147_200), ">8/8/2026</text>"));
    }
}
