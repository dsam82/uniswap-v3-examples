// SPDX-License-Identifier: MIT
pragma solidity <0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3Recipient {
    address public immutable pool;
    address public immutable tokenA;
    address public immutable tokenB;

    constructor(
        address _pool,
        address _tokenA,
        address _tokenB
    ) {
        pool = _pool;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata
    ) external {
        require(msg.sender == pool, "Unauthorised");

        IERC20(tokenA).transfer(pool, amount0);
        IERC20(tokenB).transfer(pool, amount1);
    }

    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata
    ) external {
        require(msg.sender == pool, "Unauthorised");

        if (amount0 > 0) {
            IERC20(tokenA).transfer(msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(tokenB).transfer(msg.sender, uint256(amount1));
        }
    }
}
