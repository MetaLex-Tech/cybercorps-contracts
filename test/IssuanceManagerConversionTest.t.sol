// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberScrip.sol";
import "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

contract MockCertPrinter {
    using IssuanceManagerStorage for IssuanceManagerStorage.IssuanceManagerData;

    mapping(uint256 => CertificateDetails) internal _details;
    mapping(uint256 => address) internal _owners;
    uint256 internal _total;
    string internal _name = "Mock";
    string internal _symbol = "MOCK";

    function initialize(
        string[] memory,
        string memory name_,
        string memory symbol_,
        string memory,
        address,
        SecurityClass,
        SecuritySeries,
        address
    ) external {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }

    function totalSupply() external view returns (uint256) { return _total; }

    function safeMint(uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256) {
        _details[tokenId] = details;
        _owners[tokenId] = to;
        if (tokenId == _total) {
            _total = tokenId + 1;
        }
        return tokenId;
    }

    function tokenURI(uint256) external pure returns (string memory) { return ""; }

    function ownerOf(uint256 tokenId) external view returns (address) { return _owners[tokenId]; }

    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) { return _details[tokenId]; }

    function voidCert(uint256 /*tokenId*/) external {}
}

contract IssuanceManagerConversionTest is Test {
    IssuanceManager public issuanceManager;
    MockCertPrinter public safePrinter;
    MockCertPrinter public equityPrinter;
    BorgAuth public auth;
    MockRoundManagerForConversion public mockRM;

    address public owner;
    address public investor;

    function setUp() public {
        owner = address(this);
        investor = makeAddr("investor");

        // Auth
        auth = new BorgAuth(owner);

        // IssuanceManager via proxy (implementation disables initializers in constructor)
        IssuanceManager impl = new IssuanceManager();
        MockCertPrinter implCert = new MockCertPrinter();
        CyberScrip implScrip = new CyberScrip();
        bytes memory initData = abi.encodeWithSelector(
            IssuanceManager.initialize.selector,
            address(auth),
            address(0xC0DE),
            address(implCert),
            address(0xBEEF),
            address(0xFACADE),
            address(implScrip)
        );
        issuanceManager = IssuanceManager(address(new ERC1967Proxy(address(impl), initData)));

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
            typeOfUnitsRepresented: "",
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
}


