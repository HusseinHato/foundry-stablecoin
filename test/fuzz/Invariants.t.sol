// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    address weth;
    address wbtc;

    Handler handler;


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();

        handler = new Handler(dsce, dsc);

        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).totalSupply();
        uint256 totalWbtcDeposited = IERC20(wbtc).totalSupply();

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited); 
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Total Supply: ", totalSupply);
        console.log("WETH Value: ", wethValue);
        console.log("WBTC Value: ", wbtcValue);
        console.log("Time Mint DSC is being called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply); 
    }

}