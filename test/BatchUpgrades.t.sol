// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {LeXcheX} from "../src/creds/lexchex.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LexChexCondition} from "../src/libs/conditions/lexchexCondition.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {ERC1967Proxy} from  "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from  "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {UUPSUpgradeable} from  "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {Test, console2} from "forge-std/Test.sol";

contract BatchExecutor {
    struct Op {
        address target;
        bytes data;
    }

    event OpExecuted(address indexed sender, Op op);

    error Unauthorized(address sender);
    error OpFailed(Op op);

    function executeBatch(
        Op[] calldata ops
    ) external {
        // This function is intended to be used by the smart account itself (i.e. address(this)) and no one else.
        // Also because of this, no nonce checks are needed to prevent replay attacks.
        if (msg.sender != address(this)) {
            revert Unauthorized(msg.sender);
        }

        for (uint256 i = 0; i < ops.length; i++) {
            (bool success, ) = ops[i].target.call(ops[i].data);
            if (success) {
                emit OpExecuted(msg.sender, ops[i]);
            } else {
                revert OpFailed(ops[i]);
            }
        }
    }
}

contract BatchUpgradesTest is Test {
    using ERC1967ProxyLib for address;

    address deployer = makeAddr("deployer");
    address metalexSafe = makeAddr("metalexSafe");

    address corpOwner0;
    uint256 corpOwnerPrivateKey0;

    bytes32 salt = keccak256("BatchUpgradesTest");
    bytes32 templateId = keccak256("BatchUpgradesTest.template");

    bytes32 lexchexSalt = keccak256("BatchUpgradesTest.lexchex");
    bytes32 lexchexTemplateId = keccak256("BatchUpgradesTest.template.lexchex");

    MockERC20 paymentToken = new MockERC20("Payment Token", "PAY", 18);

    BorgAuth coreAuth;
    CyberAgreementRegistry registry;
    CertificateUriBuilder uriBuilder;
    CyberCorpFactory cyberCorpFactory;
    CyberCorpSingleFactory cyberCorpSingleFactory;
    IssuanceManagerFactory issuanceManagerFactory;
    DealManagerFactory dealManagerFactory;
    RoundManagerFactory roundManagerFactory;

    BorgAuth lexchexAuth;

    BorgAuth corpAuth0;
    CyberCorp cyberCorp0;
    IssuanceManager issuanceManager0;
    DealManager dealManager0;
    RoundManager roundManager0;

    BatchExecutor batchExecutor;

    function setUp() public {
        (corpOwner0, corpOwnerPrivateKey0) = makeAddrAndKey("corpOwner0");

        // Deploy ecosystems
        
        vm.startPrank(deployer);

        BorgAuth auth = new BorgAuth{salt: salt}(deployer);

        address issuanceManagerImplementation = address(new IssuanceManager{salt: salt}());
        address cyberCertPrinterImplementation = address(new CyberCertPrinter{salt: salt}());
        address cyberCert20Implementation = address(new CyberScrip{salt: salt}());
        issuanceManagerFactory = IssuanceManagerFactory(address(
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
        ));
        vm.label(address(issuanceManagerFactory), "IssuanceManagerFactory");

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "";

        cyberCorpSingleFactory = CyberCorpSingleFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberCorpSingleFactory{salt: salt}()),
                abi.encodeWithSelector(
                    CyberCorpSingleFactory.initialize.selector,
                    address(auth),
                    address(new CyberCorp())
                )
            )
        ));
        vm.label(address(cyberCorpSingleFactory), "CyberCorpSingleFactory");

        dealManagerFactory = DealManagerFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new DealManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(auth),
                    address(new DealManager())
                )
            )
        ));
        vm.label(address(dealManagerFactory), "DealManagerFactory");

        roundManagerFactory = RoundManagerFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new RoundManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        ));
        vm.label(address(roundManagerFactory), "RoundManagerFactory");

        // Deploy upgradeable singletons

        registry = CyberAgreementRegistry(address(
            new ERC1967Proxy{salt: salt}(
                address(new CyberAgreementRegistry{salt: salt}()),
                abi.encodeWithSelector(
                    CyberAgreementRegistry.initialize.selector,
                    address(auth)
                )
            )
        ));
        vm.label(address(registry), "CyberAgreementRegistry");

        uriBuilder = CertificateUriBuilder(address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(auth)
                )
            )
        ));
        vm.label(address(uriBuilder), "CertificateUriBuilder");

        cyberCorpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(auth),
                        address(registry),
                        issuanceManagerFactory,
                        cyberCorpSingleFactory,
                        dealManagerFactory,
                        roundManagerFactory,
                        uriBuilder
                    )
                )
            )
        );
        vm.label(address(cyberCorpFactory), "CyberCorpFactory");

        cyberCorpFactory.setStable(address(paymentToken));

        string[] memory globalFieldsSafe = new string[](5);
        globalFieldsSafe[0] = "purchaseAmount";
        globalFieldsSafe[1] = "postMoneyValuationCap";
        globalFieldsSafe[2] = "expirationTime";
        globalFieldsSafe[3] = "governingJurisdiction";
        globalFieldsSafe[4] = "disputeResolution";

        string[] memory partyFieldsSafe = new string[](5);
        partyFieldsSafe[0] = "name";
        partyFieldsSafe[1] = "evmAddress";
        partyFieldsSafe[2] = "contactDetails";
        partyFieldsSafe[3] = "investorType";
        partyFieldsSafe[4] = "investorJurisdiction";

        CyberAgreementRegistry(registry).createTemplate(
            templateId,
            "SAFE",
            "https://ipfs.io/ipfs/bafybeih5wvr7zfw76plnb66teaa66rtgoikhhcqh55oecuoxtuw5c3dooi",
            globalFieldsSafe,
            partyFieldsSafe
        );

        auth.updateRole(address(metalexSafe), 200);
        auth.zeroOwner();

        // Deploy LeXcheX

        BorgAuth lexchexAuth = new BorgAuth{salt: lexchexSalt}(deployer);

        LeXcheX lexchex = LeXcheX(address(new ERC1967Proxy{salt: lexchexSalt}(
            address(new LeXcheX{salt: lexchexSalt}()),
            abi.encodeWithSelector(LeXcheX.initialize.selector, address(lexchexAuth))
        )));

        LeXcheXMinter lexchexMinter = LeXcheXMinter(address(new ERC1967Proxy{salt: lexchexSalt}(
            address(new LeXcheXMinter{salt: lexchexSalt}()),
            abi.encodeWithSelector(
                LeXcheXMinter.initialize.selector,
                address(lexchexAuth),
                address(lexchex),
                address(registry),
                metalexSafe
            )
        )));

        LexChexCondition lexchexCondition = new LexChexCondition{salt: lexchexSalt}();
        lexchexCondition.initialize(address(lexchex), address(lexchexAuth));

        // Grant LeXcheXMinter admin access to LeXcheX
        lexchexAuth.updateRole(address(lexchexMinter), lexchexAuth.ADMIN_ROLE());
        lexchexAuth.updateRole(address(metalexSafe), lexchexAuth.OWNER_ROLE());

        // Somehow this is not in the deploy script
        lexchexAuth.updateRole(address(cyberCorpFactory), lexchexAuth.OWNER_ROLE());

        vm.stopPrank();

        vm.startPrank(metalexSafe);

        cyberCorpFactory.setLexchexAuth(address(lexchexAuth));
        
        string[] memory globalFieldsLexchex = new string[](1);
        globalFieldsLexchex[0] = "expiryDate";

        string[] memory partyFieldsLexchex = new string[](4);
        partyFieldsLexchex[0] = "investorName";
        partyFieldsLexchex[1] = "investorType";
        partyFieldsLexchex[2] = "investorJurisdiction";
        partyFieldsLexchex[3] = "investorContact";

        CyberAgreementRegistry(registry).createTemplate(
            lexchexTemplateId,
            "MetaLeX LeXCheX agreement v.1.0",
            "ipfs://bafkreifikp43eagam765uiapfakvk6bc4chv62e2pv5qytrv6wlsrt6qji",
            globalFieldsLexchex,
            partyFieldsLexchex
        );

        vm.stopPrank();

        // Deploy test cyber corp

        {
            vm.startPrank(corpOwner0);

            (
                address cyberCorpAddr,
                address authAddr,
                address issuanceManager,
                address dealManagerAddr,
                address roundManagerAddr
            ) = cyberCorpFactory.deployCyberCorp(
                keccak256("corp0"),
                "Corp0",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                corpOwner0,
                CompanyOfficer({
                    eoa: corpOwner0,
                    name: "Corp Owner 0",
                    contact: "corpOwner0@corp.com",
                    title: "CEO"
                })
            );

            cyberCorp0 = CyberCorp(cyberCorpAddr);
            corpAuth0 = BorgAuth(authAddr);
            issuanceManager0 = IssuanceManager(issuanceManager);
            dealManager0 = DealManager(dealManagerAddr);
            roundManager0 = RoundManager(roundManagerAddr);

            vm.stopPrank();
        }

        // Deploy batch upgrade helper contract
        batchExecutor = new BatchExecutor();
    }

    function test_batch_upgrades() public {
        // Simulate MetaLeX releasing new versions
        vm.startPrank(metalexSafe);

        address newCyberCorpImpl = address(new CyberCorp());
        address newIssuanceManagerImpl = address(new IssuanceManager());
        address newCertPrinterImpl = address(new CyberCertPrinter());

        cyberCorpSingleFactory.setRefImplementation(newCyberCorpImpl);
        issuanceManagerFactory.setRefImplementation(newIssuanceManagerImpl);
        issuanceManagerFactory.setCyberCertPrinterRefImplementation(newCertPrinterImpl);

        assertNotEq((address(cyberCorp0)).getErc1967Implementation(), newCyberCorpImpl, "CyberCorp should not have been upgraded atm");
        assertNotEq((address(issuanceManager0)).getErc1967Implementation(), newIssuanceManagerImpl, "IssuanceManager should not have been upgraded atm");
        assertNotEq(issuanceManager0.getCertPrinterBeaconImplementation(), newCertPrinterImpl, "CyberCertPrinter should not have been upgraded atm");

        vm.stopPrank();

        // Corp owner to accept the upgrades in one transaction (with EIP-7702)

        vm.startPrank(corpOwner0);

        BatchExecutor.Op[] memory ops = new BatchExecutor.Op[](3);
        ops[0] = BatchExecutor.Op({
            target: address(cyberCorp0),
            data: abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newCyberCorpImpl, "")
        });
        ops[1] = BatchExecutor.Op({
            target: address(issuanceManager0),
            data: abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newIssuanceManagerImpl, "")
        });
        ops[2] = BatchExecutor.Op({
            target: address(issuanceManager0),
            data: abi.encodeWithSelector(IssuanceManager.upgradeCertPrinterBeaconImplementation.selector, newCertPrinterImpl)
        });

        vm.signAndAttachDelegation(address(batchExecutor), corpOwnerPrivateKey0);
        BatchExecutor(corpOwner0).executeBatch(ops);

        vm.stopPrank();

        assertEq((address(cyberCorp0)).getErc1967Implementation(), newCyberCorpImpl, "CyberCorp should have been upgraded by now");
        assertEq((address(issuanceManager0)).getErc1967Implementation(), newIssuanceManagerImpl, "IssuanceManager should have been upgraded by now");
        assertEq(issuanceManager0.getCertPrinterBeaconImplementation(), newCertPrinterImpl, "CyberCertPrinter should have been upgraded by now");
    }
}
