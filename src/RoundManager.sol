/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
 o88o     o8888o                                                                                       
                                                                                                       
                                                                                                       
                                                                                                       
 ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
 `88.       .888'             .o8             `888'                   `8888    d8'                     
  888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
  8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
  8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
  8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
 o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                       
                                                                                                       
                                                                                                       
   .oooooo.                .o8                            .oooooo.                                     
  d8P'  `Y8b              "888                           d8P'  `Y8b                                    
 888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
 888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
 888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
 `88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
  `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
              .o..P'                                                                     888           
              `Y8P'                                                                     o888o          
 _______________________________________________________________________________________________________
 
 All software, documentation and other files and information in this repository (collectively, the "Software")
 are copyright MetaLeX Labs, Inc., a Delaware corporation.
 
 All rights reserved.
 
 The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
 distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
 mechanical, including photocopying, recording, or by any information storage and retrieval system, 
 except with the express prior written permission of the copyright holder.*/

pragma solidity ^0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ILexScrowStorage.sol";
import "./libs/auth.sol";
import "./storage/RoundManagerStorage.sol";
import "./storage/RoundManagerFactoryStorage.sol";
import "./storage/BorgAuthStorage.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/ILedgerEntryToken.sol";
import "./interfaces/IRoundManagerFactory.sol";
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/ILexChex.sol";
import "./interfaces/IRoundManager.sol";

