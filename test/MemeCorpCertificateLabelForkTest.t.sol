// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {Test, console2} from "forge-std/Test.sol";

interface ITokenUri {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/// @notice The memeCorp label change ships as a refresh of the shared certificate renderers: a new image
///         renderer and a new URI builder implementation behind the existing proxy. Every company on the
///         chain renders through that proxy, so this test renders live Base certificates of each
///         available class before and after the refresh, and requires the same output.
/// @dev Skips when RPC_URL_BASE is not set. The refresh is simulated by writing the proxy's implementation
///      slot and image renderer pointer directly, so the test does not depend on the owner's keys.
contract MemeCorpCertificateLabelForkTest is Test {
    address private constant URI_PROXY = 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// Base LETs whose IssuanceManager renders through URI_PROXY, two per available class where possible
    /// (classes 0 SAFE, 1 SAFT, 2 SAFTE, 4 TokenWarrant, 6 CommonStock, 7 StockOption, 8 PreferredStock).
    function _samples() private pure returns (address[] memory s) {
        s = new address[](11);
        s[0] = 0x9600c086Ad5c601D74D78d205ca539879E875bc2;
        s[1] = 0x9cF6d693600bf9E044497eA10B14085868A11cD8;
        s[2] = 0x101a32A7bb35FA77aCfcf652dd7FBC74680ce143;
        s[3] = 0x9E17C0e30628010865EEe30b88616018e96511de;
        s[4] = 0x6B2e6b44225B2C753Fa3588a3dB9151B2cb3c63c;
        s[5] = 0xbacDC9B32224ea48f475379eb271689b3EcEf6dc;
        s[6] = 0x64d1991d980066cD66b80221704178E036033a4B;
        s[7] = 0xD433573889dC95C195610e73b0af0cb5f9d5C6aB;
        s[8] = 0x13C91f757b25965973a16Bf88900142e3Bf64049;
        s[9] = 0xC3a3A077837400C1ebF31b31cf03cf1811789C35;
        s[10] = 0x4E36A60359D8c5820fc24D63CFB2E889259155e4;
    }

    function testForkExistingCertificatesRenderTheSameAfterTheRefresh() public {
        string memory rpc = vm.envOr("RPC_URL_BASE", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);

        address[] memory lets = _samples();
        string[] memory before = new string[](lets.length);
        bool[] memory rendered = new bool[](lets.length);
        uint256 renderedCount;
        for (uint256 i; i < lets.length; ++i) {
            try ITokenUri(lets[i]).tokenURI(0) returns (string memory uri) {
                before[i] = uri;
                rendered[i] = true;
                ++renderedCount;
            } catch {
                console2.log("tokenURI(0) reverts before the refresh; skipped", lets[i]);
            }
        }
        assertGt(renderedCount, 5, "too few live certificates rendered");

        CertificateImageBuilderContract newImage = new CertificateImageBuilderContract();
        CertificateUriBuilder newImplementation = new CertificateUriBuilder();
        vm.store(URI_PROXY, IMPLEMENTATION_SLOT, bytes32(uint256(uint160(address(newImplementation)))));
        _setImageBuilder(address(newImage));
        assertEq(CertificateUriBuilder(URI_PROXY).imageBuilder(), address(newImage), "image renderer pointer");

        uint256 changed;
        for (uint256 i; i < lets.length; ++i) {
            if (!rendered[i]) continue;
            string memory afterUri = ITokenUri(lets[i]).tokenURI(0);
            if (keccak256(bytes(afterUri)) != keccak256(bytes(before[i]))) {
                ++changed;
                console2.log("rendering changed for", lets[i]);
            }
        }
        assertEq(changed, 0, "existing certificates must render the same");
    }

    /// @dev Finds the storage word that holds the image renderer pointer and replaces it.
    function _setImageBuilder(address image) private {
        address current = CertificateUriBuilder(URI_PROXY).imageBuilder();
        for (uint256 slot; slot < 64; ++slot) {
            if (vm.load(URI_PROXY, bytes32(slot)) == bytes32(uint256(uint160(current)))) {
                vm.store(URI_PROXY, bytes32(slot), bytes32(uint256(uint160(image))));
                return;
            }
        }
        revert("image renderer slot not found");
    }
}
