// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UpgradeSafeLetImageScript} from "../script/upgrade-safe-let-image.s.sol";
import {DeploymentScript} from "../script/libs/DeploymentScript.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {PreviousRenderingUriBuilder, PreviousImageRenderer} from "./UpgradeCertificateRenderingScript.t.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParams, SecurityClass} from "../src/CyberCorpConstants.sol";
import {BorgAuth, BorgAuthACL} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract InlineImageLegacyUri is UUPSUpgradeable, BorgAuthACL {
    function initialize(address auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(auth);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

contract UpgradeSafeLetImageScriptTest is Test {
    function _path() internal view returns (string memory) {
        return string.concat("script/res/test-safe-let-image-", vm.toString(uint32(msg.sig)), ".json");
    }
    UpgradeSafeLetImageScript runner;
    CertificateUriBuilder builder;
    BorgAuth auth;
    address ownerSafe;
    address deploymentWallet;

    function setUp() public {
        runner = new UpgradeSafeLetImageScript();
        ownerSafe = makeAddr("SAFE image Safe");
        vm.setEnv("PRIVATE_KEY_MAIN", "2827"); // Public toy key 0xB0B; never read an env file.
        deploymentWallet = vm.addr(0xB0B);
        vm.deal(deploymentWallet, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    function _fixture(address owner, bool currentUri) internal {
        auth = new BorgAuth(owner);
        address implementation = currentUri ? address(new CertificateUriBuilder()) : address(new PreviousRenderingUriBuilder());
        builder = CertificateUriBuilder(address(new ERC1967Proxy(implementation,
            abi.encodeCall(CertificateUriBuilder.initialize, (address(auth))))));
        address image = address(new PreviousImageRenderer());
        vm.prank(owner);
        builder.setImageBuilder(image);
    }

    function _run() internal returns (GnosisTransaction[] memory) {
        return runner.runWithArgs(block.chainid, address(builder), ownerSafe, _path());
    }

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _assertSafeDisplay() internal {
        CertificateSVGParams memory p;
        p.securityType = SecurityClass.SAFE;
        p.units = 60_000e18; // Seller's balance after a 40% secondary sale of a 100k SAFE.
        p.consideration = 100_000e18;
        p.considerationKnown = true;
        string memory svg = CertificateImageBuilderContract(builder.imageBuilder()).buildCertificateSVG(p, 0);
        assertTrue(vm.contains(svg, '>Consideration</text>'));
        assertTrue(vm.contains(svg, '>60,000</text>'));
        assertTrue(vm.contains(svg, '>Instruments</text>'));
        assertTrue(vm.contains(svg, 'text-anchor="middle">1</text>'));
        p.units = 40_000e18;
        p.consideration = 0; // Secondary buyer has no historical investmentAmountUSD.
        p.considerationKnown = false;
        svg = CertificateImageBuilderContract(builder.imageBuilder()).buildCertificateSVG(p, 0);
        assertTrue(vm.contains(svg, '>40,000</text>'));
    }

    function testAtomicUpgradeAndExactSafeJson() public {
        _fixture(ownerSafe, false);
        address previous = _implementation(address(builder));
        GnosisTransaction[] memory txs = _run();
        assertEq(txs.length, 1);
        assertNotEq(_implementation(address(builder)), previous);
        assertEq(txs[0].to, address(builder));
        assertEq(txs[0].value, 0);
        assertEq(txs[0].data, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall,
            (_implementation(address(builder)), abi.encodeCall(CertificateUriBuilder.setImageBuilder, (builder.imageBuilder())))));
        string memory json = vm.readFile(_path());
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), address(builder));
        assertEq(vm.parseJsonString(json, ".transactions[0].value"), "0");
        assertEq(vm.parseJsonBytes(json, ".transactions[0].data"), txs[0].data);
        assertFalse(vm.keyExistsJson(json, ".transactions[1]"));
        assertEq(address(builder.AUTH()), address(auth));
        assertEq(auth.userRoles(ownerSafe), 99);
        assertEq(auth.userRoles(address(this)), 0);
        _assertSafeDisplay();
        vm.removeFile(_path());
    }

    function testCurrentUriQueuesOnlyImageSetterAndRerunClearsBatch() public {
        _fixture(ownerSafe, true);
        address previous = _implementation(address(builder));
        GnosisTransaction[] memory txs = _run();
        assertEq(_implementation(address(builder)), previous);
        assertEq(txs.length, 1);
        assertEq(txs[0].data, abi.encodeCall(CertificateUriBuilder.setImageBuilder, (builder.imageBuilder())));
        _assertSafeDisplay();
        uint64 nonce = vm.getNonce(deploymentWallet);
        assertEq(_run().length, 0);
        assertEq(vm.getNonce(deploymentWallet), nonce);
        assertEq(vm.parseJson(vm.readFile(_path()), ".transactions"), abi.encode(new bytes[](0)));
        vm.removeFile(_path());
    }

    function testDeployerOwnerStillQueuesForSafe() public {
        _fixture(ownerSafe, true);
        vm.prank(ownerSafe);
        auth.updateRole(deploymentWallet, 99);
        assertEq(_run().length, 1);
        assertEq(auth.userRoles(deploymentWallet), 99);
        assertEq(auth.userRoles(ownerSafe), 99);
        vm.removeFile(_path());
    }

    function testUriUpgradeRetainsAlreadyCurrentImage() public {
        _fixture(ownerSafe, false);
        address image = address(new CertificateImageBuilderContract());
        vm.prank(ownerSafe);
        builder.setImageBuilder(image);
        address oldImplementation = _implementation(address(builder));
        GnosisTransaction[] memory txs = _run();
        assertEq(txs.length, 1);
        assertNotEq(_implementation(address(builder)), oldImplementation);
        assertEq(builder.imageBuilder(), image);
        _assertSafeDisplay();
        vm.removeFile(_path());
    }

    function testLegacyUriWithoutImageGetterUpgradesAtomically() public {
        auth = new BorgAuth(ownerSafe);
        builder = CertificateUriBuilder(address(new ERC1967Proxy(address(new InlineImageLegacyUri()),
            abi.encodeCall(InlineImageLegacyUri.initialize, (address(auth))))));
        GnosisTransaction[] memory txs = _run();
        assertEq(txs.length, 1);
        assertEq(bytes4(txs[0].data), UUPSUpgradeable.upgradeToAndCall.selector);
        assertEq(address(builder.AUTH()), address(auth));
        _assertSafeDisplay();
        vm.removeFile(_path());
    }

    function testWrongSafeRefusesBeforeDeployment() public {
        _fixture(makeAddr("different owner"), true);
        uint64 nonce = vm.getNonce(deploymentWallet);
        vm.expectRevert("Safe does not own URI_BUILDER");
        _run();
        assertEq(vm.getNonce(deploymentWallet), nonce);
    }

    function testZeroSafeRefusesBeforeDeployment() public {
        _fixture(ownerSafe, true);
        uint64 nonce = vm.getNonce(deploymentWallet);
        vm.expectRevert("Safe does not own URI_BUILDER");
        runner.runWithArgs(block.chainid, address(builder), address(0), _path());
        assertEq(vm.getNonce(deploymentWallet), nonce);
    }

    function testMissingProxyOrImplementationRefuses() public {
        uint64 nonce = vm.getNonce(deploymentWallet);
        vm.expectRevert("URI_BUILDER has no code");
        runner.runWithArgs(block.chainid, address(0x1234), ownerSafe, _path());
        address implementation = address(new CertificateUriBuilder());
        vm.expectRevert("URI_BUILDER is not an implementation proxy");
        runner.runWithArgs(block.chainid, implementation, ownerSafe, _path());
        assertEq(vm.getNonce(deploymentWallet), nonce); // No deployment from the configured signing key.
    }

    function testWrongChainRefusesBeforeDeployment() public {
        uint64 nonce = vm.getNonce(deploymentWallet);
        vm.expectRevert(abi.encodeWithSelector(DeploymentScript.ChainIdMismatch.selector, block.chainid + 1, block.chainid));
        runner.runWithArgs(block.chainid + 1, address(0), ownerSafe, _path());
        assertEq(vm.getNonce(deploymentWallet), nonce);
    }

    function testAllFourDefaultChainsAndWrapperMismatch() public {
        _fixture(ownerSafe, true);
        uint256[4] memory chains = [uint256(1), 8453, 42161, 4663];
        for (uint256 i; i < chains.length; ++i) {
            vm.chainId(chains[i]);
            DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chains[i]);
            vm.etch(core.uriBuilder, address(builder).code);
            vm.store(core.uriBuilder, ERC1967Utils.IMPLEMENTATION_SLOT, vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT));
            CertificateUriBuilder target = CertificateUriBuilder(core.uriBuilder);
            if (i == 0) target.initialize(address(new BorgAuth(core.metalexSafe)));
            address image = address(new PreviousImageRenderer());
            vm.prank(core.metalexSafe);
            target.setImageBuilder(image);
            string memory path = runner.batchPath(chains[i]);
            runner.run();
            string memory json = vm.readFile(path);
            assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(chains[i]));
            assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), core.uriBuilder);
            assertEq(bytes4(vm.parseJsonBytes(json, ".transactions[0].data")), CertificateUriBuilder.setImageBuilder.selector);
            uint64 nonce = vm.getNonce(deploymentWallet);
            vm.expectRevert(abi.encodeWithSelector(DeploymentScript.ChainIdMismatch.selector, chains[i] + 1, chains[i]));
            runner.runForChain(chains[i] + 1, path);
            assertEq(vm.getNonce(deploymentWallet), nonce);
            runner.runForChain(chains[i], path);
            assertEq(vm.parseJson(vm.readFile(path), ".transactions"), abi.encode(new bytes[](0)));
            vm.removeFile(path);
        }
    }
}
