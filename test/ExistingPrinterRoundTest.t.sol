// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RoundManagerTest, CyberCorpHelper} from "./RoundManagerTest.t.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {MockPaymentToken} from "./RoundManagerTest.t.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {Round, RoundType} from "../src/libs/RoundLib.sol";
import {RoundManagerStorage, IExistingStockPrinter} from "../src/storage/RoundManagerStorage.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";

contract ExistingPrinterRoundTest is RoundManagerTest {
    function reuseDraft() internal returns (Round memory draft) {
        draft = RoundManager(roundManager).getRound(roundId);
        vm.startPrank(corpOwner);
        uint256 classId = IssuanceManager(issuance).getPrinterClassId(draft.certPrinter[0]);
        IssuanceManager(issuance).updateSecurityClass(classId, SecurityClass.CommonStock, "ipfs://class", address(0), "");
        IssuanceManager(issuance).setPrinterClass(draft.certPrinter[0], classId);
        vm.stopPrank();
        draft.seriesType = SecuritySeries.NA;
        draft.escrowedSignature = "";
    }

    function signReuse(Round memory draft) internal view returns (Round memory, bytes32) {
        (bytes32 id, bytes32 configHash) = RoundManager(roundManager).previewExistingPrinterRound(draft);
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("RoundManager"), keccak256("1"), block.chainid, roundManager
        ));
        bytes32 message = keccak256(abi.encode(
            keccak256("EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"),
            id, uint8(draft.seriesType), draft.raiseCap, draft.minTicket, draft.maxTicket, uint8(draft.roundType),
            draft.startTime, draft.endTime, draft.templateId, draft.paymentToken, draft.pricePerUnit, draft.valuation, corp
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(corpOwnerPrivKey, keccak256(abi.encodePacked("\x19\x01", domain, message)));
        draft.escrowedSignature = abi.encodePacked(r,s,v);
        return (draft,configHash);
    }

    function test_existingPrinterAllocationPreservesOldCertificate() public {
        vm.startPrank(investor);
        (bytes32 oldAgreement,) = CyberCorpHelper.submitEOI(RoundManager(roundManager), registry, roundId, 1, 5000e6, 10000e6, corpOwner, investorPrivKey);
        vm.stopPrank();
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(oldAgreement, 7500e6);
        Round memory draft = reuseDraft();
        ILedgerEntryToken printer = ILedgerEntryToken(draft.certPrinter[0]);
        bytes32 oldDetails = keccak256(abi.encode(printer.getCertificateDetails(0)));
        bytes32 configHash;
        (draft, configHash) = signReuse(draft);
        vm.prank(corpOwner);
        bytes32 newId = RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        assertTrue(newId != roundId);
        assertEq(RoundManager(roundManager).getRound(newId).certPrinter[0], address(printer));
        assertEq(printer.totalSupply(), 1);
        vm.startPrank(investor2);
        (bytes32 agreement,) = CyberCorpHelper.submitEOI(RoundManager(roundManager), registry, newId, 2, 5000e6, 10000e6, corpOwner, investor2PrivKey);
        vm.stopPrank();
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreement, 5000e6);
        assertEq(printer.totalSupply(), 2);
        assertEq(printer.getCertificateDetails(1).unitsRepresented, 500e18);
        assertEq(keccak256(abi.encode(printer.getCertificateDetails(0))), oldDetails);
        assertEq(RoundManager(roundManager).getRound(newId).raised, 5000e6);
    }

    function test_existingPrinterRejectsChangedPurchaseTerms() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        draft.legalDetails[0] = "substituted terms";
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinterSignature.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsConfigurationChange() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.prank(corpOwner);
        ILedgerEntryToken(draft.certPrinter[0]).addDefaultLegend("new restriction");
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterConfigurationChanged.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsDuplicateRound() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.startPrank(corpOwner);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterRoundExists.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        vm.stopPrank();
    }

    function test_existingPrinterRejectsWrongSeries() public {
        Round memory draft = reuseDraft();
        draft.seriesType = SecuritySeries.SeriesSeed;
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
    }

    function test_existingPrinterRejectsUnclassifiedPrinter() public {
        Round memory draft = reuseDraft();
        vm.prank(corpOwner);
        IssuanceManager(issuance).setPrinterClass(draft.certPrinter[0], 0);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
    }

    function test_existingPrinterRejectsChangedFlagsAndPartyValues() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        draft.publicRound = !draft.publicRound;
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinterSignature.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        draft.publicRound = !draft.publicRound;
        draft.roundPartyValues[0] = "different capacity";
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinterSignature.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsOldPathSignature() public {
        bytes memory oldSignature = RoundManager(roundManager).getRound(roundId).escrowedSignature;
        Round memory draft = reuseDraft();
        (, bytes32 configHash) = RoundManager(roundManager).previewExistingPrinterRound(draft);
        draft.escrowedSignature = oldSignature;
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinterSignature.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsNonOwnerAndForeignPrinter() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.prank(investor);
        vm.expectRevert(abi.encodeWithSignature("BorgAuth_NotAuthorized(uint256,address)", 99, investor));
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        draft.certPrinter[0] = address(paymentToken);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
    }

    function test_existingPrinterRejectsTransferabilityChange() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        bool transferable = IExistingStockPrinter(draft.certPrinter[0]).transferable();
        vm.prank(corpOwner);
        ILedgerEntryToken(draft.certPrinter[0]).setGlobalTransferable(!transferable);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterConfigurationChanged.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsWrongArrayLengthAndZeroPrice() public {
        Round memory draft = reuseDraft();
        draft.pricePerUnit = 0;
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
        draft.pricePerUnit = 1e18;
        draft.extensionData = new bytes[](0);
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
    }

    function test_existingPrinterRejectsManagerMismatch() public {
        Round memory draft = reuseDraft();
        vm.mockCall(draft.certPrinter[0], abi.encodeWithSelector(ILedgerEntryToken.issuanceManager.selector), abi.encode(address(0x1234)));
        vm.expectRevert(RoundManagerStorage.InvalidExistingPrinter.selector);
        RoundManager(roundManager).previewExistingPrinterRound(draft);
    }

    function test_existingPrinterRejectsEndorsementChange() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        bool prior = IExistingStockPrinter(draft.certPrinter[0]).endorsementRequired();
        vm.mockCall(draft.certPrinter[0], abi.encodeWithSelector(IExistingStockPrinter.endorsementRequired.selector), abi.encode(!prior));
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterConfigurationChanged.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function createReuseFixture() internal {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.prank(corpOwner);
        roundId = RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectRefund() public {
        createReuseFixture();
        test_RejectEOI_RefundsAndVoids();
    }

    function test_existingPrinterRecallRefund() public {
        createReuseFixture();
        test_RecallEOI_RefundsAndVoids();
    }

    function test_existingPrinterRaiseCap() public {
        createReuseFixture();
        test_MultipleAllocations_RespectRaiseCap();
    }

    function test_existingPrinterFCFS() public {
        Round memory draft = reuseDraft();
        draft.roundType = RoundType.FCFS;
        bytes32 configHash;
        (draft, configHash) = signReuse(draft);
        vm.prank(corpOwner);
        bytes32 id = RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
        deal(address(paymentToken), address(this), 20000e6);
        CyberCorpHelper.submitFCFSRoundEOIAndAssertFinalized(RoundManager(roundManager), registry, draft.templateId, address(paymentToken), 6, id, corpOwner);
        assertEq(ILedgerEntryToken(draft.certPrinter[0]).totalSupply(), 1);
    }

    function test_existingPrinterRejectsBadgeChange() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.prank(corpOwner);
        ILedgerEntryToken(draft.certPrinter[0]).setLookThroughBadge(address(0x1234));
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterConfigurationChanged.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterRejectsSeriesDataChange() public {
        (Round memory draft, bytes32 configHash) = signReuse(reuseDraft());
        vm.prank(corpOwner);
        ILedgerEntryToken(draft.certPrinter[0]).setSeriesData(hex"1234");
        vm.prank(corpOwner);
        vm.expectRevert(RoundManagerStorage.ExistingPrinterConfigurationChanged.selector);
        RoundManager(roundManager).createRoundWithExistingPrinter(draft, configHash);
    }

    function test_existingPrinterEncodingVector() public {
        Round memory draft = reuseDraft();
        (bytes32 id, bytes32 configurationHash) = RoundManager(roundManager).previewExistingPrinterRound(draft);
        assertEq(id, bytes32(0x19edabb5ce8ae5cc0e2126ab7bdeaf96dc885d116e1616b205a3188c7aebe7a9));
        emit log_named_bytes("round encoding vector", abi.encode(draft, configurationHash, id, block.chainid, roundManager, corp, uint8(SecurityClass.CommonStock)));
    }

    function test_existingForkUpgradeAndReuse() public {
        if (!vm.envOr("RUN_REUSE_FORK", false)) { vm.skip(true); return; }
        vm.createSelectFork(vm.envString("RPC_URL_ETHEREUM"));
        emit log_named_uint("fork block", block.number);
        investorPrivKey = uint256(keccak256("existing-printer-round-fork-investor-test-only"));
        investor = vm.addr(investorPrivKey);
        assertEq(investor.code.length, 0, "test investor must be a fresh EOA");
        roundManager = 0x32854b045DA2D7C23c6D90BeA66FA114E13B7c66;
        corp = 0xe7216d30e84CDf067B08e1A41deD4Ef60DE31023;
        corpOwner = 0x3B12Bfc36931155A8Dc26c6636D0C888E9a3F55C;
        address platformOwner = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
        address factory = address(uint160(uint256(vm.load(roundManager, bytes32(uint256(keccak256("cybercorp.round.manager.storage.v1")) + 1)))));
        address registryAddress = address(uint160(uint256(vm.load(roundManager, bytes32(uint256(keccak256("cybercorp.lexscrow.storage.v1")) + 1)))));
        registry = CyberAgreementRegistry(registryAddress);
        RoundManager implementation = new RoundManager();
        vm.prank(platformOwner);
        RoundManagerFactory(factory).setRefImplementation(address(implementation));
        vm.prank(corpOwner);
        RoundManager(roundManager).upgradeToAndCall(address(implementation), "");
        assertEq(RoundManager(roundManager).existingPrinterRoundVersion(), 1);
        vm.prank(platformOwner);
        CyberCorpHelper.createTemplate(registry);
        // Synthetic test currency/template/signers on the isolated fork only.
        paymentToken = new MockPaymentToken();
        Round memory draft;
        draft.certPrinter = new address[](1);
        draft.certPrinter[0] = 0xe48F7f3DE3F68E7C53Deaf6D092C0eC6Af459e0A;
        draft.seriesType = SecuritySeries.SeriesSeed;
        draft.pricePerUnit = 10e18;
        draft.raiseCap = 100000e6;
        draft.minTicket = 1e6;
        draft.maxTicket = 100000e6;
        draft.startTime = block.timestamp;
        draft.endTime = block.timestamp + 30 days;
        draft.templateId = CyberCorpHelper.TEMPLATE_ID;
        draft.paymentToken = address(paymentToken);
        draft.authorityOfficer = vm.addr(corpOwnerPrivKey);
        draft.officerName = "Fork test officer";
        draft.officerTitle = "Test only";
        draft.legalDetails = new string[](1);
        draft.extensionData = new bytes[](1);
        draft.roundPartyValues = new string[](2);
        draft.allowTimedOffers = true;
        // Founder-approved mode retains the explicit allocation step.
        draft.roundType = RoundType.FounderApproved;
        bytes32 configurationHash;
        (draft, configurationHash) = signReuse(draft);
        ILedgerEntryToken printer = ILedgerEntryToken(draft.certPrinter[0]);
        uint256 beforeSupply = printer.totalSupply();
        vm.prank(corpOwner);
        bytes32 id = RoundManager(roundManager).createRoundWithExistingPrinter(draft, configurationHash);
        paymentToken.transfer(investor, 20000e6);
        vm.startPrank(investor);
        paymentToken.approve(roundManager, type(uint256).max);
        (bytes32 agreement,) = CyberCorpHelper.submitEOI(RoundManager(roundManager), registry, id, 999, 5000e6, 10000e6, draft.authorityOfficer, investorPrivKey);
        vm.stopPrank();
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreement, 5000e6);
        assertEq(printer.totalSupply(), beforeSupply + 1);
        assertEq(RoundManager(roundManager).getRound(id).raised, 5000e6);
    }
}
