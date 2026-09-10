// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {IUUPS} from "./RoundManagerTest.t.sol";

/// @title Real-signature guard for the deployment metadata refactor
/// @notice PumpCorpFactory moved its supplemental signature encoding into CorpFactoryMetadataLib.
/// The digest had to stay byte-identical, because officer signatures already exist over the old
/// encoding. This replays a real base-sepolia transaction that carried such a signature:
///
///   https://sepolia.basescan.org/tx/0x90067ba56599c7b5d0059a1c9506b999e6237be26dc1aa394a76867dcbe696e3
///
/// The calldata in test/res holds that officer's real metadata signature. Replaying it against the
/// refactored implementation proves the digest is unchanged: any change to the typehashes, the field
/// order, or the domain would move the digest and fail signature recovery.
///
/// Run with:
///   forge test --use solc:0.8.28 --via-ir --mc PumpCorpFactoryMetadataSigForkTest -vv
contract PumpCorpFactoryMetadataSigForkTest is Test {
    /// @dev The v5 PumpCorpFactory proxy the transaction was sent to, before the refactor.
    address constant PUMP_FACTORY = 0x5cB54A9a1415D461F07EAAc7c5d65B216906dFb9;
    address constant TX_SENDER = 0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf;
    uint256 constant TX_BLOCK = 46405683;

    /// @dev Calldata head slot of _companyPayable: 4 selector bytes, then 7 head words before it.
    uint256 constant COMPANY_PAYABLE_OFFSET = 4 + 7 * 32;

    bytes internal txCallData;
    address internal metalexSafe;

    function setUp() public {
        // One block before the transaction, so its corp salt is still unused.
        vm.createSelectFork("base_sepolia", TX_BLOCK - 1);
        txCallData = vm.parseBytes(vm.readFile("test/res/pumpcorp-v5-metadata-sig-tx.hex"));
        metalexSafe = DeploymentConstants.coreV2(block.chainid).metalexSafe;
    }

    /// @notice Baseline. The captured calldata is a valid transaction against the deployed
    /// pre-refactor implementation. Without this the replay below could pass for the wrong reason.
    function test_RealTransactionSucceedsOnThePreRefactorImplementation() public {
        vm.prank(TX_SENDER);
        (bool ok, ) = PUMP_FACTORY.call(txCallData);
        assertTrue(ok, "the captured calldata must replay on the deployed implementation");
    }

    /// @notice The same officer signature must still verify after the refactor.
    function test_RealSignatureStillVerifiesAfterTheRefactor() public {
        _upgradeToLocalImplementation();

        vm.prank(TX_SENDER);
        (bool ok, ) = PUMP_FACTORY.call(txCallData);
        assertTrue(ok, "the real officer signature must still verify after the refactor");
    }

    /// @notice Proves the replay actually exercises signature verification. Changing one signed
    /// field, the payout address, must be rejected.
    function test_TamperedPayoutAddressIsRejectedAfterTheRefactor() public {
        _upgradeToLocalImplementation();

        bytes memory tampered = _withCompanyPayable(txCallData, address(0xDEADBEEF));

        vm.prank(TX_SENDER);
        (bool ok, bytes memory ret) = PUMP_FACTORY.call(tampered);
        assertFalse(ok, "a tampered payout address must not deploy");
        assertEq(
            bytes4(ret),
            PumpCorpFactory.InvalidMetadataSignature.selector,
            "must fail on the metadata signature, not something else"
        );
    }

    /// @notice The pre-refactor implementation rejects the same tampering the same way.
    function test_TamperedPayoutAddressIsRejectedBeforeTheRefactor() public {
        bytes memory tampered = _withCompanyPayable(txCallData, address(0xDEADBEEF));

        vm.prank(TX_SENDER);
        (bool ok, bytes memory ret) = PUMP_FACTORY.call(tampered);
        assertFalse(ok, "a tampered payout address must not deploy");
        assertEq(
            bytes4(ret),
            PumpCorpFactory.InvalidMetadataSignature.selector,
            "must fail on the metadata signature, not something else"
        );
    }

    function _upgradeToLocalImplementation() private {
        // Deploy before the prank, or the CREATE consumes it.
        address newImpl = address(new PumpCorpFactory());
        vm.prank(metalexSafe);
        IUUPS(PUMP_FACTORY).upgradeToAndCall(newImpl, "");
    }

    /// @dev Overwrites the _companyPayable head word, leaving the rest of the calldata alone.
    function _withCompanyPayable(bytes memory original, address replacement)
        private
        pure
        returns (bytes memory copy)
    {
        copy = bytes.concat(original);
        bytes32 word = bytes32(uint256(uint160(replacement)));
        for (uint256 i = 0; i < 32; i++) {
            copy[COMPANY_PAYABLE_OFFSET + i] = word[i];
        }
    }
}
