pragma solidity 0.8.28;

import "./CyberCorp.sol";
import "./IssuanceManager.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";

contract CyberCorpFactory {
    error InvalidSalt();
    error DeploymentFailed();

    event CyberCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address agreementFactory,
        bytes32 salt
    );

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend,
        address cyberCertPrinterImplementation,
        address registryAddress
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address agreementFactoryAddress) {
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
            abi.encode(registryAddress)
        );
        bytes32 agreementFactorySalt = keccak256(abi.encodePacked("agreementFactory", salt));
        agreementFactoryAddress = Create2.deploy(0, agreementFactorySalt, agreementFactoryBytecode);

        // Initialize IssuanceManager
        IssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation
        );

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
        string memory defaultLegend,
        address registryAddress
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
} 