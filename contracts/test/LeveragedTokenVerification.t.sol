// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LPVault.sol";
import "../src/LeveragedLongToken.sol";
import "../src/LeveragedShortToken.sol";
import "./helpers/TestHelpers.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LeveragedTokenVerificationTest is Test {
    // Long setup
    LPVault public longVault; // Holds USDC
    LeveragedLongToken public longToken;

    // Short setup
    LPVault public shortVault; // Holds WETH
    LeveragedShortToken public shortToken;

    MockERC20 public weth;
    MockUSDC public usdc;
    MockChainlinkOracle public oracle;
    MockUniswapRouter public swapRouter;

    address public owner = address(this);
    address public lp1 = address(0x1);
    address public trader1 = address(0x3);

    uint256 constant INITIAL_ETH_PRICE = 2000 * 1e8; // $2000
    uint256 constant SWAP_PRICE = 2000 * 1e6; // $2000 USDC per WETH
    uint256 constant LEVERAGE_RATIO = 20000; // 2x
    uint256 constant INTEREST_RATE = 1000; // 10% APY
    uint24 constant POOL_FEE = 3000;

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH");
        usdc = new MockUSDC();
        oracle = new MockChainlinkOracle(int256(INITIAL_ETH_PRICE), 8);
        swapRouter = new MockUniswapRouter(address(usdc), address(weth), SWAP_PRICE, 6, 18);

        // Deploy Long Vault & Token
        LPVault longVaultImpl = new LPVault();
        bytes memory longVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector, address(usdc), "LP USDC Vault", "lpUSDC", INTEREST_RATE
        );
        ERC1967Proxy longVaultProxy = new ERC1967Proxy(address(longVaultImpl), longVaultInitData);
        longVault = LPVault(address(longVaultProxy));

        LeveragedLongToken longTokenImpl = new LeveragedLongToken();
        bytes memory longTokenInitData = abi.encodeWithSelector(
            LeveragedLongToken.initialize.selector,
            "ETH 2x Daily Long", "ETH2X", address(longVault), address(weth), address(swapRouter), address(oracle), POOL_FEE, LEVERAGE_RATIO
        );
        ERC1967Proxy longTokenProxy = new ERC1967Proxy(address(longTokenImpl), longTokenInitData);
        longToken = LeveragedLongToken(address(longTokenProxy));
        longVault.authorizeBorrower(address(longToken));

        // Deploy Short Vault & Token
        LPVault shortVaultImpl = new LPVault();
        bytes memory shortVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector, address(weth), "LP WETH Vault", "lpWETH", INTEREST_RATE
        );
        ERC1967Proxy shortVaultProxy = new ERC1967Proxy(address(shortVaultImpl), shortVaultInitData);
        shortVault = LPVault(address(shortVaultProxy));

        LeveragedShortToken shortTokenImpl = new LeveragedShortToken();
        bytes memory shortTokenInitData = abi.encodeWithSelector(
            LeveragedShortToken.initialize.selector,
            "ETH 2x Daily Short", "ETH-2X", address(shortVault), address(usdc), address(swapRouter), address(oracle), POOL_FEE, LEVERAGE_RATIO
        );
        ERC1967Proxy shortTokenProxy = new ERC1967Proxy(address(shortTokenImpl), shortTokenInitData);
        shortToken = LeveragedShortToken(address(shortTokenProxy));
        shortVault.authorizeBorrower(address(shortToken));

        // Fund Accounts
        usdc.mint(lp1, 1000000 * 1e6);
        weth.mint(lp1, 1000 ether);
        usdc.mint(trader1, 100000 * 1e6);

        // Approvals
        vm.startPrank(lp1);
        usdc.approve(address(longVault), type(uint256).max);
        weth.approve(address(shortVault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(trader1);
        usdc.approve(address(longToken), type(uint256).max);
        usdc.approve(address(shortToken), type(uint256).max);
        vm.stopPrank();
    }

    // 1. Verify Rebalance Logic Flaw (Does not adjust leverage)
    function testRebalanceDoesNotAdjustLeverage() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6); // 1000 collateral, 1000 borrow, 1 ETH held

        // Initial state
        uint256 initialUnderlying = longToken.totalUnderlying(); // 1 ETH
        uint256 initialBorrowed = longToken.totalBorrowed(); // 1000 USDC

        // Price doubles: $2000 -> $4000
        oracle.setPrice(int256(4000 * 1e8));
        swapRouter.setPrice(4000 * 1e6);

        // New Value: 1 ETH * $4000 = $4000. Debt = $1000. Equity = $3000.
        // Current Leverage = Assets / Equity = 4000 / 3000 = 1.33x
        // Target Leverage = 2x. Should borrow more to buy more ETH.

        vm.warp(block.timestamp + 1 days);
        longToken.rebalance();

        // Check if positions changed
        uint256 finalUnderlying = longToken.totalUnderlying();
        uint256 finalBorrowed = longToken.totalBorrowed();

        console.log("Initial Underlying:", initialUnderlying);
        console.log("Final Underlying:  ", finalUnderlying);
        console.log("Initial Borrowed:  ", initialBorrowed);
        console.log("Final Borrowed:    ", finalBorrowed);

        // BUG: If these are equal, rebalance didn't do anything to the portfolio
        assertEq(initialUnderlying, finalUnderlying, "Rebalance should have adjusted underlying but didn't");
        assertEq(initialBorrowed, finalBorrowed, "Rebalance should have adjusted debt but didn't");
    }

    // 2. Verify Interest Payment Missing
    function testInterestNotPaid() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6); // Borrow 1000 USDC

        // Advance time 1 year
        vm.warp(block.timestamp + 365 days);
        oracle.setPrice(int256(INITIAL_ETH_PRICE)); // Reset timestamp to avoid "Price too stale"

        // Interest rate 10%. Debt should be 1100.
        // LPVault thinks it has accrued interest.
        uint256 totalAssets = longVault.totalAssets();
        // 100k deposit + 100 interest (10% of 1000 borrowed) = 100100
        // (approximate, depending on compounding/accrual logic)
        
        // Trader redeems
        uint256 traderShares = longToken.balanceOf(trader1);
        vm.prank(trader1);
        longToken.redeem(traderShares);

        // Check LPVault actual balance
        uint256 actualBalance = usdc.balanceOf(address(longVault));
        // Should be 100000 (original deposit) + interest paid
        // If interest not paid, it's just 100000 (minus whatever is still borrowed, which is 0)
        
        console.log("LP Vault Total Assets (Accounting):", totalAssets);
        console.log("LP Vault Actual Balance (Tokens):  ", actualBalance);

        // BUG: Actual balance < Total Assets means insolvency
        assertLt(actualBalance, totalAssets, "LP Vault is insolvent due to missing interest");
    }

    // 3. Verify Bad Debt on Undercollateralized Redemption
    function testLongRedemptionUndercollateralized() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6); // Borrow 1000, Buy 1 ETH ($2000)

        // Price drops 60%: $2000 -> $800
        oracle.setPrice(int256(800 * 1e8));
        swapRouter.setPrice(800 * 1e6);

        // Assets: 1 ETH = $800. Debt: $1000. Equity: -$200.
        // User should get 0. Vault should take $200 loss.
        
        uint256 vaultBalanceBefore = usdc.balanceOf(address(longVault)); // 99000

        uint256 traderShares = longToken.balanceOf(trader1);
        vm.prank(trader1);
        longToken.redeem(traderShares);

        uint256 vaultBalanceAfter = usdc.balanceOf(address(longVault));
        uint256 repaid = vaultBalanceAfter - vaultBalanceBefore;

        console.log("Debt to Repay: 1000 USDC");
        console.log("Actually Repaid:", repaid);

        // BUG: If repaid < 1000, vault has bad debt
        assertLt(repaid, 1000 * 1e6, "Vault took a loss");
        
        // Check if debt was cleared in accounting
        (uint256 principal, ) = longVault.getDebt(address(longToken));
        console.log("Remaining Debt on Ledger:", principal);
        
        // If principal > 0, the contract thinks it still owes money but has no assets
        // If principal == 0, the contract wiped the debt but didn't pay it (LP loss invisible until withdrawal)
    }
}
