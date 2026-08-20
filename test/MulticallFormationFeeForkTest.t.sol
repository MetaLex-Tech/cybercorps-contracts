// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory);
}

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Base mainnet fork test for one Multicall3 batch that does two things:
///         it pays a 100 USDC fee to MetaLeX, and it forms a CyberCorp owned by the user.
///         The batch uses the live CyberCorpFactory, the live USDC, and the canonical Multicall3.
///         Multicall3 is the msg.sender of both inner calls. Formation takes the owner as a
///         parameter, and USDC takes the fee recipient from the signature, so neither call
///         depends on the caller.
contract MulticallFormationFeeForkTest is Test {
    IMulticall3 constant MULTICALL3 = IMulticall3(0xcA11bde05977b3631167028862bE2a173976CA11);

    uint256 constant FEE = 100e6; // USDC has 6 decimals
    uint256 constant USER_BALANCE = 1_000e6;

    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    IUSDC usdc;
    CyberCorpFactory corpFactory;
    CyberCorpSingleFactory corpSingleFactory;

    address user;
    uint256 userKey;
    address metalexPayable;
    address attacker;
    address relayer;

    function setUp() public {
        vm.createSelectFork("base");

        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        usdc = IUSDC(DeploymentConstants.deps(block.chainid).usdc);
        corpFactory = CyberCorpFactory(core.cyberCorpFactory);
        corpSingleFactory = CyberCorpSingleFactory(core.cyberCorpSingleFactory);

        // A well-known test key can carry code on a live chain. An EIP-7702 delegation makes USDC
        // take the ERC-1271 path, and the ECDSA signature then fails. Keep this address free of code.
        (user, userKey) = makeAddrAndKey("cybercorp-founder");
        assertEq(user.code.length, 0, "the signer must be a plain EOA on the fork");
        metalexPayable = makeAddr("metalexPayable");
        attacker = makeAddr("attacker");
        relayer = makeAddr("relayer");

        deal(address(usdc), user, USER_BALANCE);
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _officer() internal view returns (CompanyOfficer memory) {
        return CompanyOfficer({eoa: user, name: "Jane Doe", contact: "jane@example.com", title: "CEO"});
    }

    function _formationCall(bytes32 salt) internal view returns (bytes memory) {
        return abi.encodeCall(
            CyberCorpFactory.deployCyberCorp,
            (salt, "Acme Labs, Inc.", "corporation", "DE", "jane@example.com", "arbitration", user, _officer())
        );
    }

    /// @dev Signs an EIP-3009 authorization. The signature covers the recipient and the amount.
    function _sign(address to, uint256 value, bytes32 nonce, uint256 signerKey)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s, uint256 validBefore)
    {
        validBefore = block.timestamp + 15 minutes;
        bytes32 structHash = keccak256(
            abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, user, to, value, uint256(0), validBefore, nonce)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", usdc.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(signerKey, digest);
    }

    function _feeCall(address to, uint256 value, bytes32 nonce, uint256 signerKey)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s, uint256 validBefore) = _sign(to, value, nonce, signerKey);
        return abi.encodeCall(IUSDC.transferWithAuthorization, (user, to, value, 0, validBefore, nonce, v, r, s));
    }

    /// @dev The fee call comes first. A failed fee then stops the batch before formation spends gas.
    function _batch(bytes memory feeCall, bytes memory formationCall, bool allowFeeFailure)
        internal
        view
        returns (IMulticall3.Call3[] memory calls)
    {
        calls = new IMulticall3.Call3[](2);
        calls[0] = IMulticall3.Call3(address(usdc), allowFeeFailure, feeCall);
        calls[1] = IMulticall3.Call3(address(corpFactory), false, formationCall);
    }

    function _corpAddress(bytes32 salt) internal view returns (address) {
        return corpSingleFactory.computeCyberCorpSingleAddress(salt);
    }

    // ── tests ────────────────────────────────────────────────────────────────

    function test_feeAndFormationInOneBatch() public {
        bytes32 salt = keccak256("fee-and-formation");
        bytes32 nonce = keccak256("nonce-1");
        address expectedCorp = _corpAddress(salt);

        IMulticall3.Call3[] memory calls =
            _batch(_feeCall(metalexPayable, FEE, nonce, userKey), _formationCall(salt), false);

        uint256 gasBefore = gasleft();
        vm.prank(user);
        IMulticall3.Result[] memory res = MULTICALL3.aggregate3(calls);
        emit log_named_uint("batch gas", gasBefore - gasleft());

        (address corp, address auth,,,) = abi.decode(res[1].returnData, (address, address, address, address, address));

        assertEq(corp, expectedCorp, "corp address must match the precomputed address");

        (address officerEoa,,,) = CyberCorp(corp).companyOfficers(0);
        assertEq(officerEoa, user, "the user must be the officer");
        assertEq(BorgAuth(auth).userRoles(user), 200, "the user must hold the officer role");
        assertEq(BorgAuth(auth).userRoles(address(MULTICALL3)), 0, "Multicall3 must hold no role");

        assertEq(usdc.balanceOf(metalexPayable), FEE, "MetaLeX must receive the fee");
        assertEq(usdc.balanceOf(user), USER_BALANCE - FEE, "the fee must leave the user balance");
        assertTrue(usdc.authorizationState(user, nonce), "the authorization must be used");
    }

    /// @notice A relayer can send the same batch. The user then needs no gas.
    function test_relayerCanSendTheBatch() public {
        bytes32 salt = keccak256("relayer-batch");
        bytes32 nonce = keccak256("nonce-2");

        IMulticall3.Call3[] memory calls =
            _batch(_feeCall(metalexPayable, FEE, nonce, userKey), _formationCall(salt), false);

        vm.prank(relayer);
        MULTICALL3.aggregate3(calls);

        (address officerEoa,,,) = CyberCorp(_corpAddress(salt)).companyOfficers(0);
        assertEq(officerEoa, user, "the user must be the officer");
        assertEq(usdc.balanceOf(metalexPayable), FEE, "MetaLeX must receive the fee");
        assertEq(usdc.balanceOf(relayer), 0, "the relayer must pay no fee");
    }

    /// @notice The authorization names the recipient. An attacker cannot change it.
    function test_attackerCannotRedirectTheFee() public {
        bytes32 nonce = keccak256("nonce-3");

        // The user signs a fee to MetaLeX. The attacker keeps the signature and puts in a different recipient.
        (uint8 v, bytes32 r, bytes32 s, uint256 validBefore) = _sign(metalexPayable, FEE, nonce, userKey);
        bytes memory redirected =
            abi.encodeCall(IUSDC.transferWithAuthorization, (user, attacker, FEE, 0, validBefore, nonce, v, r, s));

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3(address(usdc), true, redirected);

        vm.prank(attacker);
        IMulticall3.Result[] memory res = MULTICALL3.aggregate3(calls);

        assertFalse(res[0].success, "the changed recipient must fail");
        assertEq(
            res[0].returnData,
            abi.encodeWithSignature("Error(string)", "FiatTokenV2: invalid signature"),
            "USDC must reject the signature"
        );
        assertEq(usdc.balanceOf(attacker), 0, "the attacker must receive nothing");
        assertEq(usdc.balanceOf(user), USER_BALANCE, "the user must keep the balance");
        assertFalse(usdc.authorizationState(user, nonce), "the nonce must stay free");
    }

    /// @notice A person can send the authorization first. The fee still goes to MetaLeX.
    ///         But the strict batch then fails, because the nonce is used.
    function test_frontRunAuthorizationRevertsTheStrictBatch() public {
        bytes32 salt = keccak256("front-run-strict");
        bytes32 nonce = keccak256("nonce-4");
        bytes memory feeCall = _feeCall(metalexPayable, FEE, nonce, userKey);

        vm.prank(attacker);
        (bool sent,) = address(usdc).call(feeCall);
        assertTrue(sent, "the direct authorization must succeed");
        assertEq(usdc.balanceOf(metalexPayable), FEE, "MetaLeX must receive the fee");

        IMulticall3.Call3[] memory calls = _batch(feeCall, _formationCall(salt), false);
        address expectedCorp = _corpAddress(salt);

        vm.prank(user);
        vm.expectRevert(bytes("Multicall3: call failed"));
        MULTICALL3.aggregate3(calls);

        assertEq(expectedCorp.code.length, 0, "no corp must exist after the revert");
    }

    /// @notice With allowFailure on the fee call, formation continues after a front-run.
    function test_frontRunAuthorizationToleratedWithAllowFailure() public {
        bytes32 salt = keccak256("front-run-tolerant");
        bytes32 nonce = keccak256("nonce-5");
        bytes memory feeCall = _feeCall(metalexPayable, FEE, nonce, userKey);

        vm.prank(attacker);
        (bool sent,) = address(usdc).call(feeCall);
        assertTrue(sent, "the direct authorization must succeed");

        IMulticall3.Call3[] memory calls = _batch(feeCall, _formationCall(salt), true);

        vm.prank(user);
        IMulticall3.Result[] memory res = MULTICALL3.aggregate3(calls);

        assertFalse(res[0].success, "the repeated authorization must fail");
        assertEq(
            res[0].returnData,
            abi.encodeWithSignature("Error(string)", "FiatTokenV2: authorization is used or canceled"),
            "the nonce must be used"
        );
        (address officerEoa,,,) = CyberCorp(_corpAddress(salt)).companyOfficers(0);
        assertEq(officerEoa, user, "formation must continue");
        assertEq(usdc.balanceOf(metalexPayable), FEE, "MetaLeX must receive the fee one time only");
    }

    /// @notice Owner-only calls cannot go in the batch. Multicall3 holds no role.
    ///         The call runs with allowFailure, so the test can read the reason.
    function test_ownerOnlyCallInTheBatchFails() public {
        bytes32 salt = keccak256("owner-only-call");
        bytes32 nonce = keccak256("nonce-6");
        address corp = _corpAddress(salt);

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](3);
        calls[0] = IMulticall3.Call3(address(usdc), false, _feeCall(metalexPayable, FEE, nonce, userKey));
        calls[1] = IMulticall3.Call3(address(corpFactory), false, _formationCall(salt));
        calls[2] = IMulticall3.Call3(corp, true, abi.encodeCall(CyberCorp.setCompanyPayable, (metalexPayable)));

        vm.prank(user);
        IMulticall3.Result[] memory res = MULTICALL3.aggregate3(calls);

        assertTrue(res[1].success, "formation must succeed");
        assertFalse(res[2].success, "the owner-only call must fail");
        assertEq(
            res[2].returnData,
            abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(99), address(MULTICALL3)),
            "the reason must be the missing role of Multicall3"
        );

        // The user holds the officer role, so the user can make the same call in a separate transaction.
        vm.prank(user);
        CyberCorp(corp).setCompanyPayable(metalexPayable);
        assertEq(CyberCorp(corp).companyPayable(), metalexPayable, "the user can set the payable address");
    }

    /// @notice A failed fee stops formation. The batch is all or nothing.
    function test_batchRevertsWhenTheUserCannotPay() public {
        bytes32 salt = keccak256("poor-user");
        bytes32 nonce = keccak256("nonce-7");
        address expectedCorp = _corpAddress(salt);

        deal(address(usdc), user, FEE - 1);

        IMulticall3.Call3[] memory calls =
            _batch(_feeCall(metalexPayable, FEE, nonce, userKey), _formationCall(salt), false);

        vm.prank(user);
        vm.expectRevert(bytes("Multicall3: call failed"));
        MULTICALL3.aggregate3(calls);

        assertEq(expectedCorp.code.length, 0, "no corp must exist after the revert");
        assertEq(usdc.balanceOf(metalexPayable), 0, "MetaLeX must receive nothing");
    }
}
