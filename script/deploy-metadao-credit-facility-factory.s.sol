// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

/// @title Credit-facility MetaDAOFactory proxy (webapp plan, option a)
/// @notice One run per chain (Base 8453, Base Sepolia 84532). It
///   1. registers the two credit-facility templates on the CyberAgreementRegistry
///      (skipped when the id already holds exactly this title and URI; reverts when
///      the id holds anything else),
///   2. deploys a fresh BorgAuth owned by the broadcaster,
///   3. deploys an ERC1967 proxy over the EXISTING MetaDAOFactory implementation
///      (no new implementation code), wired like the standard factory on that chain
///      except that Base Sepolia takes the version-5 IssuanceManager and RoundManager
///      factories the core CyberCorpFactory uses there,
///   4. copies the standard factory's officer record onto the new proxy,
///   5. grants OWNER_ROLE to the officer EOA (and, on Base, to the corp payable).
/// The broadcaster keeps OWNER_ROLE so it can store the officer's escrowed
/// signature bytes (`setMetaDAOSignatureHash`) if the officer signs offline; revoke
/// it afterwards with `auth.updateRole(broadcaster, 0)` from an owner key.
/// Nothing here changes the standard factory, the registry or any implementation.
contract DeployMetaDAOCreditFacilityFactoryScript is Script {
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

    function run() external {
        require(block.chainid == 8453 || block.chainid == 84532, "run on Base or Base Sepolia");
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

        address deployer = msg.sender;
        console2.log("chainId:", block.chainid);
        console2.log("deployer:", deployer);
        console2.log("registry:", registry);
        console2.log("issuanceManagerFactory:", issuanceManagerFactory);
        console2.log("roundManagerFactory:", roundManagerFactory);
        console2.log("segCo template id:", vm.toString(segCoId));
        console2.log("board consent template id:", vm.toString(boardConsentId));

        vm.startBroadcast();

        _ensureTemplate(registry, segCoId, SEGCO_TITLE, SEGCO_URI, globalFields, partyFields);
        _ensureTemplate(registry, boardConsentId, BOARD_CONSENT_TITLE, BOARD_CONSENT_URI, globalFields, partyFields);

        BorgAuth auth = new BorgAuth(deployer);
        MetaDAOFactory factory = MetaDAOFactory(
            address(
                new ERC1967Proxy(
                    IMPLEMENTATION,
                    abi.encodeCall(
                        MetaDAOFactory.initialize,
                        (
                            address(auth),
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
        factory.setMetaDAOOfficer(
            CompanyOfficer({eoa: officerEoa, name: officerName, contact: officerContact, title: officerTitle})
        );
        auth.updateRole(officerEoa, auth.OWNER_ROLE());
        if (block.chainid == 8453) auth.updateRole(BASE_CORP_PAYABLE, auth.OWNER_ROLE());

        vm.stopBroadcast();

        console2.log("");
        console2.log("==== Deployed (fill the credit-facility chain config with these) ====");
        console2.log("factory (proxy):", address(factory));
        console2.log("auth:", address(auth));
        console2.log("implementation:", IMPLEMENTATION);
        console2.log("officer eoa:", officerEoa);
        console2.log("owners: officer eoa", block.chainid == 8453 ? "+ corp payable" : "", "+ deployer until revoked");
        console2.log("next: officer stores the escrowed signature over", SEGCO_URI);
    }

    function _ensureTemplate(
        address registry,
        bytes32 id,
        string memory title,
        string memory uri,
        string[] memory globalFields,
        string[] memory partyFields
    ) internal {
        (string memory existingUri, string memory existingTitle) = CyberAgreementRegistry(registry).templates(id);
        if (bytes(existingUri).length == 0) {
            CyberAgreementRegistry(registry).createTemplate(id, title, uri, globalFields, partyFields);
            console2.log("template created:", title);
            return;
        }
        require(
            keccak256(bytes(existingUri)) == keccak256(bytes(uri))
                && keccak256(bytes(existingTitle)) == keccak256(bytes(title)),
            "template id already registered with other content"
        );
        console2.log("template already registered:", title);
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
