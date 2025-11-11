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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";
import "./libs/EIP712Lib.sol";
import "./storage/RoundManagerStorage.sol";
import "./storage/RoundManagerFactoryStorage.sol";
import "./storage/BorgAuthStorage.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/IRoundManagerFactory.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/ILexChex.sol";

/// @title RoundManager
/// @notice Manages fundraising rounds for CyberCorp, handling EOIs, escrows, and allocations
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract RoundManager is
    Initializable,
    BorgAuthACL,
    LexScroWLite,
    UUPSUpgradeable,
    ReentrancyGuard
{
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;
    using LexScrowStorage for LexScrowStorage.LexScrowData;
    using SafeERC20 for IERC20;

    string public constant DEPLOY_VERSION = "3"; // For version-tracking on all deployment and future upgrades

    error InvalidRound();
    error RoundNotOpen();
    error InvalidAmount();
    error InvalidAllocation();
    error AlreadyAllocated();
    error InvalidParties();
    error InvalidCertPrinter();
    error InvalidCert();
    error AgreementConditionsNotMet();
    error ZeroAddress();
    error InvalidIssuanceManager();
    error InvalidEscrowedSignature();
    error EOINotExpired();
    error EOIExpired();
    error NotEOISubmitter();
    error NotRefImplementation();

    event RoundCreated(bytes32 indexed roundId, address indexed corp, Round round, bool publicRound);
    event RoundSnapshotSet(
        bytes32 indexed roundId,
        uint256 totalCapitalSecuritiesOutstanding,
        uint256 totalConvertingSecurities,
        uint256 totalOptionsIssuedAndOutstanding,
        uint256 totalPromisedOptions,
        uint256 unissuedOptionPoolPreRound,
        uint256 unissuedOptionPoolIncreaseIncludedInCalc,
        uint256 cCapUsed
    );
    event RoundingPolicySet(
        bytes32 indexed roundId,
        uint8 mode,
        uint8 priceDecimals,
        uint8 shareDecimals
    );
    event PMVCSubseriesLabelSet(
        bytes32 indexed roundId,
        uint256 pmvc,
        string label
    );
    event EOISubmitted(
        bytes32 agreementId,
        bytes32 indexed roundId,
        address investor,
        address indexed corp,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 expiry
    );
    event AllocationMade(
        bytes32 agreementId,
        bytes32 indexed roundId,
        address indexed buyer,
        uint256 allocatedAmount,
        uint256 totalRaised,
        uint256[] certIds
    );
    event EOIRejected(bytes32  agreementId, address indexed investor, bytes32 indexed roundId);
    event RoundEndTimeUpdated(bytes32 indexed roundId, uint256 oldEndTime, uint256 newEndTime);
    event RoundClosed(bytes32 indexed roundId, uint256 closedAt);
    event EOIRecalled(bytes32 agreementId, address indexed investor, bytes32 indexed roundId);

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
        __LexScroWLite_init(_corp, _dealRegistry);

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
        RoundManagerStorage.setLexChex(_lexchex);
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
        // Validate lengths of per-cert details
        if (roundDraft.legalDetails.length != certData.length) revert InvalidCert();
        if (roundDraft.extensionData.length != certData.length) revert InvalidCert();
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

        if(!EIP712Lib.verifyEscrowedSignature(
            address(this),
            roundDraft.authorityOfficer,
            EIP712Lib.EscrowedSignatureData({
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

        Round memory round = RoundManagerStorage.createRound(
            corp,
            roundDraft,
            certData
        );

        emit RoundCreated(
            round.id,
            corp,
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
        uint256 oldEndTime = round.endTime;
        round.endTime = newEndTime;
        emit RoundEndTimeUpdated(roundId, oldEndTime, newEndTime);
    }

    /// @notice Owner can close the round immediately by setting endTime to now
    /// @param roundId The round ID
    function closeRoundNow(bytes32 roundId) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
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
        handleCounterPartyPayment(agreementId);

        emit EOISubmitted(agreementId, roundId, msg.sender, LexScrowStorage.getCorp(), eoi.minAmount, eoi.maxAmount, eoi.expiry);

        if (round.roundType == RoundType.FCFS) {
            this.allocate(agreementId, eoi.maxAmount);
        }
    }

    /// @notice Allocates an amount to an EOI and finalizes the deal
    /// @param agreementId The agreement ID
    /// @param allocatedAmount The amount to allocate
    function allocate(
        bytes32 agreementId,
        uint256 allocatedAmount
    ) external onlyOwnerOrSelf nonReentrant returns (uint256) {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        EOI storage eoi = RoundManagerStorage.getAgreementToEOI(agreementId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        // Check: round validity
        if (round.id == bytes32(0)) revert InvalidRound();

       // Check: eoi has not expired
        if (eoi.expiry < block.timestamp) revert EOIExpired();
        // Check: offer has not expired based on escrow expiry (captures per-round setting)
        if (escrow.expiry < block.timestamp) revert EOIExpired();

        uint256 remaining = round.raiseCap - round.raised;
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
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        (uint256 tokenId, uint256[] memory certIds, uint256 usedAmount, uint256 refund) = RoundManagerStorage.allocate(
            LexScrowStorage.lexScrowStorage(),
            agreementId,
            allocatedAmount
        );

        // Check: Check conditions
        if (!conditionCheck(agreementId)) revert AgreementConditionsNotMet();

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
        finalizeEscrow(agreementId);

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
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        // Effect: update status
        voidEscrow(agreementId);

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
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();
        if (block.timestamp < escrow.expiry && round.endTime > block.timestamp) revert EOINotExpired();

        // Effect: update status
        voidEscrow(agreementId);

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
    function computeFee(uint256 size) public override view returns (uint256) {
        return size * IRoundManagerFactory(RoundManagerStorage.getUpgradeFactory()).getDefaultFeeRatio() / RoundManagerFactoryStorage.BASIS_POINTS;
    }

    /// @notice Gets the payable address for the fees
    /// @dev The factory owner (MetaLeX) unilaterally set the payable address
    /// @return Payable address for the fees
    function getPlatformPayable() public override view returns (address) {
        return IRoundManagerFactory(RoundManagerStorage.getUpgradeFactory()).getPlatformPayable();
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
