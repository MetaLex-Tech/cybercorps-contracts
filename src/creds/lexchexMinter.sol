// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICyberAgreementRegistry.sol";
import "../libs/auth.sol";
import "./lexchex.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract LeXcheXMinter is Initializable, BorgAuthACL {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // Domain information
    string public constant name = "LeXcheXMinter";
    string public version;
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public AUTHORITY_TYPEHASH;
    address public auth;

    // Errors
    error InvalidSignature();
    error PaymentFailed();
    error InvalidPaymentAmount();
    error MintFailed();
    error AgreementVoided();

    // Events
    event MintRequested(address indexed requester, uint256 mintPrice, bytes32 agreementId);
    event MintCompleted(address indexed owner, uint256 tokenId, bytes32 agreementId);
    event RenewalRequested(address indexed requester, uint256 mintPrice, bytes32 agreementId);
    event RenewalCompleted(address indexed owner, uint256 tokenId, bytes32 agreementId);

    // State variables
    address public lexchex;
    address public dealRegistry;
    address public paymentToken;
    address public treasury;

    struct MintRequest {
        address owner;
        string name;
        string entityType;
        string jurisdiction;
        string contact;
        string[] portfolio;
        uint256 mintPrice;
        uint256 expiry;
    }

    struct AuthorityData {
        address owner;
        string name;
        string entityType;
        string jurisdiction;
        uint256 mintPrice;
        uint256 expiry;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _lexchex,
        address _dealRegistry,
        address _paymentToken,
        address _treasury
    ) public initializer {
        __BorgAuthACL_init(_auth);
        lexchex = _lexchex;
        dealRegistry = _dealRegistry;
        paymentToken = _paymentToken;
        treasury = _treasury;
        auth = _auth;
        version = "1";
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );

        AUTHORITY_TYPEHASH = keccak256(
            "AuthorityData(address owner,string name,string entityType,string jurisdiction,uint256 mintPrice,uint256 expiry)"
        );
    }

    function requestMint(
        MintRequest calldata request,
        bytes32 _templateId,
        uint256 _salt,
        string[] memory _globalValues,
        address[] memory _parties,
        string[][] memory _partyValues,
        bytes memory agreementSignature,  // Signature for the agreement
        bytes memory authoritySignature    // Signature from authority for verification
    ) external returns (bytes32 agreementId, uint256 tokenId) {
        // 1. Verify authority signature is from an admin using EIP-712
        if (!_verifyAuthoritySignature(request, authoritySignature)) {
            revert InvalidSignature();
        }

        // 2. Handle payment using safeTransferFrom
        if (request.mintPrice > 0) {
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // 3. Create accreditation struct
        Accreditation memory acc = Accreditation({
            agreementId: bytes32(0), // Will be set after agreement creation
            registryAddress: dealRegistry,
            name: request.name,
            entityType: request.entityType,
            jurisdiction: request.jurisdiction,
            contact: request.contact,
            issuanceDate: block.timestamp,
            expiryDate: request.expiry,
            voided: "",
            portfolio: request.portfolio,
            signature: authoritySignature  // Use authority signature here
        });

        // 4. Create and sign agreement
        agreementId = ICyberAgreementRegistry(dealRegistry).createContract(
            _templateId,
            _salt,
            _globalValues,
            _parties,
            _partyValues,
            bytes32(0), // No secret hash
            address(this),
            request.expiry
        );

        // Sign the agreement with the provided agreement signature
        ICyberAgreementRegistry(dealRegistry).signContractFor(
            request.owner,
            agreementId,
            _partyValues[0],
            agreementSignature,
            false,
            ""
        );

        // Update accreditation with agreement ID
        acc.agreementId = agreementId;

        // 5. Mint LeXcheX
        tokenId = LeXcheX(lexchex).mint(request.owner, acc);

        // 6. Finalize the agreement
        ICyberAgreementRegistry(dealRegistry).finalizeContract(agreementId);

        emit MintRequested(request.owner, request.mintPrice, agreementId);
        emit MintCompleted(request.owner, tokenId, agreementId);
    }

    function requestRenewal(
        MintRequest calldata request,
        bytes32 agreementId,
        uint256 id,
        bytes memory authoritySignature
    ) external returns (uint256 tokenId) {
        // 1. Verify authority signature is from an admin using EIP-712
        if (!_verifyAuthoritySignature(request, authoritySignature)) {
            revert InvalidSignature();
        }

        // get the accreditation
        Accreditation memory acc = LeXcheX(lexchex).accreditations(id);

        //check that the agreement has not been voided
        if(bytes(acc.voided).length > 0) {
            revert AgreementVoided();
        }

        // 2. Handle payment using safeTransferFrom
        if (request.mintPrice > 0) {
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                treasury,
                request.mintPrice
            );
        }

        // 3. Renew the agreement
        acc.expiryDate = request.expiry;
        acc.signature = authoritySignature;

        // 4. Mint LeXcheX
        LeXcheX(lexchex).setAccreditation(id, acc);

        emit RenewalRequested(request.owner, request.mintPrice, agreementId);
        emit RenewalCompleted(request.owner, tokenId, agreementId);
    }

    function _verifyAuthoritySignature(
        MintRequest memory request,
        bytes memory signature
    ) internal view returns (bool) {
        // Create AuthorityData struct for signature verification
        AuthorityData memory data = AuthorityData({
            owner: request.owner,
            name: request.name,
            entityType: request.entityType,
            jurisdiction: request.jurisdiction,
            mintPrice: request.mintPrice,
            expiry: request.expiry
        });

        // Hash the data according to EIP-712
        bytes32 digest = _hashTypedDataV4(data);

        // Recover the signer address
        address recoveredSigner = digest.recover(signature);

        // Check if the recovered signer is an admin
        return (BorgAuthACL(auth).userRoles(recoveredSigner) == BorgAuth(BorgAuthACL(auth).AUTH()).ADMIN_ROLE());
    }

    function _hashTypedDataV4(AuthorityData memory data) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        AUTHORITY_TYPEHASH,
                        data.owner,
                        keccak256(bytes(data.name)),
                        keccak256(bytes(data.entityType)),
                        keccak256(bytes(data.jurisdiction)),
                        data.mintPrice,
                        data.expiry
                    )
                )
            )
        );
    }

    // Admin functions
    function setLexchex(address _lexchex) external onlyOwner {
        lexchex = _lexchex;
    }

    function setDealRegistry(address _dealRegistry) external onlyOwner {
        dealRegistry = _dealRegistry;
    }

    function setPaymentToken(address _paymentToken) external onlyOwner {
        paymentToken = _paymentToken;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }
}
