// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UpgradeCertificateFooterScript} from "../script/upgrade-certificate-footer.s.sol";
import {DeploymentScript} from "../script/libs/DeploymentScript.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {PreviousRenderingUriBuilder, PreviousImageRenderer} from "./UpgradeCertificateRenderingScript.t.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateSVGParamsV2} from "../src/CyberCorpConstants.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Utils.sol";

contract UpgradeCertificateFooterScriptTest is Test {
    string private PATH;
    UpgradeCertificateFooterScript runner;
    CertificateUriBuilder builder;
    BorgAuth auth;
    address ownerSafe;
    address deployer;

    function setUp() public {
        runner = new UpgradeCertificateFooterScript();
        deployer = address(this);
        ownerSafe = makeAddr("footer Safe");
        vm.deal(deployer, 100 ether);
    }

    function fixture(address owner) internal {
        auth = new BorgAuth(owner);
        // Deliberately differs from current URI source: the footer script must preserve it.
        builder = CertificateUriBuilder(address(new ERC1967Proxy(address(new PreviousRenderingUriBuilder()),
            abi.encodeCall(CertificateUriBuilder.initialize, (address(auth))))));
        address image = address(new PreviousImageRenderer());
        vm.prank(owner);
        builder.setImageBuilder(image);
    }

    function testDeployerOwnerStillRequiresSafeAndRerunIsNoOp() public {
        PATH = "script/res/test-footer-deployer-owner.json";
        fixture(ownerSafe);
        vm.prank(ownerSafe);
        auth.updateRole(deployer, 99);
        bytes32 implementation = vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT);
        address oldImage = builder.imageBuilder();
        assertEq(_run(block.chainid, address(builder), ownerSafe, PATH).length, 1);
        assertNotEq(builder.imageBuilder(), oldImage);
        assertEq(vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT), implementation);
        assertEq(address(builder.AUTH()), address(auth));
        assertEq(auth.userRoles(deployer), 99);
        assertEq(auth.userRoles(ownerSafe), 99);
        assertFooter();
        uint64 nonce = vm.getNonce(deployer);
        address image = builder.imageBuilder();
        _run(block.chainid, address(builder), ownerSafe, PATH);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(builder.imageBuilder(), image);
        assertEq(vm.parseJson(vm.readFile(PATH), ".transactions"), abi.encode(new bytes[](0)));
        vm.removeFile(PATH);
    }

    function testSafeBatchOnlySetsImageAndClearsOnRerun() public {
        PATH = "script/res/test-footer-safe.json";
        fixture(ownerSafe);
        bytes32 implementation = vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT);
        GnosisTransaction[] memory txs = _run(block.chainid, address(builder), ownerSafe, PATH);
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(builder));
        assertEq(txs[0].value, 0);
        assertEq(txs[0].data, abi.encodeCall(CertificateUriBuilder.setImageBuilder, (builder.imageBuilder())));
        string memory batch = vm.readFile(PATH);
        assertEq(vm.parseJsonString(batch, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonAddress(batch, ".transactions[0].to"), address(builder));
        assertEq(vm.parseJsonBytes(batch, ".transactions[0].data"), txs[0].data);
        assertFalse(vm.keyExistsJson(batch, ".transactions[1]"));
        assertEq(vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT), implementation);
        assertEq(address(builder.AUTH()), address(auth));
        assertEq(auth.userRoles(ownerSafe), 99);
        assertEq(auth.userRoles(deployer), 0);
        assertFooter();
        uint64 nonce = vm.getNonce(deployer);
        assertEq(_run(block.chainid, address(builder), ownerSafe, PATH).length, 0);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(vm.parseJson(vm.readFile(PATH), ".transactions"), abi.encode(new bytes[](0)));
        vm.removeFile(PATH);
    }

    function testUnauthorizedOwnerRefusesBeforeDeployment() public {
        PATH = "script/res/test-footer-unauthorized.json";
        fixture(makeAddr("other owner"));
        uint64 nonce = vm.getNonce(deployer);
        address image = builder.imageBuilder();
        vm.expectRevert("Safe does not own URI_BUILDER");
        _run(block.chainid, address(builder), ownerSafe, PATH);
        assertEq(vm.getNonce(deployer), nonce);
        assertEq(builder.imageBuilder(), image);
    }

    function testWrongChainRefusesBeforeDeployment() public {
        PATH = "script/res/test-footer-wrong-chain.json";
        vm.expectRevert(abi.encodeWithSelector(DeploymentScript.ChainIdMismatch.selector, 1, block.chainid));
        _run(1, address(0), ownerSafe, PATH);
    }

    function testMissingProxyAndImplementationRefused() public {
        PATH = "script/res/test-footer-invalid-proxy.json";
        vm.expectRevert("URI_BUILDER has no code");
        _run(block.chainid, address(0x1234), ownerSafe, PATH);
        address implementation = address(new CertificateUriBuilder());
        vm.expectRevert("URI_BUILDER is not an implementation proxy");
        _run(block.chainid, implementation, ownerSafe, PATH);
    }

    function testDefaultEntrypointOnAllFiveChains() public {
        PATH = "script/res/test-footer-default-chains.json";
        fixture(ownerSafe);
        uint256[5] memory chains = [uint256(1), 8453, 42161, 11155111, 84532];
        for (uint256 i; i < chains.length; ++i) {
            vm.chainId(chains[i]);
            DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chains[i]);
            // Put a real initialized proxy at the default address, with the configured Safe as owner.
            vm.etch(core.uriBuilder, address(builder).code);
            vm.store(core.uriBuilder, ERC1967Utils.IMPLEMENTATION_SLOT,
                vm.load(address(builder), ERC1967Utils.IMPLEMENTATION_SLOT));
            BorgAuth defaultAuth = new BorgAuth(core.metalexSafe);
            CertificateUriBuilder defaultBuilder = CertificateUriBuilder(core.uriBuilder);
            if (i == 0) defaultBuilder.initialize(address(defaultAuth));
            // Defaults share the same proxy and Safe; resetting image keeps each iteration substantive.
            address oldImage = address(new PreviousImageRenderer());
            vm.prank(core.metalexSafe);
            defaultBuilder.setImageBuilder(oldImage);
            bytes32 implementation = vm.load(core.uriBuilder, ERC1967Utils.IMPLEMENTATION_SLOT);
            PATH = runner.batchPath(chains[i], core.uriBuilder);
            runner.run();
            assertEq(vm.parseJsonString(vm.readFile(PATH), ".chainId"), vm.toString(chains[i]));
            assertEq(vm.parseJsonAddress(vm.readFile(PATH), ".transactions[0].to"), core.uriBuilder);
            assertEq(vm.load(core.uriBuilder, ERC1967Utils.IMPLEMENTATION_SLOT), implementation);

            // The wrapper's explicit argument still refuses a wrong RPC before deployment.
            uint64 nonce = vm.getNonce(deployer);
            vm.expectRevert(abi.encodeWithSelector(
                DeploymentScript.ChainIdMismatch.selector, chains[i] + 1, chains[i]));
            runner.runForChain(chains[i] + 1, PATH);
            assertEq(vm.getNonce(deployer), nonce);
            runner.runForChain(chains[i], PATH);
            assertEq(vm.parseJson(vm.readFile(PATH), ".transactions"), abi.encode(new bytes[](0)));
            vm.removeFile(PATH);
        }

    }

    function _run(uint256 chainId, address proxy, address owner, string memory path)
        internal returns (GnosisTransaction[] memory)
    {
        return runner.runWithArgs(chainId, proxy, owner, path);
    }

    function assertFooter() internal {
        CertificateSVGParamsV2 memory p;
        p.certificate.corpName = "Example LLC";
        string memory svg = CertificateImageBuilderContract(builder.imageBuilder()).buildCertificateSVGV2(p, 0);
        assertTrue(vm.contains(svg,
            "This constitutes an official entry on the tokenized securities ledger of Example LLC.</text>"));
    }
}
