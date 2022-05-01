// SPDX-License-Identifier: MIT
pragma solidity <0.8.0;

import "./utils/SqrtMath.sol";
import {Address} from "./utils/Address.sol";
import {MockToken} from "./utils/MockToken.sol";
import {UniswapV3MintRecipient} from "./utils/UniswapV3MintRecipient.sol";

import {Test} from "@std/Test.sol";
import {IUniswapV3Factory} from "@v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@v3-periphery/libraries/LiquidityAmounts.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract TestUniV3Pool is Test {
    using TickMath for int24;

    IUniswapV3Factory public factory = IUniswapV3Factory(Address.UNIV3_FACTORY);
    IUniswapV3Pool public pool;
    UniswapV3MintRecipient public recipient;

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

        // setup recipient and mint tokens
        recipient = new UniswapV3MintRecipient(
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

    // function testMint
}
