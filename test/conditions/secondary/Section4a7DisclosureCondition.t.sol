// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Section4a7DisclosureCondition} from "../../../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {SecondaryConditionIntegrationBase, SpvFixture} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Section4a7DisclosureCondition — §4(a)(7) information-delivery gate (two-part test).
//
// Legal/economic intent: §4(a)(7)(d)(3) requires (1) the SPV to have a fresh information package on
// record (incl. two years of GAAP financials), enforced from posting onward, and (2) the buyer to
// acknowledge receipt of it, recorded as a party value at acceptance. Both must hold to clear.
//
// Real integration: the package is keyed by the SPV (offer.spvAddress = corp); the buyer's acknowledgment
// is a real acceptor party value carried into the settlement agreement at acceptOffer and read back from
// the real registry.
//
// Scenario × outcome (freshness policy = 480 days)
// | # | context   | package        | buyer ack | expect | rationale                        |
// |---|-----------|----------------|:---------:|:------:|----------------------------------|
// | 1 | posting   | none           |    n/a    |  fail  | package missing (part 1)         |
// | 2 | posting   | fresh          |    n/a    |  pass  | ack deferred to acceptance       |
// | 3 | accepted  | fresh          |    yes    |  pass  | both parts satisfied             |
// | 4 | accepted  | fresh          |     no    |  fail  | receipt not acknowledged         |
// | 5 | accepted  | stale          |    yes    |  fail  | package stale (part 1 fails)     |
//
// Config/authorization
// | # | case                              | expect                    |
// |---|-----------------------------------|---------------------------|
// | 6 | initialize zero registry          | revert InvalidRegistry    |
// | 7 | initialize empty acknowledgment   | revert InvalidAcknowledgment |
// | 8 | initialize zero maxAge            | revert InvalidMaxAge      |
// | 9 | setDisclosurePackage non-SPV-admin| revert (not admin)        |
// ─────────────────────────────────────────────────────────────────────────────

contract Section4a7DisclosureConditionTest is SecondaryConditionIntegrationBase {
    Section4a7DisclosureCondition internal disc;
    uint256 internal constant MAX_AGE = 480 days;
    uint256 internal constant NOW = 500 days;
    string internal constant URI = "ipfs://4a7-package";
    string internal constant ACK = "4a7:information-package-received";
    bytes32 internal offerId;

    // §4(a)(7) is the only condition that carries a per-party value on the settlement (the buyer's receipt
    // acknowledgment), so it opts into a one-field template here rather than widening the shared default.
    function _offerTemplateId() internal pure override returns (bytes32) {
        return keccak256("4a7-template");
    }

    function _offerTemplateUri() internal pure override returns (string memory) {
        return "ipfs://4a7-template";
    }

    function _partyFields() internal pure override returns (string[] memory) {
        return _one("acknowledgment");
    }

    function setUp() public {
        _setUpIntegration();
        vm.warp(NOW);
        disc = Section4a7DisclosureCondition(
            _proxy(
                address(new Section4a7DisclosureCondition()),
                abi.encodeCall(
                    Section4a7DisclosureCondition.initialize, (address(auth), address(registry), MAX_AGE)
                )
            )
        );
        offerId = _postSell();
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return disc.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // 1
    function test_Posting_NoPackage_Fails() public view {
        assertFalse(_check(bytes32(0)));
    }

    // 2
    function test_Posting_FreshPackage_Passes() public {
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), ACK);
        assertTrue(_check(bytes32(0)));
    }

    // 3
    function test_Accepted_FreshAndAcked_Passes() public {
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), ACK);
        bytes32 settlementId = _acceptSell(offerId, _one(ACK));
        assertTrue(_check(settlementId));
    }

    // 4
    function test_Accepted_FreshNoAck_Fails() public {
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), ACK);
        bytes32 settlementId = _acceptSell(offerId);
        assertFalse(_check(settlementId));
    }

    // 5
    function test_Accepted_StalePackage_Fails() public {
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW - MAX_AGE - 1), ACK);
        bytes32 settlementId = _acceptSell(offerId, _one(ACK));
        assertFalse(_check(settlementId));
    }

    // 6
    function test_Initialize_ZeroRegistry_Reverts() public {
        Section4a7DisclosureCondition impl = new Section4a7DisclosureCondition();
        vm.expectRevert(Section4a7DisclosureCondition.InvalidRegistry.selector);
        _proxy(
            address(impl),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (address(auth), address(0), MAX_AGE))
        );
    }

    // 7 — the acknowledgment string is the SPV's, so an empty one is rejected when it sets its package
    function test_SetDisclosure_EmptyAck_Reverts() public {
        vm.expectRevert(Section4a7DisclosureCondition.InvalidAcknowledgment.selector);
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), "");
    }

    // 8
    function test_Initialize_ZeroMaxAge_Reverts() public {
        Section4a7DisclosureCondition impl = new Section4a7DisclosureCondition();
        vm.expectRevert(Section4a7DisclosureCondition.InvalidMaxAge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (address(auth), address(registry), 0))
        );
    }

    // 9
    function test_SetDisclosure_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), ACK);
    }

    // Spec §4.1.4 names the acknowledgment string as a per-SPV parameter, set under that SPV's own
    // BorgAuth — each SPV's counsel words its receipt differently.
    function test_AcknowledgmentValue_IsPerSpv() public {
        SpvFixture otherSpv = new SpvFixture(address(auth));
        disc.setDisclosurePackage(address(corp), URI, uint64(NOW), ACK);
        disc.setDisclosurePackage(address(otherSpv), URI, uint64(NOW), "other wording");

        string memory ours = disc.disclosures(address(corp)).acknowledgmentValue;
        string memory theirs = disc.disclosures(address(otherSpv)).acknowledgmentValue;
        assertEq(ours, ACK);
        assertEq(theirs, "other wording");

        // The buyer's acknowledgment is matched against this SPV's wording, not the other's.
        bytes32 settlementId = _acceptSell(offerId, _one(ACK));
        assertTrue(_check(settlementId));
    }
}