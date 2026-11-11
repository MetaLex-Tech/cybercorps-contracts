// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CentQuoteParams, ICentQuoter, RobinhoodCentSafeScript} from "../script/robinhood-cent-safe.s.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/Test.sol";

contract CentSafeHarness is RobinhoodCentSafeScript {
    function savedRunBudget(string memory path, uint256 maximum, uint256 valuation)
        external
        returns (uint256, uint256)
    {
        return _savedRunBudget(path, maximum, valuation);
    }

    function defaultMaxEthIn(uint256 quoted) external pure returns (uint256) {
        return _defaultMaxEthIn(quoted);
    }

    function savedRunWindow(string memory path, bytes32 salt, uint256 start, uint256 end)
        external
        returns (uint256, uint256)
    {
        return _savedRunWindow(path, salt, start, end);
    }

    function buyMissing(Config memory c, address investor, uint256 key) external {
        _buyMissing(c, investor, key);
    }
}

/// @notice Configuration regressions use public values only, without RPC or keys.
contract RobinhoodCentSafeConfigTest is Test {
    CentSafeHarness script;
    string constant PATH = "script/res/robinhood-cent-safe-config-test.local.json";
    bytes32 constant SALT = keccak256("public-config-regression");

    function setUp() public {
        script = new CentSafeHarness();
        if (vm.exists(PATH)) vm.removeFile(PATH);
        vm.warp(1_800_000_000);
    }

    function test_DefaultDatesPersistAcrossRetryAndExpiry() public {
        (uint256 start, uint256 end) = script.savedRunWindow(PATH, SALT, 0, 0);
        assertEq(start, block.timestamp - 1 hours);
        assertEq(end, block.timestamp + 1 days);
        vm.warp(end + 1 days);
        (uint256 retryStart, uint256 retryEnd) = script.savedRunWindow(PATH, SALT, 0, 0);
        assertEq(retryStart, start);
        assertEq(retryEnd, end);
        assertLt(retryEnd, block.timestamp); // Never silently opens a new round.
        vm.removeFile(PATH);
    }

    function test_ExplicitDatesPreservedAndChangesRefused() public {
        uint256 start = block.timestamp - 60;
        uint256 end = block.timestamp + 600;
        script.savedRunWindow(PATH, SALT, start, end);
        script.savedRunWindow(PATH, SALT, start, end);
        vm.expectRevert(RobinhoodCentSafeScript.SavedRunWindowChanged.selector);
        script.savedRunWindow(PATH, SALT, start, end + 1);
        vm.expectRevert(RobinhoodCentSafeScript.SavedRunWindowChanged.selector);
        script.savedRunWindow(PATH, SALT, start + 1, end);
        vm.expectRevert(RobinhoodCentSafeScript.SavedRunWindowChanged.selector);
        script.savedRunWindow(PATH, keccak256("different-salt"), 0, 0);
        vm.removeFile(PATH);
    }

    function test_DifferentSaltFileCreatesDeliberateNewWindow() public {
        string memory otherPath = "script/res/robinhood-cent-safe-config-other-test.local.json";
        if (vm.exists(otherPath)) vm.removeFile(otherPath);
        (, uint256 end) = script.savedRunWindow(PATH, SALT, 0, 0);
        vm.warp(block.timestamp + 60);
        (, uint256 otherEnd) = script.savedRunWindow(otherPath, keccak256("new-run"), 0, 0);
        assertEq(otherEnd, end + 60);
        vm.removeFile(PATH);
        vm.removeFile(otherPath);
    }

    function test_DefaultBudgetRoundingAndCeiling() public {
        assertEq(script.defaultMaxEthIn(101), 107);
        assertEq(script.defaultMaxEthIn(4_435_612_676_307), 4_657_393_310_123);
        vm.expectRevert(RobinhoodCentSafeScript.InvalidConfig.selector);
        script.defaultMaxEthIn(0);
        uint256 ceiling = script.DEFAULT_ETH_CEILING();
        vm.expectRevert();
        script.defaultMaxEthIn(ceiling);
        vm.expectRevert();
        script.defaultMaxEthIn(type(uint256).max);
    }

    function test_BudgetAndValuationPersistAndChangesRefused() public {
        script.savedRunWindow(PATH, SALT, 0, 0);
        (uint256 maximum, uint256 valuation) = script.savedRunBudget(PATH, 5_000_000_000_000, 0);
        assertEq(maximum, 5_000_000_000_000);
        assertEq(valuation, 10_000_000);
        (uint256 retryMaximum, uint256 retryValuation) = script.savedRunBudget(PATH, 0, 0);
        assertEq(retryMaximum, maximum);
        assertEq(retryValuation, valuation);
        vm.expectRevert(RobinhoodCentSafeScript.SavedRunBudgetChanged.selector);
        script.savedRunBudget(PATH, maximum + 1, 0);
        vm.expectRevert(RobinhoodCentSafeScript.SavedRunBudgetChanged.selector);
        script.savedRunBudget(PATH, 0, valuation + 1);
        vm.removeFile(PATH);
    }
}

