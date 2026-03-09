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

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";
import "../../libs/auth.sol";

// ══════════════════════════════════════════════════════════════════════════════
//  Enums (file scope for potential centralization into CyberCorpConstants.sol)
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Liquidation preference payout structure
enum LiquidationPreferenceType {
    NonParticipating,       // single-dip: greater of preference or as-converted
    Participating,          // double-dip: preference + pro rata share of remainder
    CappedParticipating     // participating, but capped at a multiple of original issue price
}

/// @notice Anti-dilution protection mechanism
enum AntiDilutionType {
    None,
    BroadBasedWeightedAverage,
    NarrowBasedWeightedAverage,
    FullRatchet
}

/// @notice Dividend accrual behavior
enum DividendType {
    None,
    NonCumulative,      // dividends declared at board discretion, unpaid amounts do not accrue
    Cumulative          // dividends accrue whether or not declared
}

/// @notice Transfer restriction regime applicable to shares.
/// NOTE: Rule144Eligible removed — that is a holder/time condition, not a series designation.
/// SecuritiesActRestriction added — the standard "not registered" restricted-securities legend.
enum TransferRestrictionType {
    None,
    BoardConsentRequired,       // Section 8.9(a) of Bylaws — no transfer without board consent
    ROFRAndCoSale,              // subject to ROFR/Co-Sale agreement
    LockUp,                     // time-based lock-up restriction
    SecuritiesActRestriction,   // Securities Act restricted legend (standard "not registered" legend)
    CustomRestriction           // custom restriction defined by agreement or board resolution
}

/// @notice Redemption mechanism type
enum RedemptionType {
    None,
    HolderOptional,
    CompanyOptional,
    Mandatory,
    EventTriggered
}

/// @notice Types of mandatory/automatic conversion triggers
enum MandatoryConversionTriggerType {
    QualifiedIPO,
    ClassVote,
    DeemedLiquidation,
    Custom
}

/// @notice Scope of a voting right — distinguishes class-wide votes from series-specific votes.
/// Under DGCL section 151(a), the certificate of incorporation may provide that holders of any
/// class or series shall vote as a separate class or series. These are distinct:
///   - ClassWide: all series within the same share class vote together (e.g., all Preferred)
///   - SeriesSpecific: only holders of this specific series vote (e.g., Series A alone)
enum VotingScope {
    ClassWide,          // all series sharing the same shareClassKey vote together
    SeriesSpecific      // only this series votes
}

// ══════════════════════════════════════════════════════════════════════════════
//  Structs
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Mandatory/automatic conversion trigger definition
struct MandatoryConversionTrigger {
    MandatoryConversionTriggerType triggerType;
    uint256 thresholdValue;     // e.g., IPO price threshold (18 dec), vote percentage (4 dec)
    string description;         // human-readable description of the trigger condition
}

/// @notice Matter-specific voting right (used for protective provisions and special class/series votes)
struct SpecialVotingRight {
    bytes32 matterType;     // e.g., keccak256("CHARTER_AMENDMENT"), keccak256("MERGER_APPROVAL")
    uint256 votesPerShare;  // votes per share for this specific matter (18 decimals)
    uint256 threshold;      // approval threshold (4 decimal percentage, e.g. 5010 = 50.1%)
    bool isVetoRight;       // true = blocking/consent right rather than affirmative vote
    VotingScope scope;      // whether this right is exercised at the class level or series level
    string description;     // human-readable description
}

/// @notice A single transfer restriction with full legal text (DGCL section 202 compliance)
struct TransferRestriction {
    TransferRestrictionType restrictionType;
    string restrictionText;     // actual legal legend / restriction notice text
    string sourceAgreement;     // pointer to imposing agreement (e.g., "Bylaws section 8.9")
    bool isRemovable;           // whether this restriction can be removed (e.g., Rule 144 legend removal)
}

