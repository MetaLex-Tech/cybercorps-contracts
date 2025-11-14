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
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";

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
            // TODO: review needed: is this up to date?
            0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C, // multisig
            hex"63f62ac9b08c813401a02a16a820a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1b" // metadaoEscrowSig 
        );
    }

    function run(
        address multisig,
        bytes memory metadaoEscrowSig
    ) public returns (CyberAgreementRegistry registry, MetaDAOFactory metaDAOFactory) {
        // Other configs
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        string memory metaDAOOfficerName = "MetaDAO LLC, a Marshall Islands DAO limited liability company"; 
        string memory metaDAOOfficerContact = "market.governed.civilization@metadao.fi PO Box 852, Long Island Rd, Majuro, Marshall Islands MH 96960"; 
        string memory metaDAOOfficerTitle = "Director & Management Shareholder"; 
        address corpPayable = 0x59026c9A3871505c8E5fb0B021e274a0B28547F6;
        address officerAddress = 0x76A6168B69f8f1b27E06dC77a30F2D1C92733e7A;

        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        bytes32 salt = bytes32(keccak256("MetaDAOFactory.deploy.v1"));

        uint256 currentChainId = block.chainid;
        address stable;

        if (currentChainId == 1) {
            stable = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet USDC
        } else if (currentChainId == 42161) {
            stable = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum USDC
        } else if (currentChainId == 8453) {
            stable = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base USDC
        } else if (currentChainId == 84532) {
            stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC
        } else if (currentChainId == 11155111) {
            stable = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC
        } else {
            revert("Unsupported chain ID");
        }

        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        // Create templates

        string[] memory globalFields = new string[](8);
        globalFields[0] = "founderName";
        globalFields[1] = "enterpriseName";
        globalFields[2] = "companyName";
        globalFields[3] = "companyType";
        globalFields[4] = "companyJurisdiction";
        globalFields[5] = "companyContactDetails";
        globalFields[6] = "tokenSymbol";
        globalFields[7] = "tokenName";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "name";
        partyFields[1] = "contactDetails";

        // Create template for SegCo
        string memory segCoAgreementTitle = "MetaDAO Futarchy Governance SPC - SegCo combined v 1.0";
        string memory segCoAgreementUri = "ipfs://bafybeifpvfwxfmobk7nhflsczqiynp3ca5urvyk3duh7s3rwptcnfzhuje";

        // Create template for Board Consent
        string memory boardConsentTitle = "MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo v 1.0";
        string memory boardConsentUri = "ipfs://bafkreic7dscoigvwjc23vzvkmzophm34kpafu6nrctykq5bif63lqvpuoa";


        address uriBuilder = 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3;

        address issuanceManagerFactory = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;

        address cyberCorpSingleFactory = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;

        address dealManagerFactory = 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3;

        address newAgreementRegistryImplementation = address(new CyberAgreementRegistry{salt: salt}());

           

        MetaDAOFactory metaDAOFactory = MetaDAOFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new MetaDAOFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        MetaDAOFactory.initialize.selector,
                        address(auth),
                        address(registry),
                        address(issuanceManagerFactory),
                        address(cyberCorpSingleFactory),
                        address(dealManagerFactory),
                        address(0),
                        address(uriBuilder),
                        address(stable)
                    )
                )
            )
        );

        // Configure MetaDAO officer and escrowed signature BEFORE revoking deployer ownership
        metaDAOFactory.setMetaDAOOfficerEOA(officerAddress);
        metaDAOFactory.setMetaDAOOfficerName(metaDAOOfficerName);
        metaDAOFactory.setMetaDAOOfficerContact(metaDAOOfficerContact);
        metaDAOFactory.setMetaDAOOfficerTitle(metaDAOOfficerTitle);

        // Create the parent corp (one-time). Reverts if called again.
        (address parentCorp,
         address parentAuth,
         address parentIssuance,
         address parentDealMgr,
         address parentRoundMgr) = metaDAOFactory.createParentCorp(
            bytes32(keccak256("Futarchy Governance SPC")),
            "Futarchy Governance SPC",
            "segregated portfolio company",
            "Cayman Islands",
            "market.governed.civilization@metadao.fi",
            "binding arbitration",
            corpPayable
        );

        // Assign roles and revoke EOA ownership (after setup)
        auth.updateRole(address(officerAddress), auth.OWNER_ROLE());
        auth.updateRole(address(corpPayable), auth.OWNER_ROLE());


        console.log("Auth:", address(auth));
        console.log("CyberAgreementRegistry:", address(registry));
        console.log("CertificateUriBuilder:", address(uriBuilder));
        console.log("IssuanceManagerFactory:", address(issuanceManagerFactory));
        console.log("CyberCorpSingleFactory:", address(cyberCorpSingleFactory));
        console.log("DealManagerFactory:", address(dealManagerFactory));
       // console.log("RoundManagerFactory:", address(roundManagerFactory));
        //console.log("CyberCertPrinter Impl:", address(cyberCertPrinterImplementation));
       // console.log("CyberScrip Impl:", address(cyberCert20Implementation));
        console.log("MetaDAOFactory (proxy):", address(metaDAOFactory));
        console.log("ParentCorp:", parentCorp);
        console.log("ParentAuth:", parentAuth);
        console.log("ParentIssuance:", parentIssuance);
        console.log("ParentDealMgr:", parentDealMgr);
        console.log("NewAgreementRegistryImplementation:", address(newAgreementRegistryImplementation));
        //console.log("ParentRoundMgr:", parentRoundMgr);

        vm.stopBroadcast();

        return (CyberAgreementRegistry(registry), metaDAOFactory);
    }

    function _formatEscrowAgreementTypedDataJson(
        CyberAgreementRegistry registry,
        string memory contractUri,
        string[] memory partyFields,
        string[] memory partyValues
    ) internal returns (string memory) {
        string memory domainSeparatorJson = vm.serializeJsonType(
            DOMAIN_SEPARATOR_TYPE,
            abi.encode(DomainSeparator({
                name: registry.name(),
                version: registry.version(),
                chainId: block.chainid,
                verifyingContract: address(registry)
            }))
        );

        string memory escrowSignatureDataJson = vm.serializeJsonType(
            ESCROW_SIGNATUREDATA_TYPE,
            abi.encode(EscrowSignatureData({
                legalContractUri: contractUri,
                partyFields: partyFields,
                partyValues: partyValues
            }))
        );

        // Build the json string with the temporary buffer at key "outputKey"
        vm.serializeString("outputKey", "domain", domainSeparatorJson);
        vm.serializeString("outputKey", "message", escrowSignatureDataJson);
        vm.serializeString("outputKey", "primaryType", "EscrowSignatureData");
        return vm.serializeString("outputKey", "types", "{\"EIP712Domain\":[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"version\",\"type\":\"string\"},{\"name\":\"chainId\",\"type\":\"uint256\"},{\"name\":\"verifyingContract\",\"type\":\"address\"}],\"EscrowSignatureData\":[{\"name\":\"legalContractUri\",\"type\":\"string\"},{\"name\":\"partyFields\",\"type\":\"string[]\"},{\"name\":\"partyValues\",\"type\":\"string[]\"}]}");
    }
}
