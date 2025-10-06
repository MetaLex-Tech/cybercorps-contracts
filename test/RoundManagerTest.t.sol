// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RoundManager.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberCertPrinter.sol";
import "../src/storage/RoundManagerStorage.sol";
import "../src/CyberCorpConstants.sol";
import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../dependencies/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {LexChexDetails} from "../src/storage/RoundManagerStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";

// Import necessary types
using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 2000000 * 10 ** 6); // Mint 2M tokens with 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockRoundManagerV2 is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "2";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

// Mock condition that always fails
contract AlwaysFalseCondition is ICondition {
    function checkCondition(
        address,
        bytes4,
        bytes memory
    ) external pure returns (bool) {
        return false;
    }
}

// Mock condition that always pass
contract AlwaysTrueCondition is ICondition {
    function checkCondition(
        address,
        bytes4,
        bytes memory
    ) external pure returns (bool) {
        return true;
    }
}

library CyberCorpHelper {
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // EIP-712 constants for RoundManager escrow signature
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    address constant LEXCHEX_CONDITION_ADDRESS = 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42;
    address constant LEXCHEX_MINTER_ADDRESS = 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960;
    address constant UPGRADE_OWNER = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;

    bytes32 constant SALT = keccak256("CyberCorpHelper");

    bytes32 constant TEMPLATE_ID = bytes32(uint256(777));

    function mockLexChexCondition(bool isPass) internal {
        // Mock LexChexCondition to always pass
        vm.etch(
            LEXCHEX_CONDITION_ADDRESS,
            (isPass)
                ? address(new AlwaysTrueCondition()).code
                : address(new AlwaysFalseCondition()).code
        );
    }

    // Infra helpers copied from above
    function deployRegistryAndFactories(address owner) internal returns (
        CyberAgreementRegistry registry,
        CyberCorpFactory corpFactory,
        address issuanceManagerFactory,
        address cyberCorpSingleFactory,
        address dealManagerFactory,
        address roundManagerFactory,
        address uriBuilder
    ) {
        BorgAuth bootstrapAuth = new BorgAuth{salt: SALT}(owner);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new CyberAgreementRegistry{salt: SALT}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(bootstrapAuth)
                    )
                )
            )
        );

        uriBuilder = address(
            new ERC1967Proxy{salt: SALT}(
                address(new CertificateUriBuilder{salt: SALT}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(bootstrapAuth)
                )
            )
        );

        issuanceManagerFactory = address(
            new IssuanceManagerFactory{salt: SALT}(address(bootstrapAuth))
        );
        cyberCorpSingleFactory = address(
            new CyberCorpSingleFactory{salt: SALT}(address(bootstrapAuth))
        );
        dealManagerFactory = address(
            new ERC1967Proxy{salt: SALT}(
                address(new DealManagerFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    DealManagerFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(new DealManager())
                )
            )
        );

        roundManagerFactory = address(
            new ERC1967Proxy{salt: SALT}(
                address(new RoundManagerFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(new RoundManager())
                )
            )
        );

        address certPrinterImpl = address(new CyberCertPrinter{salt: SALT}());
        address cyberScripImpl = address(new CyberScrip{salt: SALT}());

        corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new CyberCorpFactory{salt: SALT}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(bootstrapAuth),
                        address(registry),
                        certPrinterImpl,
                        cyberScripImpl,
                        issuanceManagerFactory,
                        cyberCorpSingleFactory,
                        dealManagerFactory,
                        roundManagerFactory,
                        uriBuilder
                    )
                )
            )
        );

        // Perform an upgrade of the existing UUPS proxy at the known address
        address lexchexMinterUpgraded = address(new LeXcheXMinter());
        vm.prank(UPGRADE_OWNER);
        IUUPS(LEXCHEX_MINTER_ADDRESS).upgradeToAndCall(lexchexMinterUpgraded, "");

        // Ensure CyberCorpFactory is OWNER of lexchexAuth
        address lxAuth = corpFactory.lexchexAuth();
        vm.startPrank(UPGRADE_OWNER);
        BorgAuth(lxAuth).updateRole(address(corpFactory), BorgAuth(lxAuth).OWNER_ROLE());
        vm.stopPrank();
    }

    function createTemplate(CyberAgreementRegistry registry) internal {
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](2);
        partyFields[0] = "Officer Name";
        partyFields[1] = "Officer Title";
        registry.createTemplate(
            TEMPLATE_ID,
            "Test",
            "ipfs://template",
            globalFields,
            partyFields
        );
    }

    function deployCorp(
        CyberCorpFactory corpFactory,
        string memory companyName,
        address companyPayable,
        address officerEOA
    )
        internal
        returns (
            address corp,
            address auth,
            address issuance,
            address dealManager,
            address roundManager
        )
    {
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: officerEOA,
            name: "Officer",
            contact: "officer@example.com",
            title: "CEO"
        });

        (corp, auth, issuance, dealManager, roundManager) = corpFactory.deployCyberCorp(
            SALT,
            companyName,
            "corporation",
            "DE",
            "contact",
            "arbitration",
            companyPayable,
            officer
        );
    }

    function createRound(
        RoundManager rm,
        address paymentToken,
        uint8 payDec,
        bytes32 templateId,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType rountType,
        address officerEOA,
        uint256 officerPrivKey,
        address companyAddress
    ) internal returns (bytes32) {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[]
        memory certData = new RoundManager.CyberCertData[](1);
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            address(rm),
            SecuritySeries.SeriesSeed,
            raiseCap,
            minTicket,
            maxTicket,
            rountType,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            paymentToken,
            10 * (10 ** payDec),
            10_000_000,
            officerPrivKey,
            companyAddress
        );

        return rm.createRound(
            SecuritySeries.SeriesSeed,
            raiseCap,
            minTicket,
            maxTicket,
            rountType,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            certData,
            new address[](0),
            paymentToken,
            10 * (10 ** payDec),
            10_000_000,
            officerEOA,
            "Officer",
            "CEO",
            "",
            "",
            roundPartyValues,
            escrowedSig,
            true
        );
    }

    function submitEOIAndAssertFinalized(
        RoundManager rm,
        CyberAgreementRegistry registry,
        bytes32 templateId,
        address paymentToken,
        uint8 payDec,
        bytes32 roundId,
        address officerEOA
    ) internal {
        uint256 salt = 1;
        uint256 privKey = 0xA11CE;
        address investor = vm.addr(privKey);
        ERC20(payable(paymentToken)).transfer(investor, 20_000 * (10 ** payDec));
        vm.startPrank(investor);
        ERC20(payable(paymentToken)).approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 5_000 * (10 ** payDec),
            maxAmount: 10_000 * (10 ** payDec),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            templateId,
            salt,
            glValues,
            pv,
            officerEOA,
            privKey
        );

        (bytes32 agreementId, ) = rm.submitEOI(
            roundId,
            eoi,
            glValues,
            pv,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Escrow memory esc = rm.getEscrowDetails(agreementId);
        vm.assertEq(uint256(esc.status), uint256(EscrowStatus.FINALIZED));
        vm.assertGt(esc.corpAssets.length, 0);
    }

    function computeRoundId(
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId_,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        address companyAddress
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                seriesType,
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId_,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );
    }

    function computeEscrowSignature(
        address roundManager,
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId_,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        uint256 signerPrivKey,
        address companyAddress
    ) internal view returns (bytes memory sig, bytes32 roundId) {
        roundId = CyberCorpHelper.computeRoundId(
            seriesType,
            raiseCap,
            minTicket,
            maxTicket,
            roundType,
            startTime,
            endTime,
            templateId_,
            paymentToken,
            pricePerUnit,
            valuation,
            companyAddress
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("RoundManager")),
                keccak256(bytes("1")),
                block.chainid,
                roundManager
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                ESCROWEDSIGNATUREDATA_TYPEHASH,
                roundId,
                uint8(seriesType),
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId_,
                paymentToken,
                pricePerUnit,
                valuation,
                companyAddress
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivKey, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function computeEOISignature(
        CyberAgreementRegistry registry,
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        string[] memory partyValues,
        address authorityOfficer,
        uint256 signerPrivKey
    ) internal view returns (bytes memory) {
        (
            string memory legalUri,
            ,
            string[] memory glFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        address signer = vm.addr(signerPrivKey);
        address[] memory parties = new address[](2);
        parties[0] = authorityOfficer;
        parties[1] = signer;
        bytes32 contractId = keccak256(
            abi.encode(templateId, salt, globalValues, parties)
        );
        return
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                contractId,
                legalUri,
                glFields,
                partyFields,
                globalValues,
                partyValues,
                signerPrivKey
            );
    }

    function emptyLex() internal pure returns (LexChexDetails memory) {
        return LexChexDetails({
            request: MintRequest({
            uuid: 0,
            owner: address(0),
            investorName: "",
            investorType: "",
            investorJurisdiction: "",
            investorContact: "",
            mintPrice: 0,
            expiry: 0,
            paymentToken: address(0)
        }),
            templateId: bytes32(0),
            salt: 0,
            globalValues: new string[](0),
            parties: new address[](0),
            partyValues: new string[][](0),
            agreementSignature: ""
        });
    }
}

