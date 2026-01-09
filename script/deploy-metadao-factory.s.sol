// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMetaDAOFactoryScript is Script {
    // Hard-coded since we don't have programmatic access to CyberAgreementRegistry's underlying types
    string constant DOMAIN_SEPARATOR_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    string constant ESCROW_SIGNATUREDATA_TYPE = "EscrowSignatureData(string legalContractUri,string[] partyFields,string[] partyValues)";

    struct DomainSeparator {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    struct EscrowSignatureData {
        string legalContractUri;
        string[] partyFields;
        string[] partyValues;
    }

    function run() public returns (
        CyberAgreementRegistry registry, 
        MetaDAOFactory metaDAOFactory
    ) {
        return run(
            vm.envUint("PRIVATE_KEY_MAIN"), // deployerPrivateKey
            // TODO: review needed: is this up to date?
            0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C, // multisig
            "" // TBD: ask MetaDAO to sign
        );
    }

    function run(
        uint256 deployerPrivateKey,
        address multisig,
        bytes memory metadaoEscrowSig
    ) public returns (CyberAgreementRegistry registry, MetaDAOFactory metaDAOFactory) {
        // Other configs
     }
}
