
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
import "../interfaces/IRoundManagerFactory.sol";
import "../libs/EIP712Lib.sol";
import "../libs/RoundLib.sol";
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

/// @notice Certificate data structure for creating new certificates
struct CyberCertData {
    string name;
    string symbol;
    string uri;
    SecurityClass securityClass;
    SecuritySeries securitySeries;
    address extension;
    /// @notice Series-scope payload encoded by `extension`.
    bytes seriesData;
    string[] defaultLegend;
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

    // EIP-712 escrowed-signature domain (authority officer authorizes round parameters off-chain).
    string constant EIP712_NAME = "RoundManager";
    string constant EIP712_VERSION = "1";
    bytes32 constant ESCROWEDSIGNATUREDATA_TYPEHASH = keccak256(
        "EscrowedSignatureData(bytes32 roundId,uint8 seriesType,uint256 raiseCap,uint256 minTicket,uint256 maxTicket,uint8 roundType,uint256 startTime,uint256 endTime,bytes32 templateId,address paymentToken,uint256 pricePerUnit,uint256 valuation,address companyAddress)"
    );

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
    )
    external // Use external library to save space
    returns (Round memory) {

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
                    certData[i].extension,
                    certData[i].seriesData
                )
            );
            certPrinterAddresses[i] = address(certPrinter);
        }

        roundDraft.certPrinter = certPrinterAddresses;
        roundDraft.raised = 0;
        roundDraft.primarySecurityClass = certData.length > 0
            ? certData[0].securityClass
            : SecurityClass.SAFE;
        roundDraft.primarySecuritySeries = certData.length > 0
            ? certData[0].securitySeries
            : SecuritySeries.NA;

        setRound(roundDraft.id, roundDraft);

        return roundDraft;
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
    )
    external // Use external library to save space
    returns (bytes32 agreementId, uint256 tokenId) {
        Round storage round = getRound(roundId);
        address counterParty = msg.sender;

        address[] memory parties = new address[](2);
        parties[1] = counterParty;
        parties[0] = round.authorityOfficer;

        string[][] memory partyValuesArray = new string[][](2);
        partyValuesArray[0] = round.roundPartyValues;
        partyValuesArray[1] = partyValues;

        // Rounds without timed offers ignore the EOI expiry and run to the round end instead
        uint256 expiry = round.allowTimedOffers ? eoi.expiry : round.endTime;

        agreementId = ICyberAgreementRegistry(ls.DEAL_REGISTRY)
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
            eoi.maxAmount,
            true // Will be used as fee token
        );

        // Create the escrow via the shared LexScrowStorage library (no longer duplicated here)
        LexScrowStorage.createEscrow(agreementId, counterParty, corpAssets, buyerAssets, expiry);

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

        // Update the escrow (set counterparty + endorsements) via the shared LexScrowStorage library
        LexScrowStorage.updateEscrow(agreementId, counterParty, eoi.name);

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
        //Commenting this out as we are letting our front end handle this
        /*if (round.publicRound && getLexChexCondition() != address(0)) {
            ls.conditionsByEscrow[agreementId].push(ICondition(getLexChexCondition()));
        }*/
    }

    /// @notice Allocates an amount to an EOI and finalizes the deal
    /// @param agreementId The agreement ID
    /// @param allocatedAmount The amount to allocate
    function allocate(
        LexScrowStorage.LexScrowData storage ls,
        bytes32 agreementId,
        uint256 allocatedAmount
    )
    external // Use external library to save space
    returns (uint256 tokenId, uint256[] memory certIds, uint256 usedAmount, uint256 refund) {
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

        // Calculate units with 1e18 pricePerUnit; convert token amounts <-> 1e18 as needed
        // Since the entire process:
        // 1. convert from payment decimals
        // 2. round-down based on fractional units
        // 3. convert to decimals
        // is always rounding down, it is guaranteed that `usedAmount <= allocatedAmount` and the dust will be refunded

        uint8 paymentDecimals = IERC20Metadata(round.paymentToken).decimals();
        uint256 allocatedAmount1e18 = allocatedAmount;
        if (paymentDecimals < 18) {
            allocatedAmount1e18 = allocatedAmount * (10 ** (18 - paymentDecimals));
        } else if (paymentDecimals > 18) {
            allocatedAmount1e18 = allocatedAmount / (10 ** (paymentDecimals - 18));
        }

        // Support fractional units: 18-decimal units precision
        uint256 units = (allocatedAmount1e18 * 1e18) / round.pricePerUnit;
        uint256 usedAmount1e18 = (units * round.pricePerUnit) / 1e18;

        // Convert used amount back to token units for escrow/refunds/raised
        uint256 usedAmountToken = usedAmount1e18;
        if (paymentDecimals < 18) {
            usedAmountToken = usedAmount1e18 / (10 ** (18 - paymentDecimals));
        } else if (paymentDecimals > 18) {
            usedAmountToken = usedAmount1e18 * (10 ** (paymentDecimals - 18));
        }
        usedAmount = usedAmountToken;

        // Since the conversion from `usedAmount1e18` to `usedAmountToken` is always rounding down,
        // it is guaranteed that `real(usedAmountToken) <= real(investmentUSD)`
        // and the investor would never pay more than documented in the certificates
        uint256 investmentUSD = usedAmount1e18; // 18-decimal USD precision

        // Create certificate
        string memory officerName = round.officerName;
        string memory officerTitle = round.officerTitle;

        IIssuanceManager issuanceManager = getIssuanceManager();

        // Create one certificate per printer, using per-index legalDetails/extensionData
        certIds = new uint256[](round.certPrinter.length);
        for (uint256 i = 0; i < round.certPrinter.length; i++) {
            string memory certLegalDetails = "";
            bytes memory certExtensionData = "";
            if (round.legalDetails.length > i) {
                certLegalDetails = round.legalDetails[i];
            }
            if (round.extensionData.length > i) {
                certExtensionData = round.extensionData[i];
            }

            CertificateDetails memory details = CertificateDetails({
                signingOfficerName: officerName,
                signingOfficerTitle: officerTitle,
                investmentAmountUSD: investmentUSD,
                issuerUSDValuationAtTimeOfInvestment: round.valuation,
                unitsRepresented: units,
                legalDetails: certLegalDetails,
                extensionData: certExtensionData
            });

            certIds[i] = issuanceManager.createCert(
                round.certPrinter[i],
                address(this),
                details
            );

            //add officer signature from round escrowed signature
            ICyberCertPrinter(round.certPrinter[i]).addIssuerSignature(
                certIds[i],
                round.escrowedSignature
            );
        }

        if (_isStockSecurityClass(round.primarySecurityClass)) {
            bytes memory secondEscrowedSignature = "";
            address corp = LexScrowStorage.getCorp();
            try ICyberCorp(corp).getEscrowedOfficerSignatureCount() returns (uint256 count) {
                if (count > 1) {
                    try ICyberCorp(corp).getEscrowedOfficerSignature(1) returns (bytes memory sig) {
                        secondEscrowedSignature = sig;
                    } catch {}
                }
            } catch {}

            if (secondEscrowedSignature.length > 0) {
                for (uint256 i = 0; i < round.certPrinter.length; i++) {
                    ICyberCertPrinter(round.certPrinter[i]).addIssuerSignature(
                        certIds[i],
                        secondEscrowedSignature
                    );
                }
            }
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

        // Effect: Calculate refund amount (includes any dust from unit rounding) and update escrowed amount
        refund = escrow.buyerAssets[0].amount - usedAmountToken;
        escrow.buyerAssets[0].amount = usedAmountToken;

        //if the round is public and the eoi submitter does not have a valid lexchex, mint it
        if (!ILexChex(getLexChex()).hasValidLexCheX(escrow.counterParty)) {
            // Check if payment token is whitelisted
            if (IRoundManagerFactory(getUpgradeFactory()).isWhitelistedToken(round.paymentToken)) {
                // mint lexchex if over 200k for individual or 1 million for corporate using 18-decimal precision
                if (usedAmount1e18 >= 200000 * 1e18 && eoi.naturalPerson) {
                    (, tokenId) = ILexChexMinter(getLexChexMinter()).requestMintFor(eoi.lexchexDetails.request, eoi.lexchexDetails.templateId, eoi.lexchexDetails.salt, eoi.lexchexDetails.globalValues, eoi.lexchexDetails.parties, eoi.lexchexDetails.partyValues, eoi.lexchexDetails.agreementSignature);
                }
                if (usedAmount1e18 >= 1000000 * 1e18 && !eoi.naturalPerson) {
                    (, tokenId) = ILexChexMinter(getLexChexMinter()).requestMintFor(eoi.lexchexDetails.request, eoi.lexchexDetails.templateId, eoi.lexchexDetails.salt, eoi.lexchexDetails.globalValues, eoi.lexchexDetails.parties, eoi.lexchexDetails.partyValues, eoi.lexchexDetails.agreementSignature);
                }
            }
        }
    }

    /// @notice Retrieves a specific round's data
    /// @param roundId The unique identifier of the round
    /// @return Round The round data struct
    function getRound(bytes32 roundId) internal view returns (Round storage) {
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
    function getAgreementToRound(bytes32 agreementId) internal view returns (bytes32) {
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
    function getAgreementToEOI(bytes32 agreementId) internal view returns (EOI storage) {
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
    function getIssuanceManager() internal view returns (IIssuanceManager) {
        return roundManagerStorage().issuanceManager;
    }

    /// @notice Updates the issuance manager reference
    /// @param _issuanceManager Address of the new issuance manager contract
    function setIssuanceManager(address _issuanceManager) internal {
        roundManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }

    function setUpgradeFactory(address _upgradeFactory) internal {
        roundManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() internal view returns (address) {
        return roundManagerStorage().upgradeFactory;
    }

    function setLexChex(address _lexChex) internal {
        roundManagerStorage().lexChex = _lexChex;
    }

    function getLexChex() internal view returns (address) {
        return roundManagerStorage().lexChex;
    }

    function setLexChexCondition(address _lexChexCondition) internal {
        roundManagerStorage().lexChexCondition = _lexChexCondition;
    }

    function getLexChexCondition() internal view returns (address) {
        return roundManagerStorage().lexChexCondition;
    }

    function setLexChexMinter(address _lexChexMinter) internal {
        roundManagerStorage().lexChexMinter = _lexChexMinter;
    }

    function getLexChexMinter() internal view returns (address) {
        return roundManagerStorage().lexChexMinter;
    }

    /// @notice Verifies an authority officer's EIP-712 signature over escrowed round parameters.
    /// @dev Called via delegatecall from RoundManager, so address(this) is the RoundManager proxy — the
    /// correct EIP-712 verifyingContract. external to keep this off RoundManager's bytecode.
    /// @param signer Expected signer (authority officer EOA)
    /// @param data Escrowed round parameters used to build the typed data
    /// @param signature Signature bytes produced over the typed data
    /// @return isValid True if the recovered signer matches `signer`
    function verifyEscrowedSignature(
        address signer,
        EscrowedSignatureData memory data,
        bytes memory signature
    ) external view returns (bool) {
        bytes32 structHash = keccak256(
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
        );
        return EIP712Lib.verifySignature(EIP712_NAME, EIP712_VERSION, address(this), signer, structHash, signature);
    }

    function _isStockSecurityClass(SecurityClass cls) private pure returns (bool) {
        return
            cls == SecurityClass.CommonStock ||
            cls == SecurityClass.PreferredStock ||
            cls == SecurityClass.RestrictedStockPurchaseAgreement ||
            cls == SecurityClass.RestrictedStockUnit;
    }
}