contract RoundManagerTest is Test {
   // RoundManager public roundManager;
    IssuanceManager public issuanceManager;
    CyberCertPrinter public certPrinter;
    MockPaymentToken public paymentToken;

    address public owner;
    uint256 private ownerPrivKey;
    address public investor;
    uint256 private investorPrivKey;
    address public investor2;
    uint256 private investor2PrivKey;
    address public corpOwner;
    uint256 private corpOwnerPrivKey;

    // Infra
    CyberAgreementRegistry private registry;
    CyberCorpFactory private corpFactory;
    address private corp;
    address private auth;
    address private issuance;
    address private dealManager;
    address private roundManager;
    address private uriBuilder;
    address private rmFactory;
    string[] private testRoundPartyValues;
    // EIP-712 constants for RoundManager escrow signature
    bytes32 constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

    // Captured round id
    bytes32 public roundId;

    // Test round parameters
    uint256 public constant MIN_TICKET = 1000 * 10 ** 6; // 1,000 USDC
    uint256 public constant MAX_TICKET = 100000 * 10 ** 6; // 100,000 USDC
    uint256 public constant RAISE_CAP = 1000000 * 10 ** 6; // 1M USDC
    uint256 public constant PRICE_PER_UNIT = 10 * 10 ** 6; // 10 USDC per unit
    uint256 public constant VALUATION = 10000000; // $10M valuation

    function setUp() public {
        // Configs

        testRoundPartyValues = new string[](2);
        testRoundPartyValues[0] = "Officer";
        testRoundPartyValues[1] = "CEO";

        CyberCorpHelper.mockLexChexCondition(true);

        ownerPrivKey = 0xA0A0;
        owner = vm.addr(ownerPrivKey);
        investorPrivKey = 0xA11CE;
        investor = vm.addr(investorPrivKey);
        investor2PrivKey = 0xB0B;
        investor2 = vm.addr(investor2PrivKey);
        corpOwnerPrivKey = 0xCAD;
        corpOwner = vm.addr(corpOwnerPrivKey);

        // Deploy

        // Deploy mock payment token
        paymentToken = new MockPaymentToken();

        address issuanceManagerFactory;
        address cyberCorpSingleFactory;
        address dealManagerFactory;
        address uriBuilder;
        (
            registry,
            corpFactory,
            issuanceManagerFactory,
            cyberCorpSingleFactory,
            dealManagerFactory,
            rmFactory,
            uriBuilder
        ) = CyberCorpHelper.deployRegistryAndFactories(owner);

        vm.startPrank(owner);

        CyberCorpHelper.createTemplate(registry);

        // Set platform fee
        RoundManagerFactory(rmFactory).setPlatformPayable(owner);
        RoundManagerFactory(rmFactory).setDefaultFeeRatio(25);

        vm.stopPrank();

        (corp, auth, issuance, dealManager, roundManager) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Test Corp",
            corpOwner,
            corpOwner
        );

        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            paymentToken.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            corpOwner,
            corpOwnerPrivKey,
            corp
        );
        vm.stopPrank();

        // Fund investor
        paymentToken.transfer(investor, 1000000 * 10 ** 6);
        vm.prank(investor);
        paymentToken.approve(address(roundManager), type(uint256).max);
    }

    function test_RevertIf_CreateRound_InvalidSignature() public {
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Test Certificate",
            symbol: "TEST",
            uri: "https://test.uri",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        (bytes memory signature, ) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesA,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            investor2PrivKey, // wrong signer key
            corp
        );

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        RoundManager(roundManager).createRound(
            SecuritySeries.SeriesA,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            certData,
            new address[](0),
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwner,
            "Officer",
            "CEO",
            "",
            "",
            testRoundPartyValues,
            signature,
            false
        );
    }

    function test_SubmitEOI_Success() public {
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6, // 5,000 USDC
            maxAmount: 10000 * 10 ** 6, // 10,000 USDC
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value";

        string[] memory partyValues = new string[](2);
        partyValues[0] = "Party Value 1";
        partyValues[1] = "Party Value 2";

        uint256 salt = 1;
        bytes memory signature = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            corpOwner,
            investorPrivKey
        );
        address[] memory conditions = new address[](0);
        bytes32 secretHash = bytes32(0);
        uint256 expiry = block.timestamp + 7 days;
        bytes memory voidSignature = "0x";

        // Verify EOI was stored correctly by checking the EOISubmitted event
        address[] memory parties = new address[](2);
        parties[0] = corpOwner;
        parties[1] = investor;
        vm.expectEmit(true, true, true, true);
        emit RoundManager.EOISubmitted(
            keccak256(abi.encode(CyberCorpHelper.TEMPLATE_ID, salt, globalValues, parties)),
            roundId,
            investor,
            corp,
            eoi.minAmount,
            eoi.maxAmount,
            eoi.expiry
        );
        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            signature,
            salt,
            conditions,
            secretHash
        );

        assertTrue(
            agreementId != bytes32(0),
            "Agreement ID should not be zero"
        );

        vm.stopPrank();
    }

    function test_SubmitEOI_InvalidAmount() public {
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 100 * 10 ** 6, // Below MIN_TICKET
            maxAmount: 1000000 * 10 ** 6, // Above MAX_TICKET
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        string[] memory partyValues = new string[](1);


        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            1,
            globalValues,
            partyValues,
            owner,
            investorPrivKey
        );

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
        RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();
    }

    function test_Allocate_Success() public {
        // First submit an EOI
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()

        });

        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                1,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();

        // Now allocate as owner
        uint256 allocatedAmount = 7500 * 10 ** 6; // 7,500 USDC

        vm.expectEmit(true, true, true, true);
        emit RoundManager.AllocationMade(agreementId, roundId, investor, allocatedAmount, allocatedAmount, new uint256[](1));
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, allocatedAmount);

        // Verify allocation by checking if the round exists and getting its price info
        assertTrue(RoundManager(roundManager).roundExists(roundId), "Round should exist");

        // We can verify the allocation was successful by checking if an AllocationMade event was emitted

        uint256[] memory expectedCertIds = new uint256[](1);
        expectedCertIds[0] = 0; // First certificate ID


        // Verify certificate was created
        // Note: In a real test you'd need to properly mock the CertPrinter and verify its state
    }

    function test_Allocate_InvalidAmount() public {
        // Submit EOI first
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                1,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();

        // Try to allocate an amount below min
        uint256 invalidAmount = 1000 * 10 ** 6; // Below eoi.minAmount

        vm.prank(corpOwner);
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        RoundManager(roundManager).allocate(agreementId, invalidAmount);
    }

    function test_Allocate_ExceedsRaiseCap() public {
        // Submit EOI first
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: RAISE_CAP + 1, // Just over the raise cap
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        // Expect revert because eoi.maxAmount exceeds round.maxTicket bounds
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            1,
            new string[](1),
            new string[](2),
            corpOwner,
            investorPrivKey
        );
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
        RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            sig,
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();
    }

    function test_SubmitEOI_RoundClosed() public {
        // Fast forward past round end time
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.RoundNotOpen.selector)
        );

        RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            "0x",
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();
    }

    function test_MultipleAllocations_RespectRaiseCap() public {
        // Create a dedicated round with higher maxTicket to fit 600k EOIs
        RoundManager.CyberCertData[] memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        bytes32 roundIdLarge;
        (bytes memory escSigLarge, bytes32 expectedRoundIdLarge) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesPreSeed,
            1_000_000 * 10 ** 6,
            1_000 * 10 ** 6,
            1_000_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwnerPrivKey,
            corp
        );
        vm.prank(corpOwner);
        roundIdLarge = RoundManager(roundManager).createRound(
            SecuritySeries.SeriesPreSeed,
            1_000_000 * 10 ** 6, // raise cap 1M
            1_000 * 10 ** 6,
            1_000_000 * 10 ** 6, // maxTicket large enough
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            certData,
            new address[](0),
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwner,
            "Officer",
            "CEO",
            "",
            "",
            testRoundPartyValues,
            escSigLarge,
            false
        );
        assertEq(roundIdLarge, expectedRoundIdLarge);

        // Submit first EOI
        vm.startPrank(investor);
        EOI memory eoi1 = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor1@example.com",
            minAmount: 400000 * 10 ** 6, // 400k USDC
            maxAmount: 600000 * 10 ** 6, // 600k USDC
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        (bytes32 agreementId1, ) = RoundManager(roundManager).submitEOI(
            roundIdLarge,
            eoi1,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                1,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Submit second EOI from different investor
        paymentToken.transfer(investor2, 1000000 * 10 ** 6);
        vm.startPrank(investor2);
        paymentToken.approve(address(roundManager), type(uint256).max);

        EOI memory eoi2 = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "investor2@example.com",
            minAmount: 400000 * 10 ** 6, // 400k USDC
            maxAmount: 600000 * 10 ** 6, // 600k USDC
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        (bytes32 agreementId2, ) = RoundManager(roundManager).submitEOI(
            roundIdLarge,
            eoi2,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                2,
                new string[](1),
                new string[](2),
                corpOwner,
                investor2PrivKey
            ),
            2,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Allocate to first investor
        vm.startPrank(corpOwner);
        RoundManager(roundManager).allocate(agreementId1, 500000 * 10 ** 6); // 500k USDC

        // Try to allocate remaining to second investor
        RoundManager(roundManager).allocate(agreementId2, 500000 * 10 ** 6); // 500k USDC

        // When total raised equals raise cap, no more allocations should be possible
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        RoundManager(roundManager).allocate(agreementId2, 1); // Try to allocate 1 more token, should fail
        vm.stopPrank();
    }

    function test_Allocate_IgnoreVoidRequest() public {
        // Submit EOI
        vm.startPrank(investor);

        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: 5000 * 10 ** 6,
            maxAmount: 10000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        (bytes32 agreementId, uint256 tokenId) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                1,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            1,
            new address[](0),
            bytes32(0)
        );

        vm.stopPrank();

        // Simulate deal being voided externally through the registry.
        // This will not void the EOI and the owner should still be able to fill it.
        registry.voidContractFor(
            agreementId,
            investor,
            CyberAgreementUtils.signVoidAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.VOIDSIGNATUREDATA_TYPEHASH(),
                agreementId,
                investor,
                investorPrivKey
            )
        );

        // Verify the owner can fill the EOI
        uint256 balBeforeAllocate = paymentToken.balanceOf(corpOwner);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, 5_000 * 10 ** 6);

        uint256 balAfterAllocate = paymentToken.balanceOf(corpOwner);
        // 5000 * (1 - 0.25%) = 4987.5
        assertEq(balAfterAllocate - balBeforeAllocate, 4987.5 * 10 ** 6);
    }

    function test_RejectEOI_RefundsAndVoids() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Reject Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, uint256 tokenId) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                3,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        Escrow memory escBefore = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Reject as corp owner -> refund and void
        vm.prank(corpOwner);
        RoundManager(roundManager).reject(agreementId);
        Escrow memory escAfter = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor), balBefore);
    }

    function test_RejectEOI_RefundsVoidedDeal() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Reject Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                3,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        Escrow memory escBefore = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Simulate deal being voided externally through the registry
        registry.voidContractFor(
            agreementId,
            investor,
            CyberAgreementUtils.signVoidAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.VOIDSIGNATUREDATA_TYPEHASH(),
                agreementId,
                investor,
                investorPrivKey
            )
        );

        // Corp owner can no longer call `reject()` because it would try to void the agreement again
        vm.prank(corpOwner);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyVoided.selector);
        RoundManager(roundManager).reject(agreementId);

        // Instead, he could choose to skip voiding the agreement
        vm.prank(corpOwner);
        RoundManager(roundManager).reject(agreementId, false);
        Escrow memory escAfter = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor), balBefore);
    }

    function test_RecallEOI_RefundsAndVoids() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Recall Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                3,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        Escrow memory escBefore = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Simulate pass both EOI expiry and Round end time
        vm.warp(block.timestamp + 30 days);

        // Recall as investor after expiry -> refund and void
        vm.prank(investor);
        RoundManager(roundManager).recallEOI(agreementId);
        Escrow memory escAfter = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor), balBefore);
    }

    function test_RecallEOI_RefundsVoidedDeal() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Recall Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                3,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        Escrow memory escBefore = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Simulate pass both EOI expiry and Round end time
        vm.warp(block.timestamp + 30 days);

        // Simulate deal being voided externally through the registry
        registry.voidContractFor(
            agreementId,
            investor,
            CyberAgreementUtils.signVoidAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.VOIDSIGNATUREDATA_TYPEHASH(),
                agreementId,
                investor,
                investorPrivKey
            )
        );

        // Investor can no longer call `recall()` because it would try to void the agreement again
        vm.prank(investor);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyVoided.selector);
        RoundManager(roundManager).recallEOI(agreementId);

        // Instead, he could choose to skip voiding the agreement
        vm.prank(investor);
        RoundManager(roundManager).recallEOI(agreementId, false);
        Escrow memory escAfter = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escAfter.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor), balBefore);
    }

    function test_RevertIf_RecallEOI_NotExpired() public {
        // Submit EOI
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Recall Me",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "reject@example.com",
            minAmount: 2_000 * 10 ** 6,
            maxAmount: 5_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, uint256 tokenId) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                3,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            3,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        Escrow memory escBefore = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escBefore.status), uint256(EscrowStatus.PAID));

        // Immediate recall should fail as the EOI isn't expired
        vm.prank(investor);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        RoundManager(roundManager).recallEOI(agreementId);
    }

    function test_Allocate_WithFailingCondition_Reverts() public {
        // Deploy failing condition
        AlwaysFalseCondition cond = new AlwaysFalseCondition();

        // Submit EOI with condition attached
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Fail Cond",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "cond@example.com",
            minAmount: 5_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        address[] memory conditions = new address[](1);
        conditions[0] = address(cond);
        (bytes32 agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                4,
                new string[](1),
                new string[](2),
                corpOwner,
                investorPrivKey
            ),
            4,
            conditions,
            bytes32(0)
        );
        vm.stopPrank();

        // Attempt allocation -> should revert due to AgreementConditionsNotMet
        vm.prank(corpOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RoundManager.AgreementConditionsNotMet.selector
            )
        );
        RoundManager(roundManager).allocate(agreementId, 10_000 * 10 ** 6);
    }

    function test_SubmitEOI_BeforeStart_Reverts() public {
        // Create a new round with future start
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });
        bytes32 roundIdFuture;
        // Compute escrowed signature for the future round
        (bytes memory escSigFuture, ) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesF,
            100_000 * 10 ** 6,
            1_000 * 10 ** 6,
            50_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwnerPrivKey,
            corp
        );
        vm.prank(corpOwner);
        roundIdFuture = RoundManager(roundManager).createRound(
            SecuritySeries.SeriesF,
            100_000 * 10 ** 6,
            1_000 * 10 ** 6,
            50_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            certData,
            new address[](0),
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwner,
            "Officer",
            "CEO",
            "",
            "",
            testRoundPartyValues,
            escSigFuture,
            false
        );

        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Z",
            investorType: "I",
            jurisdiction: "US",
            contact: "z@z",
            minAmount: 1_000 * 10 ** 6,
            maxAmount: 2_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        //compute signature
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            6,
            new string[](1),
            new string[](2),
            corpOwner,
            investorPrivKey
        );
         vm.expectRevert(
            abi.encodeWithSelector(RoundManager.RoundNotOpen.selector)
        );
        RoundManager(roundManager).submitEOI(
            roundIdFuture,
            eoi,
            new string[](1),
            new string[](2),
            sig,
            6,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function test_IssuanceManagerGetter_ReturnsConfigured() public {
        assertEq(address(RoundManager(roundManager).issuanceManager()), issuance);
    }

    function test_RoundExists_FalseForUnknown() public {
        bytes32 unknownId = keccak256("unknown");
        assertFalse(RoundManager(roundManager).roundExists(unknownId));
    }

    function test_SubmitEOI_InvalidRound_Reverts() public {
        bytes32 unknownId = keccak256("unknown");
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "X",
            investorType: "I",
            jurisdiction: "US",
            contact: "x@x",
            minAmount: 5_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        string[] memory gl = new string[](1);
        string[] memory pv = new string[](2);
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            9,
            gl,
            pv,
            corpOwner,
            investorPrivKey
        );
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidRound.selector)
        );
        RoundManager(roundManager).submitEOI(
            unknownId,
            eoi,
            gl,
            pv,
            sig,
            9,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function test_FounderApproved_RefundsExcess_WhenRemainingBelowEscrow()
        public
    {
        // Create a new round with small raise cap so remaining < escrowed amount
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        bytes32 roundId2;
        (bytes memory escrowSig2, bytes32 expectedRoundId2) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesPreSeed,
            6_000 * 10 ** 6,
            1_000 * 10 ** 6,
            100_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwnerPrivKey,
            corp
        );
        vm.prank(corpOwner);
        roundId2 = RoundManager(roundManager).createRound(
            SecuritySeries.SeriesPreSeed,
            6_000 * 10 ** 6, // small cap
            1_000 * 10 ** 6,
            100_000 * 10 ** 6,
            RoundType.FounderApproved,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            certData,
            new address[](0),
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            corpOwner,
            "Officer",
            "CEO",
            "",
            "",
            testRoundPartyValues,
            escrowSig2,
            false
        );
        assertEq(roundId2, expectedRoundId2);

        // Investor submits EOI for 10,000 USDC, escrow pulls funds
        vm.startPrank(investor);
        EOI memory eoi = EOI({
            name: "Y",
            investorType: "I",
            jurisdiction: "US",
            contact: "y@y",
            minAmount: 1_000 * 10 ** 6,
            maxAmount: 10_000 * 10 ** 6,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        string[] memory gl = new string[](1);
        string[] memory pv = new string[](2);
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            5,
            gl,
            pv,
            corpOwner,
            investorPrivKey
        );
        uint256 balBefore = paymentToken.balanceOf(investor);
        (bytes32 agreementId, uint256 tokenId) = RoundManager(roundManager).submitEOI(
            roundId2,
            eoi,
            gl,
            pv,
            sig,
            5,
            new address[](0),
            bytes32(0)
        );
        uint256 balAfterSubmit = paymentToken.balanceOf(investor);
        assertEq(balBefore - balAfterSubmit, 10_000 * 10 ** 6);
        vm.stopPrank();

        // Allocate as owner: candidate will be remaining (6,000 USDC), refund 4,000 USDC
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, type(uint256).max);

        uint256 balAfterAllocate = paymentToken.balanceOf(investor);
        assertEq(balAfterAllocate - balAfterSubmit, 4_000 * 10 ** 6);
    }

    function test_UpgradeNextRoundManager() public {
        assertEq(RoundManager(RoundManagerFactory(rmFactory).getRefImplementation()).DEPLOY_VERSION(), "1", "reference impl version should not be changed yet");

        vm.startPrank(owner);
        RoundManagerFactory(rmFactory).setRefImplementation(address(new MockRoundManagerV2()));
        vm.stopPrank();
        assertEq(RoundManager(RoundManagerFactory(rmFactory).getRefImplementation()).DEPLOY_VERSION(), "2", "reference impl version should have changed");

        bytes32 salt = keccak256("test_UpgradeNextRounderManager");
        // Next deployment should emit events with version so indexer could be informed
        vm.expectEmit(true, true, true, true);
        emit RoundManagerFactory.RoundManagerDeployed(
            RoundManagerFactory(rmFactory).computeRoundManagerAddress(salt),
            "2"
        );
        RoundManager nextRm = RoundManager(
            RoundManagerFactory(rmFactory).deployRoundManager(salt)
        );
        assertEq(nextRm.DEPLOY_VERSION(), "2", "next deployment version should have changed");
    }

    function test_UpgradeExistingRoundManager() public {
        BorgAuth corpAuth = new BorgAuth{salt: keccak256("testUpgradeExistingRoundManager")}(corpOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        // Deploy existing RoundManagers

        RoundManager rm1 = RoundManager(
            RoundManagerFactory(rmFactory).deployRoundManager(keccak256("testUpgradeExistingRoundManager1"))
        );
        rm1.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            rmFactory
        );

        RoundManager rm2 = RoundManager(
            RoundManagerFactory(rmFactory).deployRoundManager(keccak256("testUpgradeExistingRoundManager2"))
        );
        rm2.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            rmFactory
        );

        // MetaLeX to release new RoundManager v2

        vm.startPrank(owner);
        RoundManagerFactory(rmFactory).setRefImplementation(address(new MockRoundManagerV2()));
        vm.stopPrank();

        // Corp2 owner decided to accept the upgrade

        vm.startPrank(corpOwner);
        rm2.upgradeToAndCall(address(RoundManagerFactory(rmFactory).getRefImplementation()), "");
        vm.stopPrank();

        assertEq(rm2.DEPLOY_VERSION(), "2", "Target RoundManager should be upgraded");
        assertEq(rm1.DEPLOY_VERSION(), "1", "Other RoundManager should not be upgraded");
    }

    function test_RevertIf_UpgradeNonFactoryOwner() public {
        // Non-MetaLeX admin should not be able to set new reference implementation

        address newImplementation = address(new MockRoundManagerV2());
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, BorgAuth(auth).OWNER_ROLE(), corpOwner));
        vm.prank(corpOwner);
        RoundManagerFactory(rmFactory).setRefImplementation(newImplementation);
    }

    function test_RevertIf_UpgradeExistingRoundManagerNotRefImplementation() public {
        BorgAuth corpAuth = new BorgAuth{salt: keccak256("testUpgradeExistingRoundManager")}(corpOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        // Deploy existing RoundManagers

        RoundManager rm = RoundManager(
            RoundManagerFactory(rmFactory).deployRoundManager(keccak256("testUpgradeExistingRoundManager2"))
        );
        rm.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            rmFactory
        );

        // Corp owner can't upgrade to v2 without MetaLeX releasing it first

        vm.startPrank(corpOwner);
        address nonOfficialRoundManager = address(new MockRoundManagerV2());
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.NotRefImplementation.selector)
        );
        rm.upgradeToAndCall(nonOfficialRoundManager, "");
        vm.stopPrank();
    }
}

