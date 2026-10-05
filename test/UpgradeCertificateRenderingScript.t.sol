// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentScript} from "../script/libs/DeploymentScript.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {UpgradeCertificateRenderingScript} from "../script/upgrade-certificate-rendering.s.sol";

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {Base64, CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {
    CertificateSVGParams, CertificateSVGParamsV2, SecurityClass, SecuritySeries
} from "../src/CyberCorpConstants.sol";
import {
    CertificateDetails, Endorsement, OwnerDetails, RestrictiveLegend
} from "../src/interfaces/ILedgerEntryToken.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

// A different implementation with the same storage models a URI upgrade without importing historical code.
contract PreviousRenderingUriBuilder is CertificateUriBuilder {
    function previousRevision() external pure returns (bool) {
        return true;
    }
}

contract PreviousImageRenderer {
    function buildCertificateSVG(CertificateSVGParams calldata, uint256) external pure returns (string memory) {
        return "<svg><text>Old certificate</text></svg>";
    }
}

contract UpgradeCertificateRenderingScriptTest is Test {
    uint256 private constant DEPLOYER_KEY = 0xA11CE;
    address private deployer = vm.addr(DEPLOYER_KEY);
    address private ownerSafe = makeAddr("renderer owner Safe");
    UpgradeCertificateRenderingScript private script;
    CertificateUriBuilder private builder;
    BorgAuth private auth;

    function setUp() public {
        script = new UpgradeCertificateRenderingScript();
        vm.deal(deployer, 100 ether);
    }

    function _fixture(address owner, bool currentUri) private {
        auth = new BorgAuth(owner);
        address implementation =
            currentUri ? address(new CertificateUriBuilder()) : address(new PreviousRenderingUriBuilder());
        builder = CertificateUriBuilder(
            address(new ERC1967Proxy(implementation, abi.encodeCall(CertificateUriBuilder.initialize, (address(auth)))))
        );
        address oldImage = address(new PreviousImageRenderer());
        vm.prank(owner);
        builder.setImageBuilder(oldImage);
        // The production failure: a V1 renderer cannot render when the URI builder has no issue date.
        assertEq(vm.parseJsonString(_json(), ".image"), "");
    }

    function testDirectOwnerRefreshesBothRenderersAndPreservesAuth() public {
        _fixture(deployer, false);
        address previous = _implementation();
        string memory path = "script/res/test-renderer-direct.json";
        GnosisTransaction[] memory txs =
            script.runWithArgs(block.chainid, DEPLOYER_KEY, address(builder), ownerSafe, path);
        assertEq(txs.length, 0);
        assertNotEq(_implementation(), previous);
        assertEq(address(builder.AUTH()), address(auth));
        assertEq(auth.userRoles(deployer), 99);
        assertEq(auth.userRoles(ownerSafe), 0);
        _assertLatestRendering();
        assertEq(vm.parseJson(vm.readFile(path), ".transactions"), abi.encode(new bytes[](0)));
        vm.removeFile(path);
    }

    function testSafeBatchAtomicallyUpdatesBothAndRerunClearsStaleBatch() public {
        _fixture(ownerSafe, false);
        string memory path = "script/res/test-renderer-safe.json";
        GnosisTransaction[] memory txs =
            script.runWithArgs(block.chainid, DEPLOYER_KEY, address(builder), ownerSafe, path);
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(builder));
        assertEq(txs[0].value, 0);
        assertEq(
            txs[0].data,
            abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (_implementation(), abi.encodeCall(CertificateUriBuilder.setImageBuilder, (builder.imageBuilder())))
            )
        );
        string memory batch = vm.readFile(path);
        assertEq(vm.parseJsonString(batch, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonAddress(batch, ".transactions[0].to"), address(builder));
        assertEq(vm.parseJsonBytes(batch, ".transactions[0].data"), txs[0].data);
        assertFalse(vm.keyExistsJson(batch, ".transactions[1]"));
        assertEq(address(builder.AUTH()), address(auth));
        assertEq(auth.userRoles(ownerSafe), 99);
        assertEq(auth.userRoles(deployer), 0);
        _assertLatestRendering();

        address implementation = _implementation();
        address image = builder.imageBuilder();
        uint64 nonce = vm.getNonce(deployer);
        txs = script.runWithArgs(block.chainid, DEPLOYER_KEY, address(builder), ownerSafe, path);
        assertEq(txs.length, 0);
        assertEq(_implementation(), implementation);
        assertEq(builder.imageBuilder(), image);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(vm.parseJson(vm.readFile(path), ".transactions"), abi.encode(new bytes[](0)));
        vm.removeFile(path);
    }

    function testCurrentUriOnlyQueuesImagePointerUpdate() public {
        _fixture(ownerSafe, true);
        address implementation = _implementation();
        string memory path = "script/res/test-renderer-image-only.json";
        GnosisTransaction[] memory txs =
            script.runWithArgs(block.chainid, DEPLOYER_KEY, address(builder), ownerSafe, path);
        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(CertificateUriBuilder.setImageBuilder, (builder.imageBuilder())));
        assertEq(_implementation(), implementation);
        _assertLatestRendering();
        vm.removeFile(path);
    }

    function testUnauthorizedConfigurationRefusesBeforeDeployment() public {
        _fixture(makeAddr("different owner"), false);
        address implementation = _implementation();
        address image = builder.imageBuilder();
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert("Neither deployer nor Safe owns URI_BUILDER");
        script.runWithArgs(
            block.chainid, DEPLOYER_KEY, address(builder), ownerSafe, "script/res/test-renderer-refused.json"
        );
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(_implementation(), implementation);
        assertEq(builder.imageBuilder(), image);
    }

    function testRejectsMissingProxyAndPlainImplementation() public {
        vm.expectRevert("URI_BUILDER has no code");
        script.runWithArgs(
            block.chainid, DEPLOYER_KEY, address(0x1234), ownerSafe, "script/res/test-renderer-refused.json"
        );
        address implementation = address(new CertificateUriBuilder());
        vm.expectRevert("URI_BUILDER is not an implementation proxy");
        script.runWithArgs(
            block.chainid, DEPLOYER_KEY, implementation, ownerSafe, "script/res/test-renderer-refused.json"
        );
    }

    function testRejectsWrongChain() public {
        vm.expectRevert(
            abi.encodeWithSelector(DeploymentScript.ChainIdMismatch.selector, block.chainid + 1, block.chainid)
        );
        script.runWithArgs(
            block.chainid + 1, DEPLOYER_KEY, address(0), ownerSafe, "script/res/test-renderer-refused.json"
        );
    }

    function _implementation() private view returns (address) {
        return address(uint160(uint256(vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _json() private view returns (string memory) {
        CertificateDetails memory details;
        details.unitsRepresented = 1e18;
        return builder.buildCertificateUriNotEncoded(
            "Example",
            "Corp",
            "DE",
            "",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesSeed,
            "",
            new RestrictiveLegend[](0),
            details,
            new Endorsement[](0),
            OwnerDetails("Holder", address(0xCAFE)),
            address(0),
            bytes32(0),
            1,
            address(0x1234),
            address(0)
        );
    }

    function _assertLatestRendering() private view {
        CertificateSVGParamsV2 memory params;
        params.certificate.corpName = "Example";
        params.certificate.securityType = SecurityClass.CommonStock;
        params.certificate.securitySeries = SecuritySeries.SeriesSeed;
        params.certificate.units = 1e18;
        params.certificate.jurisdiction = "DE";
        params.certificate.ownerName = "Holder";
        params.certificate.tokenId = 1;
        params.ownerAddress = address(0xCAFE);
        params.considerationKnown = true;
        params.transferRestrictions = new string[](0);
        string memory svg = CertificateImageBuilderContract(builder.imageBuilder()).buildCertificateSVGV2(params, 0);
        assertTrue(_contains(bytes(svg), bytes("Ledger Entry Token")));
        // Verify the proxy's full metadata path uses this renderer, rather than just testing the renderer directly.
        assertEq(
            vm.parseJsonString(_json(), ".image"),
            string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)))
        );
    }

    function _contains(bytes memory haystack, bytes memory needle) private pure returns (bool) {
        for (uint256 i; i + needle.length <= haystack.length; ++i) {
            bool found = true;
            for (uint256 j; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
