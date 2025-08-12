// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {WETHMock} from "test/mocks/WETHMock.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "test/mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "test/mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "test/mocks/MockMoreDebtDSC.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;

    HelperConfig config;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    address USER = makeAddr("user"); 

    address LIQUIDATOR = makeAddr("liquidator");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config,,) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth , , ) = config.activeNetworkConfig();

        // console.log("DSC Owner:", dsc.owner());
        // console.log("DSC Engine Address:", address(engine));

        // Mint some WETH for the user
        WETHMock wethMock = WETHMock(weth);
        // console.log("WETH Mock Address:", address(wethMock));
        // console.log("WETH Address:", weth);
        wethMock.mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constuctor Tests ///
    ///////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenAddressLengthAndPriceFeedLengthDoesntMatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustHaveSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////
    // Price tests /////
    ////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 20e18;
        uint256 expectedUsdValue = 40000e18; // Assuming WETH price is $2000
        uint256 actualUsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue, "USD value calculation is incorrect");
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    
    //////////////////////////////
    // Deposit Collateral Test ///
    //////////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        WETHMock wethMock = WETHMock(weth);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ercMock = new ERC20Mock();
        ercMock.mint(USER, STARTING_ERC20_BALANCE);

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenNotAllowed.selector,
                address(ercMock)
            )
        );
        engine.depositCollateral(address(ercMock), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral {
        vm.startPrank(USER);
        WETHMock wethMock = WETHMock(weth);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralAndEmitsEvent() public {
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, false, address(engine));
        emit DSCEngine.DSCEngine__CollateralDeposited(USER, address(wethMock), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        priceFeedAddresses = [wethUsdPriceFeed];
        vm.stopPrank();
        // DSCEngine receives the third parameter as dscAddress, not the tokenAddress used as collateral
        vm.startPrank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        mockCollateralToken.mint(USER, AMOUNT_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(USER);
        mockCollateralToken.approve(address(mockDsce), AMOUNT_COLLATERAL);
        // ACT / ASSERT
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userbalance = dsc.balanceOf(USER);
        assertEq(userbalance, 0);
    }

    /////////////////////////////////////////////
    // depositCollateralAndMintDSC test /////////
    /////////////////////////////////////////////

    function testRevertsIfMintedDscBreakHealthFactor() public {
        (, int256 ethPrice,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(ethPrice)) * engine.getAdditionalFeedPrecision()) / engine.getPrecision();
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        // console.log(engine.getHealthFactor(USER));
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    /////////////////////
    // MintDsc Test ////
    /////////////////////

    function testRevertsIfMintFails() public {
        address owner = msg.sender;
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(owner);
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];
        vm.startPrank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));
        vm.stopPrank();
        // ARRANGE - USER
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(mockEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertIfMintAmountIsZero() public {
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        // engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * uint256(price) * engine.getAdditionalFeedPrecision()) / engine.getPrecision();

        vm.startPrank(USER);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDSC() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(AMOUNT_TO_MINT);

        uint256 balance = dsc.balanceOf(USER);
        assertEq(balance, AMOUNT_TO_MINT);
    }

    ////////////////////
    // BurnDsc Test ////
    ////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        WETHMock wethMock = WETHMock(weth);

        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 balance = dsc.balanceOf(USER);
        assertEq(balance, 0);
    }

    /////////////////////////////
    // redeemCollateral tests ///
    /////////////////////////////

    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        
        vm.startPrank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [wethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(USER, AMOUNT_COLLATERAL);
        
        mockDsc.transferOwnership(address(mockEngine));
        vm.stopPrank();
        // ARRANGE USER
        vm.startPrank(USER);
        mockDsc.approve(address(mockEngine), AMOUNT_COLLATERAL);
        // ACT / ASSERT
        mockEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        WETHMock wethMock = WETHMock(weth);

        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 balanceBeforeRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(balanceBeforeRedeem, AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 balanceAfterRedeem = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(balanceAfterRedeem, 0);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit DSCEngine.DSCEngine__CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////////
    // redeemCollateralForDsc tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        WETHMock wethMock = WETHMock(weth);

        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 balance = dsc.balanceOf(USER);
        assertEq(balance, 0);
    }

    ////////////////////////
    // HealthFactor tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100e18;
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc  {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

    ///////////////////////
    // Liquidation tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // ARRANGE - SETUP
        WETHMock wethMock = WETHMock(weth);
        address owner = msg.sender;
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(wethUsdPriceFeed, owner);
        tokenAddresses = [weth];
        priceFeedAddresses = [wethUsdPriceFeed];

        vm.startPrank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));
        // ARRANGE - USER
        vm.startPrank(USER);
        wethMock.approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        //ARRANGE - LIQUIDATOR
        uint256 collateraltoCover = 1 ether;
        wethMock.mint(LIQUIDATOR, collateraltoCover);

        vm.startPrank(LIQUIDATOR);
        wethMock.approve(address(mockEngine), collateraltoCover);
        uint256 debtToCover = 10 ether;
        mockEngine.depositCollateralAndMintDsc(weth, collateraltoCover, AMOUNT_TO_MINT);
        mockDsc.approve(address(mockEngine), debtToCover);
        // ACT
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18, REPRESENT PRICE DROP IN ETH
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // ACT/ASSERT
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        WETHMock wethMock = WETHMock(weth);
        wethMock.mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        wethMock.approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    modifier liquidated() {
        WETHMock wethMock = WETHMock(weth);
        vm.startPrank(USER);
        wethMock.approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = 18$

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        console.log("HealthFactor", userHealthFactor);

        wethMock.mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        wethMock.approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT); // We are covering their whole debt
        vm.stopPrank();
        _;
    }
 
    function testLiquidationPayoutIsCorrect() public liquidated {
        WETHMock wethMock = WETHMock(weth);
        uint256 liquidatorWethBalance = wethMock.balanceOf(LIQUIDATOR);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + (engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) * engine.getLiquidationBonus() / engine.getLiquidationPrecision());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + (engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) * engine.getLiquidationBonus() / engine.getLiquidationPrecision());

        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);

        uint256 expectedUserCollateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 hardcodedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, hardcodedValue);
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated{
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    /////////////////////////////////
    // View & Pure Function Tests ///
    /////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = engine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

    // 2 Lazy 4 the others
}
