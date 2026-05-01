// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library DeploymentConstants {
    error UnsupportedChain(uint256 chainId);

    uint256 internal constant ETH = 1;
    uint256 internal constant BASE = 8453;

    uint256 internal constant ETH_SEPOLIA = 11155111;
    uint256 internal constant BASE_SEPOLIA = 84532;

    struct CoreDeployment {
        address metalexSafe;
        address auth;
        address cyberCorpFactory;
        address issuanceManagerFactory;
        address cyberCorpSingleFactory;
        address dealManagerFactory;
        address roundManagerFactory;
        address cyberAgreementRegistry;
        address uriBuilder;
        address lexchexAuth;
        address lexchex;
        address lexchexMinter;
        address lexchexCondition;
    }

    struct UmiaDeployment {
        address parentCoFactory;
        bytes32 segCoTemplateId;
        bytes32 boardConsentTemplateId;
    }

    struct Deps {
        address usdc;
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
                    metalexSafe: 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C,
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xbbD386D237f3b407E6511A52488850b1Da0cCad2, // different from all other chains
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34, // different from all other chains
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2,
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42
                });
        }
        else {
            return
                CoreDeployment({
                    metalexSafe: 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C,
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xD353972D7955F421d94d0eA8c42c88c417F7155A, // except base-sepolia
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9, // except base-sepolia
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2,
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42
                });
        }
    }

    function umia(uint256 chainId)
        internal
        pure
        returns (UmiaDeployment memory deployment)
    {
        if (chainId == ETH) {
            return UmiaDeployment({
                parentCoFactory: 0x5c6D411600774c8fE1Aa805d78F03202d7FCD47F,
                segCoTemplateId: 0xd9e0fbb89f8e4e973f05d6b40b6a41e3a9af845b604e9acc7aa4f2a0c37009d8,
                boardConsentTemplateId: 0x93ac1365e39b1d8237c84cf969b752ffbb717f7d8144eb47562b4060bcd91c30
            });
        } else if (chainId == ETH_SEPOLIA) {
            return UmiaDeployment({
                parentCoFactory: 0x0c6Fc81BEd7f91f7a3b3594CCc66484893634Bf9,
                segCoTemplateId: 0xb6da5c8e53767592c0eeb4c5c0d77eae7e1e2e795190e7237d837b3fbc98ed75,
                boardConsentTemplateId: 0xc02175e98621a996529fb751b30e0b7a8344ece3b00f46a29c1e904c9da87a46
            });
        } else if (chainId == BASE_SEPOLIA) {
            return UmiaDeployment({
                parentCoFactory: 0xC1304898FAfF45cA2B07C0f4E10B77843eD5a47B,
                segCoTemplateId: 0xb6da5c8e53767592c0eeb4c5c0d77eae7e1e2e795190e7237d837b3fbc98ed75,
                boardConsentTemplateId: 0xc02175e98621a996529fb751b30e0b7a8344ece3b00f46a29c1e904c9da87a46
            });
        } else {
            revert UnsupportedChain(chainId);
        }
    }

    function deps(uint256 chainId)
        internal
        pure
        returns (Deps memory deps)
    {
        if (chainId == ETH) {
            return Deps({
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
            });
        } else if (chainId == BASE) {
            return Deps({
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
            });
        } else if (chainId == ETH_SEPOLIA) {
            return Deps({
                usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
            });
        } else if (chainId == BASE_SEPOLIA) {
            return Deps({
                usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
            });
        } else {
            revert UnsupportedChain(chainId);
        }
    }
}