/// @notice Only generated public signers and local ETH funding. Never reads a
/// deployment key or mints/mock-funds USDG. Actual deployed DEX/core contracts.
contract RobinhoodCentSafeScriptTest is Test {
    CentSafeHarness script;
    RobinhoodCentSafeScript.Config config;
    address officer;
    address investor;
    uint256 officerKey;
    uint256 investorKey;
    bool enabled;

    function setUp() public {
        string memory url = vm.envOr("CENT_SAFE_FORK_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url, vm.envUint("CENT_SAFE_FORK_BLOCK"));
        enabled = true;
        script = new CentSafeHarness();
        (officer, officerKey) = makeAddrAndKey("robinhood-cent-safe-officer-20261030");
        (investor, investorKey) = makeAddrAndKey("robinhood-cent-safe-investor-20261030");
        // ETH funding only: USDG must be bought from actual pool liquidity.
        vm.deal(officer, 1 ether);
        vm.deal(investor, 1 ether);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(investor), 0);
        (uint256 quoted,) =
            ICentQuoter(script.QUOTER()).quoteExactOutputSingle(CentQuoteParams(script.poolKey(), true, 10_000, ""));
        config = RobinhoodCentSafeScript.Config({
            salt: keccak256("cent-safe-fork-20261030"),
            start: block.timestamp - 60,
            end: block.timestamp + 1 hours,
            maxEthIn: quoted * 101 / 100 + 1,
            gasReserve: 0.0001 ether,
            valuationCapUSD: 10_000_000,
            templateId: bytes32(uint256(32)),
            payout: officer,
            companyName: "Cent SAFE Fork Rehearsal",
            companyJurisdiction: "DE",
            officerName: "Rehearsal Officer",
            officerContact: "officer@example.invalid",
            investorName: "Rehearsal Investor",
            investorContact: "investor@example.invalid",
            investorType: "Individual",
            investorJurisdiction: "GB"
        });
    }

    modifier forkOnly() {
        if (!enabled) {
            vm.skip(true);
            return;
        }
        _;
    }

    function test_LiveQuotedDefaultBudgetFundsSafe() public forkOnly {
        string memory path = "script/res/robinhood-cent-safe-live-config-test.local.json";
        if (vm.exists(path)) vm.removeFile(path);
        (config.start, config.end) = script.savedRunWindow(path, config.salt, 0, 0);
        (uint256 quoted,) =
            ICentQuoter(script.QUOTER()).quoteExactOutputSingle(CentQuoteParams(script.poolKey(), true, 10_000, ""));
        (config.maxEthIn, config.valuationCapUSD) = script.savedRunBudget(path, 0, 0);
        assertEq(config.maxEthIn, (quoted * 105 + 99) / 100);
        assertLe(config.maxEthIn, script.DEFAULT_ETH_CEILING());
        assertEq(config.valuationCapUSD, 10_000_000);
        RobinhoodCentSafeScript.Result memory r = script.execute(config, officerKey, investorKey);
        assertEq(LedgerEntryToken(r.certificate).ownerOf(r.tokenId), investor);
        (uint256 retryMaximum, uint256 retryValuation) = script.savedRunBudget(path, 0, 0);
        assertEq(retryMaximum, config.maxEthIn);
        assertEq(retryValuation, config.valuationCapUSD);
        vm.removeFile(path);
    }

    function test_LoadConfigWithoutPublicSettingsAndFundSafe() public forkOnly {
        // Empty public settings model an unconfigured invocation and mask any
        // inherited operator overrides. Neither key variable is read or changed.
        string[16] memory names = [
            "SAFE_REHEARSAL_SALT",
            "SAFE_ROUND_START",
            "SAFE_ROUND_END",
            "SAFE_MAX_ETH_IN_WEI",
            "SAFE_GAS_RESERVE_WEI",
            "SAFE_VALUATION_CAP_USD",
            "SAFE_TEMPLATE_ID",
            "SAFE_COMPANY_PAYABLE",
            "SAFE_COMPANY_NAME",
            "SAFE_COMPANY_JURISDICTION",
            "SAFE_OFFICER_NAME",
            "SAFE_OFFICER_CONTACT",
            "SAFE_INVESTOR_NAME",
            "SAFE_INVESTOR_CONTACT",
            "SAFE_INVESTOR_TYPE",
            "SAFE_INVESTOR_JURISDICTION"
        ];
        for (uint256 i; i < names.length; ++i) {
            vm.setEnv(names[i], "");
        }
        bytes32 salt = keccak256(abi.encode("RobinhoodCentSAFE.default.v1", officer));
        string memory path = string.concat("script/res/robinhood-cent-safe-", vm.toString(salt), ".local.json");
        if (vm.exists(path)) vm.removeFile(path);
        config = script.loadConfig(officer);
        assertEq(config.salt, salt);
        assertEq(config.templateId, bytes32(uint256(32)));
        assertEq(config.payout, officer);
        assertEq(config.companyName, "CyberCorp SAFE Rehearsal");
        assertEq(config.investorJurisdiction, "TEST ONLY");
        assertEq(config.officerContact, "officer@example.invalid");
        RobinhoodCentSafeScript.Result memory r = script.execute(config, officerKey, investorKey);
        assertEq(LedgerEntryToken(r.certificate).ownerOf(r.tokenId), investor);
        RobinhoodCentSafeScript.Config memory retry = script.loadConfig(officer);
        assertEq(keccak256(abi.encode(retry)), keccak256(abi.encode(config)));
        vm.removeFile(path);
    }

    function test_RealSwapToOneCentSafeAndIdempotentRerun() public forkOnly {
        IERC20Metadata usdg = IERC20Metadata(script.USDG());
        address platform = DeploymentConstants.coreV2(4663).metalexSafe;
        uint256 investorEthBefore = investor.balance;
        uint256 payoutBefore = usdg.balanceOf(officer);
        uint256 feeBefore = usdg.balanceOf(platform);
        RobinhoodCentSafeScript.Result memory r = script.execute(config, officerKey, investorKey);
        assertGt(investorEthBefore - investor.balance, 0);
        assertLe(investorEthBefore - investor.balance, config.maxEthIn);
        assertEq(usdg.balanceOf(investor), 0);
        assertEq(usdg.balanceOf(officer) - payoutBefore, 9_950); // 0.00995 USDG
        assertEq(usdg.balanceOf(platform) - feeBefore, 50); // 0.00005 USDG
        assertEq(usdg.allowance(investor, r.roundManager), 0);
        assertEq(usdg.balanceOf(r.roundManager), 0);
        LedgerEntryToken cert = LedgerEntryToken(r.certificate);
        assertEq(cert.ownerOf(r.tokenId), investor);
        assertEq(cert.legalOwnerOf(r.tokenId), investor);
        assertEq(uint256(cert.securityType()), uint256(SecurityClass.SAFE));
        assertEq(uint256(cert.securitySeries()), uint256(SecuritySeries.SeriesSeed));
        assertEq(cert.getCertificateDetails(r.tokenId).investmentAmountUSD, 1e16);
        RoundManager manager = RoundManager(r.roundManager);
        assertEq(uint256(manager.getEscrowDetails(r.agreementId).status), uint256(EscrowStatus.FINALIZED));
        CyberAgreementRegistry registry =
            CyberAgreementRegistry(DeploymentConstants.coreV2(4663).cyberAgreementRegistry);
        assertTrue(registry.hasSigned(r.agreementId, officer));
        assertTrue(registry.hasSigned(r.agreementId, investor));
        (address otherInvestor, uint256 otherKey) = makeAddrAndKey("another-cent-safe-investor");
        vm.deal(otherInvestor, 1 ether);
        vm.expectRevert(RobinhoodCentSafeScript.IncompatibleExistingState.selector);
        script.execute(config, officerKey, otherKey);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(otherInvestor), 0);
        assertEq(otherInvestor.balance, 1 ether);
        uint256 remainingEth = investor.balance;
        uint256 companyBalance = usdg.balanceOf(officer);
        uint256 platformBalance = usdg.balanceOf(platform);
        // Completed reruns must not spend anything, even after the original end.
        vm.warp(config.end + 1);
        RobinhoodCentSafeScript.Result memory again = script.execute(config, officerKey, investorKey);
        assertEq(again.agreementId, r.agreementId);
        assertEq(again.certificate, r.certificate);
        assertEq(again.tokenId, r.tokenId);
        assertEq(investor.balance, remainingEth);
        assertEq(usdg.balanceOf(officer), companyBalance);
        assertEq(usdg.balanceOf(platform), platformBalance);
        console2.log("SWAP_ETH_SPENT_WEI", investorEthBefore - remainingEth);
        console2.log("CENT_SAFE_METADATA", cert.tokenURI(r.tokenId));
    }

    function test_ResumeAfterSwapDoesNotSwapAgain() public forkOnly {
        script.buyMissing(config, investor, investorKey);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(investor), 10_000);
        uint256 ethAfterSwap = investor.balance;
        RobinhoodCentSafeScript.Result memory r = script.execute(config, officerKey, investorKey);
        assertEq(investor.balance, ethAfterSwap);
        assertEq(LedgerEntryToken(r.certificate).ownerOf(r.tokenId), investor);
    }

    function test_InsufficientSwapBudgetRefusesBeforeSpending() public forkOnly {
        config.maxEthIn = 1;
        uint256 beforeEth = investor.balance;
        vm.expectRevert();
        script.execute(config, officerKey, investorKey);
        assertEq(investor.balance, beforeEth);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(investor), 0);
    }

    function test_ExpiredConfigRefuses() public forkOnly {
        config.end = block.timestamp;
        vm.expectRevert(RobinhoodCentSafeScript.Expired.selector);
        script.execute(config, officerKey, investorKey);
    }

    function test_SameSignerRefuses() public forkOnly {
        vm.expectRevert(RobinhoodCentSafeScript.SameSigner.selector);
        script.execute(config, officerKey, officerKey);
    }

    function test_WrongChainRefuses() public forkOnly {
        vm.chainId(8453);
        vm.expectRevert(RobinhoodCentSafeScript.WrongChain.selector);
        script.execute(config, officerKey, investorKey);
    }

    function test_UnfundedInvestorRefuses() public forkOnly {
        vm.deal(investor, 0);
        vm.expectRevert(abi.encodeWithSelector(RobinhoodCentSafeScript.InsufficientETH.selector, investor));
        script.execute(config, officerKey, investorKey);
    }

    function test_PlatformPayoutCollisionRefusesBeforeSwap() public forkOnly {
        config.payout = DeploymentConstants.coreV2(4663).metalexSafe;
        uint256 beforeEth = investor.balance;
        vm.expectRevert(RobinhoodCentSafeScript.InvalidConfig.selector);
        script.execute(config, officerKey, investorKey);
        assertEq(investor.balance, beforeEth);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(investor), 0);
    }

    function test_UnsupportedTemplateRefusesBeforeSwap() public forkOnly {
        config.templateId = bytes32(uint256(1));
        vm.expectRevert(RobinhoodCentSafeScript.InvalidConfig.selector);
        script.execute(config, officerKey, investorKey);
        assertEq(IERC20Metadata(script.USDG()).balanceOf(investor), 0);
    }
}
