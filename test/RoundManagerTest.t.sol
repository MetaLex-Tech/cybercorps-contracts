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
import {IERC1967} from "../dependencies/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";
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
import {RoundLib, Round} from "../src/libs/RoundLib.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LexScrowStorage, Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {LexChexDetails} from "../src/storage/RoundManagerStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {ILexChex} from "../src/interfaces/ILexChex.sol";
import {RoundManagerUpgradeHelper} from "../src/helpers/RoundManagerUpgradeHelper.sol";

// (no extra imports needed for fork-based test)

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

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockHDPaymentToken is ERC20 {
    constructor() ERC20("Mock high-decimals USD", "HDUSD") {
        _mint(msg.sender, 2000000 * 10 ** 24); // Mint 2M tokens with 24 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 24;
    }
}

contract MockLDPaymentToken is ERC20 {
    constructor() ERC20("Mock low-decimals USD", "LDUSD") {
        _mint(msg.sender, 2000000); // Mint 2M tokens with 24 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }
}

contract MockRoundManagerVTest is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "test";

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
    using RoundLib for Round;
    
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
    address constant LEXCHEX_ADDRESS = 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62;
    address constant UPGRADE_OWNER = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;

    bytes32 constant SALT = keccak256("CyberCorpHelper");

    bytes32 constant TEMPLATE_ID = bytes32(uint256(777));

    // Infra helpers copied from above
    function deployRegistryAndFactories(address owner) internal returns (
        CyberAgreementRegistry registry,
        CyberCorpFactory corpFactory,
        address issuanceManagerFactory,
        address cyberCorpSingleFactory,
        address dealManagerFactory,
        address roundManagerFactory,
        address uriBuilder,
        address helper
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

        address issuanceManagerImpl = address(new IssuanceManager{salt: SALT}());
        address certPrinterImpl = address(new CyberCertPrinter{salt: SALT}());
        address cyberScripImpl = address(new CyberScrip{salt: SALT}());
        address issuanceManagerFactory = address(
            new ERC1967Proxy{salt: SALT}(
                address(new IssuanceManagerFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(bootstrapAuth),
                    issuanceManagerImpl,
                    certPrinterImpl,
                    cyberScripImpl
                )
            )
        );

        cyberCorpSingleFactory = address(
            new ERC1967Proxy{salt: SALT}(
                address(new CyberCorpSingleFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    CyberCorpSingleFactory.initialize.selector,
                    address(bootstrapAuth),
                    address(new CyberCorp())
                )
            )
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

        helper = address(new RoundManagerUpgradeHelper{salt: SALT}(address(registry), address(roundManagerFactory)));

        corpFactory = CyberCorpFactory(
            address(
                new ERC1967Proxy{salt: SALT}(
                    address(new CyberCorpFactory{salt: SALT}()),
                    abi.encodeWithSelector(
                        CyberCorpFactory.initialize.selector,
                        address(bootstrapAuth),
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
        bytes32 templateId,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 pricePerUnit,
        uint256 valuation,
        RoundType roundType,
        uint256 officerPrivKey,
        address companyAddress,
        bool publicRound
    ) internal returns (bytes32) {
        address officerEOA = vm.addr(officerPrivKey);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCertData[]
        memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
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
            roundType,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            paymentToken,
            pricePerUnit,
            valuation,
            officerPrivKey,
            companyAddress
        );

        return rm.createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesSeed,
                    roundType,
                    publicRound,
                    true,
                    raiseCap,
                    minTicket,
                    maxTicket,
                    paymentToken,
                    pricePerUnit,
                    valuation,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    templateId,
                    officerEOA,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    roundPartyValues,
                    new bytes[](certData.length),
                    new address[](0),
                    escrowedSig
                ),
            certData
        );
    }

    function CreateLexChexRound(
        RoundManager rm,
        address paymentToken,
        bytes32 templateId,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 pricePerUnit,
        uint256 valuation,
        RoundType roundType,
        uint256 officerPrivKey,
        address companyAddress,
        bool publicRound
    ) internal returns (bytes32) {
        address officerEOA = vm.addr(officerPrivKey);

        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        CyberCertData[]
        memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
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
            roundType,
            block.timestamp,
            block.timestamp + 30 days,
            templateId,
            paymentToken,
            pricePerUnit,
            valuation,
            officerPrivKey,
            companyAddress
        );

        address[] memory conditions = new address[](1);
        conditions[0] = 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42;

        return rm.createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesSeed,
                    roundType,
                    publicRound,
                    true,
                    raiseCap,
                    minTicket,
                    maxTicket,
                    paymentToken,
                    pricePerUnit,
                    valuation,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    templateId,
                    officerEOA,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    roundPartyValues,
                    new bytes[](certData.length),
                    conditions,
                    escrowedSig
                ),
            certData
        );
    }

    function submitEOI(
        RoundManager rm,
        CyberAgreementRegistry registry,
        bytes32 roundId,
        uint256 salt,
        uint256 minAmount,
        uint256 maxAmount,
        address officerEOA,
        uint256 investorPrivKey
    ) internal returns (bytes32, uint256) {
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: minAmount,
            maxAmount: maxAmount,
            expiry: block.timestamp + 7 days,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        return RoundManager(rm).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            CyberCorpHelper.computeEOISignature(
                registry,
                CyberCorpHelper.TEMPLATE_ID,
                salt,
                new string[](1),
                new string[](2),
                officerEOA,
                investorPrivKey
            ),
            salt,
            new address[](0),
            bytes32(0)
        );
    }

    function submitFCFSRoundEOIAndAssertFinalized(
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
            templateId: bytes32(uint256(400)),
            salt: 0,
            globalValues: new string[](0),
            parties: new address[](0),
            partyValues: new string[][](0),
            agreementSignature: ""
        });
    }
}

