// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BootstrapRobinhoodScript, IRobinhoodFactory} from "../script/bootstrap-robinhood.s.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";

import {UpgradeCoreScript} from "../script/upgrade-core.s.sol";

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import "forge-std/Test.sol";

contract BootstrapHarness is BootstrapRobinhoodScript {
    function manifest() external view returns (Creation[] memory) {
        return _manifest();
    }

    function checkAddress(Creation memory entry) external pure {
        _checkAddress(entry);
    }

    function replay(Creation memory entry, address sender) external {
        _checkAddress(entry);
        _replay(entry, sender);
    }
}

interface IBridgeComponent {
    function getRefImplementation() external view returns (address);
    function getPlatformPayable() external view returns (address);
    function getDefaultFeeRatio() external view returns (uint256);
    function isWhitelistedToken(address token) external view returns (bool);
}

contract BootstrapToken {
    uint8 public constant decimals = 6;
    uint256 public totalSupply = 1_000_000e6;
}

contract BootstrapRobinhoodTest is Test {
    struct OriginalCreation {
        address addr;
        bytes data;
    }

    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    BootstrapHarness internal script;
    DeploymentConstants.CoreDeployment internal core;
    BootstrapRobinhoodScript.Config internal config;
    address internal historicalOwner;

    function setUp() public {
        vm.chainId(46630);
        script = new BootstrapHarness();
        core = DeploymentConstants.coreV2(block.chainid);
        historicalOwner = script.HISTORICAL_OWNER();
        vm.deal(historicalOwner, 100 ether);
        vm.etch(
            script.REPLAY_FACTORY(),
            hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
        );
        // Actual historical init code, not current mocks of the original proxy/storage layout.
        OriginalCreation[] memory entries =
            abi.decode(vm.parseJson(vm.readFile("test/res/robinhood-original-deployment.json")), (OriginalCreation[]));
        for (uint256 i; i < entries.length; ++i) {
            (bool ok,) = script.REPLAY_FACTORY().call(entries[i].data);
            assertTrue(ok, "original deployment failed");
            assertGt(entries[i].addr.code.length, 0);
        }
        // Model the original script's Safe role and deployer role removal.
        vm.etch(core.metalexSafe, hex"00");
        vm.startPrank(historicalOwner);
        BorgAuth(core.auth).updateRole(core.metalexSafe, 200);
        BorgAuth(core.auth).zeroOwner();
        vm.stopPrank();
        config = BootstrapRobinhoodScript.Config(address(new BootstrapToken()), core.metalexSafe, 30, true);
        // Original deployment creates a template; it must survive both upgrades unchanged.
        string[] memory fields = new string[](1);
        fields[0] = "purchaseAmount";
        vm.prank(core.metalexSafe);
        CyberAgreementRegistry(core.cyberAgreementRegistry).createTemplate(
            bytes32(uint256(1)), "SAFE", "ipfs://original", fields, fields
        );
    }

    function test_OriginalToBridge_PreservesSingletonsAndConfiguresFactories() public {
        bytes32 registryImpl = vm.load(core.cyberAgreementRegistry, IMPL_SLOT);
        bytes32 uriImpl = vm.load(core.uriBuilder, IMPL_SLOT);
        GnosisTransaction[] memory batch = script.runWithArgs(historicalOwner, config);
        assertEq(batch.length, 14);
        string memory json = script.safeBatchJson();
        assertEq(vm.parseJsonString(json, ".chainId"), "46630");
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), core.metalexSafe);
        for (uint256 i; i < batch.length; ++i) {
            string memory path = string.concat(".transactions[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(json, string.concat(path, ".to")), batch[i].to);
            assertEq(vm.parseJsonBytes(json, string.concat(path, ".data")), batch[i].data);
        }
        // No core-admin transaction is executed by the deployment phase.
        assertEq(address(uint160(uint256(vm.load(core.cyberCorpFactory, IMPL_SLOT)))), script.ORIGINAL_FACTORY_IMPL());
        script.simulateSafeBatch(config);
        assertEq(vm.load(core.cyberAgreementRegistry, IMPL_SLOT), registryImpl);
        assertEq(vm.load(core.uriBuilder, IMPL_SLOT), uriImpl);
        _assertBridge();
    }

    function test_V5CoreAcceptsBridge_ThenCreatesCorporation() public {
        bytes32 domain = CyberAgreementRegistry(core.cyberAgreementRegistry).DOMAIN_SEPARATOR();
        bytes32 templateHash = _templateHash();
        script.runWithArgs(historicalOwner, config);
        script.simulateSafeBatch(config);
        UpgradeCoreScript upgrade = new UpgradeCoreScript();
        uint256 deployerKey = 0xA11CE;
        vm.deal(vm.addr(deployerKey), 100 ether);
        GnosisTransaction[] memory batch = upgrade.runWithArgs(block.chainid, deployerKey);
        for (uint256 i; i < batch.length; ++i) {
            vm.prank(core.metalexSafe);
            (bool ok, bytes memory reason) = batch[i].to.call(batch[i].data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
        assertEq(IRobinhoodFactory(core.cyberCorpFactory).registryAddress(), core.cyberAgreementRegistry);
        assertEq(IRobinhoodFactory(core.cyberCorpFactory).uriBuilder(), core.uriBuilder);
        assertEq(CyberAgreementRegistry(core.cyberAgreementRegistry).DOMAIN_SEPARATOR(), domain);
        assertEq(_templateHash(), templateHash);
        assertEq(DealManagerFactory(core.dealManagerFactory).getUnderlyingDefaultFeeRatio(), config.primaryFeeBps);
        assertEq(DealManagerFactory(core.dealManagerFactory).getUnderlyingDefaultSecondaryFeeRatio(), 600);
        address officer = makeAddr("officer");
        (address corp, address auth, address im, address dm, address rm) = CyberCorpFactory(core.cyberCorpFactory)
            .deployCyberCorp(
            keccak256("Robinhood acceptance"),
            "Test company",
            "C Corp",
            "Delaware",
            "test@example.com",
            "Arbitration",
            officer,
            CompanyOfficer(officer, "Test officer", "test@example.com", "CEO")
        );
        assertGt(corp.code.length, 0);
        assertGt(im.code.length, 0);
        assertGt(dm.code.length, 0);
        assertGt(rm.code.length, 0);
        assertEq(BorgAuth(auth).userRoles(officer), 200);
        address implementation = address(uint160(uint256(vm.load(core.cyberCorpFactory, IMPL_SLOT))));
        vm.expectRevert(
            abi.encodeWithSelector(
                BootstrapRobinhoodScript.WrongImplementation.selector, core.cyberCorpFactory, implementation
            )
        );
        script.runWithArgs(historicalOwner, config);
    }

    function test_MainnetUsesSameAddresses() public {
        vm.chainId(4663);
        assertFalse(DeploymentConstants.isTestnet(block.chainid));
        script.runWithArgs(historicalOwner, config);
        script.simulateSafeBatch(config);
        _assertBridge();
    }

    function test_RerunBeforeV5_ReusesAllDeployments() public {
        script.runWithArgs(historicalOwner, config);
        script.simulateSafeBatch(config);
        uint64 nonce = vm.getNonce(historicalOwner);
        GnosisTransaction[] memory batch = script.runWithArgs(historicalOwner, config);
        assertEq(vm.getNonce(historicalOwner), nonce);
        assertEq(batch.length, 13); // No downgrade/repeated upgrade call.
        script.simulateSafeBatch(config);
        _assertBridge();
    }

    function test_RefusesUnsupportedChain() public {
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(BootstrapRobinhoodScript.UnsupportedChain.selector, 8453));
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesUnacknowledgedExistingCorps() public {
        config.freshDeployment = false;
        vm.expectRevert(BootstrapRobinhoodScript.InvalidConfig.selector);
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesTokenWithoutCode() public {
        config.stable = address(0x1234);
        vm.expectRevert(BootstrapRobinhoodScript.InvalidConfig.selector);
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesMissingSafe() public {
        vm.etch(core.metalexSafe, hex"");
        vm.expectRevert(abi.encodeWithSelector(BootstrapRobinhoodScript.MissingCode.selector, core.metalexSafe));
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesSafeWithoutCoreAuthority() public {
        vm.prank(core.metalexSafe);
        BorgAuth(core.auth).zeroOwner();
        vm.expectRevert(
            abi.encodeWithSelector(BootstrapRobinhoodScript.MissingOwner.selector, core.auth, core.metalexSafe)
        );
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesWrongCreate2Factory() public {
        vm.etch(script.REPLAY_FACTORY(), hex"00");
        vm.expectRevert(abi.encodeWithSelector(BootstrapRobinhoodScript.WrongCode.selector, script.REPLAY_FACTORY()));
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesFreshLexchexWithWrongSender() public {
        vm.expectRevert(
            abi.encodeWithSelector(BootstrapRobinhoodScript.MissingOwner.selector, core.lexchexAuth, address(0x1234))
        );
        script.runWithArgs(address(0x1234), config);
    }

    function test_RefusesUnknownFactoryImplementation_NoDowngrade() public {
        vm.store(core.cyberCorpFactory, IMPL_SLOT, bytes32(uint256(uint160(core.uriBuilder))));
        // Check the implementation before calling factory-specific getters.
        vm.expectRevert(
            abi.encodeWithSelector(
                BootstrapRobinhoodScript.WrongImplementation.selector, core.cyberCorpFactory, core.uriBuilder
            )
        );
        script.runWithArgs(historicalOwner, config);
    }

    function test_ManifestTamperedCreationAddressIsRejected() public {
        BootstrapRobinhoodScript.Creation[] memory entries = script.manifest();
        entries[0].data[32] = bytes1(uint8(entries[0].data[32]) ^ 1);
        vm.expectRevert(abi.encodeWithSelector(BootstrapRobinhoodScript.InvalidCreation.selector, entries[0].addr));
        script.checkAddress(entries[0]);
    }

    function test_RefusesWrongCodeAtOccupiedHistoricalAddress() public {
        BootstrapRobinhoodScript.Creation[] memory entries = script.manifest();
        vm.etch(entries[0].addr, hex"00");
        vm.expectRevert(abi.encodeWithSelector(BootstrapRobinhoodScript.WrongCode.selector, entries[0].addr));
        script.runWithArgs(historicalOwner, config);
    }

    function test_RefusesChangedComponentProxyImplementation() public {
        script.runWithArgs(historicalOwner, config);
        vm.store(core.roundManagerFactory, IMPL_SLOT, bytes32(uint256(uint160(core.uriBuilder))));
        vm.expectRevert(
            abi.encodeWithSelector(
                BootstrapRobinhoodScript.WrongImplementation.selector, core.roundManagerFactory, core.uriBuilder
            )
        );
        script.runWithArgs(historicalOwner, config);
    }

    function _templateHash() internal view returns (bytes32) {
        (bool ok, bytes memory data) = core.cyberAgreementRegistry.staticcall(
            abi.encodeWithSignature("getTemplateDetails(bytes32)", bytes32(uint256(1)))
        );
        require(ok, "template read failed");
        return keccak256(data);
    }

    function _assertBridge() internal view {
        IRobinhoodFactory factory = IRobinhoodFactory(core.cyberCorpFactory);
        assertEq(factory.registryAddress(), core.cyberAgreementRegistry);
        assertEq(factory.uriBuilder(), core.uriBuilder);
        assertEq(address(factory.AUTH()), core.auth);
        assertEq(BorgAuth(core.auth).userRoles(historicalOwner), 0);
        assertEq(BorgAuth(core.auth).userRoles(core.metalexSafe), 200);
        assertEq(factory.issuanceManagerFactory(), core.issuanceManagerFactory);
        assertEq(factory.roundManagerFactory(), core.roundManagerFactory);
        assertEq(factory.stable(), config.stable);
        assertEq(IBridgeComponent(core.roundManagerFactory).getPlatformPayable(), config.feeRecipient);
        assertEq(IBridgeComponent(core.roundManagerFactory).getDefaultFeeRatio(), config.primaryFeeBps);
        assertTrue(IBridgeComponent(core.roundManagerFactory).isWhitelistedToken(config.stable));
        assertEq(IBridgeComponent(core.dealManagerFactory).getDefaultFeeRatio(), config.primaryFeeBps);
        assertGt(IBridgeComponent(core.issuanceManagerFactory).getRefImplementation().code.length, 0);
        assertEq(BorgAuth(core.lexchexAuth).userRoles(core.lexchexMinter), BorgAuth(core.lexchexAuth).ADMIN_ROLE());
        assertEq(BorgAuth(core.lexchexAuth).userRoles(core.cyberCorpFactory), BorgAuth(core.lexchexAuth).OWNER_ROLE());
    }
}
