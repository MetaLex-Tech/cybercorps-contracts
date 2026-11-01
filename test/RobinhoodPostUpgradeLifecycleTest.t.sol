// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {DeploymentConstants} from "../script/libs/DeploymentConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorp} from "../src/CyberCorp.sol";

import {CompanyOfficer, CyberCertData, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {RoundManager} from "../src/RoundManager.sol";

import {CertificateDetails, Endorsement} from "../src/interfaces/ILedgerEntryToken.sol";
import {Round, RoundLib, RoundType} from "../src/libs/RoundLib.sol";
import {BorgAuth} from "../src/libs/auth.sol";

import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {EOI, RoundManagerStorage} from "../src/storage/RoundManagerStorage.sol";

import {
    SAFEData, SAFEExtensionV3, SAFEResolvedData, SAFESeriesData
} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/Test.sol";

/// @notice Opt-in acceptance against actual deployed code. Never runs an upgrade,
/// replaces code, mocks calls, changes roles, or writes an operator Safe batch.
/// Only the explicitly named fixture tests register a missing template locally.
contract RobinhoodPostUpgradeLifecycleTest is Test {
    using RoundLib for Round;

    bytes32 constant TEMPLATE = bytes32(uint256(32));
    uint256 constant OFFER = 10_000e6;
    uint256 constant ALLOCATION = 7_500e6;
    uint256 constant INITIAL_BALANCE = 20_000e6;

    CyberCorpFactory factory;
    CyberAgreementRegistry registry;
    CyberCorp corp;
    IssuanceManager issuance;
    RoundManager manager;
    BorgAuth auth;
    IERC20Metadata payment;
    SAFEExtensionV3 safeExtension;
    address officer;
    address investor;
    uint256 officerKey;
    uint256 investorKey;
    address payout;
    address attacker;
    uint256 selectedFork;
    uint256 baseFork;
    bool enabled;

    function setUp() public {
        string memory url = vm.envOr("ROBINHOOD_POST_FORK_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        uint256 chainId = vm.envOr("POST_UPGRADE_CHAIN_ID", uint256(4663));
        uint256 pinnedBlock = vm.envUint("POST_UPGRADE_BLOCK");
        selectedFork = vm.createSelectFork(url, pinnedBlock);
        assertEq(block.chainid, chainId);
        enabled = true;
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        factory = CyberCorpFactory(core.cyberCorpFactory);
        registry = CyberAgreementRegistry(core.cyberAgreementRegistry);
        safeExtension = SAFEExtensionV3(DeploymentConstants.extensions(chainId).safeExtensionV3);
        payment = IERC20Metadata(factory.stable());
        assertEq(payment.decimals(), 6);
        // deps() has no Robinhood entry; verify its observed USDG explicitly.
        assertEq(
            address(payment),
            chainId == 4663 ? 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168 : DeploymentConstants.deps(chainId).usdc
        );
        (officer, officerKey) = makeAddrAndKey("post-v5-safe-officer-20261030");
        (investor, investorKey) = makeAddrAndKey("post-v5-safe-investor-20261030");
        assertEq(officer.code.length, 0);
        assertEq(investor.code.length, 0);
        payout = makeAddr("post-v5-company-payout");
        attacker = makeAddr("post-v5-unprivileged-relayer");
        // Local storage funding of the actual deployed ERC20; no mock token.
        deal(address(payment), investor, INITIAL_BALANCE);
        vm.prank(attacker); // A formation relayer must receive no company control.
        (address c, address a, address im, address dm, address rm) = factory.deployCyberCorp(
            keccak256("post-v5-safe-lifecycle-20261030"),
            "Fork Acceptance Corp",
            "corporation",
            "DE",
            "officer@example.invalid",
            "arbitration",
            payout,
            CompanyOfficer(officer, "Test Officer", "officer@example.invalid", "CEO")
        );
        corp = CyberCorp(c);
        auth = BorgAuth(a);
        issuance = IssuanceManager(im);
        manager = RoundManager(rm);
        assertEq(address(corp.AUTH()), a);
        assertEq(address(issuance.AUTH()), a);
        assertEq(address(manager.AUTH()), a);
        assertEq(corp.issuanceManager(), im);
        assertEq(corp.dealManager(), dm);
        assertEq(corp.roundManager(), rm);
        assertEq(issuance.CORP(), c);
        assertEq(address(manager.issuanceManager()), im);
        assertEq(corp.companyPayable(), payout);
        assertEq(auth.userRoles(officer), 200);
        assertEq(auth.userRoles(attacker), 0);
        // Current deployed formation retains the infrastructure factory's role.
        // The unprivileged caller gains no role; do not assert exclusive ownership.
        assertEq(auth.userRoles(address(factory)), 99);
        assertEq(corp.DEPLOY_VERSION(), "5");
        assertEq(issuance.DEPLOY_VERSION(), "5");
        assertEq(manager.DEPLOY_VERSION(), "5");
    }

    modifier forkOnly() {
        if (!enabled) {
            vm.skip(true);
            return;
        }
        _;
    }

    function _round() internal view returns (Round memory draft, CyberCertData[] memory certs) {
        string[] memory legend = new string[](1);
        legend[0] = "RESTRICTED - transfer subject to applicable law and issuer approval";
        string[] memory uris = new string[](1);
        uris[0] = "IPFS://bafybeib5pqnqwbfdsnv4lqdkdglz2e4xqz2qklwdzzpbftydopzuqnri2a";
        certs = new CyberCertData[](1);
        certs[0] = CyberCertData({
            name: "Seed SAFE",
            symbol: "SEEDSAFE",
            uri: uris[0],
            securityClass: SecurityClass.SAFE,
            securitySeries: SecuritySeries.SeriesSeed,
            extension: address(safeExtension),
            seriesData: abi.encode(SAFESeriesData("Seed SAFE", uris, "Fork acceptance series")),
            defaultLegend: legend
        });
        string[] memory legal = new string[](1);
        legal[0] = uris[0];
        bytes[] memory ext = new bytes[](1);
        ext[0] = abi.encode(SAFEData("Fork acceptance certificate"));
        draft = RoundLib.draft().setTickets(
            SecuritySeries.SeriesSeed,
            RoundType.FounderApproved,
            false,
            true,
            false,
            100_000e6,
            1_000e6,
            OFFER,
            address(payment),
            1e18,
            10_000_000e18,
            block.timestamp,
            block.timestamp + 30 days
        ).setAgreement(
            TEMPLATE,
            officer,
            "Test Officer",
            "CEO",
            legal,
            _partyValues(officer, "Test Officer"),
            ext,
            new address[](0),
            ""
        );
        bytes32 id = keccak256(
            abi.encodePacked(
                draft.seriesType,
                draft.raiseCap,
                draft.minTicket,
                draft.maxTicket,
                uint8(draft.roundType),
                draft.startTime,
                draft.endTime,
                draft.templateId,
                draft.paymentToken,
                draft.pricePerUnit,
                draft.valuation,
                address(corp)
            )
        );
        RoundManagerStorage.EscrowedSignatureData memory data = RoundManagerStorage.EscrowedSignatureData(
            id,
            uint8(draft.seriesType),
            draft.raiseCap,
            draft.minTicket,
            draft.maxTicket,
            uint8(draft.roundType),
            draft.startTime,
            draft.endTime,
            TEMPLATE,
            address(payment),
            draft.pricePerUnit,
            draft.valuation,
            address(corp)
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
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01", domain, keccak256(abi.encode(RoundManagerStorage.ESCROWEDSIGNATUREDATA_TYPEHASH, data))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(officerKey, digest);
        draft.escrowedSignature = abi.encodePacked(r, s, v);
    }

    function _partyValues(address who, string memory name) internal pure returns (string[] memory values) {
        values = new string[](5);
        values[0] = name;
        values[1] = vm.toString(who);
        values[2] = "test@example.invalid";
        values[3] = "Individual";
        values[4] = "GB";
    }

    function _globals() internal view returns (string[] memory values) {
        values = new string[](5);
        values[0] = "7500";
        values[1] = "10000000";
        values[2] = vm.toString(block.timestamp + 7 days);
        values[3] = "Delaware";
        values[4] = "arbitration";
    }

    function _offer() internal view returns (EOI memory eoi) {
        eoi.name = "Test Investor";
        eoi.investorType = "Individual";
        eoi.jurisdiction = "GB";
        eoi.contact = "investor@example.invalid";
        eoi.minAmount = 1_000e6;
        eoi.maxAmount = OFFER;
        eoi.expiry = block.timestamp + 7 days;
        eoi.naturalPerson = true;
    }

    function _signature(uint256 salt, uint256 key) internal view returns (bytes memory signature) {
        (string memory uri,, string[] memory fields, string[] memory signerFields) =
            registry.getTemplateDetails(TEMPLATE);
        address[] memory parties = new address[](2);
        parties[0] = officer;
        parties[1] = investor;
        bytes32 agreementId = keccak256(abi.encode(TEMPLATE, salt, _globals(), parties, bytes32(0), address(manager)));
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            uri,
            fields,
            signerFields,
            _globals(),
            _partyValues(investor, "Test Investor"),
            investor,
            key
        );
    }

    function _submit(bytes32 id, uint256 salt, bytes memory signature) internal returns (bytes32 agreementId) {
        vm.prank(investor);
        (agreementId,) = manager.submitEOI(
            id,
            _offer(),
            _globals(),
            _partyValues(investor, "Test Investor"),
            signature,
            salt,
            new address[](0),
            bytes32(0)
        );
    }

    function _createRound() internal returns (bytes32 id) {
        (Round memory draft, CyberCertData[] memory certs) = _round();
        vm.prank(officer);
        id = manager.createRound(draft, certs);
        Round memory stored = manager.getRound(id);
        assertEq(stored.certPrinter.length, 1);
        assertEq(uint256(stored.primarySecurityClass), uint256(SecurityClass.SAFE));
        assertEq(LedgerEntryToken(stored.certPrinter[0]).issuanceManager(), address(issuance));
    }

    function test_LiveFormationAndMissingTemplateRefusal() public forkOnly {
        if (block.chainid != 4663) {
            vm.skip(true);
            return;
        }
        vm.expectRevert(CyberAgreementRegistry.TemplateDoesNotExist.selector);
        registry.getTemplateDetails(TEMPLATE);
        bytes32 id = _createRound(); // Creation alone does not check template registration.
        vm.prank(investor);
        payment.approve(address(manager), OFFER);
        vm.expectRevert(CyberAgreementRegistry.TemplateDoesNotExist.selector);
        _submit(id, 1, hex"01");
        assertEq(payment.balanceOf(investor), INITIAL_BALANCE);
        assertEq(payment.balanceOf(address(manager)), 0);
        assertEq(manager.getRound(id).raised, 0);
    }

    /// @dev Explicit local-only fixture: exact standard SAFE template read from Base.
    /// Does not change any production deployment, implementations, roles or conditions.
    function _installBaseTemplateFixtureIfMissing() internal virtual {
        try registry.getTemplateDetails(TEMPLATE) returns (
            string memory, string memory, string[] memory, string[] memory
        ) {
            return;
        } catch {
            assertEq(block.chainid, 4663);
            baseFork =
                vm.createSelectFork(vm.envString("POST_UPGRADE_BASE_RPC_URL"), vm.envUint("POST_UPGRADE_BASE_BLOCK"));
            (string memory uri, string memory title, string[] memory globals, string[] memory party) =
            CyberAgreementRegistry(DeploymentConstants.coreV2(8453).cyberAgreementRegistry).getTemplateDetails(TEMPLATE);
            vm.selectFork(selectedFork);
            registry.createTemplate(TEMPLATE, title, uri, globals, party);
        }
    }

    function test_ForkTemplateFixture_FullSafeIssuance() public forkOnly {
        _installBaseTemplateFixtureIfMissing();
        bytes32 id = _createRound();
        vm.prank(investor);
        payment.approve(address(manager), OFFER);
        bytes32 agreementId = _submit(id, 100, _signature(100, investorKey));
        assertEq(uint256(manager.getEscrowDetails(agreementId).status), uint256(EscrowStatus.PAID));
        assertEq(payment.balanceOf(investor), INITIAL_BALANCE - OFFER);
        assertEq(payment.balanceOf(address(manager)), OFFER);
        address platform = manager.getPlatformPayable();
        uint256 platformBefore = payment.balanceOf(platform);
        uint256 payoutBefore = payment.balanceOf(payout);
        uint256 fee = manager.computeFee(ALLOCATION);
        assertEq(fee, block.chainid == 4663 ? 37_500_000 : 22_500_000);
        vm.prank(officer);
        manager.allocate(agreementId, ALLOCATION);
        assertTrue(registry.isFinalized(agreementId));
        assertTrue(registry.hasSigned(agreementId, officer));
        assertTrue(registry.hasSigned(agreementId, investor));
        assertEq(payment.balanceOf(investor), INITIAL_BALANCE - ALLOCATION);
        assertEq(payment.balanceOf(address(manager)), 0);
        assertEq(payment.balanceOf(payout) - payoutBefore, ALLOCATION - fee);
        assertEq(payment.balanceOf(platform) - platformBefore, fee);
        assertEq(manager.getRound(id).raised, ALLOCATION);
        Escrow memory escrow = manager.getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.FINALIZED));
        assertEq(escrow.corpAssets.length, 1);
        LedgerEntryToken certificate = LedgerEntryToken(escrow.corpAssets[0].tokenAddress);
        uint256 tokenId = escrow.corpAssets[0].tokenId;
        assertEq(certificate.ownerOf(tokenId), investor);
        assertEq(certificate.legalOwnerOf(tokenId), investor);
        assertEq(uint256(certificate.securityType()), uint256(SecurityClass.SAFE));
        assertEq(uint256(certificate.securitySeries()), uint256(SecuritySeries.SeriesSeed));
        assertEq(certificate.getExtension(tokenId), address(safeExtension));
        CertificateDetails memory details = certificate.getCertificateDetails(tokenId);
        assertEq(details.investmentAmountUSD, 7_500e18);
        assertEq(details.issuerUSDValuationAtTimeOfInvestment, 10_000_000e18);
        assertEq(details.unitsRepresented, 7_500e18);
        assertEq(details.signingOfficerName, "Test Officer");
        SAFEResolvedData memory resolved = safeExtension.resolveCert(address(certificate), tokenId);
        assertEq(resolved.series.seriesName, "Seed SAFE");
        assertEq(resolved.certificate.customProvisions, "Fork acceptance certificate");
        Endorsement memory endorsement = certificate.getEndorsementHistory(tokenId, 0);
        assertEq(endorsement.agreementId, agreementId);
        assertEq(endorsement.endorsee, investor);
        string memory uri = certificate.tokenURI(tokenId);
        assertGt(bytes(uri).length, 100);
        assertTrue(_contains(uri, "data:application/json;base64,"));
        console2.log("Created company", address(corp));
        console2.log("SAFE LET", address(certificate));
        console2.log("Token ID", tokenId);
        console2.log("Metadata bytes", bytes(uri).length);
        console2.log("SAFE_METADATA", uri);
    }

    function test_ForkTemplateFixture_RefusalsHaveNoEffects() public forkOnly {
        _installBaseTemplateFixtureIfMissing();
        (Round memory draft, CyberCertData[] memory certs) = _round();
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, attacker));
        vm.prank(attacker);
        manager.createRound(draft, certs);
        bytes32 id = _createRound();
        vm.prank(investor);
        payment.approve(address(manager), OFFER);
        bytes memory badSignature = _signature(201, officerKey);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        _submit(id, 201, badSignature);
        assertEq(payment.balanceOf(investor), INITIAL_BALANCE);
        assertEq(payment.balanceOf(address(manager)), 0);
        bytes32 agreementId = _submit(id, 202, _signature(202, investorKey));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 99, attacker));
        vm.prank(attacker);
        manager.allocate(agreementId, ALLOCATION);
        assertEq(manager.getRound(id).raised, 0);
        assertFalse(registry.isFinalized(agreementId));
        assertEq(manager.getEscrowDetails(agreementId).corpAssets.length, 0);
        assertEq(payment.balanceOf(address(manager)), OFFER);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        vm.prank(investor);
        manager.recallEOI(agreementId);
        vm.warp(manager.getEscrowDetails(agreementId).expiry + 1);
        vm.prank(investor);
        manager.recallEOI(agreementId);
        assertEq(payment.balanceOf(investor), INITIAL_BALANCE);
        assertEq(payment.balanceOf(address(manager)), 0);
        assertTrue(registry.isVoided(agreementId));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; i++) {
            bool match_ = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
