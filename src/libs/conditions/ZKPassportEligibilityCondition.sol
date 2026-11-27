// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ICondition} from "../../interfaces/ICondition.sol";
import {ILexScrowStorage} from "../../interfaces/ILexScrowStorage.sol";
import {EligibilityRules, IZKPassportEligibilityCondition} from "../../interfaces/IZKPassportEligibilityCondition.sol";
import {
    BoundData,
    IZKPassportEligibilityHelper,
    IZKPassportHelper,
    IZKPassportVerifier,
    NullifierType,
    ProofVerificationParams
} from "../../interfaces/IZKPassportVerifier.sol";
import {BorgAuth, BorgAuthACL, IBorgAuthACL} from "../auth.sol";
import {BaseCondition} from "./baseCondition.sol";
import {IERC165} from "openzeppelin-contracts/interfaces/IERC165.sol";

/// @title ZKPassportEligibilityCondition
/// @notice Standalone ICondition enforcing zero-knowledge ZKPassport nationality allowlist/exclusion,
///         minimum age, optional sanctions, and non-salted one-passport-one-wallet binding.
/// @dev Works unmodified with all deployed RoundManager (FCFS and FounderApproved) and DealManager
///      contracts via LexScrowStorage.conditionCheck. Rules, domain, scope, and devModeAllowed are
///      immutable after initialization (closing Hexens MTLX1-29 and MTLX1-33). No nationality or
///      birthdate is disclosed onchain; only zero-knowledge membership/age predicates are verified.
contract ZKPassportEligibilityCondition is BaseCondition, BorgAuthACL, IZKPassportEligibilityCondition {
    error InvalidVerifier();
    error InvalidDomain();
    error InvalidScope();
    error InvalidMaxValidityPeriod();
    error InvalidMinimumAge();
    error ConflictingNationalityLists();
    error TooManyCountries();
    error InvalidCountryCode();
    error UnsortedOrDuplicateCountries();
    error DevModeProof();
    error InvalidProof();
    error InvalidUniqueIdentifier();
    error InvalidNullifierType();
    error InvalidBoundSender();
    error InvalidBoundChainId();
    error NationalityNotAllowed();
    error NationalityExcluded();
    error AgeRequirementNotMet();
    error ProofExpired();
    error MaxValidityPeriodExceeded();
    error ProofAlreadyUsed();
    error WalletAlreadyBound();
    error InvalidManager();
    error InvalidInvestor();

    event ProofSubmitted(address indexed account, bytes32 indexed uniqueIdentifier, uint256 expiresAt);
    event MaxValidityPeriodUpdated(uint256 maxValidityPeriod);
    event FounderOverrideUpdated(
        address indexed manager, address indexed investor, bool approved, address indexed approver
    );

    string public constant DEPLOY_VERSION = "1.0";

    // Deterministic verifier address from ZKPassport docs.
    address public constant DEFAULT_ZKPASSPORT_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;
    uint8 public constant MAX_MINIMUM_AGE = 99;
    uint256 public constant MAX_COUNTRIES = 250;

    IZKPassportVerifier public verifier;
    string public expectedDomain;
    string public expectedScope;
    uint256 public maxValidityPeriod;
    bool public devModeAllowed;

    string[] private _allowedNationalities;
    string[] private _excludedNationalities;
    uint8 public minimumAge;
    bool public enforceSanctions;

    mapping(address => uint256) public proofExpiry;
    mapping(bytes32 => uint256) public uniqueIdentifierExpiry;
    mapping(bytes32 => address) public walletOfIdentifier;
    mapping(address => bytes32) public identifierOfWallet;
    // manager => investor => approved
    mapping(address => mapping(address => bool)) public founderOverrides;

    uint256[37] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        string memory _expectedDomain,
        string memory _expectedScope,
        address _verifier,
        uint256 _maxValidityPeriod,
        bool _devModeAllowed,
        EligibilityRules memory _rules
    ) public initializer {
        __BorgAuthACL_init(_auth);

        if (bytes(_expectedDomain).length == 0) revert InvalidDomain();
        if (bytes(_expectedScope).length == 0) revert InvalidScope();
        if (_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();

        address resolvedVerifier = _verifier == address(0) ? DEFAULT_ZKPASSPORT_VERIFIER : _verifier;
        if (resolvedVerifier == address(0)) revert InvalidVerifier();

        _validateRules(_rules);

        expectedDomain = _expectedDomain;
        expectedScope = _expectedScope;
        verifier = IZKPassportVerifier(resolvedVerifier);
        maxValidityPeriod = _maxValidityPeriod;
        devModeAllowed = _devModeAllowed;

        _allowedNationalities = _rules.allowedNationalities;
        _excludedNationalities = _rules.excludedNationalities;
        minimumAge = _rules.minimumAge;
        enforceSanctions = _rules.enforceSanctions;

        emit MaxValidityPeriodUpdated(_maxValidityPeriod);
    }

    /// @notice Update the maximum accepted proof validity period for future submissions.
    function updateMaxValidityPeriod(uint256 _maxValidityPeriod) external onlyAdmin {
        if (_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        maxValidityPeriod = _maxValidityPeriod;
        emit MaxValidityPeriodUpdated(_maxValidityPeriod);
    }

    /// @notice Submit and verify a zero-knowledge ZKPassport proof, caching eligibility for msg.sender.
    function submitProof(ProofVerificationParams calldata params) external {
        // MTLX1-33: never accept caller-selected dev-mode proofs unless explicitly enabled (testnets only).
        if (params.serviceConfig.devMode && !devModeAllowed) revert DevModeProof();

        (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper rawHelper) = verifier.verify(params);
        if (!verified || address(rawHelper) == address(0)) revert InvalidProof();
        if (uniqueIdentifier == bytes32(0)) revert InvalidUniqueIdentifier();

        IZKPassportEligibilityHelper helper = IZKPassportEligibilityHelper(address(rawHelper));

        // MTLX1-33: reject salted and empty nullifiers so one passport maps to one identifier.
        NullifierType nullifierType = helper.getNullifierType(params.proofVerificationData.publicInputs);
        if (devModeAllowed) {
            if (
                nullifierType != NullifierType.NON_SALTED_NULLIFIER
                    && nullifierType != NullifierType.NON_SALTED_MOCK_NULLIFIER
            ) {
                revert InvalidNullifierType();
            }
        } else if (nullifierType != NullifierType.NON_SALTED_NULLIFIER) {
            revert InvalidNullifierType();
        }

        if (!helper.verifyScopes(params.proofVerificationData.publicInputs, expectedDomain, expectedScope)) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(params.committedInputs);
        if (boundData.senderAddress != msg.sender) revert InvalidBoundSender();
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();

        if (_allowedNationalities.length > 0) {
            if (!helper.isNationalityIn(_allowedNationalities, params.committedInputs)) {
                revert NationalityNotAllowed();
            }
        } else if (_excludedNationalities.length > 0) {
            if (!helper.isNationalityOut(_excludedNationalities, params.committedInputs)) {
                revert NationalityExcluded();
            }
        }

        if (minimumAge > 0) {
            if (!helper.isAgeAboveOrEqual(minimumAge, params.committedInputs)) {
                revert AgeRequirementNotMet();
            }
        }

        uint256 proofTimestamp = helper.getProofTimestamp(params.proofVerificationData.publicInputs);
        uint256 validityPeriod = params.serviceConfig.validityPeriodInSeconds;
        if (validityPeriod == 0 || validityPeriod > maxValidityPeriod) revert MaxValidityPeriodExceeded();

        uint256 expiresAt = proofTimestamp + validityPeriod;
        if (expiresAt < block.timestamp) revert ProofExpired();
        if (expiresAt > block.timestamp + maxValidityPeriod) revert MaxValidityPeriodExceeded();

        if (enforceSanctions) {
            helper.enforceSanctionsRoot(proofTimestamp, false, params.committedInputs);
        }

        // Enforce one-passport-one-wallet while allowing the same wallet to renew its own proof.
        if (
            uniqueIdentifierExpiry[uniqueIdentifier] != 0 && uniqueIdentifierExpiry[uniqueIdentifier] >= block.timestamp
                && walletOfIdentifier[uniqueIdentifier] != msg.sender
        ) {
            revert ProofAlreadyUsed();
        }

        bytes32 existingIdentifier = identifierOfWallet[msg.sender];
        if (
            existingIdentifier != bytes32(0) && existingIdentifier != uniqueIdentifier && proofExpiry[msg.sender] != 0
                && proofExpiry[msg.sender] >= block.timestamp
        ) {
            revert WalletAlreadyBound();
        }

        uint256 newExpiry = expiresAt > proofExpiry[msg.sender] ? expiresAt : proofExpiry[msg.sender];
        walletOfIdentifier[uniqueIdentifier] = msg.sender;
        identifierOfWallet[msg.sender] = uniqueIdentifier;
        proofExpiry[msg.sender] = newExpiry;
        uniqueIdentifierExpiry[uniqueIdentifier] = newExpiry;

        emit ProofSubmitted(msg.sender, uniqueIdentifier, newExpiry);
    }

    /// @notice Allow the owner of a RoundManager or DealManager to override eligibility for a specific investor.
    function setFounderOverride(address _manager, address _investor, bool _approved) external {
        if (_manager == address(0)) revert InvalidManager();
        if (_investor == address(0)) revert InvalidInvestor();

        BorgAuth auth = IBorgAuthACL(_manager).AUTH();
        auth.onlyRole(auth.OWNER_ROLE(), msg.sender);

        founderOverrides[_manager][_investor] = _approved;
        emit FounderOverrideUpdated(_manager, _investor, _approved, msg.sender);
    }

    /// @notice Read-only preflight eligibility check for a manager and investor wallet.
    function isEligible(address _manager, address _investor) public view returns (bool) {
        if (founderOverrides[_manager][_investor]) return true;
        uint256 expiry = proofExpiry[_investor];
        return expiry != 0 && expiry >= block.timestamp;
    }

    /// @notice Condition check called by LexScrowStorage.conditionCheck (FCFS, FounderApproved, DealManager).
    function checkCondition(address _contract, bytes4, bytes memory data)
        public
        view
        override(BaseCondition, ICondition)
        returns (bool)
    {
        bytes32 agreementId = abi.decode(data, (bytes32));
        address counterparty = ILexScrowStorage(_contract).getEscrowDetails(agreementId).counterParty;
        return isEligible(_contract, counterparty);
    }

    function getAllowedNationalities() external view returns (string[] memory) {
        return _allowedNationalities;
    }

    function getExcludedNationalities() external view returns (string[] memory) {
        return _excludedNationalities;
    }

    function getRules() external view returns (EligibilityRules memory) {
        return EligibilityRules({
            allowedNationalities: _allowedNationalities,
            excludedNationalities: _excludedNationalities,
            minimumAge: minimumAge,
            enforceSanctions: enforceSanctions
        });
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IZKPassportEligibilityCondition).interfaceId
            || interfaceId == type(ICondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function _validateRules(EligibilityRules memory _rules) internal pure {
        if (_rules.minimumAge > MAX_MINIMUM_AGE) revert InvalidMinimumAge();
        if (_rules.allowedNationalities.length > 0 && _rules.excludedNationalities.length > 0) {
            revert ConflictingNationalityLists();
        }
        _validateCountryList(_rules.allowedNationalities);
        _validateCountryList(_rules.excludedNationalities);
    }

    function _validateCountryList(string[] memory countries) internal pure {
        uint256 len = countries.length;
        if (len > MAX_COUNTRIES) revert TooManyCountries();

        bytes3 prev;
        for (uint256 i = 0; i < len; i++) {
            bytes memory code = bytes(countries[i]);
            if (code.length != 3) revert InvalidCountryCode();
            bytes1 c0 = code[0];
            bytes1 c1 = code[1];
            bytes1 c2 = code[2];
            if (c0 < 0x41 || c0 > 0x5A || c1 < 0x41 || c1 > 0x5A || c2 < 0x41 || c2 > 0x5A) {
                revert InvalidCountryCode();
            }

            bytes3 curr = bytes3(abi.encodePacked(c0, c1, c2));
            if (i > 0 && curr <= prev) revert UnsortedOrDuplicateCountries();
            prev = curr;
        }
    }
}
