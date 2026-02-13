// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Market} from "src/Market.sol";
import {MarketFactory} from "src/MarketFactory.sol";
import {JumpRateModel} from "src/JumpRateModel.sol";
import {MegaEthTestnetFastSentinelOracle} from "src/testnet/MegaEthTestnetFastSentinelOracle.sol";
import {Faucet} from "src/testnet/Faucet.sol";

import {ISuperfluid} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidToken} from "superfluid/interfaces/superfluid/ISuperfluidToken.sol";
import {BatchOperation} from "superfluid/interfaces/superfluid/Definitions.sol";
import {IConstantFlowAgreementV1} from "superfluid/interfaces/agreements/IConstantFlowAgreementV1.sol";

contract DeployScript is Script {
    using SafeTransferLib for address;

    // APR → per-second WAD = APR / 31,536,000 * 1e18
    uint256 constant JRM_BASE_PER_SECOND = 6_341_958_396; //  ~20% APR
    uint256 constant JRM_SLOPER_1_PER_SECOND = 7_927_447_995; //  +25% APR across 0 → kink
    uint256 constant JRM_SLOPE_2_PER_SECOND = 95_129_375_951; //  +300% APR across kink → 1
    uint256 constant JRM_MIN_PER_SECOND = 1_585_489_599; //  ~5% APR floor
    uint256 constant JRM_MAX_PER_SECOND = 63_419_583_967; //  ~200% APR cap
    uint256 constant JRM_KINK = 0.8e18; //  80% utilization

    uint256 constant FAUCET_MINT_AMOUNT = 0.1 ether;
    uint256 constant FAUCET_COOLDOWN = 1 days;

    uint256 constant SO_PRICE_FRESHNESS_THRESHOLD = 10 seconds * 1_000_000; // microseconds

    // assuming asset has 18 decimals
    uint256 constant MARKET_BUFFER = 0.1e18; // 10% buffer; protects solvency on withdrawals
    uint256 constant MARKET_CAP = 10_000e18; // Market cap for deposits
    uint256 constant MARKET_OTM_HALF = 0.35e18; // OTM discount h: m(δ) = h / (h + δ)
    uint256 constant MARKET_WARM_UP_PERIOD = 15 minutes;
    uint256 constant MARKET_FEE = 0; // 0.1% fee

    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    uint256 deployerPrivateKey;
    uint256 lpPrivateKey;

    address deployer;
    address admin;
    address lp;
    address ethPriceFeed;
    address superfluidHost;

    Faucet faucet;
    Market market;
    JumpRateModel rateModel;
    MegaEthTestnetFastSentinelOracle priceOracle;

    function run() external {
        deployerPrivateKey = vm.envUint("TESTNET_DEPLOYER_PRIVATE_KEY");
        lpPrivateKey = vm.envUint("TESTNET_LP_PRIVATE_KEY");
        ethPriceFeed = vm.envAddress("TESTNET_ETH_PRICE_FEED_ADDRESS");
        admin = vm.envAddress("TESTNET_ADMIN_ADDRESS");
        superfluidHost = vm.envAddress("TESTNET_SUPERFLUID_HOST");

        deployer = vm.addr(deployerPrivateKey);
        lp = vm.addr(lpPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        faucet = new Faucet("Wrapped Ether", "WETH", 18, FAUCET_MINT_AMOUNT, FAUCET_COOLDOWN, superfluidHost, deployer);
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        rateModel = new JumpRateModel(
            JRM_BASE_PER_SECOND,
            JRM_SLOPER_1_PER_SECOND,
            JRM_SLOPE_2_PER_SECOND,
            JRM_KINK,
            JRM_MIN_PER_SECOND,
            JRM_MAX_PER_SECOND
        );
        priceOracle = new MegaEthTestnetFastSentinelOracle(ethPriceFeed);
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        address marketImplementation = address(new Market(superfluidHost));
        MarketFactory marketFactory = new MarketFactory(marketImplementation, deployer);
        vm.stopBroadcast();

        bytes memory immutableArgs = abi.encode(address(faucet.SUPER_TOKEN()));
        bytes memory initializerData = abi.encodeCall(
            Market.initialize,
            (
                address(rateModel),
                address(priceOracle),
                MARKET_BUFFER,
                MARKET_CAP,
                MARKET_OTM_HALF,
                MARKET_WARM_UP_PERIOD,
                MARKET_FEE,
                MARKET_FEE,
                admin
            )
        );

        vm.startBroadcast(deployerPrivateKey);
        address marketAddress = marketFactory.deployMarket(immutableArgs, initializerData);
        market = Market(marketAddress);
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        faucet.superMint(lp, MARKET_CAP);
        vm.stopBroadcast();

        vm.startBroadcast(lpPrivateKey);
        faucet.SUPER_TOKEN().safeApprove(address(market), MARKET_CAP);
        market.deposit(MARKET_CAP, lp);
        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey);
        faucet.transferOwnership(admin);
        marketFactory.transferOwnership(admin);
        vm.stopBroadcast();

        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("LP:", lp);
        console.log("Faucet:", address(faucet));
        console.log("Faucet (ERC20):", faucet.TOKEN());
        console.log("Faucet (SUPER_TOKEN):", faucet.SUPER_TOKEN());
        console.log("JumpRateModel:", address(rateModel));
        console.log("SentinelOracle:", address(priceOracle));
        console.log("MarketFactory:", address(marketFactory));
        console.log("MarketImplementation:", marketImplementation);
        console.log("MarketProxy:", address(market));
    }
}
