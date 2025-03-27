pragma solidity 0.8.28;

import "./interfaces/IIssuanceManagerFactory.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementFactory.sol";
import "./interfaces/ICyberDealRegistry.sol";
import "./CyberCorpConstants.sol";

contract CyberCorpFactory {
    error InvalidSalt();
    error DeploymentFailed();

    address public registryAddress;
    address public cyberCertPrinterImplementation;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public cyberAgreementFactory;
    address public dealManagerFactory;
    address public stable = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;//base main net 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    event CyberCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager
    );

    event AgreementDeployed(
        address indexed agreementFactory,
        address indexed agreement,
        address indexed lexscrow,
        bytes32 salt
    );

    constructor(address _registryAddress, address _cyberCertPrinterImplementation, address _issuanceManagerFactory, address _cyberCorpSingleFactory, address _dealManagerFactory) {
        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
    }

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend,
        address _companyPayable,
        address _officer
    ) public returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, authBytecode);

        // Initialize BorgAuth
        BorgAuth(authAddress).initialize();
        BorgAuth(authAddress).updateRole(msg.sender, 200);

        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory).deployIssuanceManager(salt);

        cyberCorpAddress = ICyberCorpSingleFactory(cyberCorpSingleFactory).deployCyberCorpSingle(salt, authAddress, companyName, companyJurisdiction, companyContactDetails, defaultDisputeResolution, defaultLegend, issuanceManagerAddress, _companyPayable, _officer);

        //deploy deal manager
        dealManagerAddress = IDealManagerFactory(dealManagerFactory).deployDealManager();
        // Initialize IssuanceManager
        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation
        );

        //update role for issuance manager
        IDealManager(dealManagerAddress).initialize(authAddress, cyberCorpAddress, registryAddress, issuanceManagerAddress);
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress
        );
    }

    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        address _companyPayable,
        string memory certName,
        string memory certSymbol,
        string memory certificateUri,
        SecurityClass securityClass,
        SecuritySeries securitySeries,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[] memory _partyValues,
        bytes memory signature,
        CertificateDetails memory _details
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress, address certPrinterAddress, bytes32 id) {

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        (cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress) = deployCyberCorp(
            corpSalt,
            companyName,
            "",
            "",
            "",
            "",
            _companyPayable,
            msg.sender
        );

        //append companyname " " and then the certName
        string memory certNameWithCompany = string.concat(companyName, " ", certName);
        ICyberCertPrinter certPrinter = ICyberCertPrinter(IIssuanceManager(issuanceManagerAddress).createCertPrinter("", certNameWithCompany, certSymbol, certificateUri, securityClass, securitySeries));
        certPrinterAddress = address(certPrinter);

        // Create and sign deal
        id = IDealManager(dealManagerAddress).proposeAndSignDeal(
            certPrinterAddress,
            certPrinter.totalSupply(),
            stable,
            _paymentAmount,
            _templateId,
            salt,
            _globalValues,
            _parties,
            _details,
            msg.sender,
            signature,
            _partyValues
        );

    }
}
