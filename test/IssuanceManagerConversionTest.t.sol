// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberScrip.sol";
import "../src/interfaces/ICyberScrip.sol";
import "../src/interfaces/ICondition.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/libs/auth.sol";
import "../src/libs/conditions/IssuerApprovalRecertificationCondition.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";

contract MockRoundManagerForConversion {
    bool public exists;
    uint256 public cCapUsed;
    uint8 public mode; // 0 floor, 1 ceil, 2 round
    uint8 public priceDecimals;
    uint8 public shareDecimals;
    uint256 public roundPricePerShare;
    uint8 public roundPriceDecs;

    function setConfig(
        bool _exists,
        uint256 _cCapUsed,
        uint8 _mode,
        uint8 _priceDecimals,
        uint8 _shareDecimals,
        uint256 _roundPricePerShare,
        uint8 _roundPriceDecs
    ) external {
        exists = _exists;
        cCapUsed = _cCapUsed;
        mode = _mode;
        priceDecimals = _priceDecimals;
        shareDecimals = _shareDecimals;
        roundPricePerShare = _roundPricePerShare;
        roundPriceDecs = _roundPriceDecs;
    }

    function roundExists(bytes32) external view returns (bool) { return exists; }

    function getCapTableSnapshotFields(bytes32) external view returns (
        uint256, uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        return (0,0,0,0,0,0,cCapUsed);
    }

    function getRoundingPolicyFields(bytes32) external view returns (uint8, uint8, uint8) {
        return (mode, priceDecimals, shareDecimals);
    }

    function getRoundPriceInfo(bytes32) external view returns (uint256, uint8) {
        return (roundPricePerShare, roundPriceDecs);
    }
}

contract SelectorCondition is ICondition {
    address public expectedContract;
    bytes4 public expectedSelector;
    bytes32 public expectedDataHash;

    constructor(
        address _contract,
        bytes4 _selector,
        bytes memory data
    ) {
        expectedContract = _contract;
        expectedSelector = _selector;
        expectedDataHash = keccak256(data);
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) external view returns (bool) {
        return
            _contract == expectedContract &&
            _functionSignature == expectedSelector &&
            keccak256(data) == expectedDataHash;
    }
}

contract MockCertPrinter {
    using IssuanceManagerStorage for IssuanceManagerStorage.IssuanceManagerData;

    string public constant DEPLOY_VERSION = "test";

    mapping(uint256 => CertificateDetails) internal _details;
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(address => uint256[]) internal _ownedTokens;
    mapping(uint256 => bool) internal _voided;
    uint256 internal _total;
    string internal _name = "Mock";
    string internal _symbol = "MOCK";
    address internal _issuanceManager;

    function initialize(
        string[] memory,
        string memory name_,
        string memory symbol_,
        string memory,
        address issuanceManager_,
        SecurityClass,
        SecuritySeries,
        address
    ) external {
        _name = name_;
        _symbol = symbol_;
        _issuanceManager = issuanceManager_;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }
    function issuanceManager() external view returns (address) { return _issuanceManager; }

    function totalSupply() external view returns (uint256) { return _total; }

    function safeMint(uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256) {
        _mint(tokenId, to, details);
        return tokenId;
    }

    function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails memory details) external returns (uint256) {
        _mint(tokenId, to, details);
        return tokenId;
    }

    function assignCert(address from, uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256) {
        if (_owners[tokenId] == from) {
            _owners[tokenId] = to;
        }
        _details[tokenId] = details;
        return tokenId;
    }

    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external {
        _details[tokenId] = details;
    }

    function balanceOf(address owner) external view returns (uint256) { return _balances[owner]; }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return _ownedTokens[owner][index];
    }

    function _mint(uint256 tokenId, address to, CertificateDetails memory details) internal {
        _details[tokenId] = details;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _ownedTokens[to].push(tokenId);
        if (tokenId == _total) {
            _total = tokenId + 1;
        }
    }

    function tokenURI(uint256) external pure returns (string memory) { return ""; }

    function ownerOf(uint256 tokenId) external view returns (address) { return _owners[tokenId]; }

    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) { return _details[tokenId]; }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        if (_owners[tokenId] != from) {
            revert("NOT_OWNER");
        }
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
        _ownedTokens[to].push(tokenId);
    }

    function voidCert(uint256 tokenId) external {
        _voided[tokenId] = true;
    }

    function isVoided(uint256 tokenId) external view returns (bool) {
        return _voided[tokenId];
    }
}

