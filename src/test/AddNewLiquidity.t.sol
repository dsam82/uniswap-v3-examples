// SPDX-License-Identifier: MIT
pragma solidity <0.8.0;
pragma abicoder v2;

import "./utils/SqrtMath.sol";
import {Address} from "./utils/Address.sol";
import {MockToken} from "./utils/MockToken.sol";
import {UniswapV3Recipient} from "./utils/UniswapV3Recipient.sol";

import "@v3-core/libraries/Position.sol";
import {Test} from "@std/Test.sol";
import {console} from "@std/console.sol";
import {IUniswapV3Factory} from "@v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@v3-periphery/libraries/LiquidityAmounts.sol";
import {IQuoterV2} from "@v3-periphery/interfaces/IQuoterV2.sol";
import {QuoterV2} from "@v3-periphery/lens/QuoterV2.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract TestUniV3Pool is Test {
    using TickMath for int24;

    IUniswapV3Factory public factory = IUniswapV3Factory(Address.UNIV3_FACTORY);
    IUniswapV3Pool public pool;
    IQuoterV2 public quoter;
    UniswapV3Recipient public recipient;

    MockToken public tokenA;
    MockToken public tokenB;

    uint24 public constant fee = 3000;
    int24 public tickSpacing;

    function setUp() public {
        tokenA = new MockToken("MockTokenA", "MTA");
        tokenB = new MockToken("MockTokenB", "MTB");

        // sort tokens
        (tokenA, tokenB) = (address(tokenA) < address(tokenB))
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        // create pool
        pool = IUniswapV3Pool(
            factory.createPool(address(tokenA), address(tokenB), fee)
        );
        vm.label(address(pool), "POOL");

        quoter = new QuoterV2(address(factory), Address.WETH);
        vm.label(address(quoter), "QUOTER");

        // setup recipient and mint tokens
        recipient = new UniswapV3Recipient(
            address(pool),
            address(tokenA),
            address(tokenB)
        );
        tokenA.mint(address(recipient), 10e18);
        tokenB.mint(address(recipient), 10000e18);

        // initialize pool
        uint160 sqrtPriceX96 = encodePriceSqrtX96(1, 1000);
        pool.initialize(sqrtPriceX96);

        tickSpacing = pool.tickSpacing();
    }

    function setupMint() internal {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
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
        // find current price and tick
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // round off tick
        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        // find price from tick
        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // calculate liquidity from price
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        assertEq(
            tokenA.balanceOf(address(pool)),
            10e18 - tokenA.balanceOf(address(recipient))
        );
        assertEq(
            tokenB.balanceOf(address(pool)),
            10000e18 - tokenB.balanceOf(address(recipient))
        );
    }

    function testMintPriceLTTickLower() public {
        // find current price and tick
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // round off tick
        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick + (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 2);

        // find price from tick
        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // calculate liquidity from price
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        assertEq(
            tokenA.balanceOf(address(pool)),
            10e18 - tokenA.balanceOf(address(recipient))
        );

        // all liquiidty is in tokenA, as the lower tick is not in the range of the pool
        assertEq(tokenB.balanceOf(address(pool)), 0);
    }

    function testMintPriceGTTickUpper() public {
        // find current price and tick
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // round off tick
        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 2);
        int24 tickUpper = currentTick - (tickSpacing << 1);

        // find price from tick
        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // calculate liquidity from price
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            10e18,
            10000e18
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        // all liquiidty is in tokenB, as the upper tick is not in the range of the pool
        assertEq(tokenA.balanceOf(address(pool)), 0);
        assertEq(
            tokenB.balanceOf(address(pool)),
            10000e18 - tokenB.balanceOf(address(recipient))
        );
    }

    function testMintTwiceSameTick() public {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount0 = 10e18 >> 1;
        uint256 amount1 = 10000e18 >> 1;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            amount0,
            amount1
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        assertEq(
            tokenA.balanceOf(address(pool)),
            10e18 - tokenA.balanceOf(address(recipient))
        );
        assertEq(
            tokenB.balanceOf(address(pool)),
            10000e18 - tokenB.balanceOf(address(recipient))
        );
    }

    function testMintTwiceDifferentTick() public {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount0 = 10e18 >> 1;
        uint256 amount1 = 10000e18 >> 1;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            amount0,
            amount1
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        tickLower = tickUpper;
        tickUpper = tickUpper + (tickSpacing << 1);

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        assertEq(
            tokenA.balanceOf(address(pool)),
            10e18 - tokenA.balanceOf(address(recipient))
        );
        assertEq(
            tokenB.balanceOf(address(pool)),
            10000e18 - tokenB.balanceOf(address(recipient))
        );
    }

    function testBurn() public {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // round off tick
        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount0 = 10e18;
        uint256 amount1 = 10000e18;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            amount0,
            amount1
        );

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            liquidity
        );

        vm.prank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        vm.prank(address(recipient));
        pool.burn(tickLower, tickUpper, liquidity);

        (, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(
            keccak256(
                abi.encodePacked(address(recipient), tickLower, tickUpper)
            )
        );
        assertEq(tokensOwed0, amount0);
        assertEq(tokensOwed1, amount1);

        assertEq(
            tokenA.balanceOf(address(pool)),
            10e18 - tokenA.balanceOf(address(recipient))
        );
        assertEq(
            tokenB.balanceOf(address(pool)),
            10000e18 - tokenB.balanceOf(address(recipient))
        );
    }

    function testBurnAndCollect() public {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();

        // round off tick
        currentTick = currentTick - (currentTick % tickSpacing);

        int24 tickLower = currentTick - (tickSpacing << 1);
        int24 tickUpper = currentTick + (tickSpacing << 1);

        uint160 priceSqrtAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceSqrtBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 amount0 = 10e18;
        uint256 amount1 = 10000e18;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            amount0,
            amount1
        );

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            priceSqrtAX96,
            priceSqrtBX96,
            liquidity
        );

        vm.startPrank(address(recipient));
        pool.mint(address(recipient), tickLower, tickUpper, liquidity, hex"");

        pool.burn(tickLower, tickUpper, liquidity);

        pool.collect(
            address(recipient),
            tickLower,
            tickUpper,
            uint128(amount0),
            uint128(amount1)
        );

        assertEq(tokenA.balanceOf(address(pool)), 1);
        assertEq(tokenB.balanceOf(address(pool)), 1);
    }

    function testSwapZeroToOne() public {
        setupMint();

        tokenA.mint(address(recipient), 1e18);

        (uint256 amountOut, , , ) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(tokenA),
                tokenOut: address(tokenB),
                amountIn: 2e18,
                fee: fee,
                sqrtPriceLimitX96: 1e18
            })
        );

        vm.prank(address(recipient));
        (int256 amount0, int256 amount1) = pool.swap(
            address(recipient),
            true,
            int256(amountOut),
            2e18,
            hex""
        );

        assertGt(amount0, 0);
        assertLt(amount1, 0);
    }

    function testSwapOneToZero() public {
        setupMint();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        tokenB.mint(address(recipient), 1e18);

        (uint256 amountOut, , , ) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(tokenB),
                tokenOut: address(tokenA),
                amountIn: 2000e18,
                fee: fee,
                sqrtPriceLimitX96: sqrtPriceX96 << 1
            })
        );

        vm.prank(address(recipient));
        (int256 amount0, int256 amount1) = pool.swap(
            address(recipient),
            false,
            int256(amountOut),
            sqrtPriceX96 << 1,
            hex""
        );

        assertLt(amount0, 0);
        assertGt(amount1, 0);
    }
}
