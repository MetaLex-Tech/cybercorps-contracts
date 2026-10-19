// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

/// @title One-transaction deployer for the credit-facility MetaDAOFactory proxy
/// @notice Deploying this contract from a wallet performs, atomically, what
///   `script/deploy-metadao-credit-facility-factory.s.sol` performs step by step:
///   template registration (skipped when the id already holds the same schema,
///   reverted when it holds anything else), a fresh BorgAuth, an ERC1967 proxy over
///   the EXISTING MetaDAOFactory implementation, the standard officer record, and
///   the owner roles. The deploying wallet receives OWNER_ROLE so it can store the
///   officer's escrowed signature bytes if the officer signs offline; revoke it with
///   `auth.updateRole(wallet, 0)` afterwards. This contract drops its own role at
///   the end and keeps no power. It changes nothing on the standard factory, the
///   registry or any implementation.
contract CreditFacilityFactoryDeployer {
    address internal constant STANDARD_FACTORY = 0x734aE2b36f663D0F4233Ce4a02c13b5EB8ec959D;
    address internal constant IMPLEMENTATION = 0xD7F065826ba6dd793E8aE46B4c2F9334Fa80adbb;
    bytes32 internal constant IMPLEMENTATION_CODE_HASH =
        0x1ddb5db8ff71397e1aef7db13fb00ea0a1dfa76be83975a100071c3bf9f8c5d8;
    // Base Sepolia: the standard MetaDAO factory still points at version-3 component
    // factories; the core CyberCorpFactory there uses these version-5 ones.
    address internal constant BASE_SEPOLIA_ISSUANCE_MANAGER_FACTORY_V5 =
        0xbbD386D237f3b407E6511A52488850b1Da0cCad2;
    address internal constant BASE_SEPOLIA_ROUND_MANAGER_FACTORY_V5 =
        0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34;
    address internal constant BASE_CORP_PAYABLE = 0x59026c9A3871505c8E5fb0B021e274a0B28547F6;

    string internal constant SEGCO_TITLE =
        "MetaDAO Futarchy Governance SPC - SegCo combined - Credit Facility Operator v 1.0";
    string internal constant SEGCO_URI =
        "ipfs://bafybeigtgeoj5skx5vienw3hfegxfavwn6sn3omw4gx6gdsdoo3ioexqye";
    string internal constant BOARD_CONSENT_TITLE =
        "MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo - Credit Facility Operator v 1.0";
    string internal constant BOARD_CONSENT_URI =
        "ipfs://bafkreihiy7xvbhloloyl2pfthreq7wyar22ss5isxxckla6zhltbnexmqm";

    address public immutable factory;
    address public immutable auth;
    address public immutable deployedBy;

    event CreditFacilityFactoryDeployed(
        address indexed factory, address indexed auth, address indexed deployedBy, bytes32 segCoTemplateId, bytes32 boardConsentTemplateId
    );

    constructor() {
        require(block.chainid == 8453 || block.chainid == 84532, "deploy on Base or Base Sepolia");
        require(IMPLEMENTATION.codehash == IMPLEMENTATION_CODE_HASH, "implementation code hash drift");

        MetaDAOFactory standard = MetaDAOFactory(STANDARD_FACTORY);
        address registry = standard.registryAddress();
        address issuanceManagerFactory = standard.issuanceManagerFactory();
        address roundManagerFactory = standard.roundManagerFactory();
        if (block.chainid == 84532) {
            issuanceManagerFactory = BASE_SEPOLIA_ISSUANCE_MANAGER_FACTORY_V5;
            roundManagerFactory = BASE_SEPOLIA_ROUND_MANAGER_FACTORY_V5;
        }
        (address officerEoa, string memory officerName, string memory officerContact, string memory officerTitle) =
            standard.metaDAOOfficer();
        require(officerEoa != address(0), "standard factory has no officer");

        bytes32 segCoId = keccak256(bytes(SEGCO_TITLE));
        bytes32 boardConsentId = keccak256(bytes(BOARD_CONSENT_TITLE));
        string[] memory globalFields = _globalFields();
        string[] memory partyFields = _partyFields();
        _ensureTemplate(registry, segCoId, SEGCO_TITLE, SEGCO_URI, globalFields, partyFields);
        _ensureTemplate(registry, boardConsentId, BOARD_CONSENT_TITLE, BOARD_CONSENT_URI, globalFields, partyFields);

        BorgAuth newAuth = new BorgAuth(address(this));
        MetaDAOFactory newFactory = MetaDAOFactory(
            address(
                new ERC1967Proxy(
                    IMPLEMENTATION,
                    abi.encodeCall(
                        MetaDAOFactory.initialize,
                        (
                            address(newAuth),
                            registry,
                            issuanceManagerFactory,
                            standard.cyberCorpSingleFactory(),
                            standard.dealManagerFactory(),
                            roundManagerFactory,
                            standard.uriBuilder(),
                            standard.stable()
                        )
                    )
                )
            )
        );
        newFactory.setMetaDAOOfficer(
            CompanyOfficer({eoa: officerEoa, name: officerName, contact: officerContact, title: officerTitle})
        );

        uint256 ownerRole = newAuth.OWNER_ROLE();
        newAuth.updateRole(officerEoa, ownerRole);
        if (block.chainid == 8453) newAuth.updateRole(BASE_CORP_PAYABLE, ownerRole);
        newAuth.updateRole(msg.sender, ownerRole);
        newAuth.updateRole(address(this), 0);

        factory = address(newFactory);
        auth = address(newAuth);
        deployedBy = msg.sender;
        emit CreditFacilityFactoryDeployed(address(newFactory), address(newAuth), msg.sender, segCoId, boardConsentId);
    }

    function _ensureTemplate(
        address registry,
        bytes32 id,
        string memory title,
        string memory uri,
        string[] memory globalFields,
        string[] memory partyFields
    ) internal {
        (string memory existingUri,) = CyberAgreementRegistry(registry).templates(id);
        if (bytes(existingUri).length == 0) {
            CyberAgreementRegistry(registry).createTemplate(id, title, uri, globalFields, partyFields);
            return;
        }
        (string memory registeredUri, string memory registeredTitle, string[] memory registeredGlobal, string[] memory registeredParty) =
            CyberAgreementRegistry(registry).getTemplateDetails(id);
        require(
            keccak256(bytes(registeredUri)) == keccak256(bytes(uri))
                && keccak256(bytes(registeredTitle)) == keccak256(bytes(title))
                && keccak256(abi.encode(registeredGlobal)) == keccak256(abi.encode(globalFields))
                && keccak256(abi.encode(registeredParty)) == keccak256(abi.encode(partyFields)),
            "template id already registered with other content"
        );
    }

    function _globalFields() internal pure returns (string[] memory fields) {
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

    function _partyFields() internal pure returns (string[] memory fields) {
        fields = new string[](2);
        fields[0] = "name";
        fields[1] = "contactDetails";
    }
}
