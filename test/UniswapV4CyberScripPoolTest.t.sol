// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

import "../src/CyberScrip.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/libs/auth.sol";
import "../src/hooks/uniswap/MetalexIssuerFeeHook.sol";
import "../test/mock/TestableCyberScrip.sol";

interface IPoolManagerV4 {
    function unlock(bytes calldata data) external returns (bytes memory);
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24);
    function modifyLiquidity(
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);
    function swap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta swapDelta);
    function sync(address currency) external;
    function settle() external payable returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract HookCreate2Deployer {
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "create2 failed");
    }
}

contract UniswapV4CyberScripPoolForkTest is Test, IUnlockCallback {

    address internal constant BASE_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    uint16 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG  = 1 << 2;
    uint16 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
    uint16 internal constant AFTER_SWAP_FLAG                = 1 << 6;
    uint16 internal constant BEFORE_SWAP_FLAG               = 1 << 7;
    uint16 internal constant REQUIRED_HOOK_FLAGS =
        BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG |
        BEFORE_SWAP_RETURNS_DELTA_FLAG | AFTER_SWAP_RETURNS_DELTA_FLAG; // 0x00CC
    uint24 internal constant POOL_FEE = 3000; // 0.30%
    int24 internal constant TICK_SPACING = 60;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    IPoolManagerV4 internal poolManager;
    TestableCyberScrip internal cyberScrip;
    MetalexIssuerFeeHook internal hook;
    PoolKey internal poolKey;

    address internal metalexRecipient;
    address internal issuerRecipient;

    function setUp() public {
        vm.createSelectFork("base");

        poolManager = IPoolManagerV4(BASE_POOL_MANAGER);

        metalexRecipient = makeAddr("metalexRecipient");
        issuerRecipient = makeAddr("issuerRecipient");

        BorgAuth auth = new BorgAuth(address(this));
        auth.updateRole(address(this), auth.ADMIN_ROLE());

        hook = _deployHook();
        hook.initialize(address(auth), BASE_POOL_MANAGER);

        cyberScrip = _deployCyberScrip(address(auth));

        (address currency0, address currency1) = _sortCurrencies(address(cyberScrip), BASE_USDC);
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(hook)
        });

        hook.setPoolConfig(poolKey, metalexRecipient, issuerRecipient, 100, 100, true);

        cyberScrip.unrestrictedMint(address(this), 5_000_000 ether);
        deal(BASE_USDC, address(this), 5_000_000 * 1e6);
    }

    function test_SellExactInput_CollectsFeeInCyberScrip() public {
        _unlock(UnlockAction.InitializeAndAddLiquidity);
        _unlock(UnlockAction.SwapSellExactInput);

        // 3000 wei CS in, 100 bps fee → 3000 * 100 / 10_000 = 30
        assertEq(IERC20(address(cyberScrip)).balanceOf(metalexRecipient), 30, "metalex fee incorrect");
        assertEq(IERC20(address(cyberScrip)).balanceOf(issuerRecipient),  30, "issuer fee incorrect");
    }

    function test_BuyExactInput_CollectsFeeInUsdc() public {
        _unlock(UnlockAction.InitializeAndAddLiquidity);
        _unlock(UnlockAction.SwapBuyExactInput);

        // 3000 wei USDC in, 100 bps fee → 30
        assertEq(IERC20(BASE_USDC).balanceOf(metalexRecipient), 30, "metalex fee incorrect");
        assertEq(IERC20(BASE_USDC).balanceOf(issuerRecipient),  30, "issuer fee incorrect");
    }

    function test_SellExactOutput_CollectsFeeInCyberScrip() public {
        _unlock(UnlockAction.InitializeAndAddLiquidity);

        uint256 csBefore = IERC20(address(cyberScrip)).balanceOf(address(this));
        _unlock(UnlockAction.SwapSellExactOutput);
        uint256 metalexFee = IERC20(address(cyberScrip)).balanceOf(metalexRecipient);
        uint256 issuerFee  = IERC20(address(cyberScrip)).balanceOf(issuerRecipient);
        uint256 poolInput  = csBefore - IERC20(address(cyberScrip)).balanceOf(address(this)) - metalexFee - issuerFee;

        assertEq(metalexFee, poolInput * 100 / 10_000, "metalex fee incorrect");
        assertEq(issuerFee,  poolInput * 100 / 10_000, "issuer fee incorrect");
    }

    function test_BuyExactOutput_CollectsFeeInUsdc() public {
        _unlock(UnlockAction.InitializeAndAddLiquidity);

        uint256 usdcBefore = IERC20(BASE_USDC).balanceOf(address(this));
        _unlock(UnlockAction.SwapBuyExactOutput);
        uint256 metalexFee = IERC20(BASE_USDC).balanceOf(metalexRecipient);
        uint256 issuerFee  = IERC20(BASE_USDC).balanceOf(issuerRecipient);
        uint256 poolInput  = usdcBefore - IERC20(BASE_USDC).balanceOf(address(this)) - metalexFee - issuerFee;

        assertEq(metalexFee, poolInput * 100 / 10_000, "metalex fee incorrect");
        assertEq(issuerFee,  poolInput * 100 / 10_000, "issuer fee incorrect");
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "only pool manager");

        UnlockAction action = abi.decode(data, (UnlockAction));
        if (action == UnlockAction.InitializeAndAddLiquidity) {
            _initializeAndAddLiquidity();
            return "";
        }
        if (action == UnlockAction.SwapSellExactInput) {
            _swapSellExactInput();
            return "";
        }
        if (action == UnlockAction.SwapBuyExactInput) {
            _swapBuyExactInput();
            return "";
        }
        if (action == UnlockAction.SwapSellExactOutput) {
            _swapSellExactOutput();
            return "";
        }
        if (action == UnlockAction.SwapBuyExactOutput) {
            _swapBuyExactOutput();
            return "";
        }

        revert("unknown action");
    }

    enum UnlockAction {
        InitializeAndAddLiquidity,
        SwapSellExactInput,
        SwapBuyExactInput,
        SwapSellExactOutput,
        SwapBuyExactOutput
    }

    function _unlock(UnlockAction action) internal {
        poolManager.unlock(abi.encode(action));
    }

    function _initializeAndAddLiquidity() internal {
        poolManager.initialize(poolKey, uint160(1 << 96));

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: int256(1_000_000),
            salt: bytes32(0)
        });

        (BalanceDelta callerDelta,) = poolManager.modifyLiquidity(poolKey, params, "");
        _settleDelta(callerDelta);
    }

    function _swapSellExactInput() internal {
        bool zeroForOne = address(cyberScrip) < BASE_USDC;
        _settleDelta(poolManager.swap(poolKey, IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -3000,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        }), ""));
    }

    function _swapBuyExactInput() internal {
        bool zeroForOne = BASE_USDC < address(cyberScrip);
        _settleDelta(poolManager.swap(poolKey, IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -3000,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        }), ""));
    }

    function _swapSellExactOutput() internal {
        bool zeroForOne = address(cyberScrip) < BASE_USDC;
        _settleDelta(poolManager.swap(poolKey, IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: 3000,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        }), ""));
    }

    function _swapBuyExactOutput() internal {
        bool zeroForOne = BASE_USDC < address(cyberScrip);
        _settleDelta(poolManager.swap(poolKey, IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: 3000,
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        }), ""));
    }

    function _settleDelta(BalanceDelta delta) internal {
        int128 amount0 = _amount0(delta);
        if (amount0 < 0) {
            _pay(poolKey.currency0, uint256(uint128(-amount0)));
        } else if (amount0 > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(uint128(amount0)));
        }

        int128 amount1 = _amount1(delta);
        if (amount1 < 0) {
            _pay(poolKey.currency1, uint256(uint128(-amount1)));
        } else if (amount1 > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(uint128(amount1)));
        }
    }

    function _pay(address currency, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        poolManager.sync(currency);
        IERC20(currency).transfer(address(poolManager), amount);
        poolManager.settle();
    }

    function _sortCurrencies(address tokenA, address tokenB) internal pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _deployCyberScrip(address auth) internal returns (TestableCyberScrip) {
        ITransferRestrictionHook[] memory hooks = new ITransferRestrictionHook[](0);
        return TestableCyberScrip(address(
            new ERC1967Proxy(
                address(new TestableCyberScrip()),
                abi.encodeWithSelector(
                    CyberScrip.initialize.selector,
                    auth,
                    makeAddr("certPrinter"),
                    makeAddr("issuanceManager"),
                    "CyberScrip",
                    "CS",
                    hooks,
                    true,
                    true,
                    true
                )
            )
        ));
    }

    function _deployHook() internal returns (MetalexIssuerFeeHook) {
        HookCreate2Deployer deployer = new HookCreate2Deployer();
        bytes memory creationCode = type(MetalexIssuerFeeHook).creationCode;
        bytes32 initCodeHash = keccak256(creationCode);

        for (uint256 i = 0; i < 1_000_000; i++) {
            bytes32 salt = bytes32(i);
            address predicted = _computeCreate2Address(address(deployer), salt, initCodeHash);
            if (uint16(uint160(predicted)) == REQUIRED_HOOK_FLAGS) {
                address hookAddr = deployer.deploy(salt, creationCode);
                require(hookAddr == predicted, "hook addr mismatch");
                return MetalexIssuerFeeHook(hookAddr);
            }
        }

        revert("hook address not found");
    }

    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        // Use assembly to reuse scratch space on every iteration — avoids advancing
        // the free memory pointer 200k times and hitting MemoryOOG in the mining loop.
        bytes32 hash;
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 1), shl(96, deployer))
            mstore(add(ptr, 21), salt)
            mstore(add(ptr, 53), initCodeHash)
            hash := keccak256(ptr, 85)
        }
        return address(uint160(uint256(hash)));
    }

    function _amount0(BalanceDelta delta) internal pure returns (int128) {
        return int128(int256(BalanceDelta.unwrap(delta) >> 128));
    }

    function _amount1(BalanceDelta delta) internal pure returns (int128) {
        return int128(int256(BalanceDelta.unwrap(delta)));
    }
}
