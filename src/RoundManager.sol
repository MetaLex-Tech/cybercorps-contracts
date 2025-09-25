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
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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
    using ECDSA for bytes32;

    // EIP-712 domain constants
    string public constant EIP712_NAME = "RoundManager";
    string public constant EIP712_VERSION = "1";
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

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
    error EOINotExpired();
    error EOIExpired();
    error NotEOISubmitter();

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

    struct EscrowedSignatureData {
        bytes32 roundId;
        uint8 seriesType;
        uint256 raiseCap;
        uint256 minTicket;
        uint256 maxTicket;
        uint8 roundType;
        uint256 startTime;
        uint256 endTime;
        bytes32 templateId;
        address paymentToken;
        uint256 pricePerUnit;
        uint256 valuation;
        address companyAddress;
    }

    function _hashEscrowedTypedDataV4(
        EscrowedSignatureData memory data
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(EIP712_NAME)),
                keccak256(bytes(EIP712_VERSION)),
                block.chainid,
                address(this)
            )
        );
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        ESCROWEDSIGNATUREDATA_TYPEHASH,
                        data.roundId,
                        data.seriesType,
                        data.raiseCap,
                        data.minTicket,
                        data.maxTicket,
                        data.roundType,
                        data.startTime,
                        data.endTime,
                        data.templateId,
                        data.paymentToken,
                        data.pricePerUnit,
                        data.valuation,
                        data.companyAddress
                    )
                )
            )
        );
    }

    function _verifyEscrowedSignature(
        address signer,
        EscrowedSignatureData memory data,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 digest = _hashEscrowedTypedDataV4(data);
        address recoveredSigner = digest.recover(signature);
        return recoveredSigner == signer;
    }

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

        // No persistent DOMAIN_SEPARATOR; compute dynamically to avoid storage costs
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
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId,
        CyberCertData[] memory certData,
        address[] memory conditions,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        address authorityOfficer,
        string memory officerName,
        string memory officerTitle,
        string memory legalDetails,
        bytes memory extensionData,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature,
        bool publicRound
    ) external onlyOwner returns (bytes32 roundId) {

        if (escrowedSignature.length == 0) revert InvalidEscrowedSignature();

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
                valuation,
                LexScrowStorage.getCorp()
            )
        );

        /*if(!_verifyEscrowedSignature(
                authorityOfficer,
                EscrowedSignatureData({
                    roundId: roundId,
                    seriesType: uint8(seriesType),
                    raiseCap: raiseCap,
                    minTicket: minTicket,
                    maxTicket: maxTicket,
                    roundType: uint8(roundType),
                    startTime: startTime,
                    endTime: endTime,
                    templateId: templateId,
                    paymentToken: paymentToken,
                    pricePerUnit: pricePerUnit,
                    valuation: valuation,
                    companyAddress: LexScrowStorage.getCorp()
                }),
                escrowedSignature
        )) revert InvalidEscrowedSignature();*/
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
            roundPricePerShare: pricePerUnit,
            roundPriceDecimals: 18,
            primarySecurityClass: certData.length > 0
                ? certData[0].securityClass
                : SecurityClass.SAFE,
            primarySecuritySeries: certData.length > 0
                ? certData[0].securitySeries
                : SecuritySeries.NA,
            authorityOfficer: authorityOfficer,
            officerName: officerName,
            officerTitle: officerTitle,
            legalDetails: legalDetails,
            extensionData: extensionData,
            roundPartyValues: roundPartyValues,
            escrowedSignature: escrowedSignature,
            roundConditions: conditions,
            publicRound: publicRound
        });

        RoundManagerStorage.setRound(roundId, newRound);

        emit RoundCreated(roundId, LexScrowStorage.getCorp(), newRound, publicRound);
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
    ) external returns (bytes32 agreementId) {
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
        //check that the eoi expiry is in the future
        if (eoi.expiry < block.timestamp) revert EOIExpired();

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
                eoi.expiry
            );

        Token[] memory corpAssets = new Token[](0);
        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(
            TokenType.ERC20,
            round.paymentToken,
            0,
            eoi.maxAmount
        );

        createEscrow(agreementId, msg.sender, corpAssets, buyerAssets, eoi.expiry);

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

        updateEscrow(agreementId, msg.sender, eoi.name); 

        RoundManagerStorage.setAgreementToRound(agreementId, roundId);
        RoundManagerStorage.getRoundToAgreements(roundId).push(agreementId);
        RoundManagerStorage.setAgreementToEOI(agreementId, eoi);

        //add round conditions
        for (uint256 i = 0; i < round.roundConditions.length; i++) {
            LexScrowStorage.addConditionToEscrow(
                agreementId,
                ICondition(round.roundConditions[i])
            );
        }

        // Add EOI conditions
        for (uint256 i = 0; i < conditions.length; i++) {
            LexScrowStorage.addConditionToEscrow(
                agreementId,
                ICondition(conditions[i])
            );
        }

        //add lexchex if public round
        if (round.publicRound && RoundManagerStorage.getLexChexCondition() != address(0)) {
            LexScrowStorage.addConditionToEscrow(
                agreementId,
                ICondition(RoundManagerStorage.getLexChexCondition())
            );
        }

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
    ) external onlyOwnerOrSelf {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        EOI storage eoi = RoundManagerStorage.getAgreementToEOI(agreementId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);

        if (round.id == bytes32(0)) revert InvalidRound();

        //check that the eoi has not expired
        if (eoi.expiry < block.timestamp) revert EOIExpired();

        uint256 remaining = round.raiseCap - round.raised;
        uint256 candidate = escrow.buyerAssets[0].amount;
        if (allocatedAmount < candidate) { 
            candidate = allocatedAmount;
        }
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

        //sign the agreement with the escrow signer
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
       
        // Calculate units and investment USD
        uint256 units = allocatedAmount / round.pricePerUnit;
        uint8 paymentDecimals = IERC20Metadata(round.paymentToken).decimals();
        uint256 investmentUSD = allocatedAmount / (10 ** paymentDecimals);

        // Create certificate 
        string memory officerName = round.officerName;
        string memory officerTitle = round.officerTitle;

        CertificateDetails memory details = CertificateDetails({
            signingOfficerName: officerName,
            signingOfficerTitle: officerTitle,
            investmentAmountUSD: investmentUSD,
            issuerUSDValuationAtTimeOfInvestment: round.valuation,
            unitsRepresented: units,
            legalDetails: round.legalDetails,
            extensionData: round.extensionData
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

        escrow.signature = round.escrowedSignature;

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

        emit AllocationMade(agreementId, roundId, escrow.counterParty, allocatedAmount, round.raised, certIds); 
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

        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, escrow.counterParty, escrow.signature);

        emit EOIRejected(agreementId, escrow.counterParty, roundId);
    }

    //allow a eoi submitter to recall their eoi and get a refund after the eoi expiry
    function recallEOI(bytes32 agreementId) external {
        bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
        Round storage round = RoundManagerStorage.getRound(roundId);
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        
        if (round.id == bytes32(0)) revert InvalidRound();
        if (msg.sender != escrow.counterParty) revert NotEOISubmitter();
        if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
        if (escrow.corpAssets.length > 0) revert AlreadyAllocated();
        if (block.timestamp < escrow.expiry && round.endTime > block.timestamp) revert EOINotExpired();

        // Refund all
        uint256 amount = escrow.buyerAssets[0].amount;
        IERC20(round.paymentToken).safeTransfer(escrow.counterParty, amount);

        // Void escrow
        voidEscrow(agreementId);

        //void agreement
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, escrow.counterParty, escrow.signature);

        emit EOIRecalled(agreementId, escrow.counterParty, roundId);
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
