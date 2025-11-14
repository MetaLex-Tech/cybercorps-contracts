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
        return runWithArgs(
            vm.envUint("PRIVATE_KEY_MAIN"), // deployerPrivateKey
            // TODO: review needed: is this up to date?
            0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C, // multisig
            hex"63f62ac9b08c813401a02a16a820a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1b" // metadaoEscrowSig 
        );
    }

    function runWithArgs(
        uint256 deployerPrivateKey,
        address multisig,
        bytes memory metadaoEscrowSig
    ) public returns (CyberAgreementRegistry registry, MetaDAOFactory metaDAOFactory) {
        // Other configs
        string memory metaDAOOfficerName = "MetaDAO Officer"; // TODO TBD
        string memory metaDAOOfficerContact = "metadao@example.com"; // TODO TBD
        string memory metaDAOOfficerTitle = "CEO"; // TODO TBD

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

        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;/*address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        );*/

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
        CyberAgreementRegistry(registry).createTemplate(
            keccak256(bytes(segCoAgreementTitle)),
            segCoAgreementTitle,
            segCoAgreementUri,
            globalFields,
            partyFields
        );

        // Create template for Board Consent
        string memory boardConsentTitle = "MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo v 1.0";
        string memory boardConsentUri = "ipfs://bafkreic7dscoigvwjc23vzvkmzophm34kpafu6nrctykq5bif63lqvpuoa";
        CyberAgreementRegistry(registry).createTemplate(
            keccak256(bytes(boardConsentTitle)),
            boardConsentTitle,
            boardConsentUri,
            globalFields,
            partyFields
        );

        address uriBuilder = 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3;/*address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(auth)
                )
            )
        );*/

       // address issuanceManagerImplementation = address(new IssuanceManager{salt: salt}());
       // address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
       // address cyberCert20Implementation = address(new CyberScrip{salt: salt}());
        address issuanceManagerFactory = 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf;/*address(
            new ERC1967Proxy{salt: salt}(
                address(new IssuanceManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    issuanceManagerImplementation,
                    cyberCertPrinterImplementation,
                    cyberCert20Implementation
                )
            )
        );*/

        address cyberCorpSingleFactory = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;/*address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberCorpSingleFactory{salt: salt}()),
                abi.encodeWithSelector(
                    CyberCorpSingleFactory.initialize.selector,
                    address(auth),
                    address(new CyberCorp())
                )
            )
        );*/

        address dealManagerFactory = 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3;/*address(
            new ERC1967Proxy{salt: salt}(
                address(new DealManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            )
        );*/

        /*address roundManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        );*/

                //upgrade cyberagreementregistry
        CyberAgreementRegistry(registry).upgradeToAndCall(
            address(new CyberAgreementRegistry{salt: salt}()),
            ""
        );

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
        metaDAOFactory.setMetaDAOOfficerEOA(multisig);
        metaDAOFactory.setMetaDAOOfficerName(metaDAOOfficerName);
        metaDAOFactory.setMetaDAOOfficerContact(metaDAOOfficerContact);
        metaDAOFactory.setMetaDAOOfficerTitle(metaDAOOfficerTitle);
        
        if (metadaoEscrowSig.length > 0) {
            // If we have the signature to escrow, set it
            metaDAOFactory.setMetaDAOSignatureHash(metadaoEscrowSig);

        } else {
            // Otherwise, output the typed data for MetaDAO to sign off-chain
            string[] memory partyValues = new string[](2);
            partyValues[0] = metaDAOOfficerName;
            partyValues[1] = metaDAOOfficerContact;

            console.log("Signature required: have MetaDAO sign the following EIP-712 typed data:");
            console.log("  (can be signed with command `cast wallet sign --data '<paste json string here>'`)");
            console.log("==== JSON data start ====");
            console.log(_formatEscrowAgreementTypedDataJson(
                CyberAgreementRegistry(registry),
                boardConsentUri,
                partyFields,
                partyValues
            ));
            console.log("==== JSON data end ====");
        }

        // Create the parent corp (one-time). Reverts if called again.
        (address parentCorp,
         address parentAuth,
         address parentIssuance,
         address parentDealMgr,
         address parentRoundMgr) = metaDAOFactory.createParentCorp(
            bytes32(keccak256("MetaDAO.parent.corp.v1")),
            "MetaLeX MetaDAO",
            "corporation",
            "DE",
            "contact@metadao.example",
            "arbitration",
            multisig
        );

        // Assign roles and revoke EOA ownership (after setup)
        auth.updateRole(address(multisig), auth.OWNER_ROLE());

        /* if (_partyValues.length < 2
            || !_partyValues[0].equal(_officer.name)
            || !_partyValues[1].equal(_officer.contact)
            || !_globalValues[2].equal(companyName)
            || !_globalValues[3].equal(companyType)
            || !_globalValues[4].equal(companyJurisdiction)
            || !_globalValues[5].equal(companyContactDetails)
        ) {
            revert GlobalOrPartyValuesMismatch();
        }*/ 
        
        uint256 salta = 1;
        string memory companyName = "MetaLeX MetaDAO";
        string memory companyType = "corporation";
        string memory companyJurisdiction = "DE";
        string memory companyContactDetails = "contact@metadao.example";
        string memory defaultDisputeResolution = "arbitration";
        address _companyPayable = address(0);
        CompanyOfficer memory _officer = CompanyOfficer({eoa: deployerAddress, name: metaDAOOfficerName, contact: metaDAOOfficerContact, title: metaDAOOfficerTitle});
        bytes32 _segCoTemplateId = keccak256(bytes(segCoAgreementTitle));
        bytes32 _boardConsentTempateId = keccak256(bytes(boardConsentTitle));
        string[] memory _globalValues = new string[](8);
        _globalValues[0] = "founderName";
        _globalValues[1] = "enterpriseName";
        _globalValues[2] = companyName;
        _globalValues[3] = companyType;
        _globalValues[4] = companyJurisdiction;
        _globalValues[5] = companyContactDetails;
        _globalValues[6] = "tokenSymbol";
        _globalValues[7] = "tokenName";
        string[] memory _partyValues = new string[](2);
        _partyValues[0] = metaDAOOfficerName;
        _partyValues[1] = metaDAOOfficerContact;
        // Parties must match factory override: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = multisig;
        parties[1] = deployerAddress;
        // Compute contractId and create EIP-712 signature for deployer
        bytes32 contractId = keccak256(abi.encode(_segCoTemplateId, salta, _globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            CyberAgreementRegistry(registry).DOMAIN_SEPARATOR(),
            CyberAgreementRegistry(registry).SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoAgreementUri,
            globalFields,
            partyFields,
            _globalValues,
            _partyValues,
            deployerPrivateKey
        );
        address deployer = deployerAddress;



        metaDAOFactory.deployMetaDAOContractFor(
            salta,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            _officer,
            _segCoTemplateId,
            _boardConsentTempateId,
            _globalValues,
            _partyValues,
            signature,
            deployer
        );
        //auth.zeroOwner();

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
        //console.log("ParentCorp:", parentCorp);
        //console.log("ParentAuth:", parentAuth);
        //console.log("ParentIssuance:", parentIssuance);
        //console.log("ParentDealMgr:", parentDealMgr);
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