/// @title RoundManager
/// @notice Manages fundraising rounds for CyberCorp, handling EOIs, escrows, and allocations
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract RoundManager is
    Initializable,
    BorgAuthACL,
    UUPSUpgradeable,
    ReentrancyGuard,
    ILexScrowStorage,
    IRoundManager
{
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;
    using LexScrowStorage for LexScrowStorage.LexScrowData;
    using SafeERC20 for IERC20;

    string public constant DEPLOY_VERSION = "5.1"; // For version-tracking on all deployment and future upgrades

    error InvalidRound();
    error RoundNotOpen();
    error InvalidAmount();
    error InvalidAllocation();
    error AlreadyAllocated();
    error InvalidParties();
    error InvalidCertPrinter();
    error InvalidCert();
    error ZeroAddress();
    error InvalidIssuanceManager();
    error InvalidEscrowedSignature();
    error EOINotExpired();
    error EOIExpired();
    error NotEOISubmitter();
    error NotRefImplementation();
    error EndTimeReductionRestricted();
    error RoundAlreadyExists();
    error NotCompanyOfficer(address signer);
    error InvalidMinimum();
    error MinimumNotMet();
    error EndTimeAfterMinimumDeadline();
    error AgreementNotInRound(bytes32 agreementId);
    error ArrayLengthMismatch();
    error MinimumAlreadyMet();
    error NotCommitted(bytes32 agreementId);
    error CommitmentLocked(bytes32 agreementId);
    error SettleWindowTooShort(bytes32 agreementId);
    error CommitmentListInvalid();

    event EOIRecalled(bytes32 agreementId, address indexed investor, bytes32 indexed roundId);
    event LexChexUpdated(address indexed lexChex, address indexed oldLexChex);
    event RoundMinimumSet(bytes32 indexed roundId, uint256 minRaise, uint256 deadline);
    event RoundMinimumMet(bytes32 indexed roundId, uint256 committedTotal);
    event AllocationCommitted(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 amount, uint256 committedTotal);
    event AllocationUncommitted(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 amount, uint256 committedTotal);

    /// @notice Time a committed escrow must stay open when committed and when the minimum is met
    uint256 public constant SETTLE_WINDOW = RoundManagerStorage.SETTLE_WINDOW;

    /// @dev Restricts execution to contract itself or AUTH.OWNER_ROLE callers
    modifier onlyOwnerOrSelf() {
        if (msg.sender != address(this)) {
            AUTH.onlyRole(AUTH.OWNER_ROLE(), msg.sender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the RoundManager contract
    /// @param _auth Address of the BorgAuth contract
    /// @param _corp Address of the CyberCorp
    /// @param _dealRegistry Address of the CyberAgreementRegistry
    /// @param _issuanceManager Address of the CyberCorp's issuance manager
    /// @param _upgradeFactory Address of the upgrade factory
    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager,
        address _upgradeFactory
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        // LexScrowStorage is now a library — set escrow core addresses in storage directly
        LexScrowStorage.setCorp(_corp);
        LexScrowStorage.setDealRegistry(_dealRegistry);

        if (_corp == address(0)) revert ZeroAddress();
        if (_dealRegistry == address(0)) revert ZeroAddress();
        if (_issuanceManager == address(0)) revert ZeroAddress();

        RoundManagerStorage.setIssuanceManager(_issuanceManager);
        RoundManagerStorage.setUpgradeFactory(_upgradeFactory);

        // Default LeXcheX config
        RoundManagerStorage.setLexChex(address(0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62));
        RoundManagerStorage.setLexChexCondition(address(0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42));
        RoundManagerStorage.setLexChexMinter(address(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960));
        // No persistent DOMAIN_SEPARATOR; compute dynamically to avoid storage costs
    }

    /// @notice Sets the LeXcheX AUTH address
    function setLexChex(address _lexchex) external onlyOwner {
        if (_lexchex == address(0)) revert ZeroAddress();
        address oldLexChex = RoundManagerStorage.getLexChex();
        RoundManagerStorage.setLexChex(_lexchex);
        emit LexChexUpdated(_lexchex, oldLexChex);
    }

    /// @notice Gets the LeXcheX AUTH address
    function getLexChex() external view returns (address) {
        return RoundManagerStorage.getLexChex();
    }

    /// @notice Creates a new fundraising round
    /// @param roundDraft partially-filled round info created by RoundLib
    /// @param certData certificate info
    /// @return roundId ID of the created round
    function createRound(
        Round memory roundDraft,
        CyberCertData[] memory certData
    ) external onlyOwner returns (bytes32) {
        _validateRound(roundDraft, certData.length);
        return _emitRoundCreated(RoundManagerStorage.createRound(LexScrowStorage.getCorp(), roundDraft, certData));
    }

    /// @notice Creates a new fundraising round that issues from existing certificate printers
    /// @param roundDraft partially-filled round info created by RoundLib
    /// @param certPrinters existing certificate printers of this cyberCORP
    /// @return roundId ID of the created round
    function createRoundWithPrinters(
        Round memory roundDraft,
        address[] memory certPrinters
    ) external onlyOwner returns (bytes32) {
        _validateRound(roundDraft, certPrinters.length);
        return _emitRoundCreated(RoundManagerStorage.createRoundWithPrinters(roundDraft, certPrinters));
    }

    /// @notice Creates a founder-approved round that keeps no allocation unless `minRaise` is reached
    /// @dev The minimum is fixed at creation. Until it is met, the owner commits allocations
    /// (`setCommitments`) and marks the minimum met (`markMinimumMet`) while the round is open;
    /// then anyone settles the commitments (`settle`). Below it, `reject` and `recallEOI` refund
    /// each payment as for any round.
    /// @param roundDraft partially-filled round info created by RoundLib
    /// @param certData certificate info
    /// @param minRaise minimum total raise in the payment token, gross of fees
    /// @param deadline latest end time the round can be extended to while the minimum is unmet
    /// @return roundId ID of the created round
    function createRoundWithMinimum(
        Round memory roundDraft,
        CyberCertData[] memory certData,
        uint256 minRaise,
        uint256 deadline
    ) external onlyOwner returns (bytes32) {
        _validateRound(roundDraft, certData.length);
        bytes32 roundId = _emitRoundCreated(
            RoundManagerStorage.createRound(LexScrowStorage.getCorp(), roundDraft, certData)
        );
        RoundManagerStorage.setMinimum(roundId, minRaise, deadline);
        return roundId;
    }

    /// @notice Same as `createRoundWithMinimum`, issuing from existing certificate printers
    function createRoundWithPrintersAndMinimum(
        Round memory roundDraft,
        address[] memory certPrinters,
        uint256 minRaise,
        uint256 deadline
    ) external onlyOwner returns (bytes32) {
        _validateRound(roundDraft, certPrinters.length);
        bytes32 roundId = _emitRoundCreated(
            RoundManagerStorage.createRoundWithPrinters(roundDraft, certPrinters)
        );
        RoundManagerStorage.setMinimum(roundId, minRaise, deadline);
        return roundId;
    }

    /// @notice Returns a round's minimum raise state
    /// @return minRaise minimum total raise (0 = no minimum)
    /// @return deadline latest end time while the minimum is unmet
    /// @return met whether the minimum has been marked met
    /// @return raised amount raised (allocated) so far
    /// @return committed sum of open commitments
    function getRoundMinimum(bytes32 roundId)
        external
        view
        returns (uint256 minRaise, uint256 deadline, bool met, uint256 raised, uint256 committed)
    {
        (minRaise, deadline, met) = RoundManagerStorage.getRoundMinimum(roundId);
        raised = RoundManagerStorage.getRound(roundId).raised;
        committed = RoundManagerStorage.getCommittedTotal(roundId);
    }

    /// @dev Checks the draft, sets its id and verifies the escrowed signature
    function _validateRound(Round memory roundDraft, uint256 certCount) private view {
        // Validate lengths of per-cert details
        if (roundDraft.legalDetails.length != certCount) revert InvalidCert();
        if (roundDraft.extensionData.length != certCount) revert InvalidCert();
        if (roundDraft.escrowedSignature.length == 0) revert InvalidEscrowedSignature();
        if (roundDraft.pricePerUnit == 0) revert InvalidAmount();

        address corp = LexScrowStorage.getCorp();

        roundDraft.id = keccak256(
            abi.encodePacked(
                roundDraft.seriesType,
                roundDraft.raiseCap,
                roundDraft.minTicket,
                roundDraft.maxTicket,
                uint8(roundDraft.roundType),
                roundDraft.startTime,
                roundDraft.endTime,
                roundDraft.templateId,
                roundDraft.paymentToken,
                roundDraft.pricePerUnit,
                roundDraft.valuation,
                corp
            )
        );

        if (RoundManagerStorage.getRound(roundDraft.id).id != bytes32(0)) revert RoundAlreadyExists();

        if(!RoundManagerStorage.verifyEscrowedSignature(
            roundDraft.authorityOfficer,
            RoundManagerStorage.EscrowedSignatureData({
                roundId: roundDraft.id,
                seriesType: uint8(roundDraft.seriesType),
                raiseCap: roundDraft.raiseCap,
                minTicket: roundDraft.minTicket,
                maxTicket: roundDraft.maxTicket,
                roundType: uint8(roundDraft.roundType),
                startTime: roundDraft.startTime,
                endTime: roundDraft.endTime,
                templateId: roundDraft.templateId,
                paymentToken: roundDraft.paymentToken,
                pricePerUnit: roundDraft.pricePerUnit,
                valuation: roundDraft.valuation,
                companyAddress: corp
            }),
            roundDraft.escrowedSignature
        )) revert InvalidEscrowedSignature();

        // The round signer must be a current officer of the company.
        if (!ICyberCorp(corp).isCyberCORPOfficer(roundDraft.authorityOfficer)) revert NotCompanyOfficer(roundDraft.authorityOfficer);
    }

    function _emitRoundCreated(Round memory round) private returns (bytes32) {
        emit RoundCreated(
            round.id,
            LexScrowStorage.getCorp(),
            round,
            round.publicRound
        );

        return round.id;
    }

    // ===============
    // Round metadata
    // ===============

    function setRoundPricePerShare(
        bytes32 roundId,
        uint256 price,
        uint8 priceDecimals
    ) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        round.roundPricePerShare = price;
        round.roundPriceDecimals = priceDecimals;
    }

    function setPrimarySecurity(
        bytes32 roundId,
        SecurityClass cls,
        SecuritySeries series
    ) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        round.primarySecurityClass = cls;
        round.primarySecuritySeries = series;
    }

    /// @notice Owner can update the endTime of a round
    /// @param roundId The round ID
    /// @param newEndTime The new end timestamp
    function setRoundEndTime(bytes32 roundId, uint256 newEndTime) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        if (round.restrictEndTimeReduction && newEndTime < round.endTime) revert EndTimeReductionRestricted();
        if (RoundManagerStorage.isMinimumPending(roundId)) {
            (, uint256 deadline, ) = RoundManagerStorage.getRoundMinimum(roundId);
            if (newEndTime > deadline) revert EndTimeAfterMinimumDeadline();
        }
        uint256 oldEndTime = round.endTime;
        round.endTime = newEndTime;
        emit RoundEndTimeUpdated(roundId, oldEndTime, newEndTime);
    }

    /// @notice Owner can close the round immediately by setting endTime to now
    /// @param roundId The round ID
    function closeRoundNow(bytes32 roundId) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        if (round.restrictEndTimeReduction) revert EndTimeReductionRestricted();
        uint256 oldEndTime = round.endTime;
        round.endTime = block.timestamp;
        emit RoundEndTimeUpdated(roundId, oldEndTime, round.endTime);
        emit RoundClosed(roundId, block.timestamp);
    }

    function getRound(
        bytes32 roundId
    )
        external
        view
        returns (Round memory)
    {
        return RoundManagerStorage.getRound(roundId);
    }

    function getRoundPriceInfo(
        bytes32 roundId
    )
        external
        view
        returns (uint256 roundPricePerShare, uint8 roundPriceDecimals)
    {
        Round storage round = RoundManagerStorage.getRound(roundId);
        return (round.roundPricePerShare, round.roundPriceDecimals);
    }

    function getPrimarySecurity(
        bytes32 roundId
    ) external view returns (SecurityClass cls, SecuritySeries series) {
        Round storage round = RoundManagerStorage.getRound(roundId);
        return (round.primarySecurityClass, round.primarySecuritySeries);
    }

    function roundExists(bytes32 roundId) external view returns (bool) {
        Round storage round = RoundManagerStorage.getRound(roundId);
        return round.id != bytes32(0);
    }

    /// @notice Submits an Expression of Interest for a round
    /// @param roundId The round ID
    /// @param eoi The EOI details
    /// @param globalValues Global values for the agreement
    /// @param partyValues Party values for the agreement (single party: investor)
    /// @param signature Investor's signature for the agreement
    /// @param salt Salt for agreement ID
    /// @param conditions Condition contracts
    /// @param secretHash Secret hash if required
    /// @return agreementId The created agreement ID
    function submitEOI(
        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash
    ) external returns (bytes32 agreementId, uint256 tokenId) {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        if (
            block.timestamp < round.startTime || block.timestamp > round.endTime
        ) revert RoundNotOpen();
        if (
            eoi.minAmount > eoi.maxAmount ||
            eoi.maxAmount < round.minTicket ||
            eoi.maxAmount > round.maxTicket ||
            eoi.minAmount < round.minTicket
        ) revert InvalidAmount();
        // If round uses timed offers, require EOI expiry in the future; otherwise ignore
        if (round.allowTimedOffers && eoi.expiry < block.timestamp) revert EOIExpired();

        (agreementId, tokenId) = RoundManagerStorage.submitEOI(
            LexScrowStorage.lexScrowStorage(),
            roundId,
            eoi,
            globalValues,
            partyValues,
            signature,
            salt,
            conditions,
            secretHash
        );

        // Interaction: payments
        LexScrowStorage.handleCounterPartyPayment(agreementId);

        emit EOISubmitted(agreementId, roundId, msg.sender, LexScrowStorage.getCorp(), eoi.minAmount, eoi.maxAmount, eoi.expiry);

        if (round.roundType == RoundType.FCFS) {
            this.allocate(agreementId, eoi.maxAmount);
        }
    }

    /// @notice Allocates an amount to an EOI and finalizes the deal
    /// @param agreementId The agreement ID
    /// @param allocatedAmount The amount to allocate
    /// @dev Refused while the round's minimum is unmet: those rounds close through `allocateBatch`.
    function allocate(
        bytes32 agreementId,
        uint256 allocatedAmount
    ) external onlyOwnerOrSelf nonReentrant returns (uint256) {
        if (RoundManagerStorage.isMinimumPending(RoundManagerStorage.getAgreementToRound(agreementId))) {
            revert MinimumNotMet();
        }
        return _allocate(agreementId, allocatedAmount);
    }

    /// @notice Allocates several EOIs of one round in a single transaction
    /// @dev Refused while the round's minimum is unmet (use the commit and settle steps).
    /// Any failing allocation reverts the batch.
    /// @param agreementIds agreement IDs, all in the same round
    /// @param allocatedAmounts amount to allocate to each agreement
    function allocateBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata allocatedAmounts
    ) external onlyOwner nonReentrant {
        uint256 count = agreementIds.length;
        if (count == 0 || count != allocatedAmounts.length) revert ArrayLengthMismatch();

        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementIds[0]);
        if (RoundManagerStorage.isMinimumPending(roundId)) revert MinimumNotMet();

        for (uint256 i = 0; i < count; i++) {
            if (RoundManagerStorage.getAgreementToRound(agreementIds[i]) != roundId) {
                revert AgreementNotInRound(agreementIds[i]);
            }
            _allocate(agreementIds[i], allocatedAmounts[i]);
        }
    }

    // ===============
    // Minimum raise: commit, then settle
    // ===============

    /// @notice Step 1: sets commitments on a round whose minimum is unmet. Moves no funds.
    /// @dev Any number of calls while the round is open. A positive amount commits or replaces a
    /// commitment (the escrow must stay open for at least `SETTLE_WINDOW`; an amount above the
    /// payment is reduced to it). An amount of 0 removes the commitment.
    function setCommitments(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts
    ) external onlyOwner {
        RoundManagerStorage.setCommitments(LexScrowStorage.lexScrowStorage(), agreementIds, amounts);
    }

    /// @notice Marks the minimum met once commitments reach it; commitments are then locked
    /// @param roundId The round ID
    /// @param committedIds every committed agreement of the round, in strictly ascending order
    function markMinimumMet(bytes32 roundId, bytes32[] calldata committedIds) external onlyOwner {
        uint256 total = RoundManagerStorage.markMinimumMet(LexScrowStorage.lexScrowStorage(), roundId, committedIds);
        emit RoundMinimumMet(roundId, total);
    }

    /// @notice Step 2: settles committed allocations after the minimum is met
    /// @dev Permissionless, so settlement does not depend on the company. Each agreement is
    /// allocated at its committed amount and must settle before its escrow expiry.
    /// @param agreementIds committed agreement IDs
    function settle(bytes32[] calldata agreementIds) external nonReentrant {
        for (uint256 i = 0; i < agreementIds.length; i++) {
            _allocate(agreementIds[i], RoundManagerStorage.takeCommitment(agreementIds[i]));
        }
    }

    /// @notice Committed amount of an agreement (0 = not committed)
    function getCommittedAmount(bytes32 agreementId) external view returns (uint256) {
        return RoundManagerStorage.getCommittedAmount(agreementId);
    }

    function _allocate(
        bytes32 agreementId,
        uint256 allocatedAmount
    ) private returns (uint256) {
        // A commitment settles only through `settle`, at its committed amount.
        if (RoundManagerStorage.getCommittedAmount(agreementId) != 0) revert CommitmentLocked(agreementId);
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        EOI storage eoi = RoundManagerStorage.getAgreementToEOI(agreementId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check: round validity
        if (round.id == bytes32(0)) revert InvalidRound();

        // Check: offer has not expired based on escrow expiry ( = round.allowTimedOffers ? eoi.expiry : round.endTime)
        if (escrow.expiry < block.timestamp) revert EOIExpired();

        // Capacity held by open commitments is not available. When `settle` runs
        // this, the settling commitment has already left the committed total.
        uint256 remaining = round.raiseCap - round.raised - RoundManagerStorage.getCommittedTotal(roundId);
        uint256 candidate = escrow.buyerAssets[0].amount;
        if (allocatedAmount < candidate) { 
            candidate = allocatedAmount;
        }
        if (candidate > remaining) {
            candidate = remaining;
        }
        uint256 minRequired = round.minTicket > eoi.minAmount ? round.minTicket : eoi.minAmount;
        // We check `candidate` instead of the actual `usedAmount` against `minRequired` to provide a better user experience.
        // When `pricePerUnit` is not exactly 1e18, rounding errors can cause `usedAmount` to be slightly less than `candidate`.
        // In a normal scenario a user is likely to set `candidate` exactly to `minRequired` and expect the transaction to succeed;
        // however, if we checked `usedAmount` instead against `minRequired` and rounding pushed it just below the threshold,
        // the transaction would fail unexpectedly and cause confusion.
        if (candidate < minRequired) {
            revert InvalidAllocation();
        }
        // Do not round here; pass requested candidate and compute dust/refund in storage
        allocatedAmount = candidate;

        // Check: status
        if (escrow.status != EscrowStatus.PAID) revert LexScrowStorage.DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        (uint256 tokenId, uint256[] memory certIds, uint256 usedAmount, uint256 refund) = RoundManagerStorage.allocate(
            LexScrowStorage.lexScrowStorage(),
            agreementId,
            allocatedAmount
        );

        // Check: Check conditions
        if (!LexScrowStorage.conditionCheck(agreementId)) revert ILexScrowStorage.AgreementConditionsNotMet();

        // Effect: Finalize agreement
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
            .finalizeContract(agreementId);

        // Effect: update raised amount to reflect only usedAmount (allocated rounded down to pricePerUnit)
        // refund was computed as (original escrowed amount - usedAmount), so usedAmount = original - refund
        round.raised += usedAmount;

        if (refund > 0) {
            // Interaction: Refund
            IERC20(round.paymentToken).safeTransfer(
                escrow.counterParty,
                refund
            );
        }

        // Interaction: Finalize escrow and payments
        LexScrowStorage.finalizeEscrow(agreementId);

        emit AllocationMade(agreementId, roundId, escrow.counterParty, usedAmount, round.raised, certIds);

        return tokenId;
    }

    /// @notice Rejects an EOI and voids the deal
    /// @param agreementId The agreement ID
    function reject(bytes32 agreementId) external onlyOwner {
        reject(agreementId, true);
    }

    /// @notice Rejects an EOI and voids the deal if necessary
    /// @dev The extra parameter allows handling the edge case where the party voided the agreement by
    /// directly requesting to CyberAgreementRegistry and bypassing RoundManager.
    /// In such case, we want to skip `voidContractFor()` so it does not attempt to void the contract again.
    /// @param agreementId The agreement ID
    /// @param isVoidAgreement True if voiding the deal
    function reject(bytes32 agreementId, bool isVoidAgreement) public onlyOwner {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check: check status
        if (round.id == bytes32(0)) revert InvalidRound();
        if (escrow.status != EscrowStatus.PAID) revert LexScrowStorage.DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        // Effect: clear a commitment; refused once the minimum is met
        RoundManagerStorage.releaseCommitment(agreementId, escrow.expiry, false);

        // Effect: update status
        LexScrowStorage.voidEscrow(agreementId);

        if (isVoidAgreement) {
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, escrow.counterParty, escrow.signature);
        }

        // Interaction: Refund all
        uint256 amount = escrow.buyerAssets[0].amount;
        IERC20(round.paymentToken).safeTransfer(escrow.counterParty, amount);

        emit EOIRejected(agreementId, escrow.counterParty, roundId);
    }

    /// @notice Allow a eoi submitter to recall their eoi, get a refund and void the agreement after the eoi expiry
    /// @param agreementId The agreement ID
    function recallEOI(bytes32 agreementId) external {
        recallEOI(agreementId, true);
    }

    /// @notice Allow a eoi submitter to recall their eoi, get a refund and void the agreement if necessary after the eoi expiry
    /// @dev The extra parameter allows handling the edge case where the party voided the agreement by
    /// directly requesting to CyberAgreementRegistry and bypassing RoundManager.
    /// In such case, we want to skip `voidContractFor()` so it does not attempt to void the contract again.
    /// @param agreementId The agreement ID
    /// @param isVoidAgreement True if voiding the deal
    function recallEOI(bytes32 agreementId, bool isVoidAgreement) public {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check: check status
        if (round.id == bytes32(0)) revert InvalidRound();
        if (msg.sender != escrow.counterParty) revert NotEOISubmitter();
        if (escrow.status != EscrowStatus.PAID) revert LexScrowStorage.DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();
        if (block.timestamp < escrow.expiry && round.endTime > block.timestamp) revert EOINotExpired();

        // Effect: clear a commitment; once the minimum is met, only after the escrow expiry
        RoundManagerStorage.releaseCommitment(agreementId, escrow.expiry, true);

        // Effect: update status
        LexScrowStorage.voidEscrow(agreementId);

        // void agreement
        if (isVoidAgreement) {
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, escrow.counterParty, escrow.signature);
        }


        // Interaction: Refund all
        uint256 amount = escrow.buyerAssets[0].amount;
        IERC20(round.paymentToken).safeTransfer(escrow.counterParty, amount);

        emit EOIRecalled(agreementId, escrow.counterParty, roundId);
    }


    /// @notice Gets the issuance manager
    /// @return IIssuanceManager The issuance manager
    function issuanceManager() public view returns (IIssuanceManager) {
        return RoundManagerStorage.getIssuanceManager();
    }

    /// @notice Compute fee based on ticket size
    /// @dev Currently the factory owner (MetaLeX) unilaterally set the fee ratio;
    /// in the future, it could be determined through a governance process.
    /// @return Fee amount
    function computeFee(uint256 size) public view override(ILexScrowStorage, IRoundManager) returns (uint256) {
        return size * IRoundManagerFactory(RoundManagerStorage.getUpgradeFactory()).getDefaultFeeRatio() / RoundManagerFactoryStorage.BASIS_POINTS;
    }

    /// @notice Gets the payable address for the fees
    /// @dev The factory owner (MetaLeX) unilaterally set the payable address
    /// @return Payable address for the fees
    function getPlatformPayable() public view override(ILexScrowStorage, IRoundManager) returns (address) {
        return IRoundManagerFactory(RoundManagerStorage.getUpgradeFactory()).getPlatformPayable();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LexScrowStorage surface — thin wrappers (LexScrowStorage is now a library) so the proxy keeps
    // exposing these selectors for off-chain callers and condition contracts (ILexScrowStorage).
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get escrow details for a given agreement id
    function getEscrowDetails(bytes32 agreementId) public view returns (Escrow memory) {
        return LexScrowStorage.getEscrow(agreementId);
    }

    /// @notice Check all conditions attached to the escrow for the given agreement
    function conditionCheck(bytes32 agreementId) public view returns (bool) {
        return LexScrowStorage.conditionCheck(agreementId);
    }

    /// @notice ERC721 receiver hook for safe transfers into escrow (moved here from LexScrowStorage)
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice ERC1155 receiver hook for safe transfers into escrow (moved here from LexScrowStorage)
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        if(IRoundManagerFactory(RoundManagerStorage.getUpgradeFactory()).getRefImplementation() != newImplementation) {
            revert NotRefImplementation();
        }
    }
}
