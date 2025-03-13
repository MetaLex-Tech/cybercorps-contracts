pragma solidity 0.8.28;

import "./CyberCorp.sol";
import "./IssuanceManager.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";
import "../dependencies/cyberCorpTripler/src/DoubleTokenLexscrowRegistry.sol";
import "../dependencies/cyberCorpTripler/src/ERC721LexscrowFactory.sol";

contract CyberCorpFactory {
    error InvalidSalt();
    error DeploymentFailed();

    address public registryAddress;
    address public cyberCertPrinterImplementation;
    address public stable = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    event CyberCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address agreementFactory,
        bytes32 salt
    );

    event AgreementDeployed(
        address indexed agreementFactory,
        address indexed agreement,
        address indexed lexscrow,
        bytes32 salt
    );

    constructor(address _registryAddress, address _cyberCertPrinterImplementation) {
        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
    }

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend
    ) public returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, authBytecode);
        
        // Initialize BorgAuth
        BorgAuth(authAddress).initialize();

        // Deploy IssuanceManager with CREATE2
        bytes memory issuanceManagerBytecode = type(IssuanceManager).creationCode;
        bytes32 issuanceManagerSalt = keccak256(abi.encodePacked("issuanceManager", salt));
        issuanceManagerAddress = Create2.deploy(0, issuanceManagerSalt, issuanceManagerBytecode);

        // Deploy CyberCorp with CREATE2
        bytes memory cyberCorpBytecode = abi.encodePacked(
            type(CyberCorp).creationCode,
            abi.encode(
                authAddress,
                companyName,
                companyJurisdiction,
                companyContactDetails,
                defaultDisputeResolution,
                defaultLegend
            )
        );
        bytes32 cyberCorpSalt = keccak256(abi.encodePacked("cyberCorp", salt));
        cyberCorpAddress = Create2.deploy(0, cyberCorpSalt, cyberCorpBytecode);

        // Deploy AgreementFactory with CREATE2
        bytes memory agreementFactoryBytecode = abi.encodePacked(
            type(AgreementV2Factory).creationCode,
            abi.encode(registryAddress),
            abi.encode(issuanceManagerAddress)
        );
        bytes32 agreementFactorySalt = keccak256(abi.encodePacked("agreementFactory", salt));
        agreementFactoryAddress = Create2.deploy(0, agreementFactorySalt, agreementFactoryBytecode);

        DoubleTokenLexscrowRegistry(registryAddress).enableFactory(agreementFactoryAddress);
        // Initialize IssuanceManager
        IssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation
        );
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        // Initialize CyberCorp
        CyberCorp(cyberCorpAddress).initialize(issuanceManagerAddress, authAddress);

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            agreementFactoryAddress,
            salt
        );

        return (cyberCorpAddress, authAddress, issuanceManagerAddress, agreementFactoryAddress);
    }

    function computeAddresses(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend
    ) external view returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress) {
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.computeAddress(
            authSalt,
            keccak256(type(BorgAuth).creationCode),
            address(this)
        );

        bytes32 issuanceManagerSalt = keccak256(abi.encodePacked("issuanceManager", salt));
        issuanceManagerAddress = Create2.computeAddress(
            issuanceManagerSalt,
            keccak256(type(IssuanceManager).creationCode),
            address(this)
        );

        bytes32 cyberCorpSalt = keccak256(abi.encodePacked("cyberCorp", salt));
        bytes memory cyberCorpBytecode = abi.encodePacked(
            type(CyberCorp).creationCode,
            abi.encode(
                authAddress,
                companyName,
                companyJurisdiction,
                companyContactDetails,
                defaultDisputeResolution,
                defaultLegend
            )
        );
        cyberCorpAddress = Create2.computeAddress(
            cyberCorpSalt,
            keccak256(cyberCorpBytecode),
            address(this)
        );

        bytes32 agreementFactorySalt = keccak256(abi.encodePacked("agreementFactory", salt));
        bytes memory agreementFactoryBytecode = abi.encodePacked(
            type(AgreementV2Factory).creationCode,
            abi.encode(registryAddress)
        );
        agreementFactoryAddress = Create2.computeAddress(
            agreementFactorySalt,
            keccak256(agreementFactoryBytecode),
            address(this)
        );

        return (cyberCorpAddress, authAddress, issuanceManagerAddress, agreementFactoryAddress);
    
    
    }

    function acceptRegistryAdmin() external {
        DoubleTokenLexscrowRegistry(registryAddress).acceptAdminRole();
    }

    function deployCyberCorpAndCreateOffer(
        bytes32 salt,
        string memory companyName,
        string memory certName,
        string memory certSymbol,
        CertificateDetails memory _details
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress, address certPrinterAddress) {

        (cyberCorpAddress, authAddress, issuanceManagerAddress, agreementFactoryAddress) = deployCyberCorp(
            salt,
            companyName,
            "",
            "",
            "",
            ""
        );

        ICyberCertPrinter certPrinter = ICyberCertPrinter(IIssuanceManager(issuanceManagerAddress).createCertPrinter(cyberCertPrinterImplementation, "", certName, certSymbol));
        certPrinterAddress = address(certPrinter);  

        NFTAsset memory _nftAsset = NFTAsset({
            tokenContract: certPrinterAddress,
            tokenId: 1
        });

        LockedAsset memory _lockedAsset = LockedAsset({
            tokenContract: stable,
            totalAmount: 1
        });


        Party memory _partyA = Party({
            partyBlockchainAddy: address(msg.sender),
            partyName: companyName,
            contactDetails: ""
        });

        Party memory _partyB = Party({
            partyBlockchainAddy: address(0x0),
            partyName: "",
            contactDetails: ""
        });


        AgreementDetailsV2 memory _agreementDetails = AgreementDetailsV2({
            partyA: _partyA,
            partyB: _partyB,
            lockedAssetPartyA: _nftAsset,
            lockedAssetPartyB: _lockedAsset,
            expirationTime: block.timestamp + 1000000000000000000000000,
            secret: bytes32(0),
            conditions: new Condition[](0),
            otherConditions: ""
        });
        agreementFactoryAddress = address(new AgreementV2Factory(registryAddress, issuanceManagerAddress));

        address auth = address(IssuanceManager(issuanceManagerAddress).AUTH());
        BorgAuth(auth).updateRole(agreementFactoryAddress, 99);
        ERC721LexscrowFactory lexscrowFactory = new ERC721LexscrowFactory();

        (address _agreementAddress, address _lexscrow) = AgreementV2Factory(agreementFactoryAddress).deployLexscrowAndProposeOpenOfferERC721LexscrowAgreement(_agreementDetails, address(lexscrowFactory), _details);

        emit AgreementDeployed(agreementFactoryAddress, _agreementAddress, _lexscrow, salt);

    }
} 