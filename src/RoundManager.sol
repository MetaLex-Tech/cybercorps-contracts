
// ... existing code ...
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
 
 import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
 import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
 contract RoundManager is Initializable, UUPSUpgradeable, BorgAuthACL, LexScroWLite {
     using RoundManagerStorage for RoundManagerStorage.RoundManagerData;
     using LexScrowStorage for LexScrowStorage.LexScrowData;
     using SafeERC20 for IERC20;
 
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
 
     event RoundCreated(bytes32 indexed roundId, address corp, Round round);
     event EOISubmitted(bytes32 indexed agreementId, bytes32 indexed roundId, address investor, uint256 maxAmount);
     event AllocationMade(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 allocatedAmount, uint256 certId);
     event EOIRejected(bytes32 indexed agreementId, bytes32 indexed roundId);
 
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
     function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager, address _upgradeFactory) public initializer {
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
     /// @param terms Terms of the round
     /// @param startTime Start timestamp
     /// @param endTime End timestamp
     /// @param templateId Agreement template ID
     /// @param certPrinter Certificate printer address
     /// @param paymentToken Payment token address
     /// @param pricePerUnit Price per unit in payment token decimals
     /// @param valuation Valuation in USD
     /// @param paymentDecimals Decimals of payment token
     /// @return roundId The unique ID of the created round
     function createRound(
         string memory seriesType,
         uint256 raiseCap,
         uint256 minTicket,
         uint256 maxTicket,
         RoundType roundType,
         string memory terms,
         uint256 startTime,
         uint256 endTime,
         bytes32 templateId,
         address certPrinter,
         address paymentToken,
         uint256 pricePerUnit,
         uint256 valuation,
         uint256 paymentDecimals
     ) external onlyOwner returns (bytes32 roundId) {
         roundId = keccak256(abi.encodePacked(
             seriesType, raiseCap, minTicket, maxTicket, uint8(roundType), terms, startTime, endTime, templateId, certPrinter, paymentToken, pricePerUnit, valuation, paymentDecimals, block.timestamp
         ));
 
         Round memory newRound = Round({
             id: roundId,
             seriesType: seriesType,
             raiseCap: raiseCap,
             minTicket: minTicket,
             maxTicket: maxTicket,
             roundType: roundType,
             terms: terms,
             startTime: startTime,
             endTime: endTime,
             templateId: templateId,
             certPrinter: certPrinter,
             paymentToken: paymentToken,
             pricePerUnit: pricePerUnit,
             valuation: valuation,
             paymentDecimals: paymentDecimals,
             raised: 0
         });
 
         RoundManagerStorage.setRound(roundId, newRound);
 
         emit RoundCreated(roundId, LexScrowStorage.getCorp(), newRound);
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
     /// @param voidSignature Pre-signed void signature for potential rejection
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
         string memory name,
         bytes memory voidSignature
     ) external returns (bytes32 agreementId) {
         Round storage round = RoundManagerStorage.getRound(roundId);
         if (round.id == bytes32(0)) revert InvalidRound();
         if (block.timestamp < round.startTime || block.timestamp > round.endTime) revert RoundNotOpen();
         if (eoi.minAmount > eoi.maxAmount || eoi.maxAmount < round.minTicket || eoi.maxAmount > round.maxTicket) revert InvalidAmount();
 
         address[] memory parties = new address[](1);
         parties[0] = msg.sender;
 
         string[][] memory partyValuesArray = new string[][](1);
         partyValuesArray[0] = partyValues;
 
         agreementId = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).createContract(
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
         buyerAssets[0] = Token(TokenType.ERC20, round.paymentToken, 0, eoi.maxAmount);
 
         createEscrow(agreementId, msg.sender, corpAssets, buyerAssets, expiry);
 
         ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(
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
         RoundManagerStorage.setVoidSignature(agreementId, voidSignature);
 
         // Add conditions
         for (uint256 i = 0; i < conditions.length; i++) {
             LexScrowStorage.addConditionToEscrow(agreementId, ICondition(conditions[i]));
         }
 
         emit EOISubmitted(agreementId, roundId, msg.sender, eoi.maxAmount);
     }
 
     /// @notice Allocates an amount to an EOI and finalizes the deal
     /// @param agreementId The agreement ID
     /// @param allocatedAmount The amount to allocate
     function allocate(bytes32 agreementId, uint256 allocatedAmount) external onlyOwner {
         bytes32 roundId = RoundManagerStorage.getAgreementToRound(agreementId);
         Round storage round = RoundManagerStorage.getRound(roundId);
         EOI storage eoi = RoundManagerStorage.getAgreementToEOI(agreementId);
         Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
 
         if (round.id == bytes32(0)) revert InvalidRound();
         if (allocatedAmount < eoi.minAmount || allocatedAmount > escrow.buyerAssets[0].amount) revert InvalidAllocation();
         if (round.raised + allocatedAmount > round.raiseCap) revert InvalidAllocation();
         if (escrow.status != EscrowStatus.PAID) revert DealNotPaid();
         if (escrow.corpAssets.length > 0) revert AlreadyAllocated();
 
         // Calculate units and investment USD
         uint256 units = allocatedAmount / round.pricePerUnit;
         uint256 investmentUSD = allocatedAmount / (10 ** round.paymentDecimals);
 
         // Create certificate
         CertificateDetails memory details = CertificateDetails({
             signingOfficerName: "System",
             signingOfficerTitle: "Automated Allocation",
             investmentAmountUSD: investmentUSD,
             issuerUSDValuationAtTimeOfInvestment: round.valuation,
             unitsRepresented: units,
             legalDetails: "",
             extensionData: ""
         });
 
         uint256 certId = RoundManagerStorage.getIssuanceManager().createCert(
             round.certPrinter,
             address(this),
             details
         );
 
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
 
         ICyberCertPrinter(round.certPrinter).addEndorsement(certId, endorsement);
 
         // Add to escrow
         escrow.corpAssets.push(Token(TokenType.ERC721, round.certPrinter, certId, 1));
 
         // Refund difference
         uint256 refund = escrow.buyerAssets[0].amount - allocatedAmount;
         if (refund > 0) {
             IERC20(round.paymentToken).safeTransfer(escrow.counterParty, refund);
         }
 
         // Update escrowed amount
         escrow.buyerAssets[0].amount = allocatedAmount;
 
         // Check conditions
         if (!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
 
         // Finalize agreement
         ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).finalizeContract(agreementId);
 
         // Finalize escrow
         finalizeEscrow(agreementId);
 
         // Update raised
         round.raised += allocatedAmount;
 
         emit AllocationMade(agreementId, roundId, allocatedAmount, certId);
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
 
         // Void agreement using pre-signed signature
         ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(
             agreementId,
             escrow.counterParty,
             RoundManagerStorage.getVoidSignature(agreementId)
         );
 
         emit EOIRejected(agreementId, roundId);
     }
 
     /// @notice Gets the issuance manager
     /// @return IIssuanceManager The issuance manager
     function issuanceManager() public view returns (IIssuanceManager) {
         return RoundManagerStorage.getIssuanceManager();
     }
 
     // UUPS upgrade authorization
     function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
 }
// ... existing code ...

