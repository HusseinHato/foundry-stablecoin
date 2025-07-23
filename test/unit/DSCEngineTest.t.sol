// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import  {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {WETHMock} from "test/mocks/WETHMock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    address USER = makeAddr("user"); 

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, ,weth , , ) = config.activeNetworkConfig();

        console.log("DSC Owner:", dsc.owner());
        console.log("DSC Engine Address:", address(engine));

        // Mint some WETH for the user
        WETHMock wethMock = WETHMock(weth);
        console.log("WETH Mock Address:", address(wethMock));
        console.log("WETH Address:", weth);
        wethMock.mint(USER, STARTING_ERC20_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 20e18;
        uint256 expectedUsdValue = 40000e18; // Assuming WETH price is $2000
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value calculation is incorrect");
    }

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        WETHMock wethMock = WETHMock(weth);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

}
