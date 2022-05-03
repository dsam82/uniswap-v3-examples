pragma solidity <0.8.0;
pragma abicoder v2;

import "./utils/SqrtMath.sol";
import {Address} from "./utils/Address.sol";
import {MockToken} from "./utils/MockToken.sol";
import {UniswapV3Recipient} from "./utils/UniswapV3Recipient.sol";

import {Test} from "@std/Test.sol";
import {console} from "@std/console.sol";

import "@v3-core/libraries/Position.sol";
import {IWETH9} from "@v3-periphery/interfaces/external/IWETH9.sol";
import {IUniswapV3Factory} from "@v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@v3-periphery/libraries/LiquidityAmounts.sol";
import {IQuoterV2} from "@v3-periphery/interfaces/IQuoterV2.sol";
import {QuoterV2} from "@v3-periphery/lens/QuoterV2.sol";

contract ExistingPool is Test {
    using TickMath for int24;

    IUniswapV3Factory public factory = IUniswapV3Factory(Address.UNIV3_FACTORY);
    IUniswapV3Pool public pool;
    UniswapV3Recipient public recipient;

    IWETH9 public weth = IWETH9(Address.WETH);
    MockToken public dai = MockToken(Address.DAI);

    MockToken public tokenA;
    MockToken public tokenB;

    uint24 public constant fee = 3000;
    int24 public tickSpacing;

    function setUp() public {
        (tokenA, tokenB) = (Address.DAI < Address.WETH)
            ? (MockToken(Address.DAI), MockToken(Address.WETH))
            : (MockToken(Address.WETH), MockToken(Address.DAI));

        pool = IUniswapV3Pool(
            factory.getPool(address(tokenA), address(tokenB), fee)
        );
        tickSpacing = pool.tickSpacing();

        // setup recipient and mint tokens
        recipient = new UniswapV3Recipient(
            address(pool),
            address(tokenA),
            address(tokenB)
        );
        startHoax(address(recipient), 100e18);

        weth.deposit{value: 50e18}();
        deal(Address.DAI, address(recipient), 100000e18, true);

        vm.stopPrank();

        vm.label(address(pool), "POOL");
    }

    function setupMint()
        internal
        returns (
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper
        )
    {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        tickLower = currentTick - (tickSpacing << 1);
        tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");
    }

    function testMint() public {
        uint128 liquidityBefore = pool.liquidity();
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 mintLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        vm.prank(address(recipient));
        pool.mint(
            address(recipient),
            tickLower,
            tickUpper,
            mintLiquidity,
            hex""
        );

        uint128 liquidityAfter = pool.liquidity();

        assertEq(
            uint256(liquidityAfter - liquidityBefore),
            uint256(mintLiquidity)
        );
    }

    function testBurn() public {
        uint128 liquidityBefore = pool.liquidity();
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 mintLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                priceSqrtAX96,
                priceSqrtBX96,
                mintLiquidity
            );

        vm.prank(address(recipient));
        pool.mint(
            address(recipient),
            tickLower,
            tickUpper,
            mintLiquidity,
            hex""
        );

        vm.prank(address(recipient));
        pool.burn(tickLower, tickUpper, mintLiquidity);

        (, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(
            keccak256(
                abi.encodePacked(address(recipient), tickLower, tickUpper)
            )
        );
        assertEq(tokensOwed0, amount0);
        assertEq(tokensOwed1, amount1);

        uint128 liquidityAfterBurn = pool.liquidity();

        assertEq(uint256(liquidityAfterBurn - liquidityBefore), 0);
    }
}
