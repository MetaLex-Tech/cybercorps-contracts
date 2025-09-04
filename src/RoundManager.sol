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
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";
import "./storage/RoundManagerStorage.sol";
import "./storage/BorgAuthStorage.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/ICyberCertPrinter.sol";

/// @title RoundManager
/// @notice Manages fundraising rounds for CyberCorp, handling EOIs, escrows, and allocations
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract RoundManager is
    Initializable,
    UUPSUpgradeable,
    BorgAuthACL,
    LexScroWLite
{
    using RoundManagerStorage for RoundManagerStorage.RoundManagerData;
    using LexScrowStorage for LexScrowStorage.LexScrowData;
    using SafeERC20 for IERC20;

    /// @notice Certificate data structure for creating new certificates
    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        string[] defaultLegend;
    }

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

    event RoundCreated(bytes32 indexed roundId, address corp, Round round);
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
        bytes32 indexed agreementId,
        bytes32 indexed roundId,
        address investor,
        uint256 maxAmount
    );
    event AllocationMade(
        bytes32 indexed agreementId,
        bytes32 indexed roundId,
        uint256 allocatedAmount,
        uint256[] certIds
    );
    event EOIRejected(bytes32 indexed agreementId, bytes32 indexed roundId);

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
    }

    /// @notice Creates a new fundraising round
    /// @param seriesType The series type (e.g., Series A)
    /// @param raiseCap The maximum amount to raise
    /// @param minTicket Minimum investment per EOI
    /// @param maxTicket Maximum investment per EOI
    /// @param roundType FCFS or FounderApproved
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @param templateId Agreement template ID
    /// @param certData Certificate printer address
    /// @param paymentToken Payment token address
    /// @param pricePerUnit Price per unit in payment token decimals
    /// @param valuation Valuation in USD
    /// @return roundId The unique ID of the created round
    /// @param roundPartyValues Round party values
    /// @param escrowedSignature Escrowed signature
    function createRound(
        string memory seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId,
        CyberCertData[] memory certData,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature
    ) external onlyOwner returns (bytes32 roundId) {
        if (roundType == RoundType.FCFS) {
            if (escrowedSignature.length == 0)
                revert InvalidEscrowedSignature();
        }
        roundId = keccak256(
            abi.encodePacked(
                seriesType,
                raiseCap,
                minTicket,
                maxTicket,
                uint8(roundType),
                startTime,
                endTime,
                templateId,
                paymentToken,
                pricePerUnit,
                valuation
            )
        );
        string memory companyName = ICyberCorp(LexScrowStorage.getCorp())
            .cyberCORPName();
        IIssuanceManager issuanceManager = RoundManagerStorage
            .getIssuanceManager();

        address[] memory certPrinterAddresses = new address[](certData.length);
        for (uint256 i = 0; i < certData.length; i++) {
            ICyberCertPrinter certPrinter = ICyberCertPrinter(
                issuanceManager.createCertPrinter(
                    certData[i].defaultLegend,
                    string.concat(companyName, " ", certData[i].name),
                    certData[i].symbol,
                    certData[i].uri,
                    certData[i].securityClass,
                    certData[i].securitySeries,
                    certData[i].extension
                )
            );
            certPrinterAddresses[i] = address(certPrinter);
        }

        Round memory newRound = Round({
            id: roundId,
            seriesType: seriesType,
            raiseCap: raiseCap,
            minTicket: minTicket,
            maxTicket: maxTicket,
            roundType: roundType,
            startTime: startTime,
            endTime: endTime,
            templateId: templateId,
            certPrinter: certPrinterAddresses,
            paymentToken: paymentToken,
            pricePerUnit: pricePerUnit,
            valuation: valuation,
            raised: 0,
            roundPricePerShare: 0,
            roundPriceDecimals: 0,
            primarySecurityClass: certData.length > 0
                ? certData[0].securityClass
                : SecurityClass.CommonStock,
            primarySecuritySeries: certData.length > 0
                ? certData[0].securitySeries
                : SecuritySeries.NA,
            authorityOfficer: msg.sender,
            roundPartyValues: roundPartyValues,
            escrowedSignature: escrowedSignature
        });

        RoundManagerStorage.setRound(roundId, newRound);

        emit RoundCreated(roundId, LexScrowStorage.getCorp(), newRound);
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

    function setCapTableSnapshot(
        bytes32 roundId,
        CapTableSnapshot calldata snapshot
    ) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        RoundManagerStorage.setRoundSnapshot(roundId, snapshot);
        emit RoundSnapshotSet(
            roundId,
            snapshot.totalCapitalSecuritiesOutstanding,
            snapshot.totalConvertingSecurities,
            snapshot.totalOptionsIssuedAndOutstanding,
            snapshot.totalPromisedOptions,
            snapshot.unissuedOptionPoolPreRound,
            snapshot.unissuedOptionPoolIncreaseIncludedInCalc,
            snapshot.cCapUsed
        );
    }

    function setRoundingPolicy(
        bytes32 roundId,
        RoundingPolicy calldata policy
    ) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        RoundManagerStorage.setRoundingPolicy(roundId, policy);
        emit RoundingPolicySet(
            roundId,
            uint8(policy.mode),
            policy.priceDecimals,
            policy.shareDecimals
        );
    }

    function setPMVCSubseriesLabel(
        bytes32 roundId,
        uint256 pmvc,
        string calldata label
    ) external onlyOwner {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        RoundManagerStorage.setPMVCSubseriesLabel(roundId, pmvc, label);
        emit PMVCSubseriesLabelSet(roundId, pmvc, label);
    }

    // Getters for convenience
    // Getters with primitives to avoid cross-type coupling
    function getCapTableSnapshotFields(
        bytes32 roundId
    )
        external
        view
        returns (
            uint256 totalCapitalSecuritiesOutstanding,
            uint256 totalConvertingSecurities,
            uint256 totalOptionsIssuedAndOutstanding,
            uint256 totalPromisedOptions,
            uint256 unissuedOptionPoolPreRound,
            uint256 unissuedOptionPoolIncreaseIncludedInCalc,
            uint256 cCapUsed
        )
    {
        CapTableSnapshot memory s = RoundManagerStorage.getRoundSnapshot(
            roundId
        );
        return (
            s.totalCapitalSecuritiesOutstanding,
            s.totalConvertingSecurities,
            s.totalOptionsIssuedAndOutstanding,
            s.totalPromisedOptions,
            s.unissuedOptionPoolPreRound,
            s.unissuedOptionPoolIncreaseIncludedInCalc,
            s.cCapUsed
        );
    }

    function getRoundingPolicyFields(
        bytes32 roundId
    )
        external
        view
        returns (uint8 mode, uint8 priceDecimals, uint8 shareDecimals)
    {
        RoundingPolicy memory p = RoundManagerStorage.getRoundingPolicy(
            roundId
        );
        return (uint8(p.mode), p.priceDecimals, p.shareDecimals);
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

    function getPMVCSubseriesLabel(
        bytes32 roundId,
        uint256 pmvc
    ) external view returns (string memory) {
        return RoundManagerStorage.getPMVCSubseriesLabel(roundId, pmvc);
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
    /// @param expiry Expiry timestamp
    /// @param name Investor's name for endorsement
    /// @return agreementId The created agreement ID
    function submitEOI(
        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry,
        string memory name
    ) external returns (bytes32 agreementId) {
        Round storage round = RoundManagerStorage.getRound(roundId);
        if (round.id == bytes32(0)) revert InvalidRound();
        if (
            block.timestamp < round.startTime || block.timestamp > round.endTime
        ) revert RoundNotOpen();
        if (
            eoi.minAmount > eoi.maxAmount ||
            eoi.maxAmount < round.minTicket ||
            eoi.maxAmount > round.maxTicket
        ) revert InvalidAmount();

        address[] memory parties = new address[](2);
        parties[1] = msg.sender;
        parties[0] = round.authorityOfficer;

        string[][] memory partyValuesArray = new string[][](2);
        partyValuesArray[0] = round.roundPartyValues;
        partyValuesArray[1] = partyValues;

        agreementId = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
            .createContract(
                round.templateId,
                salt,
                globalValues,
                parties,
                partyValuesArray,
                secretHash,
                address(this),
                expiry
            );

        Token[] memory corpAssets = new Token[](0);
        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(
            TokenType.ERC20,
            round.paymentToken,
            0,
            eoi.maxAmount
        );

        createEscrow(agreementId, msg.sender, corpAssets, buyerAssets, expiry);

        if (round.roundType == RoundType.FCFS) {
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
                .signContractWithEscrow(
                    round.authorityOfficer,
                    agreementId,
                    round.roundPartyValues,
                    round.escrowedSignature,
                    false,
                    ""
                );
        }

        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
            .signContractFor(
                msg.sender,
                agreementId,
                partyValues,
                signature,
                false,
                ""
            );

        handleCounterPartyPayment(agreementId);

        updateEscrow(agreementId, msg.sender, name);

        RoundManagerStorage.setAgreementToRound(agreementId, roundId);
        RoundManagerStorage.getRoundToAgreements(roundId).push(agreementId);
        RoundManagerStorage.setAgreementToEOI(agreementId, eoi);

        // Add conditions
        for (uint256 i = 0; i < conditions.length; i++) {
            LexScrowStorage.addConditionToEscrow(
                agreementId,
                ICondition(conditions[i])
            );
        }

        emit EOISubmitted(agreementId, roundId, msg.sender, eoi.maxAmount);

        if (round.roundType == RoundType.FCFS) {
            this.allocate(agreementId, eoi.maxAmount, bytes(""));
        }
    }

    /// @notice Allocates an amount to an EOI and finalizes the deal
    /// @param agreementId The agreement ID
    /// @param allocatedAmount The amount to allocate
    /// @param signature Company officer signature to be recorded on the escrow
    function allocate(
        bytes32 agreementId,
        uint256 allocatedAmount,
        bytes memory signature
    ) external onlyOwnerOrSelf {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        EOI storage eoi = RoundManagerStorage.getAgreementToEOI(agreementId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        if (round.id == bytes32(0)) revert InvalidRound();
        // Compute allocation candidate for any round type:
        // - cap to remaining raise
        // - cap to escrowed buyer amount
        // - require at least the larger of round.minTicket and eoi.minAmount

        uint256 remaining = round.raiseCap - round.raised;
        uint256 candidate = escrow.buyerAssets[0].amount;
        if (candidate > remaining) {
            candidate = remaining;
        }
        uint256 minRequired = round.minTicket > eoi.minAmount ? round.minTicket : eoi.minAmount;
        if (candidate < minRequired) {
            revert InvalidAllocation();
        }
        allocatedAmount = candidate;
        
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        //if the round is FCFS, sign the agreement with the escrow signer
        if (round.roundType == RoundType.FCFS) {
            if (
                !ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
                    .hasSigned(agreementId, round.authorityOfficer)
            ) {
                ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
                    .signContractWithEscrow(
                        round.authorityOfficer,
                        agreementId,
                        round.roundPartyValues,
                        round.escrowedSignature,
                        false,
                        ""
                    );
            }
        }
        //else sign the agreement with the signature provided
        else {
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
                .signContractFor(
                    msg.sender,
                    agreementId,
                    round.roundPartyValues,
                    signature,
                    false,
                    ""
                );
        }

        // Calculate units and investment USD
        uint256 units = allocatedAmount / round.pricePerUnit;
        uint8 paymentDecimals = IERC20Metadata(round.paymentToken).decimals();
        uint256 investmentUSD = allocatedAmount / (10 ** paymentDecimals);

        // Create certificate (prefer officer info captured in roundPartyValues)
        string memory officerName = "System";
        string memory officerTitle = "Automated Allocation";
        
        if (round.roundPartyValues.length > 0) {
            officerName = round.roundPartyValues[0];
        }
        if (round.roundPartyValues.length > 1) {
            officerTitle = round.roundPartyValues[1];
        }

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: officerName,
            signingOfficerTitle: officerTitle,
            investmentAmountUSD: investmentUSD,
            issuerUSDValuationAtTimeOfInvestment: round.valuation,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });

        IIssuanceManager issuanceManager = RoundManagerStorage
            .getIssuanceManager();

        //loop through certPrinter and create cert for each
        uint256[] memory certIds = new uint256[](round.certPrinter.length);
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            certIds[i] = issuanceManager.createCert(
                round.certPrinter[i],
                address(this),
                details
            );
        }

        escrow.signature = round.roundType == RoundType.FCFS
            ? round.escrowedSignature
            : signature;

        // Add endorsement
        Endorsement memory endorsement = Endorsement({
            endorser: address(this),
            timestamp: block.timestamp,
            signatureHash: escrow.signature,
            registry: LexScrowStorage.getDealRegistry(),
            agreementId: agreementId,
            endorsee: escrow.counterParty,
            endorseeName: eoi.name
        });

        //loop through certPrinter and add endorsement to each
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            ICyberCertPrinter(round.certPrinter[i]).addEndorsement(
                certIds[i],
                endorsement
            );
        }

        // Add to escrow
        //loop through certPrinter and add to escrow
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            escrow.corpAssets.push(
                Token(TokenType.ERC721, round.certPrinter[i], certIds[i], 1)
            );
        }

        // Refund difference
        uint256 refund = escrow.buyerAssets[0].amount - allocatedAmount;
        if (refund > 0) {
            IERC20(round.paymentToken).safeTransfer(
                escrow.counterParty,
                refund
            );
        }

        // Update escrowed amount
        escrow.buyerAssets[0].amount = allocatedAmount;

        // Check conditions
        if (!conditionCheck(agreementId)) revert AgreementConditionsNotMet();

        // Finalize agreement
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry())
            .finalizeContract(agreementId);

        // Finalize escrow
        finalizeEscrow(agreementId);

        // Update raised
        round.raised += allocatedAmount;

        emit AllocationMade(agreementId, roundId, allocatedAmount, certIds);
    }

    /// @notice Rejects an EOI and voids the deal
    /// @param agreementId The agreement ID
    function reject(bytes32 agreementId) external onlyOwner {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        if (round.id == bytes32(0)) revert InvalidRound();
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();

        // Refund all
        uint256 amount = escrow.buyerAssets[0].amount;
        IERC20(round.paymentToken).safeTransfer(escrow.counterParty, amount);

        // Void escrow
        voidEscrow(agreementId);

        //todo: void agreement

        emit EOIRejected(agreementId, roundId);
    }

    /// @notice Gets the issuance manager
    /// @return IIssuanceManager The issuance manager
    function issuanceManager() public view returns (IIssuanceManager) {
        return RoundManagerStorage.getIssuanceManager();
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
