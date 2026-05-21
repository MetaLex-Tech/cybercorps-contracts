pragma solidity 0.8.28;

import "../../libs/auth.sol";

interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    function take(address currency, address to, uint256 amount) external;
}

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

type BalanceDelta is int256;

type BeforeSwapDelta is int256;

struct HookPermissions {
    bool beforeInitialize;
    bool afterInitialize;
    bool beforeAddLiquidity;
    bool afterAddLiquidity;
    bool beforeRemoveLiquidity;
    bool afterRemoveLiquidity;
    bool beforeSwap;
    bool afterSwap;
    bool beforeDonate;
    bool afterDonate;
    bool beforeSwapReturnDelta;
    bool afterSwapReturnDelta;
    bool beforeAddLiquidityReturnDelta;
    bool afterAddLiquidityReturnDelta;
}

interface IHooks {
    function getHookPermissions() external pure returns (HookPermissions memory);

    function beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24);

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128);

    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (bytes4);
}

contract MetalexIssuerFeeHook is IHooks, BorgAuthACL {
    uint24 public constant BPS_DENOMINATOR = 10_000;

    IPoolManager public poolManager;

    struct PoolFeeConfig {
        address metalexRecipient;
        address issuerRecipient;
        uint24 metalexFeeBps;
        uint24 issuerFeeBps;
        bool enabled;
    }

    mapping(bytes32 => PoolFeeConfig) public poolFeeConfig;

    error ZeroAddress();
    error FeeTooHigh();
    error UnauthorizedPoolManager();

    event PoolConfigUpdated(
        bytes32 indexed poolId,
        address metalexRecipient,
        address issuerRecipient,
        uint24 metalexFeeBps,
        uint24 issuerFeeBps,
        bool enabled
    );

    function initialize(
        address _auth,
        address _poolManager
    ) external initializer {
        __BorgAuthACL_init(_auth);
        _setPoolManager(_poolManager);
    }

    function setPoolConfig(
        PoolKey calldata key,
        address _metalexRecipient,
        address _issuerRecipient,
        uint24 _metalexFeeBps,
        uint24 _issuerFeeBps,
        bool _enabled
    ) external onlyAdmin {
        bytes32 poolId = _poolId(key);
        if (_enabled && (_metalexRecipient == address(0) || _issuerRecipient == address(0))) {
            revert ZeroAddress();
        }
        if (uint256(_metalexFeeBps) + uint256(_issuerFeeBps) > BPS_DENOMINATOR) {
            revert FeeTooHigh();
        }

        poolFeeConfig[poolId] = PoolFeeConfig({
            metalexRecipient: _metalexRecipient,
            issuerRecipient: _issuerRecipient,
            metalexFeeBps: _metalexFeeBps,
            issuerFeeBps: _issuerFeeBps,
            enabled: _enabled
        });

        emit PoolConfigUpdated(
            poolId,
            _metalexRecipient,
            _issuerRecipient,
            _metalexFeeBps,
            _issuerFeeBps,
            _enabled
        );
    }

    function _setPoolManager(address _poolManager) internal {
        if (_poolManager == address(0)) {
            revert ZeroAddress();
        }
        poolManager = IPoolManager(_poolManager);
    }

    function getHookPermissions() external pure returns (HookPermissions memory permissions) {
        permissions.beforeSwap = true;
        permissions.beforeSwapReturnDelta = true;
    }

    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.afterAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.afterRemoveLiquidity.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        if (msg.sender != address(poolManager)) {
            revert UnauthorizedPoolManager();
        }

        PoolFeeConfig memory config = poolFeeConfig[_poolId(key)];
        // only exact-input swaps (amountSpecified < 0) have a known input amount at this point
        if (!config.enabled || params.amountSpecified >= 0) {
            return (MetalexIssuerFeeHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
        }

        uint256 inputAmount = uint256(-params.amountSpecified);
        uint256 metalexFee = (inputAmount * config.metalexFeeBps) / BPS_DENOMINATOR;
        uint256 issuerFee = (inputAmount * config.issuerFeeBps) / BPS_DENOMINATOR;
        address currencyIn = params.zeroForOne ? key.currency0 : key.currency1;

        if (metalexFee > 0) {
            poolManager.take(currencyIn, config.metalexRecipient, metalexFee);
        }
        if (issuerFee > 0) {
            poolManager.take(currencyIn, config.issuerRecipient, issuerFee);
        }

        // positive specifiedDelta credits the hook's input-token debt, settling the take() calls above
        uint256 totalFee = metalexFee + issuerFee;
        BeforeSwapDelta delta = BeforeSwapDelta.wrap(int256(uint256(uint128(totalFee)) << 128));
        return (MetalexIssuerFeeHook.beforeSwap.selector, delta, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, int128) {
        return (MetalexIssuerFeeHook.afterSwap.selector, 0);
    }

    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.beforeDonate.selector;
    }

    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return MetalexIssuerFeeHook.afterDonate.selector;
    }

    function _poolId(PoolKey calldata key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

}
