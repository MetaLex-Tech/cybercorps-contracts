// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorp} from "../src/CyberCorp.sol";

import {CompanyOfficer, CyberCertData, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";

import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";

import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {EOI, RoundManagerStorage} from "../src/storage/RoundManagerStorage.sol";
import {SAFEData, SAFESeriesData} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Script, console2} from "forge-std/Script.sol";

// ABI pinned to Uniswap universal-router 802fe4c and its v4-periphery
// 545a5d2a87228167edde48f3b9eda122d1e3c4d6 dependency; see the runbook.
struct CentPoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct CentExactOutput {
    CentPoolKey poolKey;
    bool zeroForOne;
    uint128 amountOut;
    uint128 amountInMaximum;
    uint256 minHopPriceX36;
    bytes hookData;
}

struct CentQuoteParams {
    CentPoolKey poolKey;
    bool zeroForOne;
    uint128 exactAmount;
    bytes hookData;
}

interface ICentRouter {
    function poolManager() external view returns (address);
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface ICentQuoter {
    function quoteExactOutputSingle(CentQuoteParams memory params)
        external
        returns (uint256 amountIn, uint256 gasEstimate);
}

interface ICentStateView {
    function getLiquidity(bytes32 poolId) external view returns (uint128);
}

/// @notice Operator-run, resumable one-cent SAFE rehearsal on Robinhood mainnet.
/// @dev Keys are loaded only by run(); tests can supply generated signers to
/// execute(). No real key is embedded. Never use --skip-simulation.
contract RobinhoodCentSafeScript is Script {
    using RoundLib for Round;

    uint256 public constant INVESTMENT = 10_000; // exactly 0.01 USDG (6 decimals)
    address public constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address public constant ROUTER = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address public constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public constant QUOTER = 0x8Dc178eFB8111BB0973Dd9d722ebeFF267c98F94;
    address public constant STATE_VIEW = 0xF3334192D15450CdD385c8B70e03f9A6bD9E673b;

    struct Config {
        bytes32 salt;
        uint256 start;
        uint256 end;
        uint256 maxEthIn;
        uint256 gasReserve;
        uint256 valuationCapUSD;
        bytes32 templateId;
        address payout;
        string companyName;
        string companyJurisdiction;
        string officerName;
        string officerContact;
        string investorName;
        string investorContact;
        string investorType;
        string investorJurisdiction;
    }

    struct Result {
        address corp;
        address roundManager;
        bytes32 roundId;
        bytes32 agreementId;
        address certificate;
        uint256 tokenId;
    }

    error InvalidConfig();
    error WrongChain();
    error SameSigner();
    error Expired();
    error InsufficientETH(address account);
    error SwapBudgetExceeded(uint256 quoted, uint256 maximum);
    error IncompatibleExistingState();
    error StateCheckFailed();

    function loadConfig(address officer) public view returns (Config memory c) {
        c.salt = vm.envBytes32("SAFE_REHEARSAL_SALT");
        c.start = vm.envUint("SAFE_ROUND_START");
        c.end = vm.envUint("SAFE_ROUND_END");
        c.maxEthIn = vm.envUint("SAFE_MAX_ETH_IN_WEI");
        c.gasReserve = vm.envOr("SAFE_GAS_RESERVE_WEI", uint256(100_000_000_000_000));
        c.valuationCapUSD = vm.envUint("SAFE_VALUATION_CAP_USD");
        c.templateId = bytes32(vm.envOr("SAFE_TEMPLATE_ID", uint256(32)));
        c.payout = vm.envOr("SAFE_COMPANY_PAYABLE", officer);
        c.companyName = vm.envString("SAFE_COMPANY_NAME");
        c.companyJurisdiction = vm.envString("SAFE_COMPANY_JURISDICTION");
        c.officerName = vm.envString("SAFE_OFFICER_NAME");
        c.officerContact = vm.envString("SAFE_OFFICER_CONTACT");
        c.investorName = vm.envString("SAFE_INVESTOR_NAME");
        c.investorContact = vm.envString("SAFE_INVESTOR_CONTACT");
        c.investorType = vm.envString("SAFE_INVESTOR_TYPE");
        c.investorJurisdiction = vm.envString("SAFE_INVESTOR_JURISDICTION");
    }

    function run() external returns (Result memory) {
        uint256 officerKey = vm.envUint("PRIVATE_KEY_MAIN");
        uint256 investorKey = vm.envUint("PRIVATE_KEY_INVESTOR");
        return execute(loadConfig(vm.addr(officerKey)), officerKey, investorKey);
    }

    /// @notice Quote only; no wallet key/environment configuration is required.
    function quote() external returns (uint256 ethWei) {
        _routeChecks();
        (ethWei,) =
            ICentQuoter(QUOTER).quoteExactOutputSingle(CentQuoteParams(poolKey(), true, uint128(INVESTMENT), ""));
        console2.log("USDG output units (0.01 USDG)", INVESTMENT);
        console2.log("Quoted ETH input wei; gas additional", ethWei);
    }

    function execute(Config memory c, uint256 officerKey, uint256 investorKey) public returns (Result memory r) {
        address officer = vm.addr(officerKey);
        address investor = vm.addr(investorKey);
        _configChecks(c, officer, investor);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(4663);
        CyberCorpFactory factory = CyberCorpFactory(core.cyberCorpFactory);
        CyberAgreementRegistry registry = CyberAgreementRegistry(core.cyberAgreementRegistry);
        _templateChecks(registry, c.templateId);
        if (factory.stable() != USDG || IERC20Metadata(USDG).decimals() != 6) revert StateCheckFailed();
        address configuredPlatform = RoundManagerFactory(core.roundManagerFactory).getPlatformPayable();
        if (configuredPlatform == c.payout || configuredPlatform == investor) revert InvalidConfig();
        CompanyOfficer memory details = CompanyOfficer(officer, c.officerName, c.officerContact, "CEO");
        bytes32 boundSalt = factory.computeDeploymentSalt(
            c.salt,
            c.companyName,
            "corporation",
            c.companyJurisdiction,
            c.officerContact,
            "arbitration",
            c.payout,
            details
        );
        r.corp = CyberCorpSingleFactory(core.cyberCorpSingleFactory).computeCyberCorpSingleAddress(
            boundSalt, address(factory)
        );
        if (r.corp.code.length == 0) {
            _requireOpen(c);
            _checkGas(officer, c.gasReserve);
            // Check swap feasibility before forming a company on the first run.
            _buyMissing(c, investor, investorKey);
            vm.broadcast(officerKey);
            (address created,,,,) = factory.deployCyberCorp(
                c.salt,
                c.companyName,
                "corporation",
                c.companyJurisdiction,
                c.officerContact,
                "arbitration",
                c.payout,
                details
            );
            if (created != r.corp) revert StateCheckFailed();
        }
        CyberCorp corp = CyberCorp(r.corp);
        if (
            keccak256(bytes(corp.cyberCORPName())) != keccak256(bytes(c.companyName))
                || corp.companyPayable() != c.payout || corp.AUTH().userRoles(officer) < 99
        ) revert IncompatibleExistingState();
        r.roundManager = corp.roundManager();
        RoundManager manager = RoundManager(r.roundManager);
        (Round memory draft, CyberCertData[] memory certs) = _draft(c, officer, officerKey, r.corp, manager, registry);
        r.roundId = draft.id;
        string[] memory globals = _globals(c);
        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        uint256 salt = uint256(keccak256(abi.encode("RobinhoodCentSAFE.EOI.v1", c.salt, r.corp, investor)));
        r.agreementId = keccak256(abi.encode(c.templateId, salt, globals, parties, bytes32(0), address(manager)));
        Escrow memory escrow = manager.getEscrowDetails(r.agreementId);
        if (escrow.agreementId != bytes32(0) && escrow.status == EscrowStatus.FINALIZED) {
            _completed(r, manager, registry, investor);
            _log(r);
            return r;
        }
        if (escrow.agreementId != bytes32(0) && (escrow.status != EscrowStatus.PAID || escrow.counterParty != investor))
        {
            revert IncompatibleExistingState();
        }
        _requireOpen(c);
        _checkGas(officer, c.gasReserve);
        if (manager.roundExists(r.roundId) && manager.getRound(r.roundId).raised != 0) {
            revert IncompatibleExistingState();
        }
        if (!manager.roundExists(r.roundId)) {
            vm.broadcast(officerKey);
            manager.createRound(draft, certs);
        }
        _roundChecks(manager.getRound(r.roundId), draft);
        if (escrow.agreementId == bytes32(0)) {
            _buyMissing(c, investor, investorKey);
            if (IERC20Metadata(USDG).allowance(investor, address(manager)) != INVESTMENT) {
                if (IERC20Metadata(USDG).allowance(investor, address(manager)) != 0) {
                    vm.broadcast(investorKey);
                    if (!IERC20Metadata(USDG).approve(address(manager), 0)) revert StateCheckFailed();
                }
                vm.broadcast(investorKey);
                if (!IERC20Metadata(USDG).approve(address(manager), INVESTMENT)) revert StateCheckFailed();
            }
            string[] memory investorValues =
                _partyValues(investor, c.investorName, c.investorContact, c.investorType, c.investorJurisdiction);
            bytes memory signature = _agreementSignature(
                registry, c.templateId, r.agreementId, globals, investorValues, investor, investorKey
            );
            EOI memory eoi;
            eoi.name = c.investorName;
            eoi.investorType = c.investorType;
            eoi.jurisdiction = c.investorJurisdiction;
            eoi.contact = c.investorContact;
            eoi.minAmount = INVESTMENT;
            eoi.maxAmount = INVESTMENT;
            eoi.expiry = c.end;
            eoi.naturalPerson = keccak256(bytes(c.investorType)) == keccak256("Individual");
            vm.broadcast(investorKey);
            (bytes32 agreement,) = manager.submitEOI(
                r.roundId, eoi, globals, investorValues, signature, salt, new address[](0), bytes32(0)
            );
            if (agreement != r.agreementId) revert StateCheckFailed();
        }
        uint256 payoutBefore = IERC20Metadata(USDG).balanceOf(c.payout);
        address platform = manager.getPlatformPayable();
        if (platform != configuredPlatform) revert StateCheckFailed();
        uint256 platformBefore = IERC20Metadata(USDG).balanceOf(platform);
        uint256 fee = manager.computeFee(INVESTMENT);
        vm.broadcast(officerKey);
        manager.allocate(r.agreementId, INVESTMENT);
        if (
            IERC20Metadata(USDG).balanceOf(c.payout) - payoutBefore != INVESTMENT - fee
                || IERC20Metadata(USDG).balanceOf(platform) - platformBefore != fee
                || IERC20Metadata(USDG).allowance(investor, address(manager)) != 0
        ) revert StateCheckFailed();
        _completed(r, manager, registry, investor);
        _log(r);
    }

    function poolKey() public pure returns (CentPoolKey memory) {
        return CentPoolKey(address(0), USDG, 500, 10, address(0));
    }

    function _routeChecks() internal view {
        if (block.chainid != 4663) revert WrongChain();
        if (
            ROUTER.code.length == 0 || QUOTER.code.length == 0 || STATE_VIEW.code.length == 0
                || ICentRouter(ROUTER).poolManager() != POOL_MANAGER
                || ICentStateView(STATE_VIEW).getLiquidity(keccak256(abi.encode(poolKey()))) == 0
        ) revert StateCheckFailed();
    }

    function _configChecks(Config memory c, address officer, address investor) internal view {
        if (block.chainid != 4663) revert WrongChain();
        if (officer == investor) revert SameSigner();
        if (
            c.salt == bytes32(0) || c.start >= c.end || c.maxEthIn == 0 || c.maxEthIn > type(uint128).max
                || c.gasReserve == 0 || c.valuationCapUSD == 0 || c.valuationCapUSD > type(uint256).max / 1e18
                || c.payout == address(0) || c.payout == investor || officer.code.length != 0 || investor.code.length != 0
                || bytes(c.companyName).length == 0 || bytes(c.companyJurisdiction).length == 0
                || bytes(c.officerName).length == 0 || bytes(c.officerContact).length == 0
                || bytes(c.investorName).length == 0 || bytes(c.investorContact).length == 0
                || bytes(c.investorType).length == 0 || bytes(c.investorJurisdiction).length == 0
        ) revert InvalidConfig();
    }

    function _requireOpen(Config memory c) internal view {
        if (block.timestamp < c.start || block.timestamp >= c.end) revert Expired();
    }

    function _checkGas(address account, uint256 reserve) internal view {
        if (account.balance < reserve) revert InsufficientETH(account);
    }

    function _checkFunding(Config memory c, address investor) internal {
        if (IERC20Metadata(USDG).balanceOf(investor) >= INVESTMENT) {
            _checkGas(investor, c.gasReserve);
            return;
        }
        _routeChecks();
        uint256 missing = INVESTMENT - IERC20Metadata(USDG).balanceOf(investor);
        (uint256 quoted,) =
            ICentQuoter(QUOTER).quoteExactOutputSingle(CentQuoteParams(poolKey(), true, uint128(missing), ""));
        if (quoted > c.maxEthIn) revert SwapBudgetExceeded(quoted, c.maxEthIn);
        if (investor.balance < c.maxEthIn + c.gasReserve) revert InsufficientETH(investor);
    }

    function _buyMissing(Config memory c, address investor, uint256 key) internal {
        _checkFunding(c, investor);
        uint256 beforeBalance = IERC20Metadata(USDG).balanceOf(investor);
        if (beforeBalance >= INVESTMENT) {
            console2.log("USDG already funded; swap skipped");
            return;
        }
        uint256 missing = INVESTMENT - beforeBalance;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(CentExactOutput(poolKey(), true, uint128(missing), uint128(c.maxEthIn), 0, ""));
        params[1] = abi.encode(address(0), c.maxEthIn);
        params[2] = abi.encode(USDG, missing);
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(hex"080c0f", params); // exact output, settle ETH, take USDG
        inputs[1] = abi.encode(address(0), investor, uint256(0)); // return unspent ETH
        vm.broadcast(key);
        ICentRouter(ROUTER).execute{value: c.maxEthIn}(hex"1004", inputs, c.end);
        if (IERC20Metadata(USDG).balanceOf(investor) - beforeBalance != missing) revert StateCheckFailed();
    }

    function _templateChecks(CyberAgreementRegistry registry, bytes32 id) internal view {
        if (id != bytes32(uint256(30)) && id != bytes32(uint256(32))) revert InvalidConfig();
        (, string memory title, string[] memory globals, string[] memory parties) = registry.getTemplateDetails(id);
        string[] memory expected = new string[](5);
        expected[0] = "purchaseAmount";
        expected[1] = "postMoneyValuationCap";
        expected[2] = "expirationTime";
        expected[3] = "governingJurisdiction";
        expected[4] = "disputeResolution";
        string[] memory signerFields = new string[](5);
        signerFields[0] = "name";
        signerFields[1] = "evmAddress";
        signerFields[2] = "contactDetails";
        signerFields[3] = "investorType";
        signerFields[4] = "investorJurisdiction";
        if (
            bytes(title).length == 0
                || keccak256(abi.encode(globals, parties)) != keccak256(abi.encode(expected, signerFields))
        ) revert InvalidConfig();
    }

    function _draft(
        Config memory c,
        address officer,
        uint256 key,
        address corp,
        RoundManager manager,
        CyberAgreementRegistry registry
    ) internal view returns (Round memory d, CyberCertData[] memory certs) {
        (string memory uri,,,) = registry.getTemplateDetails(c.templateId);
        string[] memory uris = new string[](1);
        uris[0] = uri;
        string[] memory legends = new string[](1);
        legends[0] = "RESTRICTED - subject to the governing agreement";
        certs = new CyberCertData[](1);
        certs[0] = CyberCertData(
            "Seed SAFE",
            "CENTSAFE",
            uri,
            SecurityClass.SAFE,
            SecuritySeries.SeriesSeed,
            DeploymentConstants.extensions(4663).safeExtensionV3,
            abi.encode(SAFESeriesData("Seed SAFE", uris, "One-cent on-chain rehearsal")),
            legends
        );
        bytes[] memory ext = new bytes[](1);
        ext[0] = abi.encode(SAFEData("One-cent on-chain rehearsal"));
        d = RoundLib.draft().setTickets(
            SecuritySeries.SeriesSeed,
            RoundType.FounderApproved,
            false,
            true,
            false,
            INVESTMENT,
            INVESTMENT,
            INVESTMENT,
            USDG,
            1e18,
            c.valuationCapUSD * 1e18,
            c.start,
            c.end
        ).setAgreement(
            c.templateId,
            officer,
            c.officerName,
            "CEO",
            uris,
            _partyValues(officer, c.companyName, c.officerContact, "Corporation", c.companyJurisdiction),
            ext,
            new address[](0),
            ""
        );
        d.id = keccak256(
            abi.encodePacked(
                d.seriesType,
                d.raiseCap,
                d.minTicket,
                d.maxTicket,
                uint8(d.roundType),
                d.startTime,
                d.endTime,
                d.templateId,
                d.paymentToken,
                d.pricePerUnit,
                d.valuation,
                corp
            )
        );
        RoundManagerStorage.EscrowedSignatureData memory sd = RoundManagerStorage.EscrowedSignatureData(
            d.id,
            uint8(d.seriesType),
            d.raiseCap,
            d.minTicket,
            d.maxTicket,
            uint8(d.roundType),
            d.startTime,
            d.endTime,
            d.templateId,
            d.paymentToken,
            d.pricePerUnit,
            d.valuation,
            corp
        );
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("RoundManager"),
                keccak256("1"),
                block.chainid,
                address(manager)
            )
        );
        d.escrowedSignature = _sign(
            key,
            keccak256(
                abi.encodePacked(
                    "\x19\x01", domain, keccak256(abi.encode(RoundManagerStorage.ESCROWEDSIGNATUREDATA_TYPEHASH, sd))
                )
            )
        );
    }

    function _roundChecks(Round memory stored, Round memory expected) internal pure {
        if (
            stored.certPrinter.length != 1 || stored.primarySecurityClass != SecurityClass.SAFE
                || stored.primarySecuritySeries != SecuritySeries.SeriesSeed
        ) {
            revert IncompatibleExistingState();
        }
        stored.certPrinter = new address[](0);
        stored.raised = 0;
        stored.primarySecurityClass = expected.primarySecurityClass;
        stored.primarySecuritySeries = expected.primarySecuritySeries;
        if (keccak256(abi.encode(stored)) != keccak256(abi.encode(expected))) revert IncompatibleExistingState();
    }

    function _globals(Config memory c) internal pure returns (string[] memory g) {
        g = new string[](5);
        g[0] = "0.01";
        g[1] = vm.toString(c.valuationCapUSD);
        g[2] = vm.toString(c.end);
        g[3] = c.companyJurisdiction;
        g[4] = "arbitration";
    }

    function _partyValues(
        address who,
        string memory name,
        string memory contact,
        string memory kind,
        string memory jurisdiction
    ) internal pure returns (string[] memory values) {
        values = new string[](5);
        values[0] = name;
        values[1] = vm.toString(who);
        values[2] = contact;
        values[3] = kind;
        values[4] = jurisdiction;
    }

    function _agreementSignature(
        CyberAgreementRegistry registry,
        bytes32 templateId,
        bytes32 id,
        string[] memory globals,
        string[] memory values,
        address investor,
        uint256 key
    ) internal view returns (bytes memory) {
        (string memory uri,, string[] memory fields, string[] memory signerFields) =
            registry.getTemplateDetails(templateId);
        bytes32 sh = keccak256(
            abi.encode(
                registry.SIGNATUREDATA_TYPEHASH(),
                id,
                investor,
                keccak256(bytes(uri)),
                _hashStrings(fields),
                _hashStrings(signerFields),
                _hashStrings(globals),
                _hashStrings(values)
            )
        );
        return _sign(key, keccak256(abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), sh)));
    }

    function _hashStrings(string[] memory values) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](values.length);
        for (uint256 i; i < values.length; i++) {
            hashes[i] = keccak256(bytes(values[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _completed(Result memory r, RoundManager manager, CyberAgreementRegistry registry, address investor)
        internal
        view
    {
        Escrow memory e = manager.getEscrowDetails(r.agreementId);
        if (
            e.status != EscrowStatus.FINALIZED || e.counterParty != investor || e.corpAssets.length != 1
                || !registry.isFinalized(r.agreementId) || manager.getRound(r.roundId).raised != INVESTMENT
        ) revert StateCheckFailed();
        r.certificate = e.corpAssets[0].tokenAddress;
        r.tokenId = e.corpAssets[0].tokenId;
        LedgerEntryToken cert = LedgerEntryToken(r.certificate);
        if (
            cert.ownerOf(r.tokenId) != investor || cert.legalOwnerOf(r.tokenId) != investor
                || cert.securityType() != SecurityClass.SAFE || cert.securitySeries() != SecuritySeries.SeriesSeed
                || cert.getExtension(r.tokenId) != DeploymentConstants.extensions(4663).safeExtensionV3
                || !registry.hasSigned(r.agreementId, investor)
                || !registry.hasSigned(r.agreementId, manager.getRound(r.roundId).authorityOfficer)
                || cert.getCertificateDetails(r.tokenId).investmentAmountUSD != 1e16
                || bytes(cert.tokenURI(r.tokenId)).length == 0
        ) revert StateCheckFailed();
    }

    function _log(Result memory r) internal pure {
        console2.log("Company", r.corp);
        console2.log("Round manager", r.roundManager);
        console2.log("Round ID");
        console2.logBytes32(r.roundId);
        console2.log("Agreement ID");
        console2.logBytes32(r.agreementId);
        console2.log("SAFE LET", r.certificate);
        console2.log("Token ID", r.tokenId);
        console2.log("Investment USDG units", INVESTMENT);
    }
}
