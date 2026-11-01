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
    function buyMissing(Config memory c, address investor, uint256 key) external {
        _buyMissing(c, investor, key);
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
