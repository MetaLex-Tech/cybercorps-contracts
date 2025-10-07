import {SecurityClass, SecuritySeries} from "../CyberCorpConstants.sol";

enum RoundType {
    FCFS,
    FounderApproved
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

library RoundLib {
    function draft() internal pure returns (Round memory) {
        Round memory round; // all default values
        return round;
    }

    /// @notice Partially fill the given Round struct (ticket-related parameters)
    /// @dev Beware of which fields are not filled and using default values
    /// @param seriesType The series type (e.g., Series A)
    /// @param roundType FCFS or FounderApproved
    /// @param publicRound Indicate public round
    /// @param raiseCap The maximum amount to raise
    /// @param minTicket Minimum investment per EOI
    /// @param maxTicket Maximum investment per EOI
    /// @param paymentToken Payment token address
    /// @param pricePerUnit Price per unit in payment token decimals
    /// @param valuation Valuation in USD
    /// @param startTime Start timestamp
    /// @param endTime End timestamp
    /// @return Partially filled Round struct
    function setTickets(
        Round memory round,
        SecuritySeries seriesType,
        RoundType roundType,
        bool publicRound,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        uint256 startTime,
        uint256 endTime
    ) internal pure returns (Round memory) {
        round.seriesType = seriesType;
        round.roundType = roundType;
        round.publicRound = publicRound;
        round.raiseCap = raiseCap;
        round.minTicket = minTicket;
        round.maxTicket = maxTicket;
        round.paymentToken = paymentToken;
        round.pricePerUnit = pricePerUnit;
        round.roundPricePerShare = pricePerUnit; // default value
        round.roundPriceDecimals = 18; // default value
        round.valuation = valuation;
        round.startTime = startTime;
        round.endTime = endTime;
        return round;
    }

    /// @notice Partially fill the given Round struct (agreement-related parameters)
    /// @dev Beware of which fields are not filled and using default values
    /// @param templateId Agreement template ID
    /// @param roundPartyValues Round party values
    /// @param escrowedSignature Escrowed signature
    /// @return Partially filled Round struct
    function setAgreement(
        Round memory round,
        bytes32 templateId,
        address authorityOfficer,
        string memory officerName,
        string memory officerTitle,
        string memory legalDetails,
        string[] memory roundPartyValues,
        bytes memory extensionData,
        address[] memory roundConditions,
        bytes memory escrowedSignature
    ) internal pure returns (Round memory) {
        round.templateId = templateId;
        round.authorityOfficer = authorityOfficer;
        round.officerName = officerName;
        round.officerTitle = officerTitle;
        round.legalDetails = legalDetails;
        round.roundPartyValues = roundPartyValues;
        round.extensionData = extensionData;
        round.roundConditions = roundConditions;
        round.escrowedSignature = escrowedSignature;
        return round;
    }
}
