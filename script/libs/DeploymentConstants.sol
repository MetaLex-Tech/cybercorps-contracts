// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library DeploymentConstants {
    error UnsupportedChain(uint256 chainId);

    uint256 internal constant ETH_SEPOLIA = 11155111;
    uint256 internal constant BASE_SEPOLIA = 84532;

    struct CoreDeployment {
        address auth;
        address cyberCorpFactory;
        address issuanceManagerFactory;
        address cyberCorpSingleFactory;
        address dealManagerFactory;
        address roundManagerFactory;
        address cyberAgreementRegistry;
        address uriBuilder;
        address lexchexAuth;
    }

    /// @notice Latest CyberCorps V2 deployment constants.
    /// @dev Source: script/res/deployment-addresses.md
    function coreV2(uint256 chainId)
        internal
        pure
        returns (CoreDeployment memory deployment)
    {
        if (chainId == BASE_SEPOLIA) {
            return
                CoreDeployment({
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xbbD386D237f3b407E6511A52488850b1Da0cCad2,
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34,
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2
                });
        }
        else {
            return
                CoreDeployment({
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xD353972D7955F421d94d0eA8c42c88c417F7155A,
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9,
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2
                });
        }
    }
}
