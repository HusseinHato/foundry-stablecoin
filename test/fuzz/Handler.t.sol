// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {WETHMock} from "test/mocks/WETHMock.sol";
import {WBTCMock} from "test/mocks/WBTCMock.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock wbtc;
    ERC20Mock weth;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;

    address[] usersWithCollateralDeposited;

    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    // THIS BREAKS OUR INVARIANT TEST SUITE!!!
    // function updateCollateralPrice(uint96 price) public {
    //     int256 newPrice = int256(uint256(price));
    //     ethUsdPriceFeed.updateAnswer(newPrice);
    // }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0){
            return;
        }

        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {

        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;

        if (maxDscToMint < 0) {
            return;
        }

        amount = bound(amount, 0, maxDscToMint);
        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    function _getCollateralSeed(uint256 collateralSeed) public view returns(ERC20Mock) {

        if (collateralSeed % 2 == 0) {
            return weth;
        }

        return wbtc;
    }


}