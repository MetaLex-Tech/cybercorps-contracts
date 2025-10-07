
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
 
pragma solidity 0.8.28;

import "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IIssuanceManager.sol";
import "../interfaces/ICondition.sol";
import "../interfaces/ICyberCertPrinter.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../interfaces/ILexChex.sol";
import "../libs/EIP712Lib.sol";
import "../storage/LexScrowStorage.sol";
import "../storage/CyberCertPrinterStorage.sol";
import "../CyberCorpConstants.sol";

interface ILexChexMinter {
    function requestMintFor(
        MintRequest calldata request,
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes memory agreementSignature
    ) external returns (bytes32 agreementId, uint256 tokenId);
}

enum RoundType {
    FCFS,
    FounderApproved
}

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

struct Round {
    bytes32 id;
    SecuritySeries seriesType;
    uint256 raiseCap;
    uint256 minTicket;
    uint256 maxTicket;
    RoundType roundType;
    uint256 startTime;
    uint256 endTime;
    bytes32 templateId;
    address[] certPrinter;
    address paymentToken;
    uint256 pricePerUnit;
    uint256 valuation;
    uint256 raised;
    address[] roundConditions;
    // Normalized round price and primary security sold to new money
    uint256 roundPricePerShare; // normalized to priceDecimals
    uint8 roundPriceDecimals;
    SecurityClass primarySecurityClass;
    SecuritySeries primarySecuritySeries;
    address authorityOfficer;
    string officerName;
    string officerTitle;
    string legalDetails;
    bytes extensionData;
    string[] roundPartyValues;
    bytes escrowedSignature;
    bool publicRound;
}

struct EOI {
    string name;
    string investorType;
    string jurisdiction;
    string contact;
    uint256 minAmount;
    uint256 maxAmount;
    uint256 expiry;
    bool naturalPerson;
    LexChexDetails lexchexDetails;
}

struct MintRequest {
    uint256 uuid;
    address owner;
    string investorName;
    string investorType;
    string investorJurisdiction;
    string investorContact;
    uint256 mintPrice;
    uint256 expiry;
    address paymentToken;
}

struct LexChexDetails {
    MintRequest request;
    bytes32 templateId;
    uint256 salt;
    string[] globalValues;
    address[] parties;
    string[][] partyValues;
    bytes agreementSignature;
}

/// @title RoundManagerStorage
/// @notice Storage library for the RoundManager contract that handles persistent data storage
/// @dev Uses the unstructured storage pattern to manage round-related data
library RoundManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.round.manager.storage.v1");

    /// @notice Main storage layout struct that holds all round manager data
    /// @dev Uses unstructured storage pattern to avoid storage collisions
    struct RoundManagerData {
        /// @notice Reference to the issuance manager contract
        IIssuanceManager issuanceManager;
        address upgradeFactory;
        address lexChex;
        address lexChexCondition;
        address lexChexMinter;
        
        /// @notice Mapping from round IDs to their data
        mapping(bytes32 => Round) rounds;
        
        /// @notice Mapping from agreement IDs to their round ID
        mapping(bytes32 => bytes32) agreementToRound;
        
        /// @notice Mapping from round IDs to list of agreement IDs
        mapping(bytes32 => bytes32[]) roundToAgreements;
        
        /// @notice Mapping from agreement IDs to EOI data
        mapping(bytes32 => EOI) agreementToEOI;
    }

    /// @notice Retrieves the storage reference for the RoundManagerData struct
    /// @dev Uses assembly to compute the storage position
    /// @return ds Reference to the RoundManagerData struct in storage
    function roundManagerStorage() internal pure returns (RoundManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function createRound(
        address corp,
        Round memory roundDraft,
        CyberCertData[] memory certData
    ) external returns (bytes32, Round memory, uint256 err) { // TODO use enum

        bytes32 roundId = keccak256(
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
                roundId: roundId,
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
        )) return (bytes32(0), roundDraft, 1);

        string memory companyName = ICyberCorp(corp)
            .cyberCORPName();
        IIssuanceManager issuanceManager = getIssuanceManager();

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

        roundDraft.id = roundId;
        roundDraft.certPrinter = certPrinterAddresses;
        roundDraft.raised = 0;
        roundDraft.primarySecurityClass = certData.length > 0
            ? certData[0].securityClass
            : SecurityClass.SAFE;
        roundDraft.primarySecuritySeries = certData.length > 0
            ? certData[0].securitySeries
            : SecuritySeries.NA;

        setRound(roundId, roundDraft);

        return (roundId, roundDraft, 0);
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
        LexScrowStorage.LexScrowData storage ls,
        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash
    ) external returns (bytes32 agreementId, uint256 tokenId) {
        Round storage round = getRound(roundId);
        address counterParty = msg.sender;

        address[] memory parties = new address[](2);
        parties[1] = counterParty;
        parties[0] = round.authorityOfficer;

        string[][] memory partyValuesArray = new string[][](2);
        partyValuesArray[0] = round.roundPartyValues;
        partyValuesArray[1] = partyValues;

        agreementId = ICyberAgreementRegistry(ls.DEAL_REGISTRY)
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
            eoi.maxAmount,
            true // Will be used as fee token
        );

        // TODO WIP: this is a copy of
//        createEscrow(agreementId, msg.sender, corpAssets, buyerAssets, eoi.expiry);
        ls.escrows[agreementId] = Escrow({
            agreementId: agreementId,
            counterParty: counterParty,
            corpAssets: corpAssets,
            buyerAssets: buyerAssets,
            signature: abi.encodePacked(bytes32(0)),
            expiry: eoi.expiry,
            status: EscrowStatus.PENDING
        });

        if (round.roundType == RoundType.FCFS) {
            ICyberAgreementRegistry(ls.DEAL_REGISTRY)
                .signContractWithEscrow(
                    round.authorityOfficer,
                    agreementId,
                    round.roundPartyValues,
                    round.escrowedSignature,
                    false,
                    ""
                );
        }

        ICyberAgreementRegistry(ls.DEAL_REGISTRY)
            .signContractFor(
                counterParty,
                agreementId,
                partyValues,
                signature,
                false,
                ""
            );

        // TODO deprecated: this is moved outside
//        handleCounterPartyPayment(agreementId);

        // TODO WIP: this is a copy of
//        updateEscrow(agreementId, msg.sender, eoi.name);
        Escrow storage escrow = ls.escrows[agreementId];
        escrow.counterParty = counterParty;
        Endorsement memory newEndorsement = Endorsement(
            address(this),
            block.timestamp,
            escrow.signature,
            ls.DEAL_REGISTRY,
            agreementId,
            escrow.counterParty,
            eoi.name
        );
        for(uint256 i = 0; i < escrow.corpAssets.length; i++) {
            if(escrow.corpAssets[i].tokenType == TokenType.ERC721) {
                ICyberCertPrinter(escrow.corpAssets[i].tokenAddress).addEndorsement(escrow.corpAssets[i].tokenId, newEndorsement);
            }
        }

        setAgreementToRound(agreementId, roundId);
        getRoundToAgreements(roundId).push(agreementId);
        setAgreementToEOI(agreementId, eoi);

        //add round conditions
        for (uint256 i = 0; i < round.roundConditions.length; i++) {
            ls.conditionsByEscrow[agreementId].push(ICondition(round.roundConditions[i]));
        }

        // Add EOI conditions
        for (uint256 i = 0; i < conditions.length; i++) {
            ls.conditionsByEscrow[agreementId].push(ICondition(conditions[i]));
        }

        //add lexchex if public round
        if (round.publicRound && getLexChexCondition() != address(0)) {
            ls.conditionsByEscrow[agreementId].push(ICondition(getLexChexCondition()));
        }
    }

    /// @notice Allocates an amount to an EOI and finalizes the deal
    /// @param agreementId The agreement ID
    /// @param allocatedAmount The amount to allocate
    function allocate(
        LexScrowStorage.LexScrowData storage ls,
        bytes32 agreementId,
        uint256 allocatedAmount
    ) external returns (uint256 tokenId, uint256[] memory certIds, uint256 refund) {
        tokenId = 0;
        bytes32 roundId = getAgreementToRound(agreementId);
        Round storage round = getRound(roundId);
        EOI storage eoi = getAgreementToEOI(agreementId);
        Escrow storage escrow = ls.escrows[agreementId];

        // Effect: sign the agreement with the escrow signer
        if (
            !ICyberAgreementRegistry(ls.DEAL_REGISTRY)
                .hasSigned(agreementId, round.authorityOfficer)
        ) {
            ICyberAgreementRegistry(ls.DEAL_REGISTRY)
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

        IIssuanceManager issuanceManager = getIssuanceManager();

        // Effect: loop through certPrinter and create cert for each
        certIds = new uint256[](round.certPrinter.length);
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
            registry: ls.DEAL_REGISTRY,
            agreementId: agreementId,
            endorsee: escrow.counterParty,
            endorseeName: eoi.name
        });

        // Effect: loop through certPrinter and add endorsement to each
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            ICyberCertPrinter(round.certPrinter[i]).addEndorsement(
                certIds[i],
                endorsement
            );
        }

        // Effect: Add to escrow
        // loop through certPrinter and add to escrow
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            escrow.corpAssets.push(
                Token(TokenType.ERC721, round.certPrinter[i], certIds[i], 1, false)
            );
        }

        // Effect: Calculate refund amount and update escrowed amount
        refund = escrow.buyerAssets[0].amount - allocatedAmount;
        escrow.buyerAssets[0].amount = allocatedAmount;

        //if the round is public and the eoi submitter does not have a valid lexchex, mint it
        if (round.publicRound && !ILexChex(getLexChex()).hasValidLexCheX(escrow.counterParty)) {
            //mint lexchex if over 200k for individual or 1 million for corporate, account for decimals of the payment token
            if (allocatedAmount >= 200000 * (10 ** IERC20Metadata(round.paymentToken).decimals()) && eoi.naturalPerson) {
            (, tokenId) = ILexChexMinter(getLexChexMinter()).requestMintFor(eoi.lexchexDetails.request, eoi.lexchexDetails.templateId, eoi.lexchexDetails.salt, eoi.lexchexDetails.globalValues, eoi.lexchexDetails.parties, eoi.lexchexDetails.partyValues, eoi.lexchexDetails.agreementSignature);
            }
            if (allocatedAmount >= 1000000 * (10 ** IERC20Metadata(round.paymentToken).decimals()) && !eoi.naturalPerson) {
                    (, tokenId) = ILexChexMinter(getLexChexMinter()).requestMintFor(eoi.lexchexDetails.request, eoi.lexchexDetails.templateId, eoi.lexchexDetails.salt, eoi.lexchexDetails.globalValues, eoi.lexchexDetails.parties, eoi.lexchexDetails.partyValues, eoi.lexchexDetails.agreementSignature);
            }
        }
    }

    /// @notice Retrieves a specific round's data
    /// @param roundId The unique identifier of the round
    /// @return Round The round data struct
    function getRound(bytes32 roundId) public view returns (Round storage) {
        return roundManagerStorage().rounds[roundId];
    }

    /// @notice Sets a round's data
    /// @param roundId The unique identifier of the round
    /// @param round The round data to store
    function setRound(bytes32 roundId, Round memory round) internal {
        roundManagerStorage().rounds[roundId] = round;
    }

    /// @notice Retrieves the round ID for an agreement
    /// @param agreementId The agreement identifier
    /// @return bytes32 The round ID
    function getAgreementToRound(bytes32 agreementId) public view returns (bytes32) {
        return roundManagerStorage().agreementToRound[agreementId];
    }

    /// @notice Sets the round ID for an agreement
    /// @param agreementId The agreement identifier
    /// @param roundId The round ID to associate
    function setAgreementToRound(bytes32 agreementId, bytes32 roundId) internal {
        roundManagerStorage().agreementToRound[agreementId] = roundId;
    }

    /// @notice Retrieves the list of agreements for a round
    /// @param roundId The round identifier
    /// @return bytes32[] Array of agreement IDs
    function getRoundToAgreements(bytes32 roundId) internal view returns (bytes32[] storage) {
        return roundManagerStorage().roundToAgreements[roundId];
    }

    /// @notice Retrieves EOI data for an agreement
    /// @param agreementId The agreement identifier
    /// @return EOI The EOI struct
    function getAgreementToEOI(bytes32 agreementId) public view returns (EOI storage) {
        return roundManagerStorage().agreementToEOI[agreementId];
    }

    /// @notice Sets EOI data for an agreement
    /// @param agreementId The agreement identifier
    /// @param eoi The EOI data to store
    function setAgreementToEOI(bytes32 agreementId, EOI memory eoi) internal {
        roundManagerStorage().agreementToEOI[agreementId] = eoi;
    }

    /// @notice Retrieves the current issuance manager
    /// @return IIssuanceManager The current issuance manager contract
    function getIssuanceManager() public view returns (IIssuanceManager) {
        return roundManagerStorage().issuanceManager;
    }

    /// @notice Updates the issuance manager reference
    /// @param _issuanceManager Address of the new issuance manager contract
    function setIssuanceManager(address _issuanceManager) external {
        roundManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }

    function setUpgradeFactory(address _upgradeFactory) external {
        roundManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() external view returns (address) {
        return roundManagerStorage().upgradeFactory;
    }

    function setLexChex(address _lexChex) external {
        roundManagerStorage().lexChex = _lexChex;
    }

    function getLexChex() public view returns (address) {
        return roundManagerStorage().lexChex;
    }

    function setLexChexCondition(address _lexChexCondition) external {
        roundManagerStorage().lexChexCondition = _lexChexCondition;
    }

    function getLexChexCondition() internal view returns (address) {
        return roundManagerStorage().lexChexCondition;
    }

    function setLexChexMinter(address _lexChexMinter) external {
        roundManagerStorage().lexChexMinter = _lexChexMinter;
    }

    function getLexChexMinter() internal view returns (address) {
        return roundManagerStorage().lexChexMinter;
    }

    /// @param seriesType The series type (e.g., Series A)
    /// @param raiseCap The maximum amount to raise
    /// @param minTicket Minimum investment per EOI
    /// @param maxTicket Maximum investment per EOI
    /// @param roundType FCFS or FounderApproved
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @param templateId Agreement template ID
    /// @param paymentToken Payment token address
    /// @param pricePerUnit Price per unit in payment token decimals
    /// @param valuation Valuation in USD
    /// @param roundPartyValues Round party values
    /// @param escrowedSignature Escrowed signature
    /// @param publicRound Indicate public round
    /// @return Partially filled Round struct
    function createRoundDraft(
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId,
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
    ) internal pure returns (Round memory) {
        return Round({
            id: bytes32(0),
            seriesType: seriesType,
            raiseCap: raiseCap,
            minTicket: minTicket,
            maxTicket: maxTicket,
            roundType: roundType,
            startTime: startTime,
            endTime: endTime,
            templateId: templateId,
            certPrinter: new address[](0),
            paymentToken: paymentToken,
            pricePerUnit: pricePerUnit,
            valuation: valuation,
            raised: 0,
            roundConditions: new address[](0),
            roundPricePerShare: 0, // TODO is that right?
            roundPriceDecimals: 18, // TODO is that right?
            primarySecurityClass: SecurityClass.SAFE, // TODO is that right?
            primarySecuritySeries: SecuritySeries.SeriesPreSeed, // TODO is that right?
            authorityOfficer: authorityOfficer,
            officerName: officerName,
            officerTitle: officerTitle,
            legalDetails: legalDetails,
            extensionData: extensionData,
            roundPartyValues: roundPartyValues,
            escrowedSignature: escrowedSignature,
            publicRound: publicRound
        });
    }
}
