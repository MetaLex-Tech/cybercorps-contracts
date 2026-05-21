// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../test/mock/TestableCyberScrip.sol";
import "../test/mock/MockTransferHook.sol";
import "../src/libs/auth.sol";

contract CyberScripTest is Test {
    TestableCyberScrip public cyberScrip;
    address public certPrinter;
    address public issuanceManager;
    address public owner;
    address public user1;
    address public user2;
    MockTransferHook public mockHook;

    event FreezeStatusUpdated(address indexed account, bool frozen);
    event ComplianceFeatureDisabledEvent(string feature);
    event MaxHolderCountUpdated(uint256 maxHolderCount);

    function setUp() public {
        owner = address(this);
        issuanceManager = makeAddr("issuanceManager");
        certPrinter = makeAddr("certPrinter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock restriction hook
        mockHook = new MockTransferHook();

        // Setup transfer restriction hooks
        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](1);
        hooks[0] = ITransferRestrictionHook(address(mockHook));
        bytes32 salt = keccak256("CyberScripTest");
        //deploy auth
        address auth = address(new BorgAuth{salt: salt}(owner));

        // Deploy CyberScrip (testable)
        cyberScrip = TestableCyberScrip(address(
            new ERC1967Proxy(
                address(new TestableCyberScrip()),
                abi.encodeWithSelector(
                    CyberScrip.initialize.selector,
                    auth,
                    certPrinter,
                    issuanceManager,
                    "Test CyberScrip",
                    "TCS",
                    hooks,
                    true,
                    true,
                    true
                )
            )
        ));

        // Mint initial balance for user1
        cyberScrip.unrestrictedMint(user1, 1000 ether);
    }

    function test_Initialization() public {
        assertEq(cyberScrip.name(), "Test CyberScrip");
        assertEq(cyberScrip.symbol(), "TCS");
        assertEq(cyberScrip.certPrinter(), certPrinter);
        assertEq(cyberScrip.issuanceManager(), issuanceManager);
        assertEq(cyberScrip.balanceOf(user1), 1000 ether);
    }

    function test_TransferAllowed() public {
        vm.startPrank(user1);
        cyberScrip.transfer(user2, 500 ether);
        assertEq(cyberScrip.balanceOf(user1), 500 ether);
        assertEq(cyberScrip.balanceOf(user2), 500 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_TransfersDisabledByHook() public {
        mockHook.setAllowTransfers(false);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("RestrictedTransfer(string)", "Transfers disabled in mock hook"));
        cyberScrip.transfer(user2, 500 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_NonIssuanceManagerBurns() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.burnFrom(user1, 500 ether);
        vm.stopPrank();
    }

    function test_IssuanceManagerBurn() public {
        vm.startPrank(issuanceManager);
        cyberScrip.burnFrom(user1, 500 ether);
        assertEq(cyberScrip.balanceOf(user1), 500 ether);
        vm.stopPrank();
    }

    function test_UpdateTransferRestrictionHooks() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(mockHook));

        vm.startPrank(issuanceManager);
        cyberScrip.setRestrictionHook(newHooks);
        vm.stopPrank();

        // Verify transfer still works with updated hooks
        vm.startPrank(user1);
        cyberScrip.transfer(user2, 100 ether);
        assertEq(cyberScrip.balanceOf(user2), 100 ether);
        vm.stopPrank();
    }

    // ========================
    // Compliance tests
    // ========================

    function test_Init_TogglesEnabled() public {
        assertTrue(cyberScrip.canForceTransfer());
        assertTrue(cyberScrip.canForceBurn());
        assertTrue(cyberScrip.canFreeze());
    }

    function test_Init_TogglesDisabled_And_UsageReverts() public {
        // Deploy a separate instance with all toggles disabled
        ITransferRestrictionHook[] memory hooks2 = new ITransferRestrictionHook[](1);
        hooks2[0] = ITransferRestrictionHook(address(mockHook));
        TestableCyberScrip disabled = TestableCyberScrip(address(
            new ERC1967Proxy(
                address(new TestableCyberScrip()),
                abi.encodeWithSelector(
                    CyberScrip.initialize.selector,
                    makeAddr("auth"),
                    certPrinter,
                    issuanceManager,
                    "Disabled",
                    "DIS",
                    hooks2,
                    false,
                    false,
                    false
                )
            )
        ));
        disabled.unrestrictedMint(user1, 1000 ether);

        vm.startPrank(issuanceManager);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        disabled.setFrozen(user1, true);

        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        disabled.forceTransfer(user1, user2, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        disabled.forceBurn(user1, 1 ether);
        vm.stopPrank();
    }

    function test_Disable_Features() public {
        // Disable all features
        vm.startPrank(issuanceManager);
        cyberScrip.disableFreeze();
        cyberScrip.disableForceTransfer();
        cyberScrip.disableForceBurn();
        vm.stopPrank();

        // Using them should revert
        vm.startPrank(issuanceManager);
        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        cyberScrip.setFrozen(user1, true);

        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        cyberScrip.forceTransfer(user1, user2, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("ComplianceFeatureDisabled()"));
        cyberScrip.forceBurn(user1, 1 ether);
        vm.stopPrank();
    }

    function test_FreezeBlocksNormalTransfer() public {
        // Freeze sender
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("AccountFrozen(address)", user1));
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();

        // Unfreeze sender, freeze recipient
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, false);
        cyberScrip.setFrozen(user2, true);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("AccountFrozen(address)", user2));
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_ForceTransfer_IgnoresHooksAndFreeze() public {
        // Disable transfers via hook
        mockHook.setAllowTransfers(false);

        // Normal transfer should revert due to hook (no freeze yet)
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("RestrictedTransfer(string)", "Transfers disabled in mock hook"));
        cyberScrip.transfer(user2, 10 ether);
        vm.stopPrank();

        // Now freeze accounts; force transfer should still succeed ignoring both hook and freeze
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        cyberScrip.setFrozen(user2, true);
        vm.stopPrank();

        // Force transfer should succeed
        vm.startPrank(issuanceManager);
        cyberScrip.forceTransfer(user1, user2, 10 ether);
        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(user1), 990 ether);
        assertEq(cyberScrip.balanceOf(user2), 10 ether);
    }

    function test_ForceBurn_IgnoresHooksAndFreeze() public {
        // Freeze account and disable transfers in hook
        mockHook.setAllowTransfers(false);
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        vm.stopPrank();

        // Normal burnFrom works only by issuance manager; forceBurn should also work and ignore freeze
        vm.startPrank(issuanceManager);
        cyberScrip.forceBurn(user1, 50 ether);
        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(user1), 950 ether);
    }

    function test_OnlyIssuanceManagerGuard_ComplianceFunctions() public {
        // Non-issuance manager cannot call these
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.setFrozen(user2, true);

        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.forceTransfer(user1, user2, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.forceBurn(user1, 1 ether);

        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.disableFreeze();
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.disableForceTransfer();
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.disableForceBurn();
        vm.stopPrank();
    }

    // ------------------------
    // Additional coverage
    // ------------------------

    function test_HolderCount_InitAndTransferAllUpdates() public {
        assertEq(cyberScrip.holderCount(), 1);

        vm.startPrank(user1);
        cyberScrip.transfer(user2, 100 ether);
        vm.stopPrank();
        assertEq(cyberScrip.holderCount(), 2);

        vm.startPrank(user1);
        cyberScrip.transfer(user2, 900 ether);
        vm.stopPrank();
        assertEq(cyberScrip.holderCount(), 1);
    }

    function test_HolderCount_BurnToZero() public {
        vm.prank(issuanceManager);
        cyberScrip.burnFrom(user1, 1000 ether);
        assertEq(cyberScrip.holderCount(), 0);
    }

    function test_MaxHolderCountBlocksTransfer() public {
        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(1);

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSignature("HolderLimitExceeded(uint256)", 1)
        );
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_MaxHolderCountBlocksMint() public {
        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(1);

        vm.prank(issuanceManager);
        vm.expectRevert(
            abi.encodeWithSignature("HolderLimitExceeded(uint256)", 1)
        );
        cyberScrip.mint(user2, 1 ether);
    }

    function test_SetMaxHolderCount_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit MaxHolderCountUpdated(2);
        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(2);
        assertEq(cyberScrip.maxHolderCount(), 2);
    }

    function test_FreezeStatusUpdatedEventAndGetter() public {
        vm.expectEmit(true, false, false, true);
        emit FreezeStatusUpdated(user1, true);
        vm.prank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        assertTrue(cyberScrip.frozen(user1));
    }

    function test_DisableForceTransfer_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ComplianceFeatureDisabledEvent("forceTransfer");
        vm.prank(issuanceManager);
        cyberScrip.disableForceTransfer();
        assertFalse(cyberScrip.canForceTransfer());
    }

    function test_DisableForceBurn_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ComplianceFeatureDisabledEvent("forceBurn");
        vm.prank(issuanceManager);
        cyberScrip.disableForceBurn();
        assertFalse(cyberScrip.canForceBurn());
    }

    function test_DisableFreeze_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ComplianceFeatureDisabledEvent("freeze");
        vm.prank(issuanceManager);
        cyberScrip.disableFreeze();
        assertFalse(cyberScrip.canFreeze());
    }

    function test_TransferRestrictionHooksLengthAndAccessor() public {
        assertEq(cyberScrip.transferRestrictionHooksLength(), 1);
        assertEq(
            address(cyberScrip.transferRestrictionHooks(0)),
            address(mockHook)
        );
    }

    function test_CanTransfer_TrueForSelfOrZeroAmount() public {
        assertTrue(cyberScrip.canTransfer(user1, user1, 1 ether));
        assertTrue(cyberScrip.canTransfer(user1, user2, 0));
    }

    function test_CanTransfer_TrueForMintOrBurn() public {
        assertTrue(cyberScrip.canTransfer(address(0), user1, 1 ether));
        assertTrue(cyberScrip.canTransfer(user1, address(0), 1 ether));
    }

    function test_CanTransfer_FalseWhenFrozen() public {
        vm.prank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        assertFalse(cyberScrip.canTransfer(user1, user2, 1 ether));
    }

    function test_CanTransfer_FalseWhenHookDenies() public {
        mockHook.setAllowTransfers(false);
        assertFalse(cyberScrip.canTransfer(user1, user2, 1 ether));
    }

    function test_CanTransfer_RespectsHolderLimit() public {
        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(1);
        assertFalse(cyberScrip.canTransfer(user1, user2, 1 ether));
    }

    function test_CanTransfer_AllowsTransferToExistingHolderAtLimit() public {
        vm.startPrank(user1);
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();

        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(2);

        assertTrue(cyberScrip.canTransfer(user1, user2, 1 ether));
    }

    function test_WillCreateNewHolder_Behavior() public {
        assertTrue(cyberScrip.willCreateNewHolder(user2, 1 ether));
        assertFalse(cyberScrip.willCreateNewHolder(user1, 1 ether));
        assertFalse(cyberScrip.willCreateNewHolder(user2, 0));
        assertFalse(cyberScrip.willCreateNewHolder(address(0), 1 ether));
    }

    function test_CurrentHolderCount_MatchesStorage() public {
        assertEq(cyberScrip.currentHolderCount(), cyberScrip.holderCount());
    }

    function test_RemainingSlots_Unlimited() public {
        assertEq(cyberScrip.remainingSlots(), type(uint256).max);
    }

    function test_RemainingSlots_WithLimit() public {
        vm.prank(issuanceManager);
        cyberScrip.setMaxHolderCount(2);
        assertEq(cyberScrip.remainingSlots(), 1);

        vm.startPrank(user1);
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();
        assertEq(cyberScrip.remainingSlots(), 0);
    }

    function test_MintRespectsFreeze() public {
        // _update enforces freeze on recipient even for mints (to != address(0))
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user2, true);

        vm.expectRevert(abi.encodeWithSignature("AccountFrozen(address)", user2));
        cyberScrip.mint(user2, 123 ether);
        vm.stopPrank();
    }

    function test_BurnFromBypassesHooksAndFreeze() public {
        // Freeze account and disable hook transfers
        mockHook.setAllowTransfers(false);
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        // Burn should still succeed (to == address(0))
        cyberScrip.burnFrom(user1, 100 ether);
        vm.stopPrank();
        assertEq(cyberScrip.balanceOf(user1), 900 ether);
    }

    function test_TransferFromRespectsRestrictions() public {
        // Approve user2 to move from user1
        vm.startPrank(user1);
        cyberScrip.approve(user2, 50 ether);
        vm.stopPrank();

        // Deny via hook
        mockHook.setAllowTransfers(false);

        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("RestrictedTransfer(string)", "Transfers disabled in mock hook"));
        cyberScrip.transferFrom(user1, user2, 10 ether);
        vm.stopPrank();

        // Allow via hook
        mockHook.setAllowTransfers(true);
        vm.startPrank(user2);
        cyberScrip.transferFrom(user1, user2, 10 ether);
        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(user1), 990 ether);
        assertEq(cyberScrip.balanceOf(user2), 10 ether);
    }

    function test_SetRestrictionHookEmptyClearsChecks() public {
        // Deny transfers via current hook
        mockHook.setAllowTransfers(false);

        // Clear hooks
        ITransferRestrictionHook[] memory emptyHooks = new ITransferRestrictionHook[](0);
        vm.startPrank(issuanceManager);
        cyberScrip.setRestrictionHook(emptyHooks);
        vm.stopPrank();

        // Now transfer should succeed since no hooks are enforced
        vm.startPrank(user1);
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(user1), 999 ether);
        assertEq(cyberScrip.balanceOf(user2), 1 ether);
    }

    function test_MultipleHooks_SecondDenies() public {
        // Create second hook (allow)
        MockTransferHook allowHook = new MockTransferHook();
        allowHook.setAllowTransfers(true);

        // First allow, second deny
        MockTransferHook denyHook = new MockTransferHook();
        denyHook.setAllowTransfers(false);

        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](2);
        hooks[0] = ITransferRestrictionHook(address(allowHook));
        hooks[1] = ITransferRestrictionHook(address(denyHook));

        vm.startPrank(issuanceManager);
        cyberScrip.setRestrictionHook(hooks);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("RestrictedTransfer(string)", "Transfers disabled in mock hook"));
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();
    }

    function test_DisableFreezeAfterFrozen_AllowsTransfer() public {
        // Freeze sender then disable freeze feature
        vm.startPrank(issuanceManager);
        cyberScrip.setFrozen(user1, true);
        cyberScrip.disableFreeze();
        vm.stopPrank();

        // Transfer should now ignore frozen mapping
        vm.startPrank(user1);
        cyberScrip.transfer(user2, 1 ether);
        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(user1), 999 ether);
        assertEq(cyberScrip.balanceOf(user2), 1 ether);
    }

    function test_DisableIdempotent_NoRevertTwice() public {
        vm.startPrank(issuanceManager);
        cyberScrip.disableForceTransfer();
        cyberScrip.disableForceTransfer();
        cyberScrip.disableForceBurn();
        cyberScrip.disableForceBurn();
        cyberScrip.disableFreeze();
        cyberScrip.disableFreeze();
        vm.stopPrank();

        assertFalse(cyberScrip.canForceTransfer());
        assertFalse(cyberScrip.canForceBurn());
        assertFalse(cyberScrip.canFreeze());
    }

    function test_ForceTransfer_ZeroAddressReverts() public {
        vm.startPrank(issuanceManager);
        vm.expectRevert(bytes("force: zero addr"));
        cyberScrip.forceTransfer(address(0), user2, 1);

        vm.expectRevert(bytes("force: zero addr"));
        cyberScrip.forceTransfer(user1, address(0), 1);
        vm.stopPrank();
    }

    function test_ForceBurn_ZeroAddressReverts() public {
        vm.startPrank(issuanceManager);
        vm.expectRevert(bytes("forceBurn: zero addr"));
        cyberScrip.forceBurn(address(0), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_NonIssuanceManagerUpdatesHooks() public {
        ITransferRestrictionHook[] memory newHooks = new ITransferRestrictionHook[](1);
        newHooks[0] = ITransferRestrictionHook(address(mockHook));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.setRestrictionHook(newHooks);
        vm.stopPrank();
    }

    // ========================
    // Bridge Simulation Tests (IssuanceManager scripify/convert)
    // ========================

    function test_Bridge_FullScripifySimulation() public {
        // In a real scripifyCert (full), the IssuanceManager would:
        // 1. Receive the Cert, 2. Void it, 3. Mint scrip
        uint256 amount = 5000 ether;

        vm.prank(issuanceManager);
        cyberScrip.mint(user2, amount);

        assertEq(cyberScrip.balanceOf(user2), amount);
        assertEq(cyberScrip.totalSupply(), 1000 ether + amount); // 1000 from setUp
    }

    function test_Bridge_PartialScripifySimulation() public {
        // In a real scripifyCert (partial), the IssuanceManager would:
        // 1. Reduce units on Cert, 2. Mint scrip
        uint256 amount = 250 ether;

        vm.prank(issuanceManager);
        cyberScrip.mint(user1, amount);

        assertEq(cyberScrip.balanceOf(user1), 1000 ether + amount);
    }

    function test_Bridge_ConvertScripToCertSimulation() public {
        // In a real convertScripToCert, the IssuanceManager would:
        // 1. Burn scrip, 2. Unvoid or Mint new Cert
        uint256 amountToConvertBack = 400 ether;

        // User1 has 1000 ether from setUp
        vm.prank(issuanceManager);
        cyberScrip.burnFrom(user1, amountToConvertBack);

        assertEq(cyberScrip.balanceOf(user1), 600 ether);
        assertEq(cyberScrip.totalSupply(), 1000 ether - amountToConvertBack);
    }

    function test_RevertWhen_UnauthorizedBridgeMint() public {
        // Ensure only the designated issuanceManager can mint (crucial for bridge security)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.mint(user1, 100 ether);
    }

    function test_RevertWhen_UnauthorizedBridgeBurn() public {
        // Ensure only the designated issuanceManager can burn (crucial for bridge security)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotIssuanceManager()"));
        cyberScrip.burnFrom(user1, 100 ether);
    }
}