/// @notice Canonical series-wide terms, stored once per class/series.
/// All price/value fields use 18-decimal precision.
/// Percentage fields use 4-decimal precision (10**4 basis, 5010 = 50.10%).
struct SeriesTerms {
    // --- Identity & Classification ---
    bytes32 shareClassKey;              // extensible class identifier (use CLASS_COMMON, CLASS_PREFERRED, or custom)
    string seriesName;                  // human-readable display name
    uint256 parValue;                   // par value per share (18 decimals)
    uint256 authorizedShares;           // total authorized shares for this class/series
    uint256 originalIssuePrice;         // price per share at issuance (18 decimals)
    uint256 effectiveDate;              // timestamp when these terms became effective
    string sourceAuthorityURI;          // pointer to charter provision, board resolution, or amendment

    // --- Liquidation Preference & Seniority ---
    uint256 liquidationPreferenceMultiple; // multiple of OIP (18 decimals; 1e18 = 1x)
    LiquidationPreferenceType liquidationPreferenceType;
    uint256 participationCap;           // if CappedParticipating, max multiple of OIP (18 decimals); 0 otherwise
    uint256 seniorityRank;              // lower = more senior; equal rank = pari passu

    // --- Dividends ---
    DividendType dividendType;
    uint256 dividendRate;               // annual rate (18 decimals, 8% = 8e16); 0 if None
    uint256 dividendAccrualStartDate;   // timestamp; relevant for cumulative dividends
    bool dividendCompounding;           // true = compound accrual; false = simple accrual
    bool dividendIncreasesLiquidationAmount; // whether accrued unpaid dividends add to liquidation preference

    // --- Conversion ---
    bool isConvertible;
    bytes32 targetConversionSeriesId;   // seriesId of the target class/series for conversion
    uint256 conversionPrice;            // current conversion price (18 decimals); ratio = OIP / conversionPrice
    AntiDilutionType antiDilutionType;
    bool allowsFractionalConversion;    // whether fractional shares may be issued on conversion
    bool hasMandatoryConversion;
    MandatoryConversionTrigger[] mandatoryConversionTriggers;

    // --- Voting ---
    uint256 votesPerShare;              // default votes per share (18 decimals, 1e18 = 1 vote); 0 = non-voting
    uint8 designatedBoardSeats;         // board seats this series is entitled to elect
    bool hasClassVotingRights;          // whether this series participates in class-wide separate votes
                                        // (e.g., all Preferred series voting together as a single class)
    bool hasSeriesVotingRights;         // whether this series can vote separately as its own series
                                        // (e.g., Series A alone voting on matters requiring Series A consent)
    SpecialVotingRight[] specialVotingRights; // each entry specifies its own VotingScope

    // --- Transfer Restrictions ---
    TransferRestriction[] transferRestrictions;

    // --- Redemption ---
    bool isRedeemable;
    RedemptionType redemptionType;
    uint256 redemptionPrice;            // redemption price per share (18 decimals)
    string redemptionSchedule;          // human-readable or URI to redemption schedule/terms
    string redemptionTriggerDescription; // for EventTriggered: description of the triggering event
}

/// @notice Per-certificate metadata (V2). References canonical SeriesTerms via seriesId.
/// Legends are stored in dedicated mappings, not in this struct, to allow individual add/remove.
struct CertificateData {
    bytes32 seriesId;               // pointer to canonical SeriesTerms
    uint256 certificateNumber;      // unique certificate number (may equal token ID but explicitly tracked)
    uint256 numberOfShares;         // number of shares represented by this certificate
    uint256 issueDate;              // timestamp of issuance
    bool isPartlyPaid;              // whether shares are partly paid (Bylaws section 8.5, DGCL section 156)
    uint256 amountPaid;             // if partly paid, amount actually paid (18 decimals)
    uint256 totalConsideration;     // if partly paid, total consideration to be paid (18 decimals)
    string sourceAuthorityURI;      // per-certificate pointer to board resolution, subscription agreement, etc.
}

// ══════════════════════════════════════════════════════════════════════════════
//  Contract
// ══════════════════════════════════════════════════════════════════════════════

