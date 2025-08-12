// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {WETHMock} from "test/mocks/WETHMock.sol";
import {WBTCMock} from "test/mocks/WBTCMock.sol";


contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployer;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    address testUser = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepolieaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepolieaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployer: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethpriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        WETHMock wethMock = new WETHMock();
        wethMock.mint(msg.sender, 1000e18);
        wethMock.mint(testUser, 1000e18);

        MockV3Aggregator btcpriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        WBTCMock wbtcMock = new WBTCMock();
        wbtcMock.mint(msg.sender, 1000e8);
        wbtcMock.mint(testUser, 100e18);

        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethpriceFeed),
            wbtcUsdPriceFeed: address(btcpriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployer: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}