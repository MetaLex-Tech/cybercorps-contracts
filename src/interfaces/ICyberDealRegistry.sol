// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

interface ICyberDealRegistry {
    struct Template {
        string legalContractUri;
        string title;
        string[] globalFields;
        string[] partyFields;
    }

    struct ContractData {
        bytes32 templateId;
        string[] globalValues;
        address[] parties;
        uint256 numSignatures;
        bytes32 transactionHash;
    }

    event TemplateCreated(
        bytes32 indexed templateId,
        string indexed title,
        string legalContractUri,
        string[] globalFields,
        string[] signerFields
    );

    event ContractCreated(bytes32 indexed contractId, bytes32 indexed templateId, address[] parties);

    event AgreementSigned(bytes32 indexed contractId, address indexed party, uint256 timestamp);

    event ContractFullySigned(bytes32 indexed contractId, uint256 timestamp);

    function createTemplate(
        bytes32 templateId,
        string memory title,
        string memory legalContractUri,
        string[] memory globalFields,
        string[] memory partyFields
    ) external;

    function createContract(bytes32 templateId, uint256 salt, string[] memory globalValues, address[] memory parties)
        external
        returns (bytes32);

    function signContract(bytes32 contractId, string[] memory partyValues, bool fillUnallocated) external;

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated // to fill a 0 address or not
    ) external;

    function getParties(bytes32 contractId) external view returns (address[] memory);

    function hasSigned(bytes32 contractId, address signer) external view returns (bool);

    function getSignatureTimestamp(bytes32 contractId, address signer) external view returns (uint256);

    function allPartiesSigned(bytes32 contractId) external view returns (bool);

    function getContractDetails(bytes32 contractId)
        external
        view
        returns (
            bytes32 templateId,
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory partyFields,
            string[] memory globalValues,
            address[] memory parties,
            string[][] memory partyValues,
            uint256[] memory signedAt,
            uint256 numSignatures,
            bool isComplete,
            bytes32 transactionHash
        );

    function getTemplateDetails(bytes32 templateId)
        external
        view
        returns (string memory legalContractUri, string[] memory globalFields, string[] memory signerFields);

    function getSignerValues(bytes32 contractId, address signer) external view returns (string[] memory signerValues);

    function getAgreementsForParty(address party) external view returns (bytes32[] memory);

    function getContractJson(bytes32 contractId) external view returns (string memory);

    function getContractTransactionHash(bytes32 contractId) external view returns (bytes32);
}
