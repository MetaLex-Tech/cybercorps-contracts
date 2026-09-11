pragma solidity ^0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {Test} from "forge-std/Test.sol";

interface ILegacyMetadataPrinter {
    function tokenURI(uint256 id) external view returns (string memory);
    function ownerOf(uint256 id) external view returns (address);
    function DEPLOY_VERSION() external view returns (string memory);
}

contract ReservationRendererHarness is CertificateUriBuilder {
    function reservationJson(address printer, uint256 id) external view returns (string memory) {
        return unitsReservedToJson(printer, id);
    }
}

contract CertificateUriBuilderLegacyTest is Test {
    ReservationRendererHarness internal renderer;
    address internal constant PRINTER = address(0x1234);

    function setUp() public {
        renderer = new ReservationRendererHarness();
        vm.etch(PRINTER, hex"00");
    }

    function testMissingGetterOmitsFieldWithoutVersionGetter() public {
        vm.mockCallRevert(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), hex"");
        vm.mockCallRevert(PRINTER, abi.encodeWithSignature("DEPLOY_VERSION()"), hex"");
        assertEq(renderer.reservationJson(PRINTER, 1), "");
    }

    function testSupportedGettersPreserveNonzeroValues() public {
        for (uint256 version = 1; version <= 5; ++version) {
            vm.mockCall(PRINTER, abi.encodeWithSignature("DEPLOY_VERSION()"), abi.encode(vm.toString(version)));
            vm.mockCall(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), abi.encode(125e16));
            assertEq(renderer.reservationJson(PRINTER, 1), ', "unitsReserved": "1.25"');
        }
    }

    function testSupportedZeroRemainsExplicit() public {
        vm.mockCall(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), abi.encode(uint256(0)));
        assertEq(renderer.reservationJson(PRINTER, 1), ', "unitsReserved": "0.00"');
    }

    function testNoPrinterOmitsField() public view {
        assertEq(renderer.reservationJson(address(0), 1), "");
    }

    function testMissingGetterOmitsFieldRegardlessOfVersion() public {
        vm.mockCallRevert(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), hex"");
        for (uint256 version = 1; version <= 6; ++version) {
            vm.mockCall(PRINTER, abi.encodeWithSignature("DEPLOY_VERSION()"), abi.encode(vm.toString(version)));
            assertEq(renderer.reservationJson(PRINTER, 1), "");
        }
    }

    function testExplicitGetterErrorOmitsField() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "reservation failure");
        vm.mockCallRevert(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), reason);
        assertEq(renderer.reservationJson(PRINTER, 1), "");
    }

    function testMalformedGetterResponseOmitsField() public {
        vm.mockCall(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), hex"01");
        assertEq(renderer.reservationJson(PRINTER, 1), "");
    }

    function testNoCodeAndEmptyReturnOmitField() public {
        assertEq(renderer.reservationJson(address(0x5678), 1), "");
        vm.mockCall(PRINTER, abi.encodeWithSignature("unitsReserved(uint256)", 1), hex"");
        assertEq(renderer.reservationJson(PRINTER, 1), "");
    }
}

contract CertificateUriBuilderLegacyForkTest is Test {
    address internal constant PRINTER = 0x2614b85a83bE8a5B4c007F29910E9Ec75f5498BC;

    function testRealV3CertificateAfterBuilderOnlyUpgrade() public {
        _checkUpgrade(false);
    }

    function testRealV3CertificateAfterAtomicRenderingUpgrade() public {
        _checkUpgrade(true);
    }

    function _checkUpgrade(bool replaceImage) internal {
        // Pinned. The test asserts the exact owner and corp name, which change with chain state.
        vm.createSelectFork("base_sepolia", 46_649_711);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        ILegacyMetadataPrinter printer = ILegacyMetadataPrinter(PRINTER);
        assertEq(printer.DEPLOY_VERSION(), "3");
        address ownerBefore = printer.ownerOf(1);
        vm.expectRevert();
        printer.tokenURI(1);

        CertificateUriBuilder builder = CertificateUriBuilder(core.uriBuilder);
        address imageBefore = builder.imageBuilder();
        address authBefore = address(builder.AUTH());
        CertificateUriBuilder implementation = new CertificateUriBuilder();
        address nextImage = replaceImage ? address(new CertificateImageBuilderContract()) : imageBefore;
        // Local fork impersonation only. No transactions are broadcast.
        vm.prank(core.metalexSafe);
        builder.upgradeToAndCall(address(implementation), abi.encodeCall(CertificateUriBuilder.setImageBuilder, (nextImage)));
        assertEq(builder.imageBuilder(), nextImage);
        assertEq(address(builder.AUTH()), authBefore);
        assertEq(printer.ownerOf(1), ownerBefore);

        string memory uri = printer.tokenURI(1);
        string memory json = _decodeUri(uri);
        vm.parseJson(json); // Must be valid JSON, not merely a non-reverting call.
        assertFalse(vm.keyExistsJson(json, ".unitsReserved"));
        assertEq(vm.parseJsonAddress(json, ".currentOwner.ownerAddress"), ownerBefore);
        assertGt(bytes(vm.parseJsonString(json, ".cyberCORPName")).length, 0);
        // The old image renderer cannot represent an unknown date. URI-only upgrades degrade to
        // a blank image rather than display 1970; the atomic upgrade always produces the new SVG.
        if (replaceImage) assertGt(bytes(vm.parseJsonString(json, ".image")).length, 0);
        assertEq(vm.parseJsonString(json, ".type"), "SAFE");
        assertEq(vm.parseJsonString(json, ".cyberCORPName"), "Bokkerijders NV");
    }

    function _decodeUri(string memory uri) internal pure returns (string memory) {
        bytes memory input = bytes(uri);
        bytes memory prefix = bytes("data:application/json;base64,");
        require(input.length > prefix.length, "empty URI");
        for (uint256 i; i < prefix.length; ++i) {
            require(input[i] == prefix[i], "wrong URI prefix");
        }
        bytes memory alphabet = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
        uint256 length = (input.length - prefix.length) / 4 * 3;
        if (input[input.length - 1] == "=") --length;
        if (input[input.length - 2] == "=") --length;
        bytes memory output = new bytes(length);
        uint256 accumulator;
        uint256 bits;
        uint256 cursor;
        for (uint256 i = prefix.length; i < input.length && input[i] != "="; ++i) {
            uint256 value;
            while (value < 64 && alphabet[value] != input[i]) ++value;
            require(value < 64, "invalid base64");
            accumulator = (accumulator << 6) | value;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                output[cursor++] = bytes1(uint8(accumulator >> bits));
            }
        }
        return string(output);
    }
}