contract RoundManagerTest is Test {
    using RoundLib for Round;

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
    address private helper;
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

    uint256 public constant PRICE_PER_UNIT = 10 * 10 ** 18; // 10 USDC per unit (decimals = 18)
    uint256 public constant VALUATION = 10000000 * 10 ** 18; // $10M valuation (decimals = 18)

    function setUp() public {
        // For future-proof: some networks may have upgraded already. In such case we will roll back to a known block before the upgrades
        if (block.chainid == 84532) {
            console2.log("Existing deployment has been upgraded, rolling back to a known block before it...");
            vm.rollFork(33920951);
        }

        // Configs

        testRoundPartyValues = new string[](2);
        testRoundPartyValues[0] = "Officer";
        testRoundPartyValues[1] = "CEO";


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
            uriBuilder,
            helper
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
            CyberCorpHelper.TEMPLATE_ID,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Fund investor
        paymentToken.transfer(investor, 1000000 * 10 ** 6);
        vm.prank(investor);
        paymentToken.approve(address(roundManager), type(uint256).max);

        paymentToken.transfer(investor2, 1000000 * 10 ** 6);
        vm.prank(investor2);
        paymentToken.approve(address(roundManager), type(uint256).max);
    }

    function test_helperUpgrade() public {
        //upgrade cybercorpsinglefactory
        address deployer = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;

        // Upgrade all legacy corps
        vm.startPrank(deployer);
        address cyberCorpSingleFactory = 0xc8e084D3f8B3b326FCc894C7afD28F4904196406;
        ILegacyFactory(cyberCorpSingleFactory).upgradeImplementation(address(new CyberCorp()));
        vm.stopPrank();

        address officer = 0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B;
        address exampleCorp = 0xf18393487c6AE9cB75B6AD1715B72d75dEc4F669;
        //generate salt
        bytes32 salt = keccak256("test_helperUpgrade");
        vm.startPrank(officer);
        BorgAuth(CyberCorp(exampleCorp).AUTH()).updateRole(helper, BorgAuth(CyberCorp(exampleCorp).AUTH()).OWNER_ROLE());
        address newRoundManager = RoundManagerUpgradeHelper(helper).upgradeCorp(exampleCorp, salt);
        vm.stopPrank();
    }

    function test_RevertIf_CreateRound_InvalidSignature() public {
        CyberCertData[] memory certData = new CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = CyberCertData({
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
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesA,
                    RoundType.FounderApproved,
                    false,
                    true,
                    RAISE_CAP,
                    MIN_TICKET,
                    MAX_TICKET,
                    address(paymentToken),
                    PRICE_PER_UNIT,
                    VALUATION,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    corpOwner,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    testRoundPartyValues,
                    new bytes[](certData.length),
                    new address[](0),
                    signature
                ),
            certData
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

        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            5000 * 10 ** 6,
            10000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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

	function test_Allocate_RefundsDustAndUpdatesCertificateDetails() public {
		// Submit EOI with a max that creates 5 USDC dust w.r.t. 10 USDC price per unit
		vm.startPrank(investor);
		(bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
			RoundManager(roundManager),
			registry,
			roundId,
			1,
			5_000 * 10 ** 6,
			7_505 * 10 ** 6,
			corpOwner,
			investorPrivKey
		);
		vm.stopPrank();

		uint256 balAfterSubmit = paymentToken.balanceOf(investor);

		// Allocate requested amount; contract should round down and refund 5 USDC
		vm.prank(corpOwner);
		RoundManager(roundManager).allocate(agreementId, 7_505 * 10 ** 6);

        uint256 balAfterAllocate = paymentToken.balanceOf(investor);
        // With fractional units enabled and price in 18-dec, refund is any token rounding dust
        uint8 tokenDecimals = paymentToken.decimals();
        uint256 scale = 10 ** (18 - tokenDecimals);
        uint256 allocatedToken = 7_505 * 10 ** 6;
        uint256 allocated1e18 = allocatedToken * scale;
        uint256 units18 = (allocated1e18 * 1e18) / PRICE_PER_UNIT;
        uint256 used1e18 = (units18 * PRICE_PER_UNIT) / 1e18;
        uint256 usedToken = used1e18 / scale;
        assertEq(balAfterAllocate - balAfterSubmit, allocatedToken - usedToken);

		// Verify certificate details use usedAmount (rounded down) for units and USD
		Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
		assertGt(esc.corpAssets.length, 0);
		Token memory corpToken = esc.corpAssets[0];
		CertificateDetails memory details = CyberCertPrinter(corpToken.tokenAddress).getCertificateDetails(corpToken.tokenId);

        assertEq(details.unitsRepresented, units18);
        assertEq(details.investmentAmountUSD, used1e18);
	}

	function test_Allocate_EmitsRoundedAllocationAndPaysFeesOnUsedAmount() public {
		// Submit EOI with dust
		vm.startPrank(investor);
		(bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
			RoundManager(roundManager),
			registry,
			roundId,
			1,
			5_000 * 10 ** 6,
			7_505 * 10 ** 6,
			corpOwner,
			investorPrivKey
		);
		vm.stopPrank();

        // Compute expected usedAmount in token units with 18-dec price
        // scale = 10^(18 - tokenDecimals)
        uint256 scale = 10 ** (18 - 6);
        uint256 allocated1e18 = (7_505 * 10 ** 6) * scale;
        uint256 units18 = (allocated1e18 * 1e18) / PRICE_PER_UNIT;
        uint256 used1e18 = (units18 * PRICE_PER_UNIT) / 1e18;
        uint256 usedAmount = used1e18 / scale; // back to token decimals (USDC 6)
        uint256 fee = usedAmount * 25 / 10_000; // 0.25% default
		uint256 corpBalBefore = paymentToken.balanceOf(corpOwner);

		// Expect event with allocated (used) amount and totalRaised equal to used amount
		//vm.expectEmit(true, true, true, true);
		//emit RoundManager.AllocationMade(agreementId, roundId, investor, usedAmount, usedAmount, new uint256[](1));

		vm.prank(corpOwner);
		RoundManager(roundManager).allocate(agreementId, 7_505 * 10 ** 6);

		uint256 corpBalAfter = paymentToken.balanceOf(corpOwner);
		assertEq(corpBalAfter - corpBalBefore, usedAmount - fee);
	}

	function test_Allocate_FractionalUSD_DustRefundedAndUSDRoundedDown() public {
		// Create a new round with pricePerUnit = 10.5 USDC to induce fractional USD dust
		vm.startPrank(corpOwner);
		bytes32 roundId105 = CyberCorpHelper.createRound(
			RoundManager(roundManager),
			address(paymentToken),
			CyberCorpHelper.TEMPLATE_ID,
            500_000 * 10 ** 6,
			1 * 10 ** 6,
			100_000 * 10 ** 6,
			1_000_000_000_000_000_000, // 10.5 USDC with 18 decimals
			VALUATION,
			RoundType.FounderApproved,
			corpOwnerPrivKey,
			corp,
			false
		);
		vm.stopPrank();

		// Approve (investor was already funded in setUp)
		vm.startPrank(investor);
		paymentToken.approve(address(roundManager), type(uint256).max);

		// Submit EOI with max 10.75 USDC to create both unit dust (0.25) and fractional USD dust (0.5 inside used)
		(bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
			RoundManager(roundManager),
			registry,
			roundId105,
			1,
			1 * 10 ** 6,
			10_750_000, // 10.75 USDC
			corpOwner,
			investorPrivKey
		);
		vm.stopPrank();

		uint256 balAfterSubmit = paymentToken.balanceOf(investor);

		// Allocate full requested; should allocate 1 unit (10.5 USDC), refund 0.25 USDC
		vm.prank(corpOwner);
		RoundManager(roundManager).allocate(agreementId, 10_500_000);

		uint256 balAfterAllocate = paymentToken.balanceOf(investor);
		assertEq(balAfterAllocate - balAfterSubmit, 250000); // .25 USDC refund

        // Certificate USD uses 18-dec precision and reflects 10.5e18
		Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
		Token memory corpToken = esc.corpAssets[0];
		CertificateDetails memory details = CyberCertPrinter(corpToken.tokenAddress).getCertificateDetails(corpToken.tokenId);
        assertEq(details.unitsRepresented, 10500000000000000000);
		assertEq(details.investmentAmountUSD, 10500000000000000000);
	}

    /// @notice allocate() should be able to handle rare high-decimals (>18) payment token so that
    /// it wouldn't break certificate specs of 18-decimals for all numbers
    function test_Allocate_HighDecimalsPayment() public {
        // Create a high-decimal payment token
        MockHDPaymentToken hdPaymentToken = new MockHDPaymentToken();

        // Create a special round with this high-decimal payment token
        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(hdPaymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000e24,
            1_000e24,
            100_000e24,
            10e18,
            10_000_000e18,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Fund investor
        hdPaymentToken.transfer(investor, 1_000_000e24);
        vm.prank(investor);
        hdPaymentToken.approve(address(roundManager), type(uint256).max);

		// Submit EOI with a max that creates 5 USDC dust w.r.t. 10 USDC price per unit
		vm.startPrank(investor);
		(bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
			RoundManager(roundManager),
			registry,
			roundId,
			1,
			5_000e24,
			7_505e24,
			corpOwner,
			investorPrivKey
		);
		vm.stopPrank();

		uint256 balAfterSubmit = hdPaymentToken.balanceOf(investor);

		vm.prank(corpOwner);
		RoundManager(roundManager).allocate(agreementId, 7_505e24);

        uint256 balAfterAllocate = hdPaymentToken.balanceOf(investor);
        // With fractional units enabled and price in 18-dec, refund is any token rounding dust
        uint8 tokenDecimals = hdPaymentToken.decimals();
        uint256 downscale = 10 ** (tokenDecimals - 18);
        uint256 allocatedToken = 7_505e24;
        uint256 allocated1e18 = allocatedToken / downscale; // 7_505e18
        uint256 units18 = (allocated1e18 * 1e18) / 10e18; // 750.5e18
        uint256 used1e18 = (units18 * 10e18) / 1e18; // 7_505e18
        uint256 usedToken = used1e18 * downscale; // 7_505e24
        assertEq(balAfterAllocate - balAfterSubmit, allocatedToken - usedToken);

		// Verify certificate details use usedAmount (rounded down) for units and USD
		Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
		assertGt(esc.corpAssets.length, 0);
		Token memory corpToken = esc.corpAssets[0];
		CertificateDetails memory details = CyberCertPrinter(corpToken.tokenAddress).getCertificateDetails(corpToken.tokenId);

        assertEq(details.unitsRepresented, units18, "unitsRepresented should be in 18-decimals");
        assertEq(details.investmentAmountUSD, used1e18, "investmentAmountUSD should be in 18-decimals");
	}

    function test_Allocate_LowDecimalsPayment() public {
        // Create a high-decimal payment token
        MockLDPaymentToken ldPaymentToken = new MockLDPaymentToken();

        // Create a special round with this high-decimal payment token
        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(ldPaymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000,
            1_000,
            100_000,
            33e18,
            10_000_000e18,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Fund investor
        ldPaymentToken.transfer(investor, 1_000_000);
        vm.prank(investor);
        ldPaymentToken.approve(address(roundManager), type(uint256).max);

        uint256 balBeforeSubmit = ldPaymentToken.balanceOf(investor);

		vm.startPrank(investor);
		(bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
			RoundManager(roundManager),
			registry,
			roundId,
			1,
			1_000,
			1_000,
			corpOwner,
			investorPrivKey
		);
		vm.stopPrank();

		vm.prank(corpOwner);
		RoundManager(roundManager).allocate(agreementId, 1_000);

        uint256 balAfterAllocate = ldPaymentToken.balanceOf(investor);
        // allocatedAmount = 1_000
        // allocatedAmount1e18 = 1_000e18
        // units1e18 = 1_000e18 * 1e18 / 33e18 = 30303030303030303030
        // usedAmount1e18 = 30303030303030303030 * 33e18 / 1e18 = 999999999999999999990
        // usedAmount = 999999999999999999990 / 1e18 = 999
        assertEq(balBeforeSubmit - balAfterAllocate, 999);

		// Verify certificate details use usedAmount (rounded down) for units and USD
		Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
		assertGt(esc.corpAssets.length, 0);
		Token memory corpToken = esc.corpAssets[0];
		CertificateDetails memory details = CyberCertPrinter(corpToken.tokenAddress).getCertificateDetails(corpToken.tokenId);

        assertEq(details.unitsRepresented, 30303030303030303030, "unitsRepresented should be in 18-decimals");
        assertEq(details.investmentAmountUSD, 999999999999999999990, "investmentAmountUSD should be in 18-decimals");
	}

    /// @notice allocate() should handle edge cases when `usedAmount` drop below `minRequired` due to rounding error
    /// For better UX, we allow such scenarios to pass so that users could invest at exactly the minimum amounts
    /// @dev below tests the case when `minRequired` it determined by `minTicket`
    function test_Allocate_MinAllocationRoundingMinTicket() public {
        // Create a special round with `pricePerUnit` that causes rounding errors
        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000e6,
            1_000e6,
            100_000e6,
            33e18, // deliberately create rounding errors for `usedAmount` calculations
            10_000_000e18,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        uint256 investorBalanceBefore = paymentToken.balanceOf(investor);

        // Submit EOI first
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            1_000e6, // exactly `minTicket`
            1_000e6,
            corpOwner,
            investorPrivKey
        );
        vm.stopPrank();

        // Allocate at exact min. ticket should work
        // allocatedAmount1e18 = 1_000e18
        // units1e18 = 1_000e18 * 1e18 / 33e18 = 30303030303030303030
        // usedAmount1e18 = 30303030303030303030 * 33e18 / 1e18 = 999999999999999999990
        // usedAmount = 999999999999999999990 / 1e12 = 999999999
        //
        // since `minRequired` is tested against `allocateAmount` instead of `usedAmount`, above will pass

        vm.expectEmit(true, true, true, true);
        emit RoundManager.AllocationMade(
            agreementId,
            roundId,
            investor,
            1_000e6 - 1, // allocation amount would be slightly less than `minRequired` but we still let it pass
            1_000e6 - 1,
            new uint256[](1)
        );
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(
            agreementId,
            1_000e6 // founder to allocate exactly `minTicket`, expecting it to work
        );

        assertEq(investorBalanceBefore - paymentToken.balanceOf(investor), 1_000e6 - 1, "investor should spend slightly less than minTicket due to rounding");
    }

    /// @notice allocate() should handle edge cases when `usedAmount` drop below `minRequired` due to rounding error
    /// For better UX, we allow such scenarios to pass so that users could invest at exactly the minimum amounts
    /// @dev below tests the case when `minRequired` it determined by `minAmount`
    function test_Allocate_MinAllocationRoundingMinAmount() public {
        // Create a special round with `pricePerUnit` that causes rounding errors
        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000e6,
            1_000e6,
            100_000e6,
            33e18, // deliberately create rounding errors for `usedAmount` calculations
            10_000_000e18,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        uint256 investorBalanceBefore = paymentToken.balanceOf(investor);

        // Submit EOI first
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            1_500e6, // expect to get this much
            1_500e6,
            corpOwner,
            investorPrivKey
        );
        vm.stopPrank();

        // Allocate at exact min. amount should work
        // allocatedAmount1e18 = 1_500e18
        // units1e18 = 1_500e18 * 1e18 / 33e18 = 45454545454545454545
        // usedAmount1e18 = 45454545454545454545 * 33e18 / 1e18 = 1499999999999999999985
        // usedAmount = 1499999999999999999985 / 1e12 = 1499999999
        //
        // since `minRequired` is tested against `allocateAmount` instead of `usedAmount`, above will pass

        vm.expectEmit(true, true, true, true);
        emit RoundManager.AllocationMade(
            agreementId,
            roundId,
            investor,
            1_500e6 - 1, // allocation amount would be slightly less than `minRequired` but we still let it pass
            1_500e6 - 1,
            new uint256[](1)
        );
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(
            agreementId,
            1_500e6 // founder to allocate exactly `minAmount`, expecting it to work
        );

        assertEq(investorBalanceBefore - paymentToken.balanceOf(investor), 1_500e6 - 1, "investor should spend slightly less than minAmount due to rounding");
    }

    /// @notice allocate() should handle edge cases when `usedAmount` drop below `minRequired` due to rounding error
    /// For better UX, we allow such scenarios to pass so that users could invest at exactly the minimum amounts
    /// @dev below tests the case when `minRequired` it determined by round's remaining
    function test_Allocate_MinAllocationRoundingRemaining() public {
        // Create a special round with `pricePerUnit` that causes rounding errors
        vm.startPrank(corpOwner);
        roundId = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_500e6,
            500e6,
            100_000e6,
            33e18, // deliberately create rounding errors for `usedAmount` calculations
            10_000_000e18,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Investor 1 invests 1000, actually used 999.999999 (round remaining 500.000001)
        {
            // Submit EOI first
            vm.startPrank(investor);
            (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
                RoundManager(roundManager),
                registry,
                roundId,
                1,
                1_000e6, // expect to get this much
                1_000e6,
                corpOwner,
                investorPrivKey
            );
            vm.stopPrank();

            // Allocate at exact min. amount should work
            vm.prank(corpOwner);
            RoundManager(roundManager).allocate(
                agreementId,
                1_000e6 // founder to allocate exactly `minAmount`, expecting it to work
            );
        }

        Round memory round = RoundManager(roundManager).getRound(roundId);
        uint256 remaining = round.raiseCap - round.raised;
        assertEq(remaining, 1500e6 - (1000e6 - 1), "round remaining should have slightly more due to rounding errors");

        // Investor 2 invest 1000, actually used 500
        // allocatedAmount1e18 = 500.000001e18
        // units1e18 = 500.000001e18 * 1e18 / 33e18 = 15151515181818181818
        // usedAmount1e18 = 15151515181818181818 * 33e18 / 1e18 = 500000000999999999994
        // usedAmount = 500000000999999999994 / 1e12 = 500000000
        {
            uint256 investor2BalanceBefore = paymentToken.balanceOf(investor2);

            // Submit EOI first
            vm.startPrank(investor2);
            (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
                RoundManager(roundManager),
                registry,
                roundId,
                1,
                500e6,
                1_000e6,
                corpOwner,
                investor2PrivKey
            );
            vm.stopPrank();

            // Allocate remaining amount should work
            vm.prank(corpOwner);
            RoundManager(roundManager).allocate(
                agreementId,
                remaining
            );

            assertEq(investor2BalanceBefore - paymentToken.balanceOf(investor2), 500e6, "investor should spend slightly less than round remaining (500.000001) due to rounding error");
        }
    }

    function test_Allocate_InvalidAmount() public {
        // Submit EOI first
        vm.startPrank(investor);

        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            5000 * 10 ** 6,
            10000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        vm.startPrank(corpOwner);
        bytes32 roundIdLarge = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * 10 ** 6, // raise cap 1M
            1_000 * 10 ** 6,
            1_000_000 * 10 ** 6, // maxTicket large enough
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Submit first EOI
        vm.startPrank(investor);
        (bytes32 agreementId1, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundIdLarge,
            1,
            400000 * 10 ** 6, // 400k USDC
            600000 * 10 ** 6, // 600k USDC
            corpOwner,
            investorPrivKey
        );
        vm.stopPrank();

        // Submit second EOI from different investor
        vm.startPrank(investor2);
        (bytes32 agreementId2, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundIdLarge,
            2,
            400000 * 10 ** 6, // 400k USDC
            600000 * 10 ** 6, // 600k USDC
            corpOwner,
            investor2PrivKey
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
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            5000 * 10 ** 6,
            10000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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

    function test_Allocate_FeeChanged() public {
        // Submit EOIs
        vm.startPrank(investor);
        (bytes32 agreementId1, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            5000 * 10 ** 6,
            10000 * 10 ** 6,
            corpOwner,
            investorPrivKey
        );
        vm.stopPrank();

        vm.startPrank(investor2);
        (bytes32 agreementId2, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            2,
            5000 * 10 ** 6,
            10000 * 10 ** 6,
            corpOwner,
            investor2PrivKey
        );
        vm.stopPrank();

        {
            uint256 balBeforeAllocate = paymentToken.balanceOf(corpOwner);

            vm.prank(corpOwner);
            RoundManager(roundManager).allocate(agreementId1, 5_000 * 10 ** 6);

            uint256 balAfterAllocate = paymentToken.balanceOf(corpOwner);
            // 5000 * (1 - 0.25%) = 4987.5
            assertEq(balAfterAllocate - balBeforeAllocate, 4987.5 * 10 ** 6);
        }

        // Simulate fee ratio changes
        vm.prank(owner);
        RoundManagerFactory(rmFactory).setDefaultFeeRatio(100); // 1% fee

        {
            uint256 balBeforeAllocate = paymentToken.balanceOf(corpOwner);

            vm.prank(corpOwner);
            RoundManager(roundManager).allocate(agreementId2, 5_000 * 10 ** 6);

            uint256 balAfterAllocate = paymentToken.balanceOf(corpOwner);
            // 5000 * (1 - 1%) = 4950
            assertEq(balAfterAllocate - balBeforeAllocate, 4950 * 10 ** 6);
        }
    }

    function test_RejectEOI_RefundsAndVoids() public {
        uint256 balBefore = paymentToken.balanceOf(investor);

        // Submit EOI
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            3,
            2_000 * 10 ** 6,
            5_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        uint256 balBefore = paymentToken.balanceOf(investor);

        // Submit EOI
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            3,
            2_000 * 10 ** 6,
            5_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        uint256 balBefore = paymentToken.balanceOf(investor);

        // Submit EOI
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            3,
            2_000 * 10 ** 6,
            5_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        uint256 balBefore = paymentToken.balanceOf(investor);
        // Submit EOI
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            3,
            2_000 * 10 ** 6,
            5_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        uint256 balBefore = paymentToken.balanceOf(investor);

        // Submit EOI
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            3,
            2_000 * 10 ** 6,
            5_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        CyberCertData[]
            memory certData = new CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = CyberCertData({
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
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesF,
                    RoundType.FounderApproved,
                    false,
                    true,
                    100_000 * 10 ** 6,
                    1_000 * 10 ** 6,
                    50_000 * 10 ** 6,
                    address(paymentToken),
                    PRICE_PER_UNIT,
                    VALUATION,
                    block.timestamp + 1 days,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    corpOwner,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    testRoundPartyValues,
                    new bytes[](certData.length),
                    new address[](0),
                    escSigFuture
                ),
            certData
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
        vm.startPrank(corpOwner);
        bytes32 roundId2 = CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            6_000 * 10 ** 6, // raise cap 1M
            1_000 * 10 ** 6,
            100_000 * 10 ** 6, // maxTicket large enough
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false
        );
        vm.stopPrank();

        // Investor submits EOI for 10,000 USDC, escrow pulls funds
        uint256 balBefore = paymentToken.balanceOf(investor);
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId2,
            5,
            1_000 * 10 ** 6,
            10_000 * 10 ** 6,
            corpOwner,
            investorPrivKey
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
        vm.startPrank(owner);
        RoundManagerFactory(rmFactory).setRefImplementation(address(new MockRoundManagerVTest()));
        vm.stopPrank();
        assertEq(RoundManager(RoundManagerFactory(rmFactory).getRefImplementation()).DEPLOY_VERSION(), "test", "reference impl version should have changed");

        bytes32 salt = keccak256("test_UpgradeNextRounderManager");
        // Next deployment should emit events with version so indexer could be informed
        vm.expectEmit(true, true, true, true);
        emit RoundManagerFactory.RoundManagerDeployed(
            RoundManagerFactory(rmFactory).computeRoundManagerAddress(salt),
            "test"
        );
        RoundManager nextRm = RoundManager(
            RoundManagerFactory(rmFactory).deployRoundManager(salt)
        );
        assertEq(nextRm.DEPLOY_VERSION(), "test", "next deployment version should have changed");
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
        RoundManagerFactory(rmFactory).setRefImplementation(address(new MockRoundManagerVTest()));
        vm.stopPrank();

        // Corp2 owner decided to accept the upgrade

        vm.startPrank(corpOwner);
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(DealManagerFactory(rmFactory).getRefImplementation());
        rm2.upgradeToAndCall(address(RoundManagerFactory(rmFactory).getRefImplementation()), "");
        vm.stopPrank();

        assertEq(rm2.DEPLOY_VERSION(), "test", "Target RoundManager should be upgraded");
        assertNotEq(rm1.DEPLOY_VERSION(), "test", "Other RoundManager should not be upgraded");
    }

    function test_RevertIf_UpgradeNonFactoryOwner() public {
        // Non-MetaLeX admin should not be able to set new reference implementation

        address newImplementation = address(new MockRoundManagerVTest());
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
        address nonOfficialRoundManager = address(new MockRoundManagerVTest());
        vm.expectRevert(
            abi.encodeWithSelector(RoundManager.NotRefImplementation.selector)
        );
        rm.upgradeToAndCall(nonOfficialRoundManager, "");
        vm.stopPrank();
    }

    function test_Allocation_CertificateDetailsMatchRoundInputs() public {
        // Investor submits an EOI for 7,500 USDC
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundId,
            1,
            5_000 * 10 ** 6,
            7_500 * 10 ** 6,
            corpOwner,
            investorPrivKey
        );
        vm.stopPrank();

        // Allocate the full 7,500 USDC
        uint256 allocatedAmount = 7_500 * 10 ** 6;
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, allocatedAmount);

        // Inspect escrowed corp asset (certificate)
        Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertGt(esc.corpAssets.length, 0);
        Token memory corpToken = esc.corpAssets[0];

        // Certificate should have been minted to the investor and total supply should be 1
        assertEq(CyberCertPrinter(corpToken.tokenAddress).ownerOf(corpToken.tokenId), investor);
        assertEq(CyberCertPrinter(corpToken.tokenAddress).totalSupply(), 1);

        // Verify certificate details match round inputs
        CertificateDetails memory details = CyberCertPrinter(corpToken.tokenAddress).getCertificateDetails(corpToken.tokenId);

        // Officer info from createRound agreement
        assertEq(details.signingOfficerName, "Officer");
        assertEq(details.signingOfficerTitle, "CEO");

        // Investment USD and units are 18-dec; convert token amount to 1e18 and compute
        uint8 tokenDecimals = paymentToken.decimals();
        uint256 scale = 10 ** (18 - tokenDecimals);
        uint256 allocated1e18 = allocatedAmount * scale;
        uint256 expectedUnits18 = (allocated1e18 * 1e18) / PRICE_PER_UNIT;
        uint256 expectedInvestmentUSD18 = (expectedUnits18 * PRICE_PER_UNIT) / 1e18;
        assertEq(details.investmentAmountUSD, expectedInvestmentUSD18);
        assertEq(details.unitsRepresented, expectedUnits18);

        // Valuation propagated
        assertEq(details.issuerUSDValuationAtTimeOfInvestment, VALUATION);
    }

    function test_RoundPrimarySecurity_MatchesCertData() public {
        (SecurityClass cls, SecuritySeries series) = RoundManager(roundManager).getPrimarySecurity(roundId);
        assertEq(uint256(cls), uint256(SecurityClass.CommonStock));
        assertEq(uint256(series), uint256(SecuritySeries.NA));
    }

    function test_CreateRound_WithTwoCertificates_IndexMatchedDetails() public {
        // Prepare two certificate types
        CyberCertData[] memory certData = new CyberCertData[](2);
        string[] memory legendA = new string[](1);
        legendA[0] = "Legend A";
        string[] memory legendB = new string[](1);
        legendB[0] = "Legend B";
        certData[0] = CyberCertData({
            name: "Equity A",
            symbol: "EQA",
            uri: "ipfs://eqa",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: legendA
        });
        certData[1] = CyberCertData({
            name: "Equity B",
            symbol: "EQB",
            uri: "ipfs://eqb",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: legendB
        });

        // Round agreement arrays must match certData length
        string[] memory legalDetails = new string[](2);
        legalDetails[0] = "LD A";
        legalDetails[1] = "LD B";
        bytes[] memory extensionData = new bytes[](2);
        extensionData[0] = bytes("extA");
        extensionData[1] = bytes("extB");

        // officer identity and escrow signature
        uint256 officerPrivKey = corpOwnerPrivKey;
        address officerEOA = corpOwner;
        (bytes memory escSig, ) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            RoundType.FCFS,
            block.timestamp,
            block.timestamp + 30 days,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            VALUATION,
            officerPrivKey,
            corp
        );

        // Create the round (FCFS for auto-allocation)
        bytes32 roundIdTwo;
        vm.prank(corpOwner);
        roundIdTwo = RoundManager(roundManager).createRound(
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesSeed,
                    RoundType.FCFS,
                    false,
                    true,
                    RAISE_CAP,
                    MIN_TICKET,
                    MAX_TICKET,
                    address(paymentToken),
                    PRICE_PER_UNIT,
                    VALUATION,
                    block.timestamp,
                    block.timestamp + 30 days
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    officerEOA,
                    "Officer",
                    "CEO",
                    legalDetails,
                    testRoundPartyValues,
                    extensionData,
                    new address[](0),
                    escSig
                ),
            certData
        );

        // Submit EOI and auto-allocate (FCFS)
        vm.startPrank(investor);
        (bytes32 agreementId, ) = CyberCorpHelper.submitEOI(
            RoundManager(roundManager),
            registry,
            roundIdTwo,
            11,
            5_000 * 10 ** 6,
            10_000 * 10 ** 6,
            officerEOA,
            investorPrivKey
        );
        vm.stopPrank();

        // Verify two certificates minted and details are index-matched
        Escrow memory esc = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(esc.corpAssets.length, 2);

        // First certificate
        Token memory t0 = esc.corpAssets[0];
        CertificateDetails memory d0 = CyberCertPrinter(t0.tokenAddress).getCertificateDetails(t0.tokenId);
        assertEq(d0.legalDetails, "LD A");
        assertEq(keccak256(d0.extensionData), keccak256(bytes("extA")));

        // Second certificate
        Token memory t1 = esc.corpAssets[1];
        CertificateDetails memory d1 = CyberCertPrinter(t1.tokenAddress).getCertificateDetails(t1.tokenId);
        assertEq(d1.legalDetails, "LD B");
        assertEq(keccak256(d1.extensionData), keccak256(bytes("extB")));
    }

    function test_SetAndGetRoundPricePerShare() public {
        // Set and verify round price per share metadata
        vm.prank(corpOwner);
        RoundManager(roundManager).setRoundPricePerShare(roundId, 42, 2);
        (uint256 price, uint8 decimals_) = RoundManager(roundManager).getRoundPriceInfo(roundId);
        assertEq(price, 42);
        assertEq(decimals_, 2);
    }
}