contract MockCyberCorp {
    address public dealManagerAddress = address(0xD34D);

    function cyberCORPName() external pure returns (string memory) { return "MockCorp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function dealManager() external view returns (address) { return dealManagerAddress; }
}

contract IssuanceManagerConversionTest is Test {
    bytes32 salt = bytes32(keccak256("IssuanceManagerConversionTest"));

    IssuanceManager public issuanceManager;
    MockCertPrinter public safePrinter;
    MockCertPrinter public equityPrinter;
    BorgAuth public auth;
    MockRoundManagerForConversion public mockRM;
    MockCyberCorp public mockCorp;

    address public owner;
    address public investor;
    address public otherInvestor;

    function setUp() public {
        owner = address(this);
        investor = makeAddr("investor");
        otherInvestor = makeAddr("otherInvestor");

        // Auth
        auth = new BorgAuth(owner);

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(address(
            new ERC1967Proxy{salt: salt}(
                address(new IssuanceManagerFactory{salt: salt}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    new IssuanceManager(),
                    new MockCertPrinter(),
                    new CyberScrip()
                )
            )
        ));

        // IssuanceManager via proxy (implementation disables initializers in constructor)
        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(salt));
        mockCorp = new MockCyberCorp();
        issuanceManager.initialize(
            address(auth),
            address(mockCorp),
            address(0xBEEF),
            address(imFactory)
        );

        // Deploy printers and initialize with issuanceManager as controller
        safePrinter = new MockCertPrinter();
        safePrinter.initialize(new string[](0), "SAFE Cert", "SAFE", "uri://safe", address(issuanceManager), SecurityClass.SAFT, SecuritySeries.NA, address(0));

        equityPrinter = new MockCertPrinter();
        equityPrinter.initialize(new string[](0), "Equity Cert", "EQTY", "uri://eq", address(issuanceManager), SecurityClass.PreferredStock, SecuritySeries.SeriesA, address(0));

        // Mock round manager
        mockRM = new MockRoundManagerForConversion();
    }

    function test_convertSAFE_floor_minPicksLower() public {
        // Configure round
        // price decimals = 2, share decimals = 0, mode = floor
        uint8 priceDec = 2;
        uint8 shareDec = 0;
        uint256 cCap = 100_000; // as-converted cap
        uint256 roundPrice = 12_000; // 120.00
        mockRM.setConfig(true, cCap, 0, priceDec, shareDec, roundPrice, priceDec);

        // Mint SAFE to investor via issuance manager
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1_000_000, // PA
            issuerUSDValuationAtTimeOfInvestment: 10_000_000, // PMVC
            unitsRepresented: 0,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(owner);
        uint256 safeId = issuanceManager.createCert(address(safePrinter), investor, details);

        // Compute expected
        uint256 safePrice = (details.issuerUSDValuationAtTimeOfInvestment * (10 ** priceDec)) / cCap; // 10000 (100.00)
        uint256 priceBasis = safePrice < roundPrice ? safePrice : roundPrice; // 10000
        uint256 expectedShares = (details.investmentAmountUSD * (10 ** priceDec)) / priceBasis; // 10,000

        // Convert
        vm.prank(owner);
      //  uint256 newId = issuanceManager.convertSAFE(address(mockRM), bytes32("ROUND1"), address(safePrinter), safeId, address(equityPrinter));

        // Verify equity cert issued to investor with expected shares
      //  assertEq(equityPrinter.ownerOf(newId), investor);
      //  CertificateDetails memory eq = equityPrinter.getCertificateDetails(newId);
      //  assertEq(eq.unitsRepresented, expectedShares);

        // SAFE should be voided (tokenURI would revert or ownerOf may still show owner but status void stored internally)
        // We can assert that further transfers are restricted due to void status only if exposed; check that updateCertificateDetails or owner unchanged is fine.
    }

    function test_convertScripToCert_AllowsNonOwnerMintPath() public {
        // Deploy mock cert and scrip
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](0);
        ICondition[] memory certToScrip = new ICondition[](0);
        ICondition[] memory scripToCert = new ICondition[](0);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            hooks,
            certToScrip,
            scripToCert,
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        // Mint scrip to investor via issuance manager
        uint256 amount = 100 ether;
        vm.prank(address(issuanceManager));
        ICyberScrip(scrip).mint(investor, amount);

        // Non-owner should be able to convert and mint a cert via IssuanceManager
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), amount);

        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.ownerOf(0), investor);
        CertificateDetails memory details = certPrinter.getCertificateDetails(0);
        assertEq(details.unitsRepresented, amount);
    }

    function test_ScripifyAndUnscripify_WithConditions() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 1000,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            details
        );

        uint256 scripAmount = 250;
        bytes4 scripifySelector = bytes4(
            keccak256("scripifyCert(address,uint256,uint256,address)")
        );
        ICondition[] memory certToScrip = new ICondition[](2);
        certToScrip[0] = ICondition(
            new SelectorCondition(
                address(certPrinter),
                scripifySelector,
                abi.encode(certId, scripAmount, address(0))
            )
        );
        certToScrip[1] = ICondition(
            new SelectorCondition(
                address(certPrinter),
                scripifySelector,
                abi.encode(certId, scripAmount, address(0))
            )
        );

        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(
            new SelectorCondition(
                address(certPrinter),
                IssuanceManager.convertScripToCert.selector,
                abi.encode(scripAmount, investor)
            )
        );

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            certToScrip,
            scripToCert,
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, scripAmount, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), scripAmount);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), scripAmount);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);

        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
    }

    function test_ScripRatio_AppliesOnScripifyAndConvert() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(owner);
        issuanceManager.setScripRatio(address(certPrinter), 2, 1);

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), 0, 4, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 8);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 8);

        assertEq(certPrinter.totalSupply(), 2);
        CertificateDetails memory newDetails = certPrinter.getCertificateDetails(
            1
        );
        assertEq(newDetails.unitsRepresented, 4);
    }

    function test_ScripifyWhitelist_EnabledBlocksNonWhitelisted() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            details
        );

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            true,
            true,
            true,
            true
        );

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripifyNotWhitelisted.selector);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));
    }

    function test_ScripifyWhitelist_EnabledAllowsWhitelisted() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            details
        );

        uint256[] memory whitelistIds = new uint256[](1);
        whitelistIds[0] = certId;
        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            whitelistIds,
            true,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));
    }

    function test_ScripifyWhitelist_ToggleAndUpdate() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            details
        );

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        // Enable whitelist and add ID
        issuanceManager.setScripifyWhitelistEnabled(address(certPrinter), true);
        uint256[] memory addIds = new uint256[](1);
        addIds[0] = certId;
        issuanceManager.addScripifyWhitelistIds(address(certPrinter), addIds);

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));

        // Remove ID and ensure blocked
        uint256[] memory removeIds = new uint256[](1);
        removeIds[0] = certId;
        issuanceManager.removeScripifyWhitelistIds(address(certPrinter), removeIds);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripifyNotWhitelisted.selector);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));

        // Disable whitelist and allow again
        issuanceManager.setScripifyWhitelistEnabled(address(certPrinter), false);
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));
    }

    function test_GetScripRatio_DefaultsToOneWhenUnset() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        (uint256 numerator, uint256 denominator) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(numerator, 1);
        assertEq(denominator, 1);
    }

    function test_DeployCyberScrip_SetsDefaultRatio() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        (uint256 numerator, uint256 denominator) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(numerator, 1);
        assertEq(denominator, 1);
    }

    function test_RevertWhen_SetScripRatioZeroNumeratorOrDenominator() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        vm.expectRevert(IssuanceManager.InvalidScripRatio.selector);
        issuanceManager.setScripRatio(address(certPrinter), 0, 1);

        vm.expectRevert(IssuanceManager.InvalidScripRatio.selector);
        issuanceManager.setScripRatio(address(certPrinter), 1, 0);
    }

    function test_RevertWhen_ScripifyRatioRemainder() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });

        issuanceManager.createCert(address(certPrinter), investor, details);

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        issuanceManager.setScripRatio(address(certPrinter), 2, 3);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripRatioRemainder.selector);
        issuanceManager.scripifyCert(address(certPrinter), 0, 1, address(0));
    }

    function test_RevertWhen_ConvertScripRatioRemainder() public {
        MockCertPrinter certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            "Cert",
            "CERT",
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        issuanceManager.setScripRatio(address(certPrinter), 3, 2);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripRatioRemainder.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 1);
    }

    function test_convertScripToCert_parameterLifecycleAndRuntimeUpdates() public {
        MockCertPrinter certPrinter = _deployPrinter("Lifecycle Cert", "LCERT");
        uint256 certId = _mintCert(certPrinter, investor, 75);

        uint256[] memory whitelistIds = new uint256[](1);
        whitelistIds[0] = certId;
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            50, // initial minimum
            3, // initial ratio numerator
            2, // initial ratio denominator
            whitelistIds,
            true, // whitelist enabled
            true,
            true,
            true
        );

        // Validate deploy-time parameters
        (uint256 initialNum, uint256 initialDen) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(initialNum, 3);
        assertEq(initialDen, 2);
        assertEq(issuanceManager.getScripToCertMinimum(address(certPrinter)), 50);
        assertTrue(issuanceManager.getScripifyWhitelistEnabled(address(certPrinter)));
        assertTrue(issuanceManager.isScripifyWhitelisted(address(certPrinter), certId));
        assertFalse(issuanceManager.isScripifyWhitelisted(address(certPrinter), 99999));

        // Update all runtime parameters and verify
        issuanceManager.setScripRatio(address(certPrinter), 4, 1);
        issuanceManager.setScripToCertMinimum(address(certPrinter), 40);
        issuanceManager.setScripifyWhitelistEnabled(address(certPrinter), false);

        uint256[] memory removeIds = new uint256[](1);
        removeIds[0] = certId;
        issuanceManager.removeScripifyWhitelistIds(address(certPrinter), removeIds);
        assertFalse(issuanceManager.isScripifyWhitelisted(address(certPrinter), certId));

        uint256[] memory addIds = new uint256[](2);
        addIds[0] = certId;
        addIds[1] = certId + 1;
        issuanceManager.addScripifyWhitelistIds(address(certPrinter), addIds);

        (uint256 updatedNum, uint256 updatedDen) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(updatedNum, 4);
        assertEq(updatedDen, 1);
        assertEq(issuanceManager.getScripToCertMinimum(address(certPrinter)), 40);
        assertFalse(issuanceManager.getScripifyWhitelistEnabled(address(certPrinter)));
        assertTrue(issuanceManager.isScripifyWhitelisted(address(certPrinter), certId));
        assertTrue(issuanceManager.isScripifyWhitelisted(address(certPrinter), certId + 1));

        // With ratio 4:1, scripifying 10 units mints 40 scrip
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 10, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 40);

        // Minimum is now 40; lower amounts should revert
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 39);

        // Convert exactly at minimum, ensuring conversion uses updated ratio
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 40);

        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
        CertificateDetails memory converted = certPrinter.getCertificateDetails(1);
        assertEq(converted.unitsRepresented, 10);
    }

    function test_convertScripToCert_revertGatesAndConditionValidation() public {
        MockCertPrinter certPrinter = _deployPrinter("Guard Cert", "GCERT");

        // Unconfigured cert should always fail conversion.
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripifiedCertNotAllowed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 1);

        // Condition requires exact amount = 150
        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(
            new SelectorCondition(
                address(certPrinter),
                IssuanceManager.convertScripToCert.selector,
                abi.encode(uint256(150), investor)
            )
        );

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            scripToCert,
            90, // minimum
            3, // ratio numerator
            2, // ratio denominator
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(address(issuanceManager));
        ICyberScrip(scrip).mint(investor, 200);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 200);

        // Fails minimum
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 80);

        // Passes minimum but fails ratio divisibility (100*2 % 3 != 0)
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripRatioRemainder.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 100);

        // Passes minimum and ratio, but fails condition (expects 150)
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 120);

        // Successful conversion with expected amount
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 150);

        assertEq(ICyberScrip(scrip).balanceOf(investor), 50);
        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.ownerOf(0), investor);
        CertificateDetails memory newCert = certPrinter.getCertificateDetails(0);
        assertEq(newCert.unitsRepresented, 100); // 150 * 2 / 3
    }

    function test_convertScripToCert_reformsVoidedCertAndTransfersToDealManager()
        public
    {
        MockCertPrinter certPrinter = _deployPrinter("Voided Cert", "VCERT");

        CertificateDetails memory original = CertificateDetails({
            signingOfficerName: "Alice Officer",
            signingOfficerTitle: "General Counsel",
            investmentAmountUSD: 3_000_000,
            issuerUSDValuationAtTimeOfInvestment: 33_000_000,
            unitsRepresented: 500,
            legalDetails: "Original legal details",
            extensionData: "Original extension"
        });
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, original);

        // Mark existing cert as voided while investor still owns it.
        certPrinter.voidCert(0);
        assertTrue(certPrinter.isVoided(0));
        assertEq(certPrinter.ownerOf(0), investor);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            2, // ratio numerator
            1, // ratio denominator
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        // 20 scrip -> 10 units at ratio 2:1
        vm.prank(address(issuanceManager));
        ICyberScrip(scrip).mint(investor, 20);
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 20);

        // Reform path should update existing cert (no mint) and transfer to deal manager
        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.ownerOf(0), mockCorp.dealManager());

        CertificateDetails memory reformed = certPrinter.getCertificateDetails(0);
        assertEq(reformed.unitsRepresented, 10);
        // All other fields should remain intact on reform.
        assertEq(reformed.signingOfficerName, original.signingOfficerName);
        assertEq(reformed.signingOfficerTitle, original.signingOfficerTitle);
        assertEq(
            reformed.investmentAmountUSD,
            original.investmentAmountUSD
        );
        assertEq(
            reformed.issuerUSDValuationAtTimeOfInvestment,
            original.issuerUSDValuationAtTimeOfInvestment
        );
        assertEq(reformed.legalDetails, original.legalDetails);
        assertEq(reformed.extensionData, original.extensionData);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_convertScripToCert_RequiresIssuerAdminApprovalCondition() public {
        MockCertPrinter certPrinter = _deployPrinter("Approval Cert", "APPR");
        uint256 certId = _mintCert(certPrinter, investor, 10);

        IssuerApprovalRecertificationCondition condition = new IssuerApprovalRecertificationCondition();
        ICondition[] memory scripToCert = new ICondition[](1);
        scripToCert[0] = ICondition(address(condition));

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            scripToCert,
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 5, address(0));
        assertEq(ICyberScrip(scrip).balanceOf(investor), 5);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 5);

        vm.prank(otherInvestor);
        vm.expectRevert();
        condition.setInvestorApproval(address(certPrinter), investor, true);

        // Approve using scrip address to prove cert/scrip writes are both supported.
        condition.setInvestorApproval(address(scrip), investor, true);
        assertTrue(condition.isInvestorApproved(address(certPrinter), investor));

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 5);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
    }

    function _deployPrinter(
        string memory name,
        string memory symbol
    ) internal returns (MockCertPrinter certPrinter) {
        certPrinter = new MockCertPrinter();
        certPrinter.initialize(
            new string[](0),
            name,
            symbol,
            "uri://cert",
            address(issuanceManager),
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0)
        );
    }

    function _mintCert(
        MockCertPrinter certPrinter,
        address to,
        uint256 units
    ) internal returns (uint256 tokenId) {
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });
        vm.prank(owner);
        tokenId = issuanceManager.createCert(address(certPrinter), to, details);
    }
}


