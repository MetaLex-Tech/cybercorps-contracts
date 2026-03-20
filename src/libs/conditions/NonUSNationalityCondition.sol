// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./baseCondition.sol";
import "../LexScroWLite.sol";
import "../auth.sol";
import "../../interfaces/IZKPassportVerifier.sol";

/// @title NonUSNationalityCondition
/// @notice Round condition requiring a valid, non-US ZKPassport proof for the participant
contract NonUSNationalityCondition is BaseCondition, BorgAuthACL {
    error InvalidVerifier();
    error InvalidProof();
    error InvalidScope();
    error InvalidBoundSender();
    error InvalidBoundChainId();
    error InvalidMaxValidityPeriod();
    error USAOrSanctionedCountriesNotAllowed();
    error ProofExpired();
    error ProofAlreadyUsed();
    error MaxValidityPeriodExceeded();

    event ProofSubmitted(
        address indexed account,
        uint256 expiresAt
    );

    event MaxValidityPeriodUpdated(uint256 maxValidityPeriod);
    event ExcludedCountriesUpdated(string[] countries);

    // Deterministic verifier address from ZKPassport docs.
    address public constant DEFAULT_ZKPASSPORT_VERIFIER =
        0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    IZKPassportVerifier public verifier;
    string public expectedDomain;
    string public expectedScope;
    uint256 public maxValidityPeriod;

    mapping(address => uint256) public proofExpiry;
    mapping(bytes32 => bool) public usedProofIdentifiers;

    string[] public excludedCountries;

    /// @notice initialize atomically since this is not an upgradeable contract
    constructor(
        address _auth,
        string memory _expectedDomain,
        string memory _expectedScope,
        address _verifier,
        uint256 _maxValidityPeriod,
        string[] memory _excludedCountries
    ) {
        initialize(
            _auth,
            _expectedDomain,
            _expectedScope,
            _verifier,
            _maxValidityPeriod,
            _excludedCountries
        );
    }

    function initialize(
        address _auth,
        string memory _expectedDomain,
        string memory _expectedScope,
        address _verifier,
        uint256 _maxValidityPeriod,
        string[] memory _excludedCountries
    ) public initializer {
        __BorgAuthACL_init(_auth);

        expectedDomain = _expectedDomain;
        expectedScope = _expectedScope;

        address resolvedVerifier = _verifier == address(0)
            ? DEFAULT_ZKPASSPORT_VERIFIER
            : _verifier;
        if (resolvedVerifier == address(0)) revert InvalidVerifier();
        verifier = IZKPassportVerifier(resolvedVerifier);

        if(_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        maxValidityPeriod = _maxValidityPeriod;
        emit MaxValidityPeriodUpdated(_maxValidityPeriod);

        excludedCountries = _excludedCountries;
        emit ExcludedCountriesUpdated(_excludedCountries);
    }

    function updateMaxValidityPeriod(uint256 _maxValidityPeriod) external onlyAdmin {
        if(_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        maxValidityPeriod = _maxValidityPeriod;
        emit MaxValidityPeriodUpdated(_maxValidityPeriod);
    }

    function updateExcludedCountries(string[] calldata _excludedCountries) external onlyAdmin {
        excludedCountries = _excludedCountries;
        emit ExcludedCountriesUpdated(_excludedCountries);
    }

    /// @notice Submit and verify ZKPassport proof, then cache non-US eligibility for the caller
    function submitProof(
        ProofVerificationParams calldata params,
        bool isIDCard
    ) external {
        (bool verified, bytes32 uniqueIdentifier, IZKPassportHelper helper) = verifier.verify(params);
        if (!verified || address(helper) == address(0)) revert InvalidProof();

        if (usedProofIdentifiers[uniqueIdentifier]) revert ProofAlreadyUsed();
        usedProofIdentifiers[uniqueIdentifier] = true;

        if (
            !helper.verifyScopes(
                params.proofVerificationData.publicInputs,
                expectedDomain,
                expectedScope
            )
        ) {
            revert InvalidScope();
        }

        BoundData memory boundData = helper.getBoundData(params.committedInputs);
        if (boundData.senderAddress != msg.sender) revert InvalidBoundSender();
        if (boundData.chainId != block.chainid) revert InvalidBoundChainId();

        if(!helper.isNationalityOut(excludedCountries, params.committedInputs)) revert USAOrSanctionedCountriesNotAllowed();

        uint256 proofTimestamp = helper.getProofTimestamp(
            params.proofVerificationData.publicInputs
        );

        // Check against the sanctioned watchlist at the time of the proof
        helper.enforceSanctionsRoot(
            proofTimestamp,
            false,
            params.committedInputs
        );

        uint256 validityPeriod = params.serviceConfig.validityPeriodInSeconds;
        if (validityPeriod > maxValidityPeriod) revert MaxValidityPeriodExceeded();

        uint256 expiresAt = proofTimestamp + validityPeriod;
        if (expiresAt < block.timestamp) revert ProofExpired();

        proofExpiry[msg.sender] = expiresAt;
        emit ProofSubmitted(msg.sender, expiresAt);
    }

    /// @notice Condition check used by LexScroWLite.conditionCheck
    function checkCondition(
        address _contract,
        bytes4,
        bytes memory data
    ) public view override returns (bool) {
        LexScroWLite lexScrow = LexScroWLite(_contract);
        bytes32 agreementId = abi.decode(data, (bytes32));
        address counterparty = lexScrow.getEscrowDetails(agreementId).counterParty;
        return proofExpiry[counterparty] >= block.timestamp;
    }

}