// Separate FCFS tests in their own contract to avoid the original setUp()
contract RoundManagerFCFSTest is Test {
    using RoundLib for Round;
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;

    function setUp() public {
    }

    function test_UpgradeSteps_RM_Corp_RefImplementation() public {
        address me = address(this);
        (
            ,
            CyberCorpFactory corpFactory,
            ,
            address cyberCorpSingleFactory,
            ,
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

        address newCorpImpl = address(new CyberCorp());
        CyberCorpSingleFactory(cyberCorpSingleFactory).setRefImplementation(newCorpImpl);
        assertEq(CyberCorpSingleFactory(cyberCorpSingleFactory).getRefImplementation(), newCorpImpl, "CyberCorp refImplementation should have been updated");
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

        // Update CyberCorp reference implementation so all new deployment uses the new one
        CyberCorpSingleFactory(cyberCorpSingleFactory).setRefImplementation(address(new CyberCorp()));

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
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
        );

        CyberCorpHelper.submitFCFSRoundEOIAndAssertFinalized(
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
        CyberCertData[]
            memory certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
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
            RoundLib.draft()
                .setTickets(
                    SecuritySeries.SeriesPreSeed,
                    RoundType.FCFS,
                    true,
                    true,
                    1,
                    1,
                    1,
                    address(0xDEAD),
                    1,
                    1,
                    block.timestamp,
                    block.timestamp + 1
                )
                .setAgreement(
                    CyberCorpHelper.TEMPLATE_ID,
                    officerEOA,
                    "Officer",
                    "CEO",
                    new string[](certData.length),
                    roundPartyValues,
                    new bytes[](certData.length),
                    new address[](0),
                    escSig
                ),
            certData
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
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
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
            CyberCorpHelper.TEMPLATE_ID,
            50_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            80_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
        );

        uint256 salt = 1;
        uint256 privKey = 0xB0B;
        address investor = vm.addr(privKey);
        usdc.transfer(investor, 80_000 * (10 ** usdc.decimals()));
        uint256 startBal = usdc.balanceOf(investor);
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        CyberCorpHelper.submitEOI(
            rm,
            registry,
            roundId,
            salt,
            10_000 * (10 ** usdc.decimals()),
            80_000 * (10 ** usdc.decimals()),
            officerEOA,
            privKey
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
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            1_000 * (10 ** usdc.decimals()),
            100_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
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
            CyberCorpHelper.TEMPLATE_ID,
            1_500 * (10 ** usdc.decimals()),
            1_500 * (10 ** usdc.decimals()),
            100_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
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
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
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

        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            100_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            50_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            true
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

    function test_FCFS_PublicRound_IndividualOver200k_LexChexRequired() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            address rmFactoryAddr,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, , , , address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();
        vm.label(address(usdc), "MockPaymentToken");

        // Prepare officer identity for the round
        uint256 officerPrivKey = 0xBEEF01;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a public FCFS round with maxTicket above 200k
        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            false
        );

        // Investor setup: natural person investing > 200k
        uint256 salt = 7;
        uint256 investorPrivKey = 0xC0FFEE;
        address investor = vm.addr(investorPrivKey);
        usdc.transfer(investor, 300_000 * (10 ** usdc.decimals()));

        //white list the mock payment token MockPaymentToken: [0x27cc01A4676C73fe8b6d0933Ac991BfF1D77C4da]
        RoundManagerFactory(rmFactoryAddr).setWhitelistedToken(address(usdc), true);
       
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 200_000 * (10 ** usdc.decimals()),
            maxAmount: 250_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });
         // Attach a valid LeXcheX mint payload aligned to template 400 so auto-mint can succeed
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor;

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
            bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                vm,
                lxRegistry.DOMAIN_SEPARATOR(),
                lxRegistry.SIGNATUREDATA_TYPEHASH(),
                lxContractId,
                legalUri,
                lxGlFields,
                lxPartyFields,
                lxGlobalValues,
                lxPartyValues[0],
                investorPrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Minimal agreement signature for EOI
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            glValues,
            pv,
            officerEOA,
            investorPrivKey
        );

        rm.submitEOI(
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

        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(investor), 1, "LexChex should be minted for the investor");
    }

      function test_FCFS_PublicRound_UnderIndividualOver200k_LexChexRequired() public {
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            ,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        (address corp, , , , address rmAddr) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public",
            me,
            me
        );
        RoundManager rm = RoundManager(rmAddr);

        // Allow RoundManager to transfer certs by setting it as the corp's dealManager
        vm.prank(address(corpFactory));
        CyberCorp(corp).setDealManager(address(rm));

        MockPaymentToken usdc = new MockPaymentToken();

        // Prepare officer identity for the round
        uint256 officerPrivKey = 0xBEEF01;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a public FCFS round with maxTicket above 200k
        bytes32 roundId = CyberCorpHelper.CreateLexChexRound(
            rm,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corp,
            true
        );

        // Investor setup: natural person investing > 200k
        uint256 salt = 7;
        uint256 investorPrivKey = 0xC0FFEE2;
        address investor = vm.addr(investorPrivKey);
        usdc.transfer(investor, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(investor);
        usdc.approve(address(rm), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 10_000 * (10 ** usdc.decimals()),
            maxAmount: 15_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        // Attach a valid LeXcheX mint payload aligned to template 400 to avoid MismatchedFieldsLength if auto-mint is ever triggered
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor;

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
            bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                vm,
                lxRegistry.DOMAIN_SEPARATOR(),
                lxRegistry.SIGNATUREDATA_TYPEHASH(),
                lxContractId,
                legalUri,
                lxGlFields,
                lxPartyFields,
                lxGlobalValues,
                lxPartyValues[0],
                investorPrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Prepare a valid LeXcheX MintRequest (templateId = bytes32(uint256(400))) for use if auto-mint is triggered later
        {
            // Resolve LexChexMinter and its registry on the fork
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());

            // Template and values
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);

            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";

            address[] memory lxParties = new address[](1);
            lxParties[0] = investor; // owner signs

            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;           // investorName
            lxPartyValues[0][1] = eoi.investorType;   // investorType
            lxPartyValues[0][2] = eoi.jurisdiction;   // investorJurisdiction
            lxPartyValues[0][3] = eoi.contact;        // investorContact

            // Compute agreementId and signature for the LeXcheX agreement
            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
            bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                vm,
                lxRegistry.DOMAIN_SEPARATOR(),
                lxRegistry.SIGNATUREDATA_TYPEHASH(),
                lxContractId,
                legalUri,
                lxGlFields,
                lxPartyFields,
                lxGlobalValues,
                lxPartyValues[0],
                investorPrivKey
            );

            // Populate lexchexDetails
            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: investor,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Minimal agreement signature for EOI
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            glValues,
            pv,
            officerEOA,
            investorPrivKey
        );

        //make sure lexchex is not valid
        assert(!ILexChex(0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62).hasValidLexCheX(investor));

        vm.expectRevert(RoundManager.AgreementConditionsNotMet.selector);
        rm.submitEOI(
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
    }

    function test_FCFS_PublicRound_LexChexMinting_Whitelist() public {
        // This test uses CreateLexChexRound to include the LexChex condition
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            ,
            ,
            address rmFactoryAddr,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        MockPaymentToken usdc = new MockPaymentToken();

        // Prepare officer
        uint256 officerPrivKey = 0xBEEF02;
        address officerEOA = vm.addr(officerPrivKey);

        // Create a separate Corp and RoundManager for this test
        (address corpPub, , , , address rmAddrPub) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Corp Public Whitelist",
            me,
            me
        );
        RoundManager rmPub = RoundManager(rmAddrPub);

        // Allow RoundManager to transfer certs
        vm.prank(address(corpFactory));
        CyberCorp(corpPub).setDealManager(address(rmPub));

        // Create Public FCFS Round
        bytes32 pubRoundId = CyberCorpHelper.CreateLexChexRound(
            rmPub,
            address(usdc),
            CyberCorpHelper.TEMPLATE_ID,
            1_000_000 * (10 ** usdc.decimals()),
            2_000 * (10 ** usdc.decimals()),
            300_000 * (10 ** usdc.decimals()),
            10 * (10 ** usdc.decimals()),
            10_000_000,
            RoundType.FCFS,
            officerPrivKey,
            corpPub,
            true // publicRound
        );

        // Investor 1: Non-whitelisted token
        uint256 inv1PrivKey = 0x11111;
        address inv1 = vm.addr(inv1PrivKey);
        usdc.mint(inv1, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv1);
        usdc.approve(address(rmPub), type(uint256).max);

        EOI memory eoi = EOI({
            name: "High Roller 1",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "email",
            minAmount: 200_000 * (10 ** usdc.decimals()),
            maxAmount: 250_000 * (10 ** usdc.decimals()),
            expiry: block.timestamp + 7 days,
            naturalPerson: true,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        // LexChex Details setup (boilerplate to pass validation if minting were attempted)
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);
            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";
            address[] memory lxParties = new address[](1);
            lxParties[0] = inv1;
            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
            bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                vm,
                lxRegistry.DOMAIN_SEPARATOR(),
                lxRegistry.SIGNATUREDATA_TYPEHASH(),
                lxContractId,
                legalUri,
                lxGlFields,
                lxPartyFields,
                lxGlobalValues,
                lxPartyValues[0],
                inv1PrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 1,
                    owner: inv1,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // EOI Signature
        string[] memory glValues = new string[](1);
        glValues[0] = "g";
        string[] memory pv = new string[](2);
        pv[0] = "Officer";
        pv[1] = "CEO";
        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            123,
            glValues,
            pv,
            officerEOA,
            inv1PrivKey
        );

        // SUBMIT EOI - Should succeed but NOT mint LexChex because token is not whitelisted
        vm.expectRevert(RoundManager.AgreementConditionsNotMet.selector);
        rmPub.submitEOI(
            pubRoundId,
            eoi,
            glValues,
            pv,
            sig,
            123,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        // Check LexChex balance
        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(inv1), 0, "LexChex should not be minted for non-whitelisted token");

        // PART 2: Whitelist Token
        vm.prank(me);
        RoundManagerFactory(rmFactoryAddr).setWhitelistedToken(address(usdc), true);


        // Investor 2: Whitelisted token
        uint256 inv2PrivKey = 0x22222;
        address inv2 = vm.addr(inv2PrivKey);
        usdc.mint(inv2, 300_000 * (10 ** usdc.decimals()));
        vm.startPrank(inv2);
        usdc.approve(address(rmPub), type(uint256).max);

        // Reuse EOI struct but update signer info
        eoi.name = "High Roller 2";
        
        // Update LexChex details for Investor 2
        {
            LeXcheXMinter minter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
            CyberAgreementRegistry lxRegistry = CyberAgreementRegistry(minter.dealRegistry());
            bytes32 lxTemplateId = bytes32(uint256(400));
            uint256 lxSalt = block.timestamp + 1;
            (string memory legalUri, , string[] memory lxGlFields, string[] memory lxPartyFields) = lxRegistry.getTemplateDetails(lxTemplateId);
            string[] memory lxGlobalValues = new string[](1);
            lxGlobalValues[0] = "2029-01-01";
            address[] memory lxParties = new address[](1);
            lxParties[0] = inv2;
            string[][] memory lxPartyValues = new string[][](1);
            lxPartyValues[0] = new string[](4);
            lxPartyValues[0][0] = eoi.name;
            lxPartyValues[0][1] = eoi.investorType;
            lxPartyValues[0][2] = eoi.jurisdiction;
            lxPartyValues[0][3] = eoi.contact;

            bytes32 lxContractId = keccak256(abi.encode(lxTemplateId, lxSalt, lxGlobalValues, lxParties));
            bytes memory lxSig = CyberAgreementUtils.signAgreementTypedData(
                vm,
                lxRegistry.DOMAIN_SEPARATOR(),
                lxRegistry.SIGNATUREDATA_TYPEHASH(),
                lxContractId,
                legalUri,
                lxGlFields,
                lxPartyFields,
                lxGlobalValues,
                lxPartyValues[0],
                inv2PrivKey
            );

            eoi.lexchexDetails = LexChexDetails({
                request: MintRequest({
                    uuid: 2,
                    owner: inv2,
                    investorName: eoi.name,
                    investorType: eoi.investorType,
                    investorJurisdiction: eoi.jurisdiction,
                    investorContact: eoi.contact,
                    mintPrice: 0,
                    expiry: block.timestamp + 30 days,
                    paymentToken: address(usdc)
                }),
                templateId: lxTemplateId,
                salt: uint256(lxSalt),
                globalValues: lxGlobalValues,
                parties: lxParties,
                partyValues: lxPartyValues,
                agreementSignature: lxSig
            });
        }

        // Compute EOI Signature for Investor 2
        sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            124,
            glValues,
            pv,
            officerEOA,
            inv2PrivKey
        );

        // SUBMIT EOI - Should succeed AND mint LexChex
        rmPub.submitEOI(
            pubRoundId,
            eoi,
            glValues,
            pv,
            sig,
            124,
            new address[](0),
            bytes32(0)
        );
        vm.stopPrank();

        assertEq(ILexChex(CyberCorpHelper.LEXCHEX_ADDRESS).balanceOf(inv2), 1, "LexChex SHOULD be minted for whitelisted token");
    }
}

