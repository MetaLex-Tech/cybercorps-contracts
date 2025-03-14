pragma solidity 0.8.28;

import "./interfaces/IIssuanceManagerFactory.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/IIssuanceManager.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/ICyberCorp.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementFactory.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/IAgreementFactory.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/IDoubleTokenLexscrowRegistry.sol";
import "../dependencies/cyberCorpTripler/src/interfaces/CyberCorpConstants.sol";

contract CyberCorpFactory {
    error InvalidSalt();
    error DeploymentFailed();

    address public registryAddress;
    address public cyberCertPrinterImplementation;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public cyberAgreementFactory;
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

    constructor(address _registryAddress, address _cyberCertPrinterImplementation, address _issuanceManagerFactory, address _cyberCorpSingleFactory, address _cyberAgreementFactory) {
        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        cyberAgreementFactory = _cyberAgreementFactory;
    }

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend
    ) public returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress, address lexscrowFactory) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, authBytecode);
        
        // Initialize BorgAuth
        BorgAuth(authAddress).initialize();

        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory).deployIssuanceManager(salt);

        cyberCorpAddress = ICyberCorpSingleFactory(cyberCorpSingleFactory).deployCyberCorpSingle(salt, authAddress, companyName, companyJurisdiction, companyContactDetails, defaultDisputeResolution, defaultLegend);

        (agreementFactoryAddress, lexscrowFactory) = ICyberAgreementFactory(cyberAgreementFactory).deployAgreementFactory(registryAddress, issuanceManagerAddress);

        IDoubleTokenLexscrowRegistry(registryAddress).enableFactory(agreementFactoryAddress);

        // Initialize IssuanceManager
        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation
        );
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        // Initialize CyberCorp
        ICyberCorp(cyberCorpAddress).initialize(issuanceManagerAddress, authAddress);

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            agreementFactoryAddress,
            salt
        );

        return (cyberCorpAddress, authAddress, issuanceManagerAddress, agreementFactoryAddress, lexscrowFactory);
    }

    function acceptRegistryAdmin() external {
        IDoubleTokenLexscrowRegistry(registryAddress).acceptAdminRole();
    }

    function deployCyberCorpAndCreateOffer(
        bytes32 salt,
        string memory companyName,
        string memory certName,
        string memory certSymbol,
        SecurityClass securityClass,
        SecuritySeries securitySeries,
        CertificateDetails memory _details
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress, address certPrinterAddress) {

        address lexscrowFactory;
        (cyberCorpAddress, authAddress, issuanceManagerAddress, agreementFactoryAddress, lexscrowFactory) = deployCyberCorp(
            salt,
            companyName,
            "",
            "",
            "",
            ""
        );

        //append companyname " " and then the certName
        string memory certNameWithCompany = string.concat(companyName, " ", certName); 
        ICyberCertPrinter certPrinter = ICyberCertPrinter(IIssuanceManager(issuanceManagerAddress).createCertPrinter(cyberCertPrinterImplementation, "", certNameWithCompany, certSymbol, securityClass, securitySeries));
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

        address auth = address(IIssuanceManager(issuanceManagerAddress).AUTH());
        BorgAuth(auth).updateRole(agreementFactoryAddress, 99);


        (address _agreementAddress, address _lexscrow) = IAgreementFactory(agreementFactoryAddress).deployLexscrowAndProposeSAFEDeal(_agreementDetails, lexscrowFactory, _details);

        emit AgreementDeployed(agreementFactoryAddress, _agreementAddress, _lexscrow, salt);

    }
} 