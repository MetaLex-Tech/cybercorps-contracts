// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../../src/CyberAgreementRegistry.sol";

/// @notice The credit-facility template pair and the one rule both deployment
///   paths (the Foundry script and the one-transaction deployer) apply when a
///   template id is already registered: the whole schema must match, or the
///   deployment refuses. Shared so the rule has one home and one test.
library CreditFacilityTemplates {
    string internal constant SEGCO_TITLE =
        "MetaDAO Futarchy Governance SPC - SegCo combined - Credit Facility Operator v 1.0";
    string internal constant SEGCO_URI =
        "ipfs://bafybeigtgeoj5skx5vienw3hfegxfavwn6sn3omw4gx6gdsdoo3ioexqye";
    string internal constant BOARD_CONSENT_TITLE =
        "MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo - Credit Facility Operator v 1.0";
    string internal constant BOARD_CONSENT_URI =
        "ipfs://bafkreihiy7xvbhloloyl2pfthreq7wyar22ss5isxxckla6zhltbnexmqm";

    error TemplateSchemaMismatch(bytes32 templateId);

    function segCoId() internal pure returns (bytes32) {
        return keccak256(bytes(SEGCO_TITLE));
    }

    function boardConsentId() internal pure returns (bytes32) {
        return keccak256(bytes(BOARD_CONSENT_TITLE));
    }

    function globalFields() internal pure returns (string[] memory fields) {
        fields = new string[](10);
        fields[0] = "founderName";
        fields[1] = "enterpriseName";
        fields[2] = "companyName";
        fields[3] = "companyType";
        fields[4] = "companyJurisdiction";
        fields[5] = "companyContactDetails";
        fields[6] = "tokenSymbol";
        fields[7] = "tokenName";
        fields[8] = "opcoName";
        fields[9] = "opcoJurisdiction";
    }

    function partyFields() internal pure returns (string[] memory fields) {
        fields = new string[](2);
        fields[0] = "name";
        fields[1] = "contactDetails";
    }

    /// @notice Registers both templates, reusing an id only when its registered
    ///   URI, title, global fields and party fields all equal the expected ones.
    function ensureBoth(address registry) internal {
        ensure(registry, segCoId(), SEGCO_TITLE, SEGCO_URI);
        ensure(registry, boardConsentId(), BOARD_CONSENT_TITLE, BOARD_CONSENT_URI);
    }

    /// @return created true when this call registered the template, false when an
    ///   identical registration was reused.
    function ensure(address registry, bytes32 id, string memory title, string memory uri)
        internal
        returns (bool created)
    {
        string[] memory expectedGlobal = globalFields();
        string[] memory expectedParty = partyFields();
        (string memory existingUri,) = CyberAgreementRegistry(registry).templates(id);
        if (bytes(existingUri).length == 0) {
            CyberAgreementRegistry(registry).createTemplate(id, title, uri, expectedGlobal, expectedParty);
            return true;
        }
        (string memory registeredUri, string memory registeredTitle, string[] memory registeredGlobal, string[] memory registeredParty) =
            CyberAgreementRegistry(registry).getTemplateDetails(id);
        bool same = keccak256(bytes(registeredUri)) == keccak256(bytes(uri))
            && keccak256(bytes(registeredTitle)) == keccak256(bytes(title))
            && keccak256(abi.encode(registeredGlobal)) == keccak256(abi.encode(expectedGlobal))
            && keccak256(abi.encode(registeredParty)) == keccak256(abi.encode(expectedParty));
        if (!same) revert TemplateSchemaMismatch(id);
        return false;
    }
}