contract CyberCorpFactoryPublicRoundTest is Test {
    using RoundLib for Round;

    function test_CyberCorpFactory_DeployCorp_And_CreatePublicRound() public {
        address me = address(this);
        (
            CyberAgreementRegistry registry,
            CyberCorpFactory corpFactory,
            ,
            address cyberCorpSingleFactory,
            ,
            address rmFactory,
            ,
        ) = CyberCorpHelper.deployRegistryAndFactories(me);
        CyberCorpHelper.createTemplate(registry);

        // Payment token
        MockPaymentToken usdc = new MockPaymentToken();

        // Officer
        uint256 officerPrivKey = 0xC0FF;
        address officerEOA = vm.addr(officerPrivKey);
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: officerEOA,
            name: "Officer",
            contact: "officer@example.com",
            title: "CEO"
        });

        // Round params
        uint256 salt = 42;
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));
        address predictedCorp = CyberCorpSingleFactory(cyberCorpSingleFactory).computeCyberCorpSingleAddress(corpSalt);
        address predictedRM = RoundManagerFactory(rmFactory).computeRoundManagerAddress(corpSalt);

        bytes32 templateId = CyberCorpHelper.TEMPLATE_ID;
        uint256 raiseCap = 100_000 * (10 ** usdc.decimals());
        uint256 minTicket = 2_000 * (10 ** usdc.decimals());
        uint256 maxTicket = 50_000 * (10 ** usdc.decimals());
        uint256 pricePerUnit = 10 * (10 ** usdc.decimals());
        uint256 valuation = 1_000_000_000_000_000_000_000;
        uint256 startTime = block.timestamp;
        uint256 endTime = block.timestamp + 30 days;

        (bytes memory escSig, bytes32 expectedRoundId) = CyberCorpHelper.computeEscrowSignature(
            predictedRM,
            SecuritySeries.SeriesSeed,
            raiseCap,
            minTicket,
            maxTicket,
            RoundType.FCFS,
            startTime,
            endTime,
            templateId,
            address(usdc),
            pricePerUnit,
            valuation,
            officerPrivKey,
            predictedCorp
        );

        // Certificate data
        CyberCertData[] memory certData = new CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = officer.name;
        roundPartyValues[1] = officer.title;

        (
            address corp,
            ,
            ,
            ,
            address roundManager,
            bytes32 roundId
        ) = corpFactory.deployCyberCorpAndCreateRound(
            salt,
            SecuritySeries.SeriesSeed,
            "Corp CF",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            me,
            officer,
            new string[](certData.length),
            new bytes[](certData.length),
            certData,
            templateId,
            address(usdc),
            pricePerUnit,
            valuation,
            roundPartyValues,
            escSig,
            RoundType.FCFS,
            new address[](0),
            raiseCap,
            minTicket,
            maxTicket,
            startTime,
            endTime,
            true,
            true
        );

        // Validations
        assertEq(corp, predictedCorp, "Corp address should match prediction");
        assertEq(roundManager, predictedRM, "RoundManager address should match prediction");
        assertTrue(RoundManager(roundManager).roundExists(roundId), "Round should exist");

        (SecurityClass cls, SecuritySeries series) = RoundManager(roundManager).getPrimarySecurity(roundId);
        assertEq(uint256(cls), uint256(SecurityClass.CommonStock));
        assertEq(uint256(series), uint256(SecuritySeries.NA));
    }
}
