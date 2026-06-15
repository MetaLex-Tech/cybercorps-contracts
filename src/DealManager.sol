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

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/auth.sol";
import "./storage/DealManagerStorage.sol";
import "./storage/DealManagerFactoryStorage.sol";
import "./storage/BorgAuthStorage.sol";
import "./storage/SecondaryTradeStorage.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/IDealManagerStorage.sol";
import "./interfaces/ISecondaryTradeStorage.sol";
import "./interfaces/ILexScrowStorage.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementRegistry.sol";

/// @title DealManager
/// @notice Manages the lifecycle of deals between parties, including creation, signing, payment, and finalization for a CyberCorp
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract DealManager is
    Initializable,
    BorgAuthACL,
    UUPSUpgradeable,
    ReentrancyGuard,
    IDealManager,
    IDealManagerStorage,
    ISecondaryTradeStorage,
    ILexScrowStorage
{
    using DealManagerStorage for DealManagerStorage.DealManagerData;
    using SafeERC20 for IERC20;

    string public constant DEPLOY_VERSION = "4.0.1"; // For version-tracking on all deployment and future upgrades

    // Library-emitted events/errors are inherited from the per-library interfaces (IDealManagerStorage,
    // ISecondaryTradeStorage and ILexScrowStorage) so their selectors/topics appear in DealManager's ABI.

    // The errors/event below are owned and used directly by DealManager. (Shared
    error ZeroAddress();
    error PartyValuesLengthMismatch();
    error ConditionAlreadyExists();
    error ConditionDoesNotExist();
    error NotRefImplementation();
    event MinTradeThresholdSet(uint256 minUnits, uint256 minConsideration, address setter);

    /// @notice Maps agreement IDs to arrays of counter party values for closed deals.
    mapping(bytes32 => string[]) public counterPartyValues;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the DealManager contract
    /// @dev Sets up the contract with required addresses and initializes parent contracts
    /// @param _auth Address of the BorgAuth contract
    /// @param _corp Address of the CyberCorp
    /// @param _dealRegistry Address of the CyberAgreementRegistry
    /// @param _issuanceManager Address of the CyberCorp's issuance manager
    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager, address _upgradeFactory) public initializer {
        __BorgAuthACL_init(_auth);
        
        if (_corp == address(0)) revert ZeroAddress();
        if (_dealRegistry == address(0)) revert ZeroAddress();
        if (_issuanceManager == address(0)) revert ZeroAddress();

        // Set storage values
        DealManagerStorage.setIssuanceManager(_issuanceManager);

        // Initialize LexScrowStorage core addresses (LexScrowStorage is now a library — set storage directly)
        LexScrowStorage.setCorp(_corp);
        LexScrowStorage.setDealRegistry(_dealRegistry);
        DealManagerStorage.setUpgradeFactory(_upgradeFactory);
    }

    /// @notice Proposes a new deal
    /// @dev Creates a new agreement and certificate for the deal
    /// @param _certPrinterAddress Array of certificate printer addresses
    /// @param _paymentToken Address of the token used for payment
    /// @param _paymentAmount Amount to be paid
    /// @param _templateId ID of the agreement template to use
    /// @param _salt Random value for unique agreement ID generation
    /// @param _globalValues Array of global values for the agreement, must match the template
    /// @param _parties Array of party addresses
    /// @param _certDetails Details of the certificate to be created
    /// @param _partyValues Array of party-specific values, must match the template
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of the secret required for finalization (if any)
    /// @param expiry Timestamp when the deal expires
    /// @return agreementId Unique identifier for the agreement
    /// @return certIds IDs of the created certificate
    function proposeDeal(
        address[] memory _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails[] memory _certDetails,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256[] memory certIds) {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        return DealManagerStorage.proposeDeal(
            _certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt,
            _globalValues, _parties, _certDetails, _partyValues, conditions, secretHash, expiry
        );
    }

    /// @notice Proposes and signs a deal in one transaction
    /// @dev Combines deal proposal and initial signature
    /// @param _certPrinterAddress Array of certificate printer addresses
    /// @param _paymentToken Address of the token used for payment
    /// @param _paymentAmount Amount to be paid
    /// @param _templateId ID of the agreement template to use
    /// @param _salt Random value for unique agreement ID generation
    /// @param _globalValues Array of global values for the agreement, must match the template
    /// @param _parties Array of party addresses
    /// @param _certDetails Details of the certificate to be created
    /// @param proposer Address of the deal proposer
    /// @param signature Signature of the proposer
    /// @param _partyValues Array of party-specific values, must match the template
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of the secret required for finalization (if any)
    /// @param expiry Timestamp when the deal expires
    /// @return agreementId Unique identifier for the agreement
    /// @return certIds IDs of the created certificate
    function proposeAndSignDeal(
        address[] memory _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails[] memory _certDetails,
        address proposer,
        bytes memory signature,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256[] memory certIds) {
        // Implemented here (not in DealManagerStorage) on purpose: keeping proposeAndSignDeal out of that
        // library stops the via-ir Yul optimizer from inlining proposeDeal into it (which overflows the
        // stack). proposeDeal is reached via a cross-contract delegatecall, so its heavy body stays in the
        // linked library and is never inlined here.
        if(_partyValues.length > _parties.length) revert PartyValuesLengthMismatch();

        (agreementId, certIds) = DealManagerStorage.proposeDeal(
            _certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt,
            _globalValues, _parties, _certDetails, _partyValues, conditions, secretHash, expiry
        );
        // NOTE: proposer is expected to be listed as a party in the parties array.

        // Update the escrow signature
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        escrow.signature = signature;

        if(_partyValues.length > 1) {
            if(_partyValues[1].length != _partyValues[0].length) revert PartyValuesLengthMismatch();
            DealManagerStorage.setCounterPartyValues(agreementId, _partyValues[1]);
        }
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(proposer, agreementId, _partyValues[0], signature, false, "");
    }

    /// @notice Signs a deal and processes payment
    /// @dev Validates signature and processes payment for the deal
    /// @param signer Address of the signer
    /// @param agreementId Unique identifier for the agreement
    /// @param signature Digital Signature hash of the signer
    /// @param partyValues Array of party-specific values, must match the template
    /// @param _fillUnallocated Whether to fill unallocated slots
    /// @param name Name of the signer
    /// @param secret Secret required for finalization (if any)
    function signDealAndPay(
        address signer,
        bytes32 agreementId,
        bytes memory signature,
        string[] memory partyValues,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.signDealAndPay(signer, agreementId, signature, partyValues, _fillUnallocated, name, secret);
    }

    /// @notice Signs and finalizes a deal in one transaction
    /// @dev Combines signing, payment, and finalization steps
    /// @param signer Address of the signer
    /// @param agreementId Unique identifier for the agreement
    /// @param partyValues Array of party-specific values, must match the template
    /// @param signature Digital Signature hash of the signer   
    /// @param _fillUnallocated Whether to fill unallocated slots
    /// @param name Name of the signer
    /// @param secret Secret required for finalization (if any)
    function signAndFinalizeDeal(
        address signer,
        bytes32 agreementId,
        string[] memory partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public nonReentrant {
        // Thin wrapper over the linked DealManagerStorage logic. nonReentrant is required here because the
        // moved logic invokes finalizeDeal as an internal library call that no longer passes through the
        // guarded finalizeDeal wrapper below.
        DealManagerStorage.signAndFinalizeDeal(signer, agreementId, partyValues, signature, _fillUnallocated, name, secret);
    }

    /// @notice Finalizes a deal
    /// @dev Checks signatures, conditions and finalizes the agreement
    /// @param agreementId Unique identifier for the agreement
    function finalizeDeal(bytes32 agreementId) public nonReentrant {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.finalizeDeal(agreementId);
    }

    /// @notice Voids an expired deal
    /// @dev Voids the certificate and agreement for an expired deal
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public nonReentrant {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.voidExpiredDeal(agreementId, signer, signature);
    }

    /// @notice Revokes a pending deal
    /// @dev Can only be called for deals in pending status
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.revokeDeal(agreementId, signer, signature);
    }

    /// @notice Signs to void a deal
    /// @dev If the deal is paid, initiates refund process
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public nonReentrant {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.signToVoid(agreementId, signer, signature);
    }

    /// @notice Refund a voided deal
    /// @dev Use this method to initiate refund if the deal agreement has been voided externally
    /// (e.g. directly to CyberAgreementRegistry without being processed by Deal Manager)
    /// @param agreementId Unique identifier for the agreement
    function refundVoidedDeal(bytes32 agreementId) public nonReentrant {
        // Thin wrapper over the linked DealManagerStorage logic (delegatecall keeps storage/msg.sender)
        DealManagerStorage.refundVoidedDeal(agreementId);
    }

    /// @notice Adds a condition to a deal
    /// @dev Can only be called by owner for pending deals
    /// @param agreementId Unique identifier for the agreement
    /// @param condition Address of the condition contract to add
    function addCondition(bytes32 agreementId, address condition) public onlyOwner {
        //make sure the contract is still pending
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is not already in the list
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        for(uint256 i = 0; i < conditions.length; i++) {
            if(conditions[i] == ICondition(condition)) revert ConditionAlreadyExists();
        }
        LexScrowStorage.addConditionToEscrow(agreementId, ICondition(condition));
    }

    /// @notice Removes a condition from a deal
    /// @dev Can only be called by owner for pending deals
    /// @param agreementId Unique identifier for the agreement
    /// @param index Index of the condition to remove
    function removeConditionAt(bytes32 agreementId, uint256 index) public onlyOwner {
        //make sure the contract is still pending
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is in the list
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        if(index >= conditions.length) revert ConditionDoesNotExist();

        LexScrowStorage.removeConditionFromEscrow(agreementId, index);
    }

    /// @notice Sets the deal registry address
    /// @dev Can only be called by owner
    /// @param _dealRegistry New deal registry address
    function setDealRegistry(address _dealRegistry) public onlyOwner {
        LexScrowStorage.setDealRegistry(_dealRegistry);
    }

    /// @notice Sets the corporation address
    /// @dev Can only be called by owner
    /// @param _corp New corporation address
    function setCorp(address _corp) public onlyOwner {
        LexScrowStorage.setCorp(_corp);
    }

    /// @notice Sets the issuance manager address
    /// @dev Can only be called by owner
    /// @param _issuanceManager New issuance manager address
    function setIssuanceManager(address _issuanceManager) public onlyOwner {
        DealManagerStorage.setIssuanceManager(_issuanceManager);
    }

    /// @notice Gets the current issuance manager
    /// @return IIssuanceManager The current issuance manager contract
    function issuanceManager() public view returns (IIssuanceManager) {
        return DealManagerStorage.getIssuanceManager();
    }

    /// @notice Gets the counter party values for an agreement
    /// @param agreementId Unique identifier for the agreement
    /// @return string[] Array of counter party values
    function getCounterPartyValues(bytes32 agreementId) public view returns (string[] memory) {
        return DealManagerStorage.getCounterPartyValues(agreementId);
    }


    /// @notice Creates an offer for an existing CyberCorp
    /// @dev Creates certificate printers and proposes a deal without deploying a new CyberCorp
    /// @param _certData Array of certificate data structures
    /// @param _templateId ID of the agreement template to use
    /// @param _globalValues Array of global values for the agreement
    /// @param _parties Array of party addresses
    /// @param _paymentAmount Amount to be paid
    /// @param _partyValues Array of party-specific values
    /// @param signature Digital signature for the deal
    /// @param _details Certificate details for each certificate
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of secret required for finalization
    /// @param expiry Deal expiration timestamp
    /// @param stableAddress Address of the stable token for payment
    /// @param salt Salt value for unique agreement ID generation
    /// @return certPrinterAddress Array of deployed certificate printer addresses
    /// @return id Unique agreement ID
    /// @return certIds Array of certificate IDs created
    function proposeAndSignNewCertsDeal(
        uint256 salt,
        DealManagerStorage.CyberCertData[] memory _certData,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails[] memory _details,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry,
        address stableAddress
    ) external onlyOwner returns (
        address[] memory certPrinterAddress,
        bytes32 id,
        uint256[] memory certIds
    )  {
        // Lives here alongside proposeAndSignDeal (its only internal caller) so that function can stay out of
        // DealManagerStorage — see the note on proposeAndSignDeal.
        certPrinterAddress = new address[](_certData.length);
        // Scope companyName + loop temporaries so they (and _certData) are freed before the heavy
        // proposeAndSignDeal call below — keeps via-ir stack scheduling within budget.
        {
            // Get company name from the parent CyberCorp
            string memory companyName = ICyberCorp(LexScrowStorage.getCorp()).cyberCORPName();
            for (uint256 i = 0; i < _certData.length; i++) {
                certPrinterAddress[i] = DealManagerStorage.getIssuanceManager().createCertPrinter(
                    _certData[i].defaultLegend,
                    string.concat(companyName, " ", _certData[i].name),
                    _certData[i].symbol,
                    _certData[i].uri,
                    _certData[i].securityClass,
                    _certData[i].securitySeries,
                    _certData[i].extension
                );
            }
        }

        // Create and sign deal
        certIds = new uint256[](certPrinterAddress.length);
        (id, certIds) = proposeAndSignDeal(
            certPrinterAddress,
            stableAddress,
            _paymentAmount,
            _templateId,
            salt,
            _globalValues,
            _parties,
            _details,
            msg.sender,
            signature,
            _partyValues,
            conditions,
            secretHash,
            expiry
        );
    }

    /// @notice Compute fee based on ticket size
    /// @dev Currently the factory owner (MetaLeX) unilaterally set the fee ratio;
    /// in the future, it could be determined through a governance process.
    /// @return Fee amount
    function computeFee(uint256 size) public view returns (uint256) {
        return size * IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getDefaultFeeRatio() / DealManagerFactoryStorage.BASIS_POINTS;
    }

    /// @notice Gets the payable address for the fees
    /// @dev The factory owner (MetaLeX) unilaterally set the payable address
    /// @return Payable address for the fees
    function getPlatformPayable() public view returns (address) {
        return IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getPlatformPayable();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LexScrowStorage surface — thin wrappers (LexScrowStorage is now a library) so the proxy keeps
    // exposing these selectors for off-chain callers and condition contracts (ILexScrowStorage).
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Get escrow details for a given agreement id
    function getEscrowDetails(bytes32 agreementId) public view returns (Escrow memory) {
        return LexScrowStorage.getEscrow(agreementId);
    }

    /// @notice Check all conditions attached to the escrow for the given agreement
    function conditionCheck(bytes32 agreementId) public view returns (bool) {
        return LexScrowStorage.conditionCheck(agreementId);
    }

    /// @notice ERC721 receiver hook for safe transfers into escrow (moved here from LexScrowStorage)
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice ERC1155 receiver hook for safe transfers into escrow (moved here from LexScrowStorage)
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — threshold setters
    // ─────────────────────────────────────────────────────────────────────────

    function setMinTradeThreshold(uint256 units, uint256 consideration) external onlyAdmin {
        SecondaryTradeStorage.SecondaryTradeData storage ds = SecondaryTradeStorage.secondaryTradeStorage();
        ds.minTradeUnits = units;
        ds.minTradeConsideration = consideration;
        emit MinTradeThresholdSet(units, consideration, msg.sender);
    }

    function setDefaultIntegrator(address integrator) external onlyAdmin {
        if (integrator != address(0)) {
            if (!IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).isIntegratorWhitelisted(integrator))
                revert IntegratorNotWhitelisted();
        }
        SecondaryTradeStorage.secondaryTradeStorage().defaultIntegrator = integrator;
    }

    function getOffer(bytes32 offerId) external view returns (Offer memory) {
        return SecondaryTradeStorage.secondaryTradeStorage().offers[offerId];
    }

    function getSecondaryEscrow(bytes32 agreementId) external view returns (SecondaryEscrow memory) {
        return SecondaryTradeStorage.secondaryTradeStorage().escrows[agreementId];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — offer lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    // TODO implement *For()
    /// @notice Posts a secondary-trade offer. Thin wrapper over the linked SecondaryTradeStorage logic.
    function postOffer(PostOfferParams calldata params) external nonReentrant returns (bytes32 offerId) {
        return SecondaryTradeStorage.postOffer(params);
    }

    // TODO implement *For()
    /// @notice Cancels a non-terminal offer and returns its uncommitted assets to the offeror
    /// @dev Only the free pool (uncommitted units / consideration) is refunded/released. Settlements already
    /// accepted stay ACCEPTED and resolve on their own — finalized normally, or voided via the two-party
    /// voidSecondaryAgreement / expiry path; their assets stay in DealManager custody until then.
    /// @param offerId Offer to cancel
    function cancelOffer(bytes32 offerId) external nonReentrant {
        SecondaryTradeStorage.cancelOffer(offerId);
    }

    // TODO implement *For()
    /// @notice Accepts (fully or partially) a secondary-trade offer. Thin wrapper over the linked logic.
    function acceptOffer(AcceptOfferParams calldata params) external nonReentrant returns (bytes32 settlementAgreementId) {
        return SecondaryTradeStorage.acceptOffer(params);
    }

    /// @notice Records a party's request to void an ACCEPTED secondary settlement before it is finalized or expires
    /// @dev Finalizer-vouched request channel: the registry voids the agreement only once BOTH parties have
    /// requested (or it is past expiry). The local escrow is settled only when that actually happens, keeping
    /// DealManager and the registry in sync; a lone request just records intent and the counterparty can still finalize.
    /// @param agreementId Settlement agreement to void
    /// @param signer Caller's address (must equal msg.sender)
    /// @param signature Caller's EIP-712 void signature, forwarded to the agreement registry
    function voidSecondaryAgreement(bytes32 agreementId, address signer, bytes memory signature) external nonReentrant {
        SecondaryTradeStorage.voidSecondaryAgreement(agreementId, signer, signature);
    }

    /// @notice Syncs a secondary settlement that was voided directly in the agreement registry
    /// @dev Callable by anyone; guards against double-void via the terminal-state checks
    /// @param agreementId Settlement agreement that was already voided in the registry
    function syncVoidedSettlement(bytes32 agreementId) external nonReentrant {
        SecondaryTradeStorage.syncVoidedSettlement(agreementId);
    }

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        if(IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getRefImplementation() != newImplementation) {
            revert NotRefImplementation();
        }
    }
}
