// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import { IUniswapV2Factory } from "v2-core/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router01 } from "v2-periphery/interfaces/IUniswapV2Router01.sol";
import { IWETH } from "v2-periphery/interfaces/IWETH.sol";
import { IFakeLendingProtocol } from "./interfaces/IFakeLendingProtocol.sol";

// This is liquidator contract for testing,
// all you need to implement is flash swap from uniswap pool and call lending protocol liquidate function in uniswapV2Call
// lending protocol liquidate rule can be found in FakeLendingProtocol.sol
contract Liquidator is IUniswapV2Callee, Ownable {
    address internal immutable _FAKE_LENDING_PROTOCOL;
    address internal immutable _UNISWAP_ROUTER;
    address internal immutable _UNISWAP_FACTORY;
    address internal immutable _WETH9;
    uint256 internal constant _MINIMUM_PROFIT = 0.01 ether;
    struct Callbackdata{
        uint256 repayAmount;
        address path;
    }

    constructor(address lendingProtocol, address uniswapRouter, address uniswapFactory) {
        _FAKE_LENDING_PROTOCOL = lendingProtocol;
        _UNISWAP_ROUTER = uniswapRouter;
        _UNISWAP_FACTORY = uniswapFactory;
        _WETH9 = IUniswapV2Router01(uniswapRouter).WETH();
    }

    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        require(sender == address(this), "Sender must be this contract");
        require(amount0 != 0 || amount1 != 0, "amount0 or amount1 must be greater then zero");
        Callbackdata memory callbackData = abi.decode(data, (Callbackdata));

        address repayToken = callbackData.path[0];
        address borrowToken = callbackData.path[1];
        //80usdc -> 1 ether
        IERC20(borrowToken).approve(_FAKE_LENDING_PROTOCOL, callbackData.amountOut);
        IFakeLendingProtocol(_FAKE_LENDING_PROTOCOL).liquidatePosition();

        IWETH(repayToken).deposit{ value:callbackData.repayAmount }();

        IERC20(repayToken).transfer(callbackData.pair, callbackData.repayAmount);
        
    }

    // we use single hop path for testing
    function liquidate(address[] calldata path, uint256 amountOut) external {
        require(amountOut > 0, "AmountOut must be greater than 0");
        // TODO
        address pair = IUniswapV2Factory(_UNISWAP_FACTORY).getPair(path[0], path[1]);
        require(pair != address(0), "Pair not found");

        uint[] memory amountIn = IUniswapV2Router01(_UNISWAP_ROUTER).getAmountsIn(amountOut, path);
        Callbackdata memory data = Callbackdata(amountIn[0], path, pair, amountOut);
        IUniswapV2Pair(pair).swap(0, amountOut, address(this), abi.encode(data));
    }

    receive() external payable {}
}
