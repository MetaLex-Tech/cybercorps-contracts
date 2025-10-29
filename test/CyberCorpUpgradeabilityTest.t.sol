// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC721EnumerableUpgradeable
} from "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC721Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract RugCyberCorp {
    function acceptDealManagerUpgrade(address dm, address newImpl) external {
        DealManager(dm).upgradeToAndCall(newImpl, "");
    }
}

contract DealManagerRugger is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "ngmi";

    function showMeTheMoney(address token) external {
        ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override {}
}

contract RugCyberCertPrinter is ERC721EnumerableUpgradeable {
    // Burn token without any permission check
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}

contract RugCyberScrip is ERC20Upgradeable {
    // Mint token without any permission check
    function mint(address account, uint256 value) external {
        _mint(account, value);
    }
}

contract CyberCorpUpgradeabilityTest is Test {
    address public constant LEXCHEX_OWNER = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
    bytes32 public constant TEMPLATE_ID = keccak256("test template");
    uint256 public constant PAYMENT_AMOUNT = 100 ether;

    bytes32 public salt = keccak256("CyberCorpUpgradeabilityTest");

    uint256 public metalexPrivateKey;
    address public metalex;
    uint256 public corpOwnerPrivateKey;
    address public corpOwner;
    uint256 public alicePrivateKey;
    address public alice;

    MockERC20 public paymentToken;

    BorgAuth public metalexAuth;
    CyberCorpFactory public cyberCorpFactory;
    CyberCorpSingleFactory public cyberCorpSingleFactory;
    IssuanceManagerFactory public imFactory;
    DealManagerFactory public dmFactory;
    RoundManagerFactory public rmFactory;

    address public cyberCorpAddr;
    address public corpAuthAddr;
    address public imAddr;
    address public dmAddr;
    address public rmAddr;
    address[] public cyberCertPrinterAddrs;
    bytes32 public agreementId;
    uint256[] public certIds;

    function setUp() public {
        (metalex, metalexPrivateKey) = makeAddrAndKey("metalex");
        (corpOwner, corpOwnerPrivateKey) = makeAddrAndKey("corpOwner");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");

        metalexAuth = new BorgAuth(metalex);

        CyberAgreementRegistry registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(metalexAuth))
                )
            )
        );
        vm.label(address(registry), "CyberAgreementRegistry");

        CertificateUriBuilder uriBuilder = CertificateUriBuilder(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CertificateUriBuilder{salt: salt}()),
                    abi.encodeWithSelector(CertificateUriBuilder.initialize.selector, address(metalexAuth))
                )
            )
        );
        vm.label(address(uriBuilder), "CertificateUriBuilder");

        cyberCorpSingleFactory = new CyberCorpSingleFactory(address(metalexAuth));
        vm.label(address(cyberCorpSingleFactory), "CyberCorpSingleFactory");

        imFactory = new IssuanceManagerFactory(address(metalexAuth));
        vm.label(address(imFactory), "IssuanceManagerFactory");

        dmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new DealManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector, address(metalexAuth), address(new DealManager())
                    )
                )
            )
        );
        vm.label(address(dmFactory), "DealManagerFactory");

        rmFactory = RoundManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new RoundManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        RoundManagerFactory.initialize.selector, address(metalexAuth), address(new RoundManager())
                    )
                )
            )
        );
        vm.label(address(rmFactory), "RoundManagerFactory");

        cyberCorpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberCorpFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(metalexAuth),
                        address(registry),
                        new CyberCertPrinter(),
                        new CyberScrip(),
                        address(imFactory),
                        address(cyberCorpSingleFactory),
                        address(dmFactory),
                        address(rmFactory),
                        address(uriBuilder)
                    )
                )
            )
        );
        vm.label(address(cyberCorpFactory), "CyberCorpFactory");

        // Set payment token
        paymentToken = new MockERC20("Payment Token", "PAY", 18);
        vm.prank(metalex);
        cyberCorpFactory.setStable(address(paymentToken));

        // Grant the test CybercorpFactory access to LexCheX
        address lxAuth = cyberCorpFactory.lexchexAuth();
        vm.startPrank(LEXCHEX_OWNER);
        BorgAuth(lxAuth).updateRole(address(cyberCorpFactory), BorgAuth(lxAuth).OWNER_ROLE());
        vm.stopPrank();
        assertEq(address(cyberCorpFactory.AUTH()), address(metalexAuth), "CyberCorpFactory should be owned by MetaLeX");
        BorgAuth(lxAuth).onlyRole(BorgAuth(lxAuth).OWNER_ROLE(), address(cyberCorpFactory));

        // Create templates for tests
        string memory templateUri = "ipfs.io/ipfs/[cid]";
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";
        vm.prank(metalex);
        registry.createTemplate(TEMPLATE_ID, "Test Template", templateUri, globalFields, partyFields);

        // Simulate CyberCorp creation

        CyberCorpFactory.CyberCertData[] memory certData = new CyberCorpFactory.CyberCertData[](1);
        certData[0] = CyberCorpFactory.CyberCertData({
            name: "Cert Name 1",
            symbol: "Cert Symbol 1",
            uri: templateUri,
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesPreSeed,
            extension: address(0),
            defaultLegend: new string[](0)
        });

        CertificateDetails[] memory certDetails = new CertificateDetails[](1);
        certDetails[0] = CertificateDetails({
            signingOfficerName: "",
            signingOfficerTitle: "",
            investmentAmountUSD: 0,
            issuerUSDValuationAtTimeOfInvestment: 10000000,
            unitsRepresented: 0,
            legalDetails: "Legal Details, jusidictione etc",
            extensionData: ""
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";
        address[] memory parties = new address[](2);
        parties[0] = corpOwner;
        parties[1] = alice;
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Counter Party Value 1";

        bytes32 expectedAgreementId = keccak256(abi.encode(TEMPLATE_ID, uint256(salt), globalValues, parties));

        vm.startPrank(corpOwner);
        (cyberCorpAddr, corpAuthAddr, imAddr, dmAddr, rmAddr, cyberCertPrinterAddrs, agreementId, certIds) =
            cyberCorpFactory.deployCyberCorpAndCreateOffer(
                uint256(salt),
                "CyberCorp",
                "Limited Liability Company",
                "Juris",
                "Contact Details",
                "Dispute Res",
                corpOwner,
                CompanyOfficer({eoa: corpOwner, name: "Mr. Robot", contact: "robot@corp.com", title: "CEO"}),
                certData,
                TEMPLATE_ID,
                globalValues,
                parties,
                PAYMENT_AMOUNT,
                partyValues,
                CyberAgreementUtils.signAgreementTypedData(
                    vm,
                    registry.DOMAIN_SEPARATOR(),
                    registry.SIGNATUREDATA_TYPEHASH(),
                    expectedAgreementId,
                    templateUri,
                    globalFields,
                    partyFields,
                    globalValues,
                    partyValues[0],
                    corpOwnerPrivateKey
                ),
                certDetails,
                new address[](0), // conditions
                bytes32(0), // secretHash
                block.timestamp + 1000000
            );
        vm.stopPrank();

        // Simulate alice sign and pay

        vm.startPrank(alice);
        paymentToken.mint(alice, PAYMENT_AMOUNT);
        paymentToken.approve(dmAddr, PAYMENT_AMOUNT);
        DealManager(dmAddr)
            .signDealAndPay(
                alice,
                agreementId,
                CyberAgreementUtils.signAgreementTypedData(
                    vm,
                    registry.DOMAIN_SEPARATOR(),
                    registry.SIGNATUREDATA_TYPEHASH(),
                    agreementId,
                    templateUri,
                    globalFields,
                    partyFields,
                    globalValues,
                    partyValues[1],
                    alicePrivateKey
                ),
                partyValues[1],
                true,
                "Alice",
                ""
            );
        vm.stopPrank();
    }

    /// @dev TODO WIP: this is supposed to revert
    function test_RevertIf_RugCyberCorpAfterPayment() public {
        uint256 multisigBalanceBefore = paymentToken.balanceOf(metalex);

        vm.startPrank(metalex);

        // Upgrade CyberCorp beacon to a corrupted implementation
        address newCyberCorpImpl = address(new RugCyberCorp());
        cyberCorpSingleFactory.upgradeImplementation(newCyberCorpImpl);

        RugCyberCorp corp = RugCyberCorp(DealManager(dmAddr).issuanceManager().CORP());

        // Release corrupted DealManager
        address dealManagerRuggerImpl = address(new DealManagerRugger());
        dmFactory.setRefImplementation(dealManagerRuggerImpl);

        // Use corrupted CyberCorp to accept corrupted DealManager release
        corp.acceptDealManagerUpgrade(dmAddr, dealManagerRuggerImpl);

        // Profit(?)
        DealManagerRugger(dmAddr).showMeTheMoney(address(paymentToken));

        vm.stopPrank();

        assertEq(
            paymentToken.balanceOf(metalex) - multisigBalanceBefore,
            PAYMENT_AMOUNT,
            "should receive deal manager's token"
        );
    }

    /// @dev TODO WIP: this is supposed to revert
    function test_RevertIf_RugIssuanceManagerAfterPayment() public {
        // Assume Base-sepolia
        uint256 multisigBalanceBefore = paymentToken.balanceOf(metalex);

        vm.startPrank(metalex);

        // Upgrade IssuanceManager beacon to a corrupted implementation
        address ruggerImpl = address(new RugCyberCorp());
        imFactory.upgradeImplementation(ruggerImpl);

        RugCyberCorp rugger = RugCyberCorp(address(DealManager(dmAddr).issuanceManager()));

        // Release corrupted DealManager
        address dealManagerRuggerImpl = address(new DealManagerRugger());
        dmFactory.setRefImplementation(dealManagerRuggerImpl);

        // Use corrupted IssuanceManager to accept corrupted DealManager release
        rugger.acceptDealManagerUpgrade(dmAddr, dealManagerRuggerImpl);

        // Profit(?)
        DealManagerRugger(dmAddr).showMeTheMoney(address(paymentToken));

        vm.stopPrank();

        assertEq(
            paymentToken.balanceOf(metalex) - multisigBalanceBefore,
            PAYMENT_AMOUNT,
            "should receive deal manager's token"
        );
    }

    /// @dev TODO WIP: this is supposed to revert
    function test_RevertIf_RugCyberCertificatePrinter() public {
        // Finalize the deal so certificate is transferred to alice
        DealManager(dmAddr).finalizeDeal(agreementId);

        // Sanity check
        assertEq(CyberCertPrinter(cyberCertPrinterAddrs[0]).ownerOf(certIds[0]), alice);

        vm.startPrank(metalex);

        // IssuanceManagerFactory can unilaterally control any CyberCertPrinter
        imFactory.upgradePrinterBeaconAt(imAddr, address(new RugCyberCertPrinter()));

        // Burn certificate at will
        CyberCertPrinter(cyberCertPrinterAddrs[0]).burn(certIds[0]);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, certIds[0]));
        CyberCertPrinter(cyberCertPrinterAddrs[0]).ownerOf(certIds[0]);
    }

    /// @dev TODO WIP: this is supposed to revert
    function test_RevertIf_RugCyberScrip() public {
        // Finalize the deal so certificate is transferred to alice
        DealManager(dmAddr).finalizeDeal(agreementId);

        // CyberCorpFactory does not utilize CyberScrip yet, so we will simulate it here

        CyberScrip cyberScrip = CyberScrip(
            IssuanceManager(imAddr)
                .deployCyberScrip(
                    cyberCertPrinterAddrs[0], // certAddress
                    new ITransferRestrictionHook[](0), // typeRestrictionHooks
                    new ICondition[](0), // certToScripConditions
                    new ICondition[](0) // scripToCertConditions
                )
        );

        assertEq(cyberScrip.IssuanceManager(), imAddr);

        vm.startPrank(metalex);

        // IssuanceManagerFactory can unilaterally control any CyberScrip
        // TODO WIP: IssuanceManager hasn't implemented it yet
        imFactory.upgradeScripBeaconAt(imAddr, address(new RugCyberScrip()));

        // Mint token at will
        RugCyberScrip(address(cyberScrip)).mint(metalex, 100 ether);

        vm.stopPrank();

        assertEq(cyberScrip.balanceOf(metalex), 100 ether);
    }
}
