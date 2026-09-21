// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library DeploymentConstants {
    error UnsupportedChain(uint256 chainId);

    uint256 internal constant ETH = 1;
    uint256 internal constant BASE = 8453;
    uint256 internal constant ARBITRUM = 42161;

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
        address lexchexBadgeAuth;
        address lexchex;
        address lexchexBadge;
        address lexchexMinter;
        address lexchexCondition;
        address zkpassportCondition;
    }

    struct ExtensionDeployment {
        address safeExtension;
        address safeExtensionV3;
        address aceSafeExtension;
        address aceSafeExtensionV3;
        address saftExtension;
        address saftExtensionV2;
        address saftExtensionV3;
        address safteExtension;
        address ethosSafteExtension;
        address safteExtensionV2;
        address safteExtensionV3;
        address tokenWarrantExtension;
        address tokenWarrantExtensionV2;
        address tokenWarrantExtensionV3;
        address shareExtension;
        address shareExtensionV3;
        address fundInterestExtensionV3;
    }

    struct SecondaryConditionDeployment {
        address eligibility;
        address usStateOfResidence;
        address legionSoulbound;
        address holderCap;
        address cfius;
        address section4a7Disclosure;
        address rule144Disclosure;
        address holdingPeriod;
        address legalOpinion;
        address regSDistributionCompliance;
        address gpLpApproval;
        address accreditedInvestor;
        address qualifiedPurchaser;
        address qualifiedInstitutionalBuyer;
        address nonUsPerson;
        address spvWhitelist;
        address syndicate;
        address killSwitch;
        address timeSettlementPeriod;
    }

    struct UmiaDeployment {
        address parentCoFactory;
        bytes32 segCoTemplateId;
        bytes32 boardConsentTemplateId;
    }

    struct PumpDeployment {
        address pumpCorpFactory;
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
        if (chainId == ETH_SEPOLIA) {
            return
                CoreDeployment({
                    metalexSafe: 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C,
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xD353972D7955F421d94d0eA8c42c88c417F7155A,
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9,
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2,
                    lexchexBadgeAuth: address(0), // TODO: not yet deployed on this chain
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexBadge: address(0), // TODO: not yet deployed on this chain
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42,
                    zkpassportCondition: 0xd91a24Ac7D2981c6d660EDEe05Aec22eA5B95E95 // difference from production chains
                });
        } else if (chainId == BASE_SEPOLIA) {
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
                    lexchexBadgeAuth: 0x197333Fc7A828e623fbfcF88eCdc976136F0cf1d,
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexBadge: 0x114664773Ba721a6AA43890d5FDE7939aF37618F,
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42,
                    zkpassportCondition: address(0) // no ZKPassport Verifier available
                });
        } else if (chainId == ARBITRUM) {
            return
                CoreDeployment({
                    metalexSafe: 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C,
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xD353972D7955F421d94d0eA8c42c88c417F7155A,
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9,
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2,
                    lexchexBadgeAuth: address(0), // TODO: not yet deployed on this chain
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexBadge: address(0), // TODO: not yet deployed on this chain
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42,
                    zkpassportCondition: address(0) // TODO: not yet deployed on this chain
                });
        } else {
            return
                CoreDeployment({
                    metalexSafe: 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C,
                    auth: 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01,
                    cyberCorpFactory: 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2,
                    issuanceManagerFactory: 0xD353972D7955F421d94d0eA8c42c88c417F7155A,
                    cyberCorpSingleFactory: 0xBE0D3D13AA07501beAC9b72dE9e9292E66C7A5C4,
                    dealManagerFactory: 0x3982b078f2ac306219c9540Ebc908360a960C251,
                    roundManagerFactory: 0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9,
                    cyberAgreementRegistry: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
                    uriBuilder: 0x5500c095ea7dE6F8a5E15949e24B80604cc670A3,
                    lexchexAuth: 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2,
                    lexchexBadgeAuth: address(0), // TODO: not yet deployed on this chain
                    lexchex: 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62,
                    lexchexBadge: address(0), // TODO: not yet deployed on this chain
                    lexchexMinter: 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960,
                    lexchexCondition: 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42,
                    zkpassportCondition: 0xe71fE689bFAA4939A760EDF7e07f44372a43932A
                });
        }
    }

    /// @notice Certificate extension proxies.
    function extensions(uint256 chainId)
        internal
        pure
        returns (ExtensionDeployment memory deployment)
    {
        if (chainId == BASE) {
            return ExtensionDeployment({
                safeExtension: 0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8,
                safeExtensionV3: address(0), // TODO: not yet deployed on this chain
                aceSafeExtension: 0x6aDaef2B79FD1cbA130c5807B31DE435FEa58EAC,
                aceSafeExtensionV3: address(0), // TODO: not yet deployed on this chain
                saftExtension: 0x109D2A13932bE393011835B308F81ce1992E365B,
                saftExtensionV2: 0x37c2A0e801e569e01f0972186aF4DB01409e92c1,
                saftExtensionV3: address(0), // TODO: not yet deployed on this chain
                safteExtension: 0xE070eDA75695bE3ED4B9ec3719b76Dd36794787C,
                ethosSafteExtension: 0xC23fFF0B06aE5EBea862611F489b1329108ce603, // older SAFTEExtension code, used by the Ethos SAFTE template
                safteExtensionV2: 0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A,
                safteExtensionV3: address(0), // TODO: not yet deployed on this chain
                tokenWarrantExtension: 0xbad0b411C37cfF66e4C0B7764Db2d499eA757bb4,
                tokenWarrantExtensionV2: 0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F,
                tokenWarrantExtensionV3: address(0), // TODO: not yet deployed on this chain
                shareExtension: 0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81,
                shareExtensionV3: address(0), // TODO: not yet deployed on this chain
                fundInterestExtensionV3: address(0) // TODO: not yet deployed on this chain
            });
        } else if (chainId == BASE_SEPOLIA) {
            // The v5 rehearsal deployed the V3 proxies here first. CREATE2 gives the same
            // addresses on the other chains when the V3 script runs there.
            return ExtensionDeployment({
                safeExtension: 0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8,
                safeExtensionV3: 0x740003076c9F16c4a364AE07f3770FB77899299b,
                aceSafeExtension: address(0), // deployed on Base only
                aceSafeExtensionV3: 0x9a8ef946F18C4296e50f8DF0C97b5Cf5d1b5eCD2,
                saftExtension: 0x109D2A13932bE393011835B308F81ce1992E365B,
                saftExtensionV2: 0x37c2A0e801e569e01f0972186aF4DB01409e92c1,
                saftExtensionV3: 0x2Bf1b2f8f6009c5524886243CE4F2EF34e3d4957,
                safteExtension: 0xE070eDA75695bE3ED4B9ec3719b76Dd36794787C,
                ethosSafteExtension: 0xC23fFF0B06aE5EBea862611F489b1329108ce603, // older SAFTEExtension code, used by the Ethos SAFTE template
                safteExtensionV2: 0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A,
                safteExtensionV3: 0xE79C2b4a35b2509b27686D025FB8Fbab2Ca49406,
                tokenWarrantExtension: 0xbad0b411C37cfF66e4C0B7764Db2d499eA757bb4,
                tokenWarrantExtensionV2: 0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F,
                tokenWarrantExtensionV3: 0x3Bdb711517eEbd6A88D9Aa30B141adC43BAB033e,
                shareExtension: 0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81,
                shareExtensionV3: 0xa21C434379CC44bfeD6e3c1342e49951804ec30f,
                fundInterestExtensionV3: 0x2322D1dcC199d7A9Ee60F331cA9D76d244F09a15
            });
        } else if (chainId == ETH || chainId == ETH_SEPOLIA) {
            return ExtensionDeployment({
                safeExtension: 0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8,
                safeExtensionV3: address(0), // TODO: not yet deployed on this chain
                aceSafeExtension: address(0), // deployed on Base only
                aceSafeExtensionV3: address(0), // TODO: not yet deployed on this chain
                saftExtension: 0x109D2A13932bE393011835B308F81ce1992E365B,
                saftExtensionV2: 0x37c2A0e801e569e01f0972186aF4DB01409e92c1,
                saftExtensionV3: address(0), // TODO: not yet deployed on this chain
                safteExtension: 0xE070eDA75695bE3ED4B9ec3719b76Dd36794787C,
                ethosSafteExtension: 0xC23fFF0B06aE5EBea862611F489b1329108ce603, // older SAFTEExtension code, used by the Ethos SAFTE template
                safteExtensionV2: 0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A,
                safteExtensionV3: address(0), // TODO: not yet deployed on this chain
                tokenWarrantExtension: 0xbad0b411C37cfF66e4C0B7764Db2d499eA757bb4,
                tokenWarrantExtensionV2: 0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F,
                tokenWarrantExtensionV3: address(0), // TODO: not yet deployed on this chain
                shareExtension: 0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81,
                shareExtensionV3: address(0), // TODO: not yet deployed on this chain
                fundInterestExtensionV3: address(0) // TODO: not yet deployed on this chain
            });
        } else if (chainId == ARBITRUM) {
            return ExtensionDeployment({
                safeExtension: 0xB2E732d29b89ec36a8Dd23CFD32901056b6579C8,
                safeExtensionV3: address(0), // TODO: not yet deployed on this chain
                aceSafeExtension: address(0), // deployed on Base only
                aceSafeExtensionV3: address(0), // TODO: not yet deployed on this chain
                saftExtension: 0x109D2A13932bE393011835B308F81ce1992E365B,
                saftExtensionV2: 0x37c2A0e801e569e01f0972186aF4DB01409e92c1,
                saftExtensionV3: address(0), // TODO: not yet deployed on this chain
                safteExtension: 0xE070eDA75695bE3ED4B9ec3719b76Dd36794787C,
                ethosSafteExtension: 0xC23fFF0B06aE5EBea862611F489b1329108ce603, // older SAFTEExtension code, used by the Ethos SAFTE template
                safteExtensionV2: 0x4Acdc8618BF2C3d760a357ec11A8290c79f5b41A,
                safteExtensionV3: address(0), // TODO: not yet deployed on this chain
                tokenWarrantExtension: 0xbad0b411C37cfF66e4C0B7764Db2d499eA757bb4,
                tokenWarrantExtensionV2: 0xF5A9984DfcA4D6Dd55D6151F0cd2F4Af9522BC8F,
                tokenWarrantExtensionV3: address(0), // TODO: not yet deployed on this chain
                shareExtension: 0x80e8205b74e3E9882C3C57aA0b36cD465E7A4b81,
                shareExtensionV3: address(0), // TODO: not yet deployed on this chain
                fundInterestExtensionV3: address(0) // TODO: not yet deployed on this chain
            });
        } else {
            revert UnsupportedChain(chainId);
        }
    }

    /// @notice Shared secondary-trading condition singletons.
    /// @dev One instance per chain, configured per SPV. The last six addresses are
    ///      parameterizations of LexChexBadgeKindCondition: one proxy per fact-key.
    function secondaryConditions(uint256 chainId)
        internal
        pure
        returns (SecondaryConditionDeployment memory deployment)
    {
        if (chainId == BASE_SEPOLIA) {
            // deployed with salt "CyberCorpV5-SecondaryConditionsV1.0.0"
            return SecondaryConditionDeployment({
                eligibility: 0x64f43CEfc89279aB6a529eb4C7432cF4b37f3E4B,
                usStateOfResidence: 0x1d4918a83E1F971317f0DD529f088B208Ec24d8C,
                legionSoulbound: 0x3b96b3a385009B4D0C523DfD6D5B4cf5365e2A04,
                holderCap: 0xA8422D5fFE6b697152aEE19d13910302dE1E0576,
                cfius: 0x89Fa72549b5Fadf209377d5348C30bca4c7e0462,
                section4a7Disclosure: 0x42c9e2dadE9669c725D88b78cD0e545FD9e7F723,
                rule144Disclosure: 0x7e30Ef03A0C4C7094D464b714E2480EF30088629,
                holdingPeriod: 0xc5417d7DDE94310Ba334e31517deFED0aa0ED81F,
                legalOpinion: 0xD27317AED94BE6d310eA6B8c4e08360957ff24e3,
                regSDistributionCompliance: 0xe8A325Ba2dF0ba3E08A55B3E3F2bBBBc9354CebB,
                gpLpApproval: 0x4be9Eaff732F4BA3f1Fc6359a2F0858F70637c69,
                accreditedInvestor: 0xedac303CAfdedd92aB6fbECFafFC0a648d9157a1,
                qualifiedPurchaser: 0xE4bcf1c4EA266bbD7F3c58A3aa02c43B5cdc9875,
                qualifiedInstitutionalBuyer: 0x8A617187aF27a98c89548dfFd886EEab0De0936F,
                nonUsPerson: 0xe2AAc5187058a5c97Da7e6D3D6F9D5811124dcBb,
                spvWhitelist: 0x0f2952dcf0279782e6048D2800ee3BeAd9f59f33,
                syndicate: 0x089b4Dba2E3EB49f875c0D7F92A06276B204870f,
                killSwitch: 0x4c3b9Ec3B6e416A64Fde4a17Ea856e1cf2fE0344, // staging admin keys
                timeSettlementPeriod: 0x1E466EcbBC41f6777c4458F8880E62dBf1D08fAd
            });
        } else if (chainId == ETH || chainId == BASE || chainId == ARBITRUM || chainId == ETH_SEPOLIA) {
            // TODO: not yet deployed on these chains. Each zero field makes
            //       `script/deploy-secondary-conditions.s.sol` deploy a new proxy. Record the
            //       address here after the run, so a later run upgrades that proxy instead.
            return deployment;
        } else {
            revert UnsupportedChain(chainId);
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

    /// @notice Pump stack proxies. The pump stack exists on Base only.
    function pump(uint256 chainId)
        internal
        pure
        returns (PumpDeployment memory deployment)
    {
        if (chainId == BASE) {
            return PumpDeployment({
                pumpCorpFactory: 0xe73Ea052c2891cE1668742142a6634Df09c88512
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
