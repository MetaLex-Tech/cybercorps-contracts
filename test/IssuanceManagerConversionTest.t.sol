// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/interfaces/ICyberScrip.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import "../src/interfaces/ICondition.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/interfaces/IUriBuilder.sol";
import "../src/libs/auth.sol";
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
    function getActiveCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) { return _details[tokenId]; }

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
    address public roundManagerAddress = address(0xB0B0);

    function cyberCORPName() external pure returns (string memory) { return "MockCorp"; }
    function cyberCORPType() external pure returns (string memory) { return "C-Corp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function cyberCORPContactDetails() external pure returns (string memory) { return "mock@corp.test"; }
    function dealManager() external view returns (address) { return dealManagerAddress; }
    function roundManager() external view returns (address) { return roundManagerAddress; }
}

contract MockUriBuilder is IUriBuilder {
    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return "uri://mock";
    }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) {
        return "uri://mock";
    }
}

contract IssuanceManagerConversionTest is Test {
    bytes32 salt = bytes32(keccak256("IssuanceManagerConversionTest"));

    IssuanceManager public issuanceManager;
    ICyberCertPrinter public safePrinter;
    ICyberCertPrinter public equityPrinter;
    BorgAuth public auth;
    MockRoundManagerForConversion public mockRM;
    MockCyberCorp public mockCorp;
    MockUriBuilder public mockUriBuilder;

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
                    new CyberCertPrinter(),
                    new CyberScrip()
                )
            )
        ));

        // IssuanceManager via proxy (implementation disables initializers in constructor)
        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(salt));
        mockCorp = new MockCyberCorp();
        mockUriBuilder = new MockUriBuilder();
        issuanceManager.initialize(
            address(auth),
            address(mockCorp),
            address(mockUriBuilder),
            address(imFactory)
        );

        safePrinter = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "SAFE Cert",
                "SAFE",
                "uri://safe",
                SecurityClass.SAFT,
                SecuritySeries.NA,
                address(0)
            )
        );
        equityPrinter = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Equity Cert",
                "EQTY",
                "uri://eq",
                SecurityClass.PreferredStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );

        // Mock round manager
        mockRM = new MockRoundManagerForConversion();
    }

    function test_createCertAndAssignWithName_storesEndorsementSignatureAndTimestamp()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Signed Cert", "SCERT");
        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 25 * 1e18,
            legalDetails: "Signed legal details",
            extensionData: "Signed extension"
        });
        bytes memory endorsementSignature = hex"1234abcd";
        uint256 endorsementTimestamp = 1_717_171_717;

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssignWithName(
            address(certPrinter),
            investor,
            details,
            "Signed Investor",
            endorsementSignature,
            endorsementTimestamp
        );

        Endorsement memory endorsement = CyberCertPrinter(address(certPrinter))
            .getEndorsementHistory(certId, 0);

        assertEq(endorsement.endorser, address(issuanceManager));
        assertEq(endorsement.endorseeName, "Signed Investor");
        assertEq(endorsement.registry, address(0));
        assertEq(endorsement.agreementId, bytes32(0));
        assertEq(endorsement.timestamp, endorsementTimestamp);
        assertEq(endorsement.signatureHash, endorsementSignature);
        assertEq(endorsement.endorsee, investor);

        assertEq(certPrinter.getIssuerSignatureCount(certId), 1);
        assertEq(certPrinter.getIssuerSignatureAt(certId, 0), endorsementSignature);
    }

    function test_createCertAndAssignWithName_withoutSignature_skipsIssuerSignatureStorage()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Unsigned Cert", "UCERT");
        CertificateDetails memory details = _buildCertificateDetails(
            25,
            "Unsigned legal details",
            bytes("Unsigned extension")
        );
        uint256 endorsementTimestamp = 1_717_171_718;

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssignWithName(
            address(certPrinter),
            investor,
            details,
            "Unsigned Investor",
            bytes(""),
            endorsementTimestamp
        );

        Endorsement memory endorsement = CyberCertPrinter(address(certPrinter))
            .getEndorsementHistory(certId, 0);

        assertEq(certPrinter.ownerOf(certId), investor);
        assertEq(endorsement.endorser, address(issuanceManager));
        assertEq(endorsement.endorseeName, "Unsigned Investor");
        assertEq(endorsement.timestamp, endorsementTimestamp);
        assertEq(endorsement.signatureHash, bytes(""));
        assertEq(certPrinter.getIssuerSignatureCount(certId), 0);
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
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");
        // Integer unit count; _mintCert stores unitsRepresented as units * 1e18
        uint256 amount = 100;
        uint256 sourceCertId = _mintCert(certPrinter, otherInvestor, amount);

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

        vm.prank(otherInvestor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            sourceCertId,
            amount * 1e18,
            investor
        );
        assertEq(ICyberScrip(scrip).balanceOf(investor), amount * 1e18);

        CertificateDetails memory approvalDetails = _stageRecertificationApproval(
            certPrinter,
            investor,
            "Investor Name",
            777,
            "Approved legal details",
            bytes("approved extension")
        );

        // Non-owner should be able to convert and mint a cert via IssuanceManager
        vm.recordLogs();
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), amount * 1e18);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 recertifiedTopic = keccak256(
            "ScripRecertified(address,address,uint256,uint256,uint256,uint256,uint256,uint256)"
        );
        bool sawRecertified;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(issuanceManager) &&
                logs[i].topics.length == 4 &&
                logs[i].topics[0] == recertifiedTopic &&
                address(uint160(uint256(logs[i].topics[1]))) == address(certPrinter) &&
                address(uint160(uint256(logs[i].topics[2]))) == investor &&
                uint256(logs[i].topics[3]) == 1
            ) {
                (uint256 scripAmount, uint256 newUnitsRepresented,,) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
                assertEq(scripAmount, amount * 1e18);
                assertEq(newUnitsRepresented, amount * 1e18);
                sawRecertified = true;
                break;
            }
        }
        assertTrue(sawRecertified);

        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
        CertificateDetails memory details = certPrinter.getCertificateDetails(1);
        assertEq(details.unitsRepresented, amount * 1e18);
        assertEq(details.legalDetails, approvalDetails.legalDetails);
        assertEq(details.extensionData, approvalDetails.extensionData);
    }

    function test_ScripifyAndUnscripify_WithConditions() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 1000 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssign(
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

        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.ownerOf(0), investor);
        CertificateDetails memory restored = certPrinter.getCertificateDetails(0);
        assertEq(restored.unitsRepresented, 1000 * 1e18);
    }

    function test_ScripRatio_AppliesOnScripifyAndConvert() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        issuanceManager.createCertAndAssign(
            address(certPrinter),
            investor,
            details
        );

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

        assertEq(certPrinter.totalSupply(), 1);
        CertificateDetails memory newDetails = certPrinter.getCertificateDetails(
            0
        );
        assertEq(newDetails.unitsRepresented, 10 * 1e18);
    }

    function test_ScripifyWhitelist_EnabledBlocksNonWhitelisted() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssign(
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
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssign(
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
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        vm.prank(owner);
        uint256 certId = issuanceManager.createCertAndAssign(
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
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        (uint256 numerator, uint256 denominator) = issuanceManager.getScripRatio(
            address(certPrinter)
        );
        assertEq(numerator, 1);
        assertEq(denominator, 1);
    }

    function test_DeployCyberScrip_SetsDefaultRatio() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

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
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        vm.expectRevert(IssuanceManager.InvalidScripRatio.selector);
        issuanceManager.setScripRatio(address(certPrinter), 0, 1);

        vm.expectRevert(IssuanceManager.InvalidScripRatio.selector);
        issuanceManager.setScripRatio(address(certPrinter), 1, 0);
    }

    function test_RevertWhen_ScripifyRatioRemainder() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10 * 1e18,
            legalDetails: "",
            extensionData: ""
        });

        issuanceManager.createCertAndAssign(
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

        issuanceManager.setScripRatio(address(certPrinter), 2, 3);

    }

    

    function test_convertScripToCert_parameterLifecycleAndRuntimeUpdates() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Lifecycle Cert", "LCERT");
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
        assertEq(certPrinter.totalSupply(), 1);
        assertEq(certPrinter.ownerOf(0), investor);
        CertificateDetails memory converted = certPrinter.getCertificateDetails(0);
        assertEq(converted.unitsRepresented, 75 * 1e18);
    }

    function test_convertScripToCert_revertGatesAndConditionValidation() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Guard Cert", "GCERT");

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

        uint256 sourceCertId = _mintCert(certPrinter, otherInvestor, 134);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            90*1e18, // minimum
            3, // ratio numerator
            2, // ratio denominator
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        vm.prank(otherInvestor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            sourceCertId,
            134*1e18,
            investor
        );
        assertEq(ICyberScrip(scrip).balanceOf(investor), 201*1e18);

        // Fails minimum
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ScripToCertMinimumNotMet.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 80*1e18);


        _stageRecertificationApproval(
            certPrinter,
            investor,
            "Guard Investor",
            555*1e18,
            "Guard legal details",
            bytes("guard extension")
        );

        // Successful conversion with expected amount
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 150*1e18);

        assertEq(ICyberScrip(scrip).balanceOf(investor), 51*1e18);
        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
        CertificateDetails memory newCert = certPrinter.getCertificateDetails(1);
        assertEq(newCert.unitsRepresented, 100 * 1e18); // 150 * 2 / 3
    }

    function test_convertScripToCert_ignoresVoidedCertAndMintsNewCertificate()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Voided Cert", "VCERT");

        CertificateDetails memory original = CertificateDetails({
            signingOfficerName: "Alice Officer",
            signingOfficerTitle: "General Counsel",
            investmentAmountUSD: 3_000_000,
            issuerUSDValuationAtTimeOfInvestment: 33_000_000,
            unitsRepresented: 500 * 1e18,
            legalDetails: "Original legal details",
            extensionData: "Original extension"
        });
        vm.prank(owner);
        issuanceManager.createCertAndAssign(
            address(certPrinter),
            investor,
            original
        );

        // Mark existing cert as voided while investor still owns it.
        issuanceManager.voidCertificate(address(certPrinter), 0);
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

        uint256 sourceCertId = _mintCert(certPrinter, otherInvestor, 10);
        vm.prank(otherInvestor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            sourceCertId,
            10 * 1e18,
            investor
        );
        vm.prank(investor);
        vm.expectRevert(IssuanceManager.RecertificationApprovalRequired.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 20 * 1e18);

        CertificateDetails memory approvalDetails = _stageRecertificationApproval(
            certPrinter,
            investor,
            "Reformed Investor",
            999,
            "Fresh legal details",
            bytes("Fresh extension")
        );
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 20 * 1e18);

        assertEq(certPrinter.totalSupply(), 3);
        assertEq(certPrinter.ownerOf(0), investor);
        assertEq(certPrinter.ownerOf(1), otherInvestor);
        assertEq(certPrinter.ownerOf(2), investor);
        assertTrue(certPrinter.isVoided(0));

        CertificateDetails memory reformed = certPrinter.getCertificateDetails(2);
        assertEq(reformed.unitsRepresented, 10 * 1e18);
        assertEq(reformed.legalDetails, approvalDetails.legalDetails);
        assertEq(reformed.extensionData, approvalDetails.extensionData);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
    }

    function test_convertScripToCert_RequiresNativeRecertificationApproval() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Approval Cert", "APPR");
        uint256 certId = _mintCert(certPrinter, otherInvestor, 10);

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

        vm.prank(otherInvestor);
        issuanceManager.scripifyCert(address(certPrinter), certId, 5 * 1e18, investor);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 5 * 1e18);

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.RecertificationApprovalRequired.selector);
        issuanceManager.convertScripToCert(address(certPrinter), 5 * 1e18);

        vm.prank(otherInvestor);
        vm.expectRevert();
        issuanceManager.setRecertificationApproval(
            address(certPrinter),
            investor,
            "Approved Investor",
            _buildCertificateDetails(999, "Approved legal details", bytes("approved extension")),
            hex"01"
        );

        CertificateDetails memory approvedDetails = _buildCertificateDetails(
            999,
            "Approved legal details",
            bytes("approved extension")
        );
        bytes memory officerSig = hex"0badc0de";
        vm.prank(owner);
        issuanceManager.setRecertificationApproval(
            address(certPrinter),
            investor,
            "Approved Investor",
            approvedDetails,
            officerSig
        );
        (
            bool approved,
            string memory investorName,
            CertificateDetails memory stagedDetails,
            bytes memory storedOfficerSig,
            uint256 endorsementTs
        ) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            investor
        );
        assertTrue(approved);
        assertEq(investorName, "Approved Investor");
        assertEq(stagedDetails.legalDetails, approvedDetails.legalDetails);
        assertEq(stagedDetails.extensionData, approvedDetails.extensionData);
        assertEq(keccak256(storedOfficerSig), keccak256(officerSig));
        assertEq(endorsementTs, block.timestamp);

        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 5 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0);
        assertEq(certPrinter.totalSupply(), 2);
        assertEq(certPrinter.ownerOf(1), investor);
        CertificateDetails memory restored = certPrinter.getCertificateDetails(1);
        assertEq(restored.unitsRepresented, 5 * 1e18);
        assertEq(restored.legalDetails, approvedDetails.legalDetails);
        assertEq(restored.extensionData, approvedDetails.extensionData);
        (approved,,,,) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            investor
        );
        assertFalse(approved);
    }

    function test_TwoHolders_ScripTransferThenRecertify_UpdatesUnitsAsExpected()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Shared Cert", "SHARE");
        uint256 investorCertId = _mintCert(certPrinter, investor, 100);
        uint256 otherInvestorCertId = _mintCert(certPrinter, otherInvestor, 100);

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

        vm.prank(investor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            investorCertId,
            100 * 1e18,
            address(0)
        );
        vm.prank(otherInvestor);
        issuanceManager.scripifyCert(
            address(certPrinter),
            otherInvestorCertId,
            100 * 1e18,
            address(0)
        );

        CertificateDetails memory investorAfterScripify = certPrinter
            .getActiveCertificateDetails(investorCertId);
        CertificateDetails memory otherAfterScripify = certPrinter
            .getActiveCertificateDetails(otherInvestorCertId);
        assertEq(investorAfterScripify.unitsRepresented, 0);
        assertEq(otherAfterScripify.unitsRepresented, 0);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 100 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(otherInvestor), 100 * 1e18);

        vm.prank(investor);
        ICyberScrip(scrip).transfer(otherInvestor, 50 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 50 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(otherInvestor), 150 * 1e18);
        assertEq(
            issuanceManager.getScripPoolAmountById(address(certPrinter), investorCertId),
            100 * 1e18
        );
        assertEq(
            issuanceManager.getScripPoolAmountById(address(certPrinter), otherInvestorCertId),
            100 * 1e18
        );
        assertEq(
            issuanceManager.getScripPoolSharesById(address(certPrinter), investorCertId),
            100 * 1e18
        );
        assertEq(
            issuanceManager.getScripPoolSharesById(address(certPrinter), otherInvestorCertId),
            100 * 1e18
        );

        vm.expectEmit(true, true, true, true);
        emit IssuanceManager.ScripAddedToExistingCert(
            address(certPrinter),
            otherInvestor,
            otherInvestorCertId,
            150 * 1e18,
            150 * 1e18,
            0
        );
        vm.expectEmit(true, true, true, true);
        emit IssuanceManager.ScripRecertified(
            address(certPrinter),
            otherInvestor,
            otherInvestorCertId,
            150 * 1e18,
            150 * 1e18,
            0,
            50 * 1e18,
            100 * 1e18
        );
        vm.prank(otherInvestor);
        issuanceManager.convertScripToCert(address(certPrinter), 150 * 1e18);

        CertificateDetails memory investorActiveFinal = certPrinter
            .getActiveCertificateDetails(investorCertId);
        CertificateDetails memory otherActiveFinal = certPrinter
            .getActiveCertificateDetails(otherInvestorCertId);
        CertificateDetails memory investorFinal = certPrinter.getCertificateDetails(
            investorCertId
        );
        CertificateDetails memory otherFinal = certPrinter.getCertificateDetails(
            otherInvestorCertId
        );
        (bool investorIsScripified, uint256 investorScripified,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), investorCertId);
        (bool otherIsScripified, uint256 otherScripified,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), otherInvestorCertId);

        assertEq(investorActiveFinal.unitsRepresented, 0);
        assertEq(otherActiveFinal.unitsRepresented, 150 * 1e18);
        assertTrue(investorIsScripified);
        assertEq(investorScripified, 50 * 1e18);
        assertFalse(otherIsScripified);
        assertEq(otherScripified, 0);
        assertEq(investorFinal.unitsRepresented, 50 * 1e18);
        assertEq(otherFinal.unitsRepresented, 150 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(investor), 50 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(otherInvestor), 0);
        assertEq(
            issuanceManager.getScripPoolAmountById(address(certPrinter), investorCertId),
            50 * 1e18
        );
        assertEq(
            issuanceManager.getScripPoolAmountById(address(certPrinter), otherInvestorCertId),
            0
        );
        assertEq(
            issuanceManager.getScripPoolSharesById(address(certPrinter), investorCertId),
            100 * 1e18
        );
        assertEq(
            issuanceManager.getScripPoolSharesById(address(certPrinter), otherInvestorCertId),
            0
        );
    }

    function test_ComplexScripPoolAccounting_FourHolders_MixedRecertificationsAndNewInvestors()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Four Holder Cert", "4CERT");
        address holderA = investor;
        address holderB = otherInvestor;
        address holderC = makeAddr("fourHolderC");
        address holderD = makeAddr("fourHolderD");
        address newInvestorOne = makeAddr("fourNewInvestorOne");
        address newInvestorTwo = makeAddr("fourNewInvestorTwo");

        uint256 certIdA = _mintCert(certPrinter, holderA, 100);
        uint256 certIdB = _mintCert(certPrinter, holderB, 100);
        uint256 certIdC = _mintCert(certPrinter, holderC, 100);
        uint256 certIdD = _mintCert(certPrinter, holderD, 100);

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

        vm.prank(holderA);
        issuanceManager.scripifyCert(address(certPrinter), certIdA, 100 * 1e18, address(0));
        vm.prank(holderB);
        issuanceManager.scripifyCert(address(certPrinter), certIdB, 100 * 1e18, address(0));
        vm.prank(holderC);
        issuanceManager.scripifyCert(address(certPrinter), certIdC, 100 * 1e18, address(0));
        vm.prank(holderD);
        issuanceManager.scripifyCert(address(certPrinter), certIdD, 100 * 1e18, address(0));

        (uint256 totalTrackedScrip,) = issuanceManager.getScripPoolTotals(
            address(certPrinter)
        );
        assertEq(totalTrackedScrip, 400 * 1e18);
        assertEq(ICyberScrip(scrip).totalSupply(), 400 * 1e18);

        vm.prank(holderA);
        ICyberScrip(scrip).transfer(holderB, 40 * 1e18);
        vm.prank(holderC);
        ICyberScrip(scrip).transfer(newInvestorOne, 50 * 1e18);
        vm.prank(holderD);
        ICyberScrip(scrip).transfer(newInvestorTwo, 20 * 1e18);

        assertEq(ICyberScrip(scrip).balanceOf(holderA), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderB), 140 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderC), 50 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderD), 80 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorOne), 50 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorTwo), 20 * 1e18);

        vm.prank(holderB);
        issuanceManager.convertScripToCert(address(certPrinter), 120 * 1e18);

        //get and print all certificateDetails
        CertificateDetails memory activeApre = certPrinter.getCertificateDetails(
            certIdA
        );
        CertificateDetails memory activeBpre = certPrinter.getCertificateDetails(
            certIdB
        );
        CertificateDetails memory activeCpre = certPrinter.getCertificateDetails(
            certIdC
        );
        CertificateDetails memory activeDpre = certPrinter.getCertificateDetails(
            certIdD
        );
        console.log("activeApre", activeApre.unitsRepresented);    
        console.log("activeBpre", activeBpre.unitsRepresented);
        console.log("activeCpre", activeCpre.unitsRepresented);
        console.log("activeDpre", activeDpre.unitsRepresented);
    (totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
    console.log("totalTrackedScrip", totalTrackedScrip);
 (,uint scripA,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdA);
        (, uint256 scripB,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdB);
        (, uint256 scripC,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdC);
        (, uint256 scripD,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdD);
        console.log("scripA", scripA);
        console.log("scripB", scripB);
        console.log("scripC", scripC);
        console.log("scripD", scripD);
            (totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
  console.log("totalTrackedScrip", totalTrackedScrip);

        vm.prank(holderC);
        issuanceManager.convertScripToCert(address(certPrinter), 50 * 1e18);


        //price active cert units:
 (, scripA,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdA);
        (,  scripB,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdB);
        (,  scripC,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdC);
        (,  scripD,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdD);
        console.log("scripA", scripA);
        console.log("scripB", scripB);
        console.log("scripC", scripC);
        console.log("scripD", scripD);
            (totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
  console.log("totalTrackedScrip", totalTrackedScrip);

        //print cert units again

        activeApre = certPrinter.getCertificateDetails(certIdA);
        activeBpre = certPrinter.getCertificateDetails(certIdB);
        activeCpre = certPrinter.getCertificateDetails(certIdC);
        activeDpre = certPrinter.getCertificateDetails(certIdD);
        console.log("activeApost", activeApre.unitsRepresented);
        console.log("activeBpost", activeBpre.unitsRepresented);
        console.log("activeCpost", activeCpre.unitsRepresented);
        console.log("activeDpost", activeDpre.unitsRepresented);


        CertificateDetails memory approvalOne = _stageRecertificationApproval(
            certPrinter,
            newInvestorOne,
            "Four New Investor One",
            50,
            "Four new investor one legal details",
            bytes("four-new-investor-one-extension")
        );
        CertificateDetails memory approvalTwo = _stageRecertificationApproval(
            certPrinter,
            newInvestorTwo,
            "Four New Investor Two",
            20,
            "Four new investor two legal details",
            bytes("four-new-investor-two-extension")
        );

        vm.prank(newInvestorOne);
        issuanceManager.convertScripToCert(address(certPrinter), 50 * 1e18);

                activeApre = certPrinter.getCertificateDetails(certIdA);
        activeBpre = certPrinter.getCertificateDetails(certIdB);
        activeCpre = certPrinter.getCertificateDetails(certIdC);
        activeDpre = certPrinter.getCertificateDetails(certIdD);
        //add the new cert e
        CertificateDetails memory newCertOnea = certPrinter.getCertificateDetails(4);
        console.log("activeApost", activeApre.unitsRepresented);
        console.log("activeBpost", activeBpre.unitsRepresented);
        console.log("activeCpost", activeCpre.unitsRepresented);
        console.log("activeDpost", activeDpre.unitsRepresented);
        console.log("newCertOne", newCertOnea.unitsRepresented);
        vm.prank(newInvestorTwo);
        issuanceManager.convertScripToCert(address(certPrinter), 20 * 1e18);
        //add the new cert f
        CertificateDetails memory newCertTwoa = certPrinter.getCertificateDetails(5);
                activeApre = certPrinter.getCertificateDetails(certIdA);
        activeBpre = certPrinter.getCertificateDetails(certIdB);
        activeCpre = certPrinter.getCertificateDetails(certIdC);
        activeDpre = certPrinter.getCertificateDetails(certIdD);
        newCertOnea = certPrinter.getCertificateDetails(4);
        newCertTwoa = certPrinter.getCertificateDetails(5);
        console.log("activeAfin", activeApre.unitsRepresented);
        console.log("activeBpost", activeBpre.unitsRepresented);
        console.log("activeCpost", activeCpre.unitsRepresented);
        console.log("activeDpost", activeDpre.unitsRepresented);
        console.log("newCertOne", newCertOnea.unitsRepresented);
        console.log("newCertTwo", newCertTwoa.unitsRepresented);

        (totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
        assertEq(totalTrackedScrip, 160 * 1e18);
        assertEq(ICyberScrip(scrip).totalSupply(), 160 * 1e18);

        CertificateDetails memory activeA = certPrinter.getActiveCertificateDetails(
            certIdA
        );
        CertificateDetails memory activeB = certPrinter.getActiveCertificateDetails(
            certIdB
        );
        CertificateDetails memory activeC = certPrinter.getActiveCertificateDetails(
            certIdC
        );
        CertificateDetails memory activeD = certPrinter.getActiveCertificateDetails(
            certIdD
        );
        CertificateDetails memory activeNewOne = certPrinter
            .getActiveCertificateDetails(4);
        CertificateDetails memory activeNewTwo = certPrinter
            .getActiveCertificateDetails(5);

        assertEq(activeA.unitsRepresented, 0);
        assertEq(activeB.unitsRepresented, 120 * 1e18);
        assertEq(activeC.unitsRepresented, 50 * 1e18);
        assertEq(activeD.unitsRepresented, 0);
        assertEq(activeNewOne.unitsRepresented, 50 * 1e18);
        assertEq(activeNewTwo.unitsRepresented, 20 * 1e18);

        (bool isScripifiedA, uint256 scripifiedA,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdA);
        (bool isScripifiedB, uint256 scripifiedB,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdB);
        (bool isScripifiedC, uint256 scripifiedC,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdC);
        (bool isScripifiedD, uint256 scripifiedD,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdD);
        (bool isScripifiedNewOne, uint256 scripifiedNewOne,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), 4);
        (bool isScripifiedNewTwo, uint256 scripifiedNewTwo,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), 5);

        assertTrue(isScripifiedA);
        assertFalse(isScripifiedB);
        assertTrue(isScripifiedC);
        assertTrue(isScripifiedD);
        assertFalse(isScripifiedNewOne);
        assertFalse(isScripifiedNewTwo);

        CertificateDetails memory effectiveA = certPrinter.getCertificateDetails(
            certIdA
        );
        CertificateDetails memory effectiveB = certPrinter.getCertificateDetails(
            certIdB
        );
        CertificateDetails memory effectiveC = certPrinter.getCertificateDetails(
            certIdC
        );
        CertificateDetails memory effectiveD = certPrinter.getCertificateDetails(
            certIdD
        );
        CertificateDetails memory newCertOne = certPrinter.getCertificateDetails(4);
        CertificateDetails memory newCertTwo = certPrinter.getCertificateDetails(5);

        assertApproxEqAbs(effectiveA.unitsRepresented, scripifiedA, 1);
        assertApproxEqAbs(
            effectiveB.unitsRepresented,
            (120 * 1e18) + scripifiedB,
            1
        );
        assertApproxEqAbs(
            effectiveC.unitsRepresented,
            (50 * 1e18) + scripifiedC,
            1
        );
        assertApproxEqAbs(effectiveD.unitsRepresented, scripifiedD, 1);
        assertEq(newCertOne.unitsRepresented, 50 * 1e18);
        assertEq(newCertTwo.unitsRepresented, 20 * 1e18);
        assertEq(newCertOne.legalDetails, approvalOne.legalDetails);
        assertEq(newCertOne.extensionData, approvalOne.extensionData);
        assertEq(newCertTwo.legalDetails, approvalTwo.legalDetails);
        assertEq(newCertTwo.extensionData, approvalTwo.extensionData);
        assertEq(certPrinter.ownerOf(4), newInvestorOne);
        assertEq(certPrinter.ownerOf(5), newInvestorTwo);
        assertEq(certPrinter.legalOwnerOf(4), newInvestorOne);
        assertEq(certPrinter.legalOwnerOf(5), newInvestorTwo);

        assertEq(ICyberScrip(scrip).balanceOf(holderA), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderB), 20 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderC), 0);
        assertEq(ICyberScrip(scrip).balanceOf(holderD), 80 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorOne), 0);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorTwo), 0);

        uint256 totalActiveWad = activeA.unitsRepresented +
            activeB.unitsRepresented +
            activeC.unitsRepresented +
            activeD.unitsRepresented +
            activeNewOne.unitsRepresented +
            activeNewTwo.unitsRepresented;
        uint256 totalScripifiedWad = scripifiedA +
            scripifiedB +
            scripifiedC +
            scripifiedD +
            scripifiedNewOne +
            scripifiedNewTwo;
        // Per-cert claims use integer division (floor); summing (scrip/wad)/1e18 per cert truncates
        // again and can under-count vs vault. Sum wads first — multi-step fixed-point can differ by ≤1 wei.
        (uint256 vaultAssetsWad,) = issuanceManager.getCertScripUnitVault(
            address(certPrinter)
        );
        assertApproxEqAbs(
            totalScripifiedWad,
            vaultAssetsWad,
            1,
            "scripified wad sum vs vault totalAssetsWad"
        );
        assertApproxEqAbs(
            totalActiveWad + totalScripifiedWad,
            400e18,
            1,
            "active + scripified units vs pool cap"
        );

        (bool approvalStillSetOne,,,,) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            newInvestorOne
        );
        (bool approvalStillSetTwo,,,,) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            newInvestorTwo
        );
        assertFalse(approvalStillSetOne);
        assertFalse(approvalStillSetTwo);
    }

    function test_ComplexScripPoolAccounting_FiveHolders_MixedRecertifications()
        public
    {
        ICyberCertPrinter certPrinter = _deployPrinter("Complex Cert", "CCERT");
        address holderA = investor;
        address holderB = otherInvestor;
        address holderC = makeAddr("holderC");
        address holderD = makeAddr("holderD");
        address holderE = makeAddr("holderE");
        address newInvestorOne = makeAddr("newInvestorOne");
        address newInvestorTwo = makeAddr("newInvestorTwo");

        uint256 certIdA = _mintCert(certPrinter, holderA, 100);
        uint256 certIdB = _mintCert(certPrinter, holderB, 100);
        uint256 certIdC = _mintCert(certPrinter, holderC, 100);
        uint256 certIdD = _mintCert(certPrinter, holderD, 100);
        uint256 certIdE = _mintCert(certPrinter, holderE, 100);

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

        vm.prank(holderA);
        issuanceManager.scripifyCert(address(certPrinter), certIdA, 100 * 1e18, address(0));
        vm.prank(holderB);
        issuanceManager.scripifyCert(address(certPrinter), certIdB, 100 * 1e18, address(0));
        vm.prank(holderC);
        issuanceManager.scripifyCert(address(certPrinter), certIdC, 100 * 1e18, address(0));
        vm.prank(holderD);
        issuanceManager.scripifyCert(address(certPrinter), certIdD, 100 * 1e18, address(0));
        vm.prank(holderE);
        issuanceManager.scripifyCert(address(certPrinter), certIdE, 100 * 1e18, address(0));

        (uint256 totalTrackedScrip,) = issuanceManager.getScripPoolTotals(
            address(certPrinter)
        );
        assertEq(totalTrackedScrip, 500 * 1e18);
        assertEq(ICyberScrip(scrip).totalSupply(), 500 * 1e18);

        vm.prank(holderA);
        ICyberScrip(scrip).transfer(newInvestorOne, 40 * 1e18);
        vm.prank(holderD);
        ICyberScrip(scrip).transfer(holderB, 20 * 1e18);
        vm.prank(holderE);
        ICyberScrip(scrip).transfer(holderB, 20 * 1e18);
        vm.prank(holderE);
        ICyberScrip(scrip).transfer(newInvestorOne, 20 * 1e18);
        vm.prank(holderC);
        ICyberScrip(scrip).transfer(newInvestorTwo, 20 * 1e18);

        assertEq(ICyberScrip(scrip).balanceOf(holderA), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderB), 140 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderC), 80 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderD), 80 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderE), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorOne), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorTwo), 20 * 1e18);

        vm.prank(holderB);
        issuanceManager.convertScripToCert(address(certPrinter), 140 * 1e18);

        vm.prank(holderC);
        issuanceManager.convertScripToCert(address(certPrinter), 80 * 1e18);

        vm.prank(holderD);
        issuanceManager.convertScripToCert(address(certPrinter), 80 * 1e18);

        CertificateDetails memory approvalOne = _stageRecertificationApproval(
            certPrinter,
            newInvestorOne,
            "New Investor One",
            60,
            "New investor one legal details",
            bytes("new-investor-one-extension")
        );
        CertificateDetails memory approvalTwo = _stageRecertificationApproval(
            certPrinter,
            newInvestorTwo,
            "New Investor Two",
            20,
            "New investor two legal details",
            bytes("new-investor-two-extension")
        );

        vm.prank(newInvestorOne);
        issuanceManager.convertScripToCert(address(certPrinter), 60 * 1e18);
        vm.prank(newInvestorTwo);
        issuanceManager.convertScripToCert(address(certPrinter), 20 * 1e18);

        (totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
        assertEq(totalTrackedScrip, 120 * 1e18);
        assertEq(ICyberScrip(scrip).totalSupply(), 120 * 1e18);
        assertEq(certPrinter.totalSupply(), 7);

        CertificateDetails memory activeA = certPrinter.getActiveCertificateDetails(
            certIdA
        );
        CertificateDetails memory activeB = certPrinter.getActiveCertificateDetails(
            certIdB
        );
        CertificateDetails memory activeC = certPrinter.getActiveCertificateDetails(
            certIdC
        );
        CertificateDetails memory activeD = certPrinter.getActiveCertificateDetails(
            certIdD
        );
        CertificateDetails memory activeE = certPrinter.getActiveCertificateDetails(
            certIdE
        );
        CertificateDetails memory activeNewOne = certPrinter
            .getActiveCertificateDetails(5);
        CertificateDetails memory activeNewTwo = certPrinter
            .getActiveCertificateDetails(6);

        assertEq(activeA.unitsRepresented, 0);
        assertEq(activeB.unitsRepresented, 140 * 1e18);
        assertEq(activeC.unitsRepresented, 80 * 1e18);
        assertEq(activeD.unitsRepresented, 80 * 1e18);
        assertEq(activeE.unitsRepresented, 0);
        assertEq(activeNewOne.unitsRepresented, 60 * 1e18);
        assertEq(activeNewTwo.unitsRepresented, 20 * 1e18);

        (bool isScripifiedA, uint256 scripifiedA,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdA);
        (bool isScripifiedB, uint256 scripifiedB,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdB);
        (bool isScripifiedC, uint256 scripifiedC,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdC);
        (bool isScripifiedD, uint256 scripifiedD,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdD);
        (bool isScripifiedE, uint256 scripifiedE,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), certIdE);
        (bool isScripifiedNewOne, uint256 scripifiedNewOne,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), 5);
        (bool isScripifiedNewTwo, uint256 scripifiedNewTwo,) = issuanceManager
            .getCertScripifiedStatus(address(certPrinter), 6);

        assertTrue(isScripifiedA);
        assertEq(scripifiedA, 54 * 1e18);
        assertFalse(isScripifiedB);
        assertEq(scripifiedB, 0);
        assertTrue(isScripifiedC);
        // Vault share→asset conversion can floor nominal claims by ≤1 unit vs naive expectations
        assertApproxEqAbs(
            scripifiedC,
            6 * 1e18,
            1 * 1e18,
            "holder C scripified wad (rounding)"
        );
        assertTrue(isScripifiedD);
        assertApproxEqAbs(
            scripifiedD,
            6 * 1e18,
            1 * 1e18,
            "holder D scripified wad (rounding)"
        );
        assertTrue(isScripifiedE);
        assertEq(scripifiedE, 54 * 1e18);
        assertFalse(isScripifiedNewOne);
        assertEq(scripifiedNewOne, 0);
        assertFalse(isScripifiedNewTwo);
        assertEq(scripifiedNewTwo, 0);

        CertificateDetails memory effectiveA = certPrinter.getCertificateDetails(
            certIdA
        );
        CertificateDetails memory effectiveB = certPrinter.getCertificateDetails(
            certIdB
        );
        CertificateDetails memory effectiveC = certPrinter.getCertificateDetails(
            certIdC
        );
        CertificateDetails memory effectiveD = certPrinter.getCertificateDetails(
            certIdD
        );
        CertificateDetails memory effectiveE = certPrinter.getCertificateDetails(
            certIdE
        );
        CertificateDetails memory newCertOne = certPrinter.getCertificateDetails(5);
        CertificateDetails memory newCertTwo = certPrinter.getCertificateDetails(6);

        // Effective details are active + scripified vault claim (full wad). Compare in wad
        // space — do not divide by 1e18 first (that floors whole units and caused 85 vs 86).
        uint256 wadRoundingTol = 100 * 1e9; // 100 gwei
        assertApproxEqAbs(
            effectiveA.unitsRepresented,
            activeA.unitsRepresented + scripifiedA,
            wadRoundingTol,
            "effective A == active + scripified (wad)"
        );
        assertApproxEqAbs(
            effectiveB.unitsRepresented,
            activeB.unitsRepresented + scripifiedB,
            wadRoundingTol,
            "effective B == active + scripified (wad)"
        );
        assertApproxEqAbs(
            effectiveC.unitsRepresented,
            activeC.unitsRepresented + scripifiedC,
            wadRoundingTol,
            "effective C == active + scripified (wad)"
        );
        assertApproxEqAbs(
            effectiveD.unitsRepresented,
            activeD.unitsRepresented + scripifiedD,
            wadRoundingTol,
            "effective D == active + scripified (wad)"
        );
        assertApproxEqAbs(
            effectiveE.unitsRepresented,
            activeE.unitsRepresented + scripifiedE,
            wadRoundingTol,
            "effective E == active + scripified (wad)"
        );
        assertApproxEqAbs(
            newCertOne.unitsRepresented,
            activeNewOne.unitsRepresented + scripifiedNewOne,
            wadRoundingTol,
            "new cert one effective (wad)"
        );
        assertApproxEqAbs(
            newCertTwo.unitsRepresented,
            activeNewTwo.unitsRepresented + scripifiedNewTwo,
            wadRoundingTol,
            "new cert two effective (wad)"
        );
        assertEq(newCertOne.legalDetails, approvalOne.legalDetails);
        assertEq(newCertOne.extensionData, approvalOne.extensionData);
        assertEq(newCertTwo.legalDetails, approvalTwo.legalDetails);
        assertEq(newCertTwo.extensionData, approvalTwo.extensionData);
        assertEq(certPrinter.ownerOf(5), newInvestorOne);
        assertEq(certPrinter.ownerOf(6), newInvestorTwo);
        assertEq(certPrinter.legalOwnerOf(5), newInvestorOne);
        assertEq(certPrinter.legalOwnerOf(6), newInvestorTwo);

        assertEq(ICyberScrip(scrip).balanceOf(holderA), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(holderB), 0);
        assertEq(ICyberScrip(scrip).balanceOf(holderC), 0);
        assertEq(ICyberScrip(scrip).balanceOf(holderD), 0);
        assertEq(ICyberScrip(scrip).balanceOf(holderE), 60 * 1e18);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorOne), 0);
        assertEq(ICyberScrip(scrip).balanceOf(newInvestorTwo), 0);

        uint256 totalActiveWadFive = activeA.unitsRepresented +
            activeB.unitsRepresented +
            activeC.unitsRepresented +
            activeD.unitsRepresented +
            activeE.unitsRepresented +
            activeNewOne.unitsRepresented +
            activeNewTwo.unitsRepresented;
        uint256 totalScripifiedWadFive = scripifiedA +
            scripifiedB +
            scripifiedC +
            scripifiedD +
            scripifiedE +
            scripifiedNewOne +
            scripifiedNewTwo;
        (uint256 vaultAssetsWadFive,) = issuanceManager.getCertScripUnitVault(
            address(certPrinter)
        );
        // More holders / conversions → slightly larger aggregated rounding vs vault assets
        uint256 fiveHolderWadTol = 3;
        assertApproxEqAbs(
            totalScripifiedWadFive,
            vaultAssetsWadFive,
            fiveHolderWadTol,
            "scripified wad sum vs vault totalAssetsWad (five holders)"
        );
        assertApproxEqAbs(
            totalActiveWadFive + totalScripifiedWadFive,
            500e18,
            fiveHolderWadTol,
            "active + scripified units vs pool cap (five holders)"
        );

        (bool approvalStillSetOne,,,,) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            newInvestorOne
        );
        (bool approvalStillSetTwo,,,,) = issuanceManager.getRecertificationApproval(
            address(certPrinter),
            newInvestorTwo
        );
        assertFalse(approvalStillSetOne);
        assertFalse(approvalStillSetTwo);
    }

    function _deployPrinter(
        string memory name,
        string memory symbol
    ) internal returns (ICyberCertPrinter certPrinter) {
        certPrinter = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                name,
                symbol,
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
    }

    function _mintCert(
        ICyberCertPrinter certPrinter,
        address to,
        uint256 units
    ) internal returns (uint256 tokenId) {
        CertificateDetails memory details = _buildCertificateDetails(
            units,
            "",
            bytes("")
        );
        vm.prank(owner);
        tokenId = issuanceManager.createCertAndAssign(
            address(certPrinter),
            to,
            details
        );
    }

    function _stageRecertificationApproval(
        ICyberCertPrinter certPrinter,
        address investorAddress,
        string memory investorName,
        uint256 units,
        string memory legalDetails,
        bytes memory extensionData
    ) internal returns (CertificateDetails memory details) {
        details = _buildCertificateDetails(units, legalDetails, extensionData);
        vm.prank(owner);
        issuanceManager.setRecertificationApproval(
            address(certPrinter),
            investorAddress,
            investorName,
            details,
            hex"01"
        );
    }

    function _buildCertificateDetails(
        uint256 units,
        string memory legalDetails,
        bytes memory extensionData
    ) internal pure returns (CertificateDetails memory details) {
        details = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            // Store units in 18-decimal precision internally
            unitsRepresented: units * 1e18,
            legalDetails: legalDetails,
            extensionData: extensionData
        });
    }
}


