// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LPVault.sol";
import "../src/LeveragedLongToken.sol";
import "../src/LeveragedShortToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployLeveraged - Deploy ETH 2x Long and Short ETFs
/// @notice Deploys separate LP Vaults for long (USDC) and short (WETH) products
contract DeployLeveragedScript is Script {
    // Base Sepolia addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant SWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;

    // Chainlink ETH/USD on Base Sepolia
    address constant ETH_USD_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    // Configuration
    uint256 constant LEVERAGE_RATIO = 20000; // 2x leverage
    uint256 constant INTEREST_RATE = 500; // 5% APY
    uint24 constant POOL_FEE = 3000; // 0.3% Uniswap fee tier

    function run() external {
        vm.startBroadcast();

        // ═══════════════════════════════════════════════════════════════
        //                    LONG ETF (ETH2X)
        // ═══════════════════════════════════════════════════════════════
        // LP Vault holds USDC → Long token borrows USDC → buys WETH

        LPVault longVaultImpl = new LPVault();
        bytes memory longVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector,
            USDC, // LPs deposit USDC
            "LP USDC Vault (Long)",
            "lpUSDC-L",
            INTEREST_RATE
        );
        ERC1967Proxy longVaultProxy = new ERC1967Proxy(address(longVaultImpl), longVaultInitData);
        LPVault longVault = LPVault(address(longVaultProxy));

        LeveragedLongToken longTokenImpl = new LeveragedLongToken();
        bytes memory longTokenInitData = abi.encodeWithSelector(
            LeveragedLongToken.initialize.selector,
            "ETH 2x Daily Long",
            "ETH2X",
            address(longVault),
            WETH, // underlying
            SWAP_ROUTER,
            ETH_USD_FEED,
            POOL_FEE,
            LEVERAGE_RATIO
        );
        ERC1967Proxy longTokenProxy = new ERC1967Proxy(address(longTokenImpl), longTokenInitData);
        LeveragedLongToken longToken = LeveragedLongToken(address(longTokenProxy));

        longVault.authorizeBorrower(address(longToken));

        // ═══════════════════════════════════════════════════════════════
        //                    SHORT ETF (ETH-2X)
        // ═══════════════════════════════════════════════════════════════
        // LP Vault holds WETH → Short token borrows WETH → sells for USDC

        LPVault shortVaultImpl = new LPVault();
        bytes memory shortVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector,
            WETH, // LPs deposit WETH
            "LP WETH Vault (Short)",
            "lpWETH-S",
            INTEREST_RATE
        );
        ERC1967Proxy shortVaultProxy = new ERC1967Proxy(address(shortVaultImpl), shortVaultInitData);
        LPVault shortVault = LPVault(address(shortVaultProxy));

        LeveragedShortToken shortTokenImpl = new LeveragedShortToken();
        bytes memory shortTokenInitData = abi.encodeWithSelector(
            LeveragedShortToken.initialize.selector,
            "ETH 2x Daily Short",
            "ETH-2X",
            address(shortVault),
            USDC, // stable for collateral
            SWAP_ROUTER,
            ETH_USD_FEED,
            POOL_FEE,
            LEVERAGE_RATIO
        );
        ERC1967Proxy shortTokenProxy = new ERC1967Proxy(address(shortTokenImpl), shortTokenInitData);
        LeveragedShortToken shortToken = LeveragedShortToken(address(shortTokenProxy));

        shortVault.authorizeBorrower(address(shortToken));

        vm.stopBroadcast();

        // Log deployment info
        console.log("=== ETH Leveraged ETFs Deployed ===");
        console.log("");
        console.log("--- LONG (ETH2X) ---");
        console.log("LP Vault (lpUSDC-L):", address(longVault));
        console.log("Long Token (ETH2X):", address(longToken));
        console.log("Mechanism: Deposit USDC -> Borrow USDC -> Buy WETH");
        console.log("");
        console.log("--- SHORT (ETH-2X) ---");
        console.log("LP Vault (lpWETH-S):", address(shortVault));
        console.log("Short Token (ETH-2X):", address(shortToken));
        console.log("Mechanism: Deposit USDC -> Borrow WETH -> Sell for USDC");

        // Save deployment addresses
        string memory basescanUrl = "https://sepolia.basescan.org/address/";

        vm.writeFile(
            "deployments/leveraged-etfs.json",
            string(
                abi.encodePacked(
                    '{\n',
                    '  "network": "base-sepolia",\n',
                    '  "chainId": 84532,\n',
                    '  "long": {\n',
                    '    "lpVault": "', vm.toString(address(longVault)), '",\n',
                    '    "lpVaultImpl": "', vm.toString(address(longVaultImpl)), '",\n',
                    '    "token": "', vm.toString(address(longToken)), '",\n',
                    '    "tokenImpl": "', vm.toString(address(longTokenImpl)), '",\n',
                    '    "mechanism": "borrow USDC, buy WETH"\n',
                    '  },\n',
                    '  "short": {\n',
                    '    "lpVault": "', vm.toString(address(shortVault)), '",\n',
                    '    "lpVaultImpl": "', vm.toString(address(shortVaultImpl)), '",\n',
                    '    "token": "', vm.toString(address(shortToken)), '",\n',
                    '    "tokenImpl": "', vm.toString(address(shortTokenImpl)), '",\n',
                    '    "mechanism": "borrow WETH, sell for USDC"\n',
                    '  },\n',
                    '  "config": {\n',
                    '    "leverage": "2x",\n',
                    '    "interestRate": "5%",\n',
                    '    "poolFee": "0.3%"\n',
                    '  },\n',
                    '  "external": {\n',
                    '    "WETH": "', vm.toString(WETH), '",\n',
                    '    "USDC": "', vm.toString(USDC), '",\n',
                    '    "SwapRouter": "', vm.toString(SWAP_ROUTER), '",\n',
                    '    "ETH_USD_Feed": "', vm.toString(ETH_USD_FEED), '"\n',
                    '  },\n',
                    '  "verification": {\n',
                    '    "longVault": "', basescanUrl, vm.toString(address(longVault)), '",\n',
                    '    "longToken": "', basescanUrl, vm.toString(address(longToken)), '",\n',
                    '    "shortVault": "', basescanUrl, vm.toString(address(shortVault)), '",\n',
                    '    "shortToken": "', basescanUrl, vm.toString(address(shortToken)), '"\n',
                    '  }\n',
                    '}'
                )
            )
        );
    }
}