// Separate FCFS tests in their own contract to avoid the original setUp()
contract RoundManagerFCFSTest is Test {
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

    function setUp() public {
        CyberCorpHelper.mockLexChexCondition(true);
    }

    function test_UpgradeSteps_RMFactory_CorpFactory_CorpBeacon() public {
        address me = address(this);
        (
            ,
            CyberCorpFactory corpFactory,
            ,
            address cyberCorpSingleFactory,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);

        address auth = address(corpFactory.AUTH());
        RoundManagerFactory rmFactory = RoundManagerFactory(address(
            new ERC1967Proxy(
                address(new RoundManagerFactory()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(auth),
                    address(new RoundManager())
                )
            )
        ));
        rmFactory.setRefImplementation(address(new RoundManager()));

        IUUPS(address(corpFactory)).upgradeToAndCall(address(new CyberCorpFactory()), "");

        corpFactory.setRoundManagerFactory(address(rmFactory));
        assertEq(corpFactory.roundManagerFactory(), address(rmFactory));

        CyberCorpSingleFactory(cyberCorpSingleFactory).upgradeImplementation(address(new CyberCorp()));
        assertTrue(CyberCorpSingleFactory(cyberCorpSingleFactory).getBeaconImplementation() != address(0));
    }

    function test_UpgradedInfra_FCFS_AutoAllocates() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            address cyberCorpSingleFactory,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        // Apply upgrades
        RoundManagerFactory rmFactory = RoundManagerFactory(address(
            new ERC1967Proxy(
                address(new RoundManagerFactory()),
                abi.encodeWithSelector(
                    RoundManagerFactory.initialize.selector,
                    address(corpFactory.AUTH()),
                    address(new RoundManager())
                )
            )
        ));
        rmFactory.setRefImplementation(address(new RoundManager()));
        IUUPS(address(corpFactory)).upgradeToAndCall(address(new CyberCorpFactory()), "");
        corpFactory.setRoundManagerFactory(address(rmFactory));
        CyberCorpSingleFactory(cyberCorpSingleFactory).upgradeImplementation(address(new CyberCorp()));

        // Deploy upgraded corp and round manager
        (address corp, , , , address roundManager) = CyberCorpHelper.deployCorp(corpFactory, "Upgraded Corp", me, me);
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(roundManager));

        RoundManager rm = RoundManager(payable(roundManager));
        MockPaymentToken usdc = new MockPaymentToken();

        // Create round via helper to minimize local stack usage
        vm.prank(address(corpFactory));
        uint256 officerPrivKey = 0xA0A5;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        CyberCorpHelper.submitEOIAndAssertFinalized(
            rm,
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            address(usdc),
            usdc.decimals(),
            roundId,
            officerEOA
        );
    }

    function test_FCFS_CreateRound_RequiresEscrowSignature() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);

        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp A",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        RoundManager.CyberCertData[]
            memory certData = new RoundManager.CyberCertData[](1);
        certData[0] = RoundManager.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });
        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Officer";
        roundPartyValues[1] = "CEO";

        // Provide a valid escrow signature now that RoundManager enforces it
        uint256 officerPrivKey = 0xAA01;
        address officerEOA = vm.addr(officerPrivKey);
        (bytes memory escSig, ) = CyberCorpHelper.computeEscrowSignature(
            address(rm),
            SecuritySeries.SeriesPreSeed,
            1,
            1,
            1,
            RoundType.FCFS,
            block.timestamp,
            block.timestamp + 1,
            CyberCorpHelper.TEMPLATE_ID,
            address(0xDEAD),
            1,
            1,
            officerPrivKey,
            corp
        );
        rm.createRound(
            SecuritySeries.SeriesPreSeed,
            1,
            1,
            1,
            RoundType.FCFS,
            block.timestamp,
            block.timestamp + 1,
            CyberCorpHelper.TEMPLATE_ID,
            certData,
            new address[](0),
            address(0xDEAD),
            1,
            1,
            officerEOA,
            "Officer",
            "CEO",
            "",
            "",
            roundPartyValues,
            escSig,
            true
        );
    }

    function test_FCFS_SubmitEOI_AutoAllocates_FinalizesAndMints() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp B",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        uint256 officerPrivKey = 0xAA04;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        uint256 salt = 1;
        uint256 privKey = 0xA11CE;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 20_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        uint256 meUsdcBalanceBefore = usdc.balanceOf(me);

        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 5_000 * (10 ** usdc.decimals()),
            maxAmount: 10_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officerEOA,
            privKey
        );

        (bytes32 agreementId, ) = rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        Escrow memory esc = rm.getEscrowDetails(agreementId);
        assertEq(uint256(esc.status), uint256(EscrowStatus.FINALIZED));
        assertGt(esc.corpAssets.length, 0);
        assertEq(usdc.balanceOf(me) - meUsdcBalanceBefore, 10_000 * (10 ** usdc.decimals()), "Investor should have paid maximum ticket size");
        Token memory corpToken = esc.corpAssets[0];
        assertEq(CyberCertPrinter(corpToken.tokenAddress).ownerOf(corpToken.tokenId), investor, "Investor should have received equity");
    }

    function test_FCFS_RefundsExcessPayment() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp C",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        // Simulate a round where `maxTicket` > `raiseCap` so an investor could deposit more than remaining
        // and trigger a refund

        MockPaymentToken usdc = new MockPaymentToken();
        uint256 officerPrivKey = 0xAA02;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            50_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            80_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        uint256 salt = 1;
        uint256 privKey = 0xB0B;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 80_000 * (10 ** usdc.decimals()));
        uint256 startBal = usdc.balanceOf(investor);
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 2",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 10_000 * (10 ** usdc.decimals()),
            maxAmount: 80_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officerEOA,
            privKey
        );

        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Investor deposited 80k at the beginning, but later got refunded the 30k difference from remaining cap
        uint256 endBal = usdc.balanceOf(investor);
        assertEq(startBal - endBal, 50_000 * (10 ** usdc.decimals()), "Investor should have paid exactly raise cap");
    }

    function test_FCFS_SubmitEOI_InvalidAmount_Reverts() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp D",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);
        MockPaymentToken usdc = new MockPaymentToken();
        uint256 officerPrivKey = 0xAA03;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            1_000 * (10 ** usdc.decimals()),
            100_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        address investor = address(0x333);
        usdc.transfer(investor, 5_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "Investor 3",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 100,
            maxAmount: 500,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            hex"01",
            1,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }

    function test_FCFS_SubmitEOI_RemainingBelowMin_RevertsAndNoFundsPulled()
        public
    {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp E",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));
        MockPaymentToken usdc = new MockPaymentToken();

        uint256 officerPrivKey = 0xA0A5;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            1_500 * (10 ** usdc.decimals()),
            1_500 * (10 ** usdc.decimals()),
            100_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        uint256 salt1 = 1;
        uint256 privKey1 = 0xC01;
        address inv1 = vm.addr(privKey1);
        usdc.transfer(inv1, 100_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv1);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi1 = EOI({
            name: "A",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 1_000 * (10 ** usdc.decimals()),
            maxAmount: 2_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";
        bytes memory sig1 = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt1,
            globalValues,
            partyValues,
            officerEOA,
            privKey1
        );
                vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAmount.selector)
        );
        rm.submitEOI(
            roundId,
            eoi1,
            globalValues,
            partyValues,
            sig1,
            salt1,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        uint256 salt2 = 2;
        uint256 privKey2 = 0xD02;
        address inv2 = vm.addr(privKey2);
        uint256 startBal = usdc.balanceOf(inv2);
        usdc.transfer(inv2, 2_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv2);
        usdc.approve(address(rm), type(uint256).max);
        EOI memory eoi2 = EOI({
            name: "B",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 2_000 * (10 ** usdc.decimals()),
            maxAmount: 2_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
        bytes memory sig2 = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt2,
            globalValues,
            partyValues,
            officerEOA,
            privKey2
        );
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.InvalidAllocation.selector)
        );
        rm.submitEOI(
            roundId,
            eoi2,
            globalValues,
            partyValues,
            sig2,
            salt2,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
        assertEq(
            usdc.balanceOf(inv2),
            startBal + 2_000 * (10 ** usdc.decimals())
        );
    }

    function test_RevertIf_FCFS_SubmitEOI_FailLexChexCondition() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,

        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, address auth, address issuance, address dealManager, address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp B",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        uint256 officerPrivKey = 0xAA04;
        address officerEOA = vm.addr(officerPrivKey);
        bytes32 roundId = CyberCorpHelper.createRound(
            rm,
            address(usdc),
            usdc.decimals(),
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            RoundType.FCFS,
            officerEOA,
            officerPrivKey,
            corp
        );

        uint256 salt = 1;
        uint256 privKey = 0xA11CE;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 20_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        uint256 meUsdcBalanceBefore = usdc.balanceOf(me);

        EOI memory eoi = EOI({
            name: "Investor 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 5_000 * (10 ** usdc.decimals()),
            maxAmount: 10_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        string[] memory globalValues = new string[](1);
        globalValues[0] = "g";
        string[] memory partyValues = new string[](2);
        partyValues[0] = "Officer";
        partyValues[1] = "CEO";

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            globalValues,
            partyValues,
            officerEOA,
            privKey
        );

        // Mock LexChexCondition to always fail
        CyberCorpHelper.mockLexChexCondition(false);

        vm.expectRevert(RoundManager.AgreementConditionsNotMet.selector);
        rm.submitEOI(
            roundId,
            eoi,
            globalValues,
            partyValues,
            sig,
            salt,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();
    }
}
