 
/* All software, documentation and other files and information in this repository (collectively, the "Software")
 are copyright MetaLeX Labs, Inc., a Delaware corporation.
 
 All rights reserved.
 
 The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
 distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
 mechanical, including photocopying, recording, or by any information storage and retrieval system, 
 except with the express prior written permission of the copyright holder.*/
 
 pragma solidity 0.8.28;
 
 enum RoundType {
     FCFS,
     FounderApproved
 }
 
 struct Round {
     bytes32 id;
     string seriesType;
     uint256 raiseCap;
     uint256 minTicket;
     uint256 maxTicket;
     RoundType roundType;
     string terms;
     uint256 startTime;
     uint256 endTime;
     bytes32 templateId;
     address certPrinter;
     address paymentToken;
     uint256 pricePerUnit;
     uint256 valuation;
     uint256 paymentDecimals;
     uint256 raised;
 }
 
 struct EOI {
     string name;
     string investorType;
     string jurisdiction;
     string contact;
     uint256 minAmount;
     uint256 maxAmount;
 }
 
 interface IRoundManager {
     event RoundCreated(bytes32 indexed roundId, address corp, Round round);
     event EOISubmitted(bytes32 indexed agreementId, bytes32 indexed roundId, address investor, uint256 maxAmount);
     event AllocationMade(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 allocatedAmount, uint256 certId);
     event EOIRejected(bytes32 indexed agreementId, bytes32 indexed roundId);
 
     function createRound(
         string calldata seriesType,
         uint256 raiseCap,
         uint256 minTicket,
         uint256 maxTicket,
         RoundType roundType,
         string calldata terms,
         uint256 startTime,
         uint256 endTime,
         bytes32 templateId,
         address certPrinter,
         address paymentToken,
         uint256 pricePerUnit,
         uint256 valuation,
         uint256 paymentDecimals
     ) external returns (bytes32 roundId);
 
     function submitEOI(
         bytes32 roundId,
         EOI calldata eoi,
         string[] calldata globalValues,
         string[] calldata partyValues,
         bytes calldata signature,
         uint256 salt,
         address[] calldata conditions,
         bytes32 secretHash,
         uint256 expiry,
         string calldata name,
         bytes calldata voidSignature
     ) external returns (bytes32 agreementId);
 
     function allocate(bytes32 agreementId, uint256 allocatedAmount) external;
 
     function reject(bytes32 agreementId) external;
 
     function issuanceManager() external view returns (address);
 } 