// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity ^0.8.20;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract Invariants is StdInvariant, Test {
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;

//     address weth;
//     address wbtc;


//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (,,weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).totalSupply();
//         uint256 totalWbtcDeposited = IERC20(wbtc).totalSupply();

//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited); 
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

//         assert(wethValue + wbtcValue >= totalSupply); 
//     }

// }