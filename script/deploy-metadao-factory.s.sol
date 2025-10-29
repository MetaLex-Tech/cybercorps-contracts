// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMetaDAOFactoryScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
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

        address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        address registry = address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        );

        address uriBuilder = address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(auth)
                )
            )
        );

        address issuanceManagerImplementation = address(new IssuanceManager{salt: salt}());
        address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
        address cyberCert20Implementation = address(new CyberScrip{salt: salt}());
        address issuanceManagerFactory = address(
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
        );

        address cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: salt}(address(auth))
        );
        address dealManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new DealManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            )
        );
        address roundManagerFactory = address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        );

        MetaDAOFactory metaDAOFactory = MetaDAOFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new MetaDAOFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        MetaDAOFactory.initialize.selector,
                        address(auth),
                        address(registry),
                        cyberCertPrinterImplementation,
                        cyberCert20Implementation,
                        address(issuanceManagerFactory),
                        address(cyberCorpSingleFactory),
                        address(dealManagerFactory),
                        address(roundManagerFactory),
                        address(uriBuilder),
                        address(stable)
                    )
                )
            )
        );

        // Configure MetaDAO officer and escrowed signature BEFORE revoking deployer ownership
        metaDAOFactory.setMetaDAOOfficerEOA(multisig);
        metaDAOFactory.setMetaDAOOfficerName("MetaDAO Officer");
        metaDAOFactory.setMetaDAOOfficerContact("metadao@example.com");
        metaDAOFactory.setMetaDAOOfficerTitle("CEO");
        // Example escrowed signature payload (bytes)
        metaDAOFactory.setMetaDAOSignatureHash(abi.encodePacked("EXAMPLE_META_ESCROW_SIG"));

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
        auth.zeroOwner();

        console.log("Auth:", address(auth));
        console.log("CyberAgreementRegistry:", address(registry));
        console.log("CertificateUriBuilder:", address(uriBuilder));
        console.log("IssuanceManagerFactory:", address(issuanceManagerFactory));
        console.log("CyberCorpSingleFactory:", address(cyberCorpSingleFactory));
        console.log("DealManagerFactory:", address(dealManagerFactory));
        console.log("RoundManagerFactory:", address(roundManagerFactory));
        console.log("CyberCertPrinter Impl:", address(cyberCertPrinterImplementation));
        console.log("CyberScrip Impl:", address(cyberCert20Implementation));
        console.log("MetaDAOFactory (proxy):", address(metaDAOFactory));
        console.log("ParentCorp:", parentCorp);
        console.log("ParentAuth:", parentAuth);
        console.log("ParentIssuance:", parentIssuance);
        console.log("ParentDealMgr:", parentDealMgr);
        console.log("ParentRoundMgr:", parentRoundMgr);

        vm.stopBroadcast();
    }
}