contract ShareExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {

    // ──────────────────────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────────────────────

    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;

    /// @notice Extensible share class identifiers (use arbitrary bytes32 for exotic classes)
    bytes32 public constant CLASS_COMMON = keccak256("COMMON");
    bytes32 public constant CLASS_PREFERRED = keccak256("PREFERRED");

    // ──────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────

    event SeriesCreated(bytes32 indexed seriesId, bytes32 indexed shareClassKey, string seriesName);
    event SeriesTermsUpdated(bytes32 indexed seriesId, string fieldChanged);
    event ConversionPriceAdjusted(bytes32 indexed seriesId, uint256 oldPrice, uint256 newPrice);
    event AuthorizedSharesChanged(bytes32 indexed seriesId, uint256 oldAmount, uint256 newAmount);
    event LegendAdded(uint256 indexed tokenId, uint256 legendIndex, bytes32 legendHash);
    event LegendRemoved(uint256 indexed tokenId, uint256 legendIndex, bytes32 legendHash);
    event IssuerNameUpdated(string oldName, string newName);

    // ──────────────────────────────────────────────────────────────
    //  State variables
    //  NOTE: These occupy the same storage slots as the former __gap[30].
    //  6 slots used + 24 reserved = 30 total (preserves layout).
    // ──────────────────────────────────────────────────────────────

    /// @notice Canonical series terms registry
    mapping(bytes32 => SeriesTerms) internal _seriesRegistry;       // slot 0
    /// @notice Ordered list of series IDs for enumeration
    bytes32[] public seriesIds;                                      // slot 1
    /// @notice O(1) existence check for series
    mapping(bytes32 => bool) public seriesExists;                   // slot 2
    /// @notice Per-certificate legend texts keyed by token ID
    mapping(uint256 => string[]) internal _certificateLegends;      // slot 3
    /// @notice Parallel array of legend hashes for efficient on-chain verification
    mapping(uint256 => bytes32[]) internal _certificateLegendHashes; // slot 4
    /// @notice Issuer name — changeable by board/owner (covers name changes, mergers)
    string public issuerName;                                        // slot 5

    /// @dev Reserved storage for future upgrades
    uint256[24] private __gap;                                       // slots 6-29

    // ──────────────────────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────────────────────

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    // ══════════════════════════════════════════════════════════════
    //  Series Management (onlyOwner / board-authorized)
    // ══════════════════════════════════════════════════════════════

    /// @notice Register a new series with canonical terms
    /// @param seriesId Unique identifier for the series (immutable once created)
    /// @param terms The full series terms struct
    function createSeries(bytes32 seriesId, SeriesTerms memory terms) external onlyOwner {
        require(seriesId != bytes32(0), "ShareExtension: zero seriesId");
        require(!seriesExists[seriesId], "ShareExtension: series already exists");

        (bool valid, string memory err) = _validateSeriesTermsInternal(terms);
        require(valid, err);

        _seriesRegistry[seriesId] = terms;
        seriesIds.push(seriesId);
        seriesExists[seriesId] = true;

        emit SeriesCreated(seriesId, terms.shareClassKey, terms.seriesName);
    }

    /// @notice Replace the full terms for an existing series
    /// @param seriesId The series to update
    /// @param terms The new full series terms
    function updateSeriesTerms(bytes32 seriesId, SeriesTerms memory terms) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");

        (bool valid, string memory err) = _validateSeriesTermsInternal(terms);
        require(valid, err);

        _seriesRegistry[seriesId] = terms;

        emit SeriesTermsUpdated(seriesId, "ALL");
    }

    /// @notice Update conversion price independently (e.g., anti-dilution adjustment)
    function updateConversionPrice(bytes32 seriesId, uint256 newPrice) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        SeriesTerms storage s = _seriesRegistry[seriesId];
        require(s.isConvertible, "ShareExtension: series is not convertible");

        uint256 oldPrice = s.conversionPrice;
        s.conversionPrice = newPrice;

        emit ConversionPriceAdjusted(seriesId, oldPrice, newPrice);
    }

    /// @notice Update authorized shares independently (e.g., charter amendment)
    function updateAuthorizedShares(bytes32 seriesId, uint256 newAmount) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        require(newAmount > 0, "ShareExtension: authorizedShares must be > 0");

        SeriesTerms storage s = _seriesRegistry[seriesId];
        uint256 oldAmount = s.authorizedShares;
        s.authorizedShares = newAmount;

        emit AuthorizedSharesChanged(seriesId, oldAmount, newAmount);
    }

    /// @notice Update series display name
    function updateSeriesName(bytes32 seriesId, string calldata newName) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        _seriesRegistry[seriesId].seriesName = newName;
        emit SeriesTermsUpdated(seriesId, "seriesName");
    }

    // ══════════════════════════════════════════════════════════════
    //  Certificate Data (ICertificateExtension compatibility)
    // ══════════════════════════════════════════════════════════════

    /// @notice Encode certificate data into extension bytes
    function encodeCertificateData(CertificateData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    /// @notice Decode certificate data from extension bytes
    function decodeCertificateData(bytes memory data) external pure returns (CertificateData memory) {
        return abi.decode(data, (CertificateData));
    }

    // ══════════════════════════════════════════════════════════════
    //  Legend Management (per-certificate)
    // ══════════════════════════════════════════════════════════════

    /// @notice Add a legend to a specific certificate
    /// @param tokenId The ERC-721 token ID
    /// @param legendText The full legal legend/restriction notice text
    function addLegend(uint256 tokenId, string calldata legendText) external onlyOwner {
        bytes32 h = keccak256(bytes(legendText));
        _certificateLegends[tokenId].push(legendText);
        _certificateLegendHashes[tokenId].push(h);

        emit LegendAdded(tokenId, _certificateLegends[tokenId].length - 1, h);
    }

    /// @notice Remove a legend from a specific certificate by index (swap-and-pop)
    /// @param tokenId The ERC-721 token ID
    /// @param legendIndex Index of the legend to remove
    function removeLegend(uint256 tokenId, uint256 legendIndex) external onlyOwner {
        string[] storage legends = _certificateLegends[tokenId];
        bytes32[] storage hashes = _certificateLegendHashes[tokenId];
        require(legendIndex < legends.length, "ShareExtension: legend index out of bounds");

        bytes32 removedHash = hashes[legendIndex];

        // Swap with last element and pop
        uint256 lastIdx = legends.length - 1;
        if (legendIndex != lastIdx) {
            legends[legendIndex] = legends[lastIdx];
            hashes[legendIndex] = hashes[lastIdx];
        }
        legends.pop();
        hashes.pop();

        emit LegendRemoved(tokenId, legendIndex, removedHash);
    }

    /// @notice Get all legends for a certificate
    function getLegends(uint256 tokenId) external view returns (string[] memory texts, bytes32[] memory hashes) {
        return (_certificateLegends[tokenId], _certificateLegendHashes[tokenId]);
    }

    /// @notice Initialize a certificate's legends from its series' default transfer restrictions
    /// @dev Should be called at mint time to populate initial restriction notices
    function initializeLegends(uint256 tokenId, bytes32 seriesId) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");

        TransferRestriction[] storage restrictions = _seriesRegistry[seriesId].transferRestrictions;
        for (uint256 i = 0; i < restrictions.length; i++) {
            if (bytes(restrictions[i].restrictionText).length > 0) {
                bytes32 h = keccak256(bytes(restrictions[i].restrictionText));
                _certificateLegends[tokenId].push(restrictions[i].restrictionText);
                _certificateLegendHashes[tokenId].push(h);
                emit LegendAdded(tokenId, _certificateLegends[tokenId].length - 1, h);
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  Issuer Identity
    // ══════════════════════════════════════════════════════════════

    /// @notice Set or update the issuer name (single authoritative value for all certs)
    function setIssuerName(string calldata _name) external onlyOwner {
        string memory oldName = issuerName;
        issuerName = _name;
        emit IssuerNameUpdated(oldName, _name);
    }

    // ══════════════════════════════════════════════════════════════
    //  Read Helpers
    // ══════════════════════════════════════════════════════════════

    /// @notice Get full series terms for a given series ID
    function getSeriesTerms(bytes32 seriesId) external view returns (SeriesTerms memory) {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        return _seriesRegistry[seriesId];
    }

    /// @notice Get all registered series IDs
    function getAllSeriesIds() external view returns (bytes32[] memory) {
        return seriesIds;
    }

    /// @notice Get full share info: series terms + decoded certificate data + legends
    /// @param certExtensionData The encoded CertificateData bytes
    /// @param tokenId The ERC-721 token ID (for legend lookup)
    function getFullShareInfo(bytes memory certExtensionData, uint256 tokenId)
        external
        view
        returns (SeriesTerms memory terms, CertificateData memory cert, string[] memory legends)
    {
        cert = abi.decode(certExtensionData, (CertificateData));
        require(seriesExists[cert.seriesId], "ShareExtension: series does not exist");
        terms = _seriesRegistry[cert.seriesId];
        legends = _certificateLegends[tokenId];
    }

    // ══════════════════════════════════════════════════════════════
    //  Validation
    // ══════════════════════════════════════════════════════════════

    /// @notice Validate series terms without modifying state
    /// @dev `view` because it may check seriesExists for targetConversionSeriesId
    function validateSeriesTerms(SeriesTerms memory terms) external view returns (bool valid, string memory error) {
        return _validateSeriesTermsInternal(terms);
    }

    /// @notice Validate certificate data consistency
    function validateCertificateData(CertificateData memory data) external view returns (bool valid, string memory error) {
        return _validateCertificateDataInternal(data);
    }

    // ══════════════════════════════════════════════════════════════
    //  ICertificateExtension Overrides
    // ══════════════════════════════════════════════════════════════

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    /// @notice Render extension data as a JSON fragment.
    /// @dev `view` (not `pure`) because it reads seriesRegistry and issuerName.
    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        if (data.length == 0) return "";

        CertificateData memory cert = abi.decode(data, (CertificateData));
        require(seriesExists[cert.seriesId], "ShareExtension: unknown seriesId in extension data");

        return _buildURI(cert);
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — Validation
    // ══════════════════════════════════════════════════════════════

    function _validateSeriesTermsInternal(SeriesTerms memory t) internal view returns (bool, string memory) {
        // 9. authorizedShares must be > 0
        if (t.authorizedShares == 0) return (false, "ShareExtension: authorizedShares must be > 0");

        // 10. parValue should be > 0
        if (t.parValue == 0) return (false, "ShareExtension: parValue must be > 0");

        // 1. If not convertible, conversion fields must be zero/empty
        if (!t.isConvertible) {
            if (t.conversionPrice != 0) return (false, "ShareExtension: conversionPrice must be 0 when not convertible");
            if (t.targetConversionSeriesId != bytes32(0)) return (false, "ShareExtension: targetConversionSeriesId must be zero when not convertible");
            if (t.mandatoryConversionTriggers.length > 0) return (false, "ShareExtension: mandatoryConversionTriggers must be empty when not convertible");
            if (t.hasMandatoryConversion) return (false, "ShareExtension: hasMandatoryConversion must be false when not convertible");
        }

        // 2. If convertible, targetConversionSeriesId must be non-zero
        if (t.isConvertible) {
            if (t.targetConversionSeriesId == bytes32(0)) return (false, "ShareExtension: targetConversionSeriesId must be non-zero when convertible");
        }

        // 3. If dividendType == None, dividendRate must be 0
        if (t.dividendType == DividendType.None) {
            if (t.dividendRate != 0) return (false, "ShareExtension: dividendRate must be 0 when dividendType is None");
        }

        // 4. If dividendType == Cumulative, accrualStartDate should be non-zero
        if (t.dividendType == DividendType.Cumulative) {
            if (t.dividendAccrualStartDate == 0) return (false, "ShareExtension: dividendAccrualStartDate should be non-zero for Cumulative dividends");
        }

        // 5. If not CappedParticipating, participationCap must be 0
        if (t.liquidationPreferenceType != LiquidationPreferenceType.CappedParticipating) {
            if (t.participationCap != 0) return (false, "ShareExtension: participationCap must be 0 when not CappedParticipating");
        }

        // 6. If CappedParticipating, participationCap must be > 0
        if (t.liquidationPreferenceType == LiquidationPreferenceType.CappedParticipating) {
            if (t.participationCap == 0) return (false, "ShareExtension: participationCap must be > 0 when CappedParticipating");
        }

        // 7. If not redeemable, redemptionPrice must be 0 and redemptionType must be None
        if (!t.isRedeemable) {
            if (t.redemptionPrice != 0) return (false, "ShareExtension: redemptionPrice must be 0 when not redeemable");
            if (t.redemptionType != RedemptionType.None) return (false, "ShareExtension: redemptionType must be None when not redeemable");
        }

        // 11. hasMandatoryConversion requires at least one trigger
        if (t.hasMandatoryConversion) {
            if (t.mandatoryConversionTriggers.length == 0) return (false, "ShareExtension: hasMandatoryConversion requires at least one trigger");
        }

        return (true, "");
    }

    function _validateCertificateDataInternal(CertificateData memory d) internal view returns (bool, string memory) {
        // 13. seriesId must reference an existing series
        if (!seriesExists[d.seriesId]) return (false, "ShareExtension: seriesId does not reference an existing series");

        // 14. If partly paid, amountPaid < totalConsideration and totalConsideration > 0
        if (d.isPartlyPaid) {
            if (d.totalConsideration == 0) return (false, "ShareExtension: totalConsideration must be > 0 when partly paid");
            if (d.amountPaid >= d.totalConsideration) return (false, "ShareExtension: amountPaid must be < totalConsideration when partly paid");
        }

        // 15. If not partly paid, amountPaid and totalConsideration should both be 0
        if (!d.isPartlyPaid) {
            if (d.amountPaid != 0) return (false, "ShareExtension: amountPaid must be 0 when not partly paid");
            if (d.totalConsideration != 0) return (false, "ShareExtension: totalConsideration must be 0 when not partly paid");
        }

        return (true, "");
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — URI Builder
    // ══════════════════════════════════════════════════════════════

    function _buildURI(CertificateData memory cert) internal view returns (string memory) {
        SeriesTerms storage terms = _seriesRegistry[cert.seriesId];

        string memory p1 = _buildIdentity(terms);
        string memory p2 = _buildEconomics(terms);
        string memory p3 = _buildDividends(terms);
        string memory p4 = _buildConversion(terms);
        string memory p5 = _buildVoting(terms);
        string memory p6 = _buildRestrictionsRedemption(terms);
        string memory p7 = _buildCertificate(cert);
        string memory p8 = _buildIssuer();

        return string(abi.encodePacked(
            ', "shareDetails": {',
            p1, p2, p3, p4, p5, p6, p7, p8,
            "}"
        ));
    }

    function _buildIdentity(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"shareClassKey": "', _shareClassKeyToString(t.shareClassKey),
            '", "seriesName": "', t.seriesName,
            '", "parValue": "', _uint256ToString(t.parValue),
            '", "authorizedShares": "', _uint256ToString(t.authorizedShares),
            '", "originalIssuePrice": "', _uint256ToString(t.originalIssuePrice),
            '", "effectiveDate": "', _uint256ToString(t.effectiveDate),
            '", '
        ));
    }

    function _buildEconomics(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"liquidationPreferenceMultiple": "', _uint256ToString(t.liquidationPreferenceMultiple),
            '", "liquidationPreferenceType": "', _liquidationPrefTypeToString(t.liquidationPreferenceType),
            '", "participationCap": "', _uint256ToString(t.participationCap),
            '", "seniorityRank": "', _uint256ToString(t.seniorityRank),
            '", '
        ));
    }

    function _buildDividends(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"dividendType": "', _dividendTypeToString(t.dividendType),
            '", "dividendRate": "', _uint256ToString(t.dividendRate),
            '", "dividendCompounding": "', _boolToString(t.dividendCompounding),
            '", "dividendIncreasesLiquidationAmount": "', _boolToString(t.dividendIncreasesLiquidationAmount),
            '", '
        ));
    }

    function _buildConversion(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"isConvertible": "', _boolToString(t.isConvertible),
            '", "conversionPrice": "', _uint256ToString(t.conversionPrice),
            '", "antiDilutionType": "', _antiDilutionTypeToString(t.antiDilutionType),
            '", "allowsFractionalConversion": "', _boolToString(t.allowsFractionalConversion),
            '", "hasMandatoryConversion": "', _boolToString(t.hasMandatoryConversion),
            '", "mandatoryConversionTriggerCount": "', _uint256ToString(t.mandatoryConversionTriggers.length),
            '", '
        ));
    }

    function _buildVoting(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"votesPerShare": "', _uint256ToString(t.votesPerShare),
            '", "designatedBoardSeats": "', _uint256ToString(uint256(t.designatedBoardSeats)),
            '", "hasClassVotingRights": "', _boolToString(t.hasClassVotingRights),
            '", "hasSeriesVotingRights": "', _boolToString(t.hasSeriesVotingRights),
            '", "specialVotingRightsCount": "', _uint256ToString(t.specialVotingRights.length),
            '", '
        ));
    }

    function _buildRestrictionsRedemption(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"transferRestrictionCount": "', _uint256ToString(t.transferRestrictions.length),
            '", "isRedeemable": "', _boolToString(t.isRedeemable),
            '", "redemptionType": "', _redemptionTypeToString(t.redemptionType),
            '", "redemptionPrice": "', _uint256ToString(t.redemptionPrice),
            '", '
        ));
    }

    function _buildCertificate(CertificateData memory c) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"certificateNumber": "', _uint256ToString(c.certificateNumber),
            '", "numberOfShares": "', _uint256ToString(c.numberOfShares),
            '", "issueDate": "', _uint256ToString(c.issueDate),
            '", "isPartlyPaid": "', _boolToString(c.isPartlyPaid),
            '", "amountPaid": "', _uint256ToString(c.amountPaid),
            '", "totalConsideration": "', _uint256ToString(c.totalConsideration),
            '", '
        ));
    }

    function _buildIssuer() internal view returns (string memory) {
        return string(abi.encodePacked(
            '"issuerName": "', issuerName, '"'
        ));
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — String Helpers
    // ══════════════════════════════════════════════════════════════

    function _shareClassKeyToString(bytes32 key) internal pure returns (string memory) {
        if (key == CLASS_COMMON) return "Common";
        if (key == CLASS_PREFERRED) return "Preferred";
        return "Custom";
    }

    function _liquidationPrefTypeToString(LiquidationPreferenceType t) internal pure returns (string memory) {
        if (t == LiquidationPreferenceType.NonParticipating) return "NonParticipating";
        if (t == LiquidationPreferenceType.Participating) return "Participating";
        if (t == LiquidationPreferenceType.CappedParticipating) return "CappedParticipating";
        return "Unknown";
    }

    function _antiDilutionTypeToString(AntiDilutionType t) internal pure returns (string memory) {
        if (t == AntiDilutionType.None) return "None";
        if (t == AntiDilutionType.BroadBasedWeightedAverage) return "BroadBasedWeightedAverage";
        if (t == AntiDilutionType.NarrowBasedWeightedAverage) return "NarrowBasedWeightedAverage";
        if (t == AntiDilutionType.FullRatchet) return "FullRatchet";
        return "Unknown";
    }

    function _dividendTypeToString(DividendType t) internal pure returns (string memory) {
        if (t == DividendType.None) return "None";
        if (t == DividendType.NonCumulative) return "NonCumulative";
        if (t == DividendType.Cumulative) return "Cumulative";
        return "Unknown";
    }

    function _transferRestrictionTypeToString(TransferRestrictionType t) internal pure returns (string memory) {
        if (t == TransferRestrictionType.None) return "None";
        if (t == TransferRestrictionType.BoardConsentRequired) return "BoardConsentRequired";
        if (t == TransferRestrictionType.ROFRAndCoSale) return "ROFRAndCoSale";
        if (t == TransferRestrictionType.LockUp) return "LockUp";
        if (t == TransferRestrictionType.SecuritiesActRestriction) return "SecuritiesActRestriction";
        if (t == TransferRestrictionType.CustomRestriction) return "CustomRestriction";
        return "Unknown";
    }

    function _redemptionTypeToString(RedemptionType t) internal pure returns (string memory) {
        if (t == RedemptionType.None) return "None";
        if (t == RedemptionType.HolderOptional) return "HolderOptional";
        if (t == RedemptionType.CompanyOptional) return "CompanyOptional";
        if (t == RedemptionType.Mandatory) return "Mandatory";
        if (t == RedemptionType.EventTriggered) return "EventTriggered";
        return "Unknown";
    }

    function _boolToString(bool b) internal pure returns (string memory) {
        return b ? "true" : "false";
    }

    function _uint256ToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // ──────────────────────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────────────────────

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
