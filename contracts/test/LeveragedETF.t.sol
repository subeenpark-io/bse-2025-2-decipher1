// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LPVault.sol";
import "../src/LeveragedLongToken.sol";
import "../src/LeveragedShortToken.sol";
import "./helpers/TestHelpers.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LeveragedETFTest is Test {
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
    address public lp2 = address(0x2);
    address public trader1 = address(0x3);
    address public trader2 = address(0x4);

    uint256 constant INITIAL_ETH_PRICE = 2000 * 1e8; // $2000 with 8 decimals (Chainlink format)
    uint256 constant SWAP_PRICE = 2000 * 1e6; // $2000 with 6 decimals (USDC per WETH for swap router)
    uint256 constant LEVERAGE_RATIO = 20000; // 2x
    uint256 constant INTEREST_RATE = 500; // 5% APY
    uint24 constant POOL_FEE = 3000; // 0.3%

    function setUp() public {
        // Deploy mock tokens
        weth = new MockERC20("Wrapped ETH", "WETH");
        usdc = new MockUSDC();

        // Deploy mock oracle ($2000 ETH price, 8 decimals like Chainlink)
        oracle = new MockChainlinkOracle(int256(INITIAL_ETH_PRICE), 8);

        // Deploy mock swap router (USDC/WETH at $2000)
        swapRouter = new MockUniswapRouter(address(usdc), address(weth), SWAP_PRICE, 6, 18);

        // ═══════════════════════════════════════════════════════════════
        //                    LONG SETUP (LP Vault holds USDC)
        // ═══════════════════════════════════════════════════════════════
        LPVault longVaultImpl = new LPVault();
        bytes memory longVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector, address(usdc), "LP USDC Vault", "lpUSDC", INTEREST_RATE
        );
        ERC1967Proxy longVaultProxy = new ERC1967Proxy(address(longVaultImpl), longVaultInitData);
        longVault = LPVault(address(longVaultProxy));

        LeveragedLongToken longTokenImpl = new LeveragedLongToken();
        bytes memory longTokenInitData = abi.encodeWithSelector(
            LeveragedLongToken.initialize.selector,
            "ETH 2x Daily Long",
            "ETH2X",
            address(longVault),
            address(weth),
            address(swapRouter),
            address(oracle),
            POOL_FEE,
            LEVERAGE_RATIO
        );
        ERC1967Proxy longTokenProxy = new ERC1967Proxy(address(longTokenImpl), longTokenInitData);
        longToken = LeveragedLongToken(address(longTokenProxy));

        longVault.authorizeBorrower(address(longToken));

        // ═══════════════════════════════════════════════════════════════
        //                    SHORT SETUP (LP Vault holds WETH)
        // ═══════════════════════════════════════════════════════════════
        LPVault shortVaultImpl = new LPVault();
        bytes memory shortVaultInitData = abi.encodeWithSelector(
            LPVault.initialize.selector, address(weth), "LP WETH Vault", "lpWETH", INTEREST_RATE
        );
        ERC1967Proxy shortVaultProxy = new ERC1967Proxy(address(shortVaultImpl), shortVaultInitData);
        shortVault = LPVault(address(shortVaultProxy));

        LeveragedShortToken shortTokenImpl = new LeveragedShortToken();
        bytes memory shortTokenInitData = abi.encodeWithSelector(
            LeveragedShortToken.initialize.selector,
            "ETH 2x Daily Short",
            "ETH-2X",
            address(shortVault),
            address(usdc),
            address(swapRouter),
            address(oracle),
            POOL_FEE,
            LEVERAGE_RATIO
        );
        ERC1967Proxy shortTokenProxy = new ERC1967Proxy(address(shortTokenImpl), shortTokenInitData);
        shortToken = LeveragedShortToken(address(shortTokenProxy));

        shortVault.authorizeBorrower(address(shortToken));

        // ═══════════════════════════════════════════════════════════════
        //                    FUND TEST ACCOUNTS
        // ═══════════════════════════════════════════════════════════════

        // LPs for long vault (provide USDC)
        usdc.mint(lp1, 1000000 * 1e6); // 1M USDC
        usdc.mint(lp2, 1000000 * 1e6);

        // LPs for short vault (provide WETH)
        weth.mint(lp1, 1000 ether);
        weth.mint(lp2, 1000 ether);

        // Traders deposit USDC for both long and short
        usdc.mint(trader1, 100000 * 1e6);
        usdc.mint(trader2, 100000 * 1e6);

        // Approvals for long vault (USDC)
        vm.prank(lp1);
        usdc.approve(address(longVault), type(uint256).max);
        vm.prank(lp2);
        usdc.approve(address(longVault), type(uint256).max);

        // Approvals for short vault (WETH)
        vm.prank(lp1);
        weth.approve(address(shortVault), type(uint256).max);
        vm.prank(lp2);
        weth.approve(address(shortVault), type(uint256).max);

        // Trader approvals for long token
        vm.prank(trader1);
        usdc.approve(address(longToken), type(uint256).max);
        vm.prank(trader2);
        usdc.approve(address(longToken), type(uint256).max);

        // Trader approvals for short token
        vm.prank(trader1);
        usdc.approve(address(shortToken), type(uint256).max);
        vm.prank(trader2);
        usdc.approve(address(shortToken), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    LP VAULT TESTS
    // ═══════════════════════════════════════════════════════════════

    function testLongVaultInitialization() public view {
        assertEq(longVault.name(), "LP USDC Vault");
        assertEq(longVault.symbol(), "lpUSDC");
        assertEq(longVault.asset(), address(usdc));
    }

    function testShortVaultInitialization() public view {
        assertEq(shortVault.name(), "LP WETH Vault");
        assertEq(shortVault.symbol(), "lpWETH");
        assertEq(shortVault.asset(), address(weth));
    }

    function testLPDepositToLongVault() public {
        uint256 depositAmount = 10000 * 1e6; // 10k USDC

        vm.prank(lp1);
        uint256 shares = longVault.deposit(depositAmount, lp1);

        assertEq(shares, depositAmount);
        assertEq(longVault.balanceOf(lp1), depositAmount);
    }

    function testLPDepositToShortVault() public {
        uint256 depositAmount = 10 ether;

        vm.prank(lp1);
        uint256 shares = shortVault.deposit(depositAmount, lp1);

        assertEq(shares, depositAmount);
        assertEq(shortVault.balanceOf(lp1), depositAmount);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    LONG TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════

    function testLongTokenInitialization() public view {
        assertEq(longToken.name(), "ETH 2x Daily Long");
        assertEq(longToken.symbol(), "ETH2X");
        assertEq(longToken.leverageRatio(), LEVERAGE_RATIO);
        assertEq(address(longToken.lpVault()), address(longVault));
    }

    function testMintLongToken() public {
        // LP provides USDC liquidity
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        // Trader mints long token with 1000 USDC
        uint256 collateral = 1000 * 1e6;

        vm.prank(trader1);
        uint256 shares = longToken.mint(collateral);

        assertGt(shares, 0);
        assertEq(longToken.balanceOf(trader1), shares);
        assertEq(longToken.totalCollateral(), collateral);

        // Should have borrowed USDC from vault (for 2x, borrow same as deposit)
        assertEq(longToken.totalBorrowed(), collateral);

        // Should have swapped to WETH
        // $2000 total / $2000 per ETH = 1 ETH
        assertGt(longToken.totalUnderlying(), 0);
    }

    function testLongTokenMechanism() public {
        // LP provides liquidity
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        // Trader deposits 1000 USDC
        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        // Verify mechanism:
        // 1. Deposited 1000 USDC
        // 2. Borrowed 1000 USDC (for 2x)
        // 3. Swapped 2000 USDC -> 1 WETH
        assertEq(longToken.totalCollateral(), 1000 * 1e6);
        assertEq(longToken.totalBorrowed(), 1000 * 1e6);
        // At $2000/ETH, 2000 USDC = 1 ETH
        assertEq(longToken.totalUnderlying(), 1 ether);
    }

    function testLongReturns_PriceUp() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        uint256 navBefore = longToken.getCurrentNav();

        // Price goes up 10%
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 110 / 100));

        uint256 navAfter = longToken.getCurrentNav();

        // With 2x leverage, NAV should increase ~20%
        assertGt(navAfter, navBefore);
        assertGt(navAfter, navBefore * 115 / 100);
    }

    function testLongReturns_PriceDown() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        uint256 navBefore = longToken.getCurrentNav();

        // Price goes down 10%
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 90 / 100));

        uint256 navAfter = longToken.getCurrentNav();

        // With 2x leverage, NAV should decrease ~20%
        assertLt(navAfter, navBefore);
        assertLt(navAfter, navBefore * 85 / 100);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SHORT TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════

    function testShortTokenInitialization() public view {
        assertEq(shortToken.name(), "ETH 2x Daily Short");
        assertEq(shortToken.symbol(), "ETH-2X");
        assertEq(shortToken.leverageRatio(), LEVERAGE_RATIO);
        assertEq(address(shortToken.lpVault()), address(shortVault));
    }

    function testMintShortToken() public {
        // LP provides WETH liquidity
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        // Trader mints short token with 1000 USDC
        uint256 collateral = 1000 * 1e6;

        vm.prank(trader1);
        uint256 shares = shortToken.mint(collateral);

        assertGt(shares, 0);
        assertEq(shortToken.balanceOf(trader1), shares);
        assertEq(shortToken.totalCollateral(), collateral);

        // Should have borrowed WETH from vault
        // For 2x short with $1000 collateral, borrow $2000 worth of ETH = 1 ETH
        assertGt(shortToken.totalBorrowed(), 0);

        // Should have stable from selling borrowed WETH
        assertGt(shortToken.totalStableHeld(), collateral);
    }

    function testShortTokenMechanism() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        shortToken.mint(1000 * 1e6);

        // Verify mechanism:
        // 1. Deposited 1000 USDC
        // 2. Borrowed 1 ETH (worth $2000 for 2x exposure)
        // 3. Sold 1 ETH -> 2000 USDC
        // 4. Total stable held = 1000 + 2000 = 3000 USDC
        assertEq(shortToken.totalCollateral(), 1000 * 1e6);
        assertEq(shortToken.totalBorrowed(), 1 ether);
        assertEq(shortToken.totalStableHeld(), 3000 * 1e6);
    }

    function testShortReturns_PriceDown() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        shortToken.mint(1000 * 1e6);

        uint256 navBefore = shortToken.getCurrentNav();

        // Price goes DOWN 10% - good for shorts!
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 90 / 100));

        uint256 navAfter = shortToken.getCurrentNav();

        // With 2x leverage, NAV should INCREASE ~20%
        assertGt(navAfter, navBefore);
        assertGt(navAfter, navBefore * 115 / 100);
    }

    function testShortReturns_PriceUp() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        shortToken.mint(1000 * 1e6);

        uint256 navBefore = shortToken.getCurrentNav();

        // Price goes UP 10% - bad for shorts!
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 110 / 100));

        uint256 navAfter = shortToken.getCurrentNav();

        // With 2x leverage, NAV should DECREASE ~20%
        assertLt(navAfter, navBefore);
        assertLt(navAfter, navBefore * 85 / 100);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    REBALANCE TESTS
    // ═══════════════════════════════════════════════════════════════

    function testLongRebalance() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        // Wait for rebalance window
        vm.warp(block.timestamp + 21 hours);

        // Rebalance should work
        longToken.rebalance();

        assertEq(longToken.lastRebalanceTime(), block.timestamp);
    }

    function testShortRebalance() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        shortToken.mint(1000 * 1e6);

        vm.warp(block.timestamp + 21 hours);

        shortToken.rebalance();

        assertEq(shortToken.lastRebalanceTime(), block.timestamp);
    }

    function testRebalanceTooSoon() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        vm.expectRevert("Too soon");
        longToken.rebalance();
    }

    function testForceRebalance() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        // Owner can force rebalance anytime
        longToken.forceRebalance();
    }

    function testNeedsRebalance() public {
        assertFalse(longToken.needsRebalance());

        vm.warp(block.timestamp + 21 hours);

        assertTrue(longToken.needsRebalance());
    }

    // ═══════════════════════════════════════════════════════════════
    //                    PAUSE TESTS
    // ═══════════════════════════════════════════════════════════════

    function testLongVaultPause() public {
        vm.prank(lp1);
        longVault.deposit(10000 * 1e6, lp1);

        longVault.pause();

        vm.prank(lp1);
        vm.expectRevert();
        longVault.deposit(1000 * 1e6, lp1);

        longVault.unpause();

        vm.prank(lp1);
        longVault.deposit(1000 * 1e6, lp1);
    }

    function testLongTokenPause() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        uint256 shares = longToken.mint(1000 * 1e6);

        longToken.pause();

        vm.prank(trader2);
        vm.expectRevert();
        longToken.mint(1000 * 1e6);

        vm.prank(trader1);
        vm.expectRevert();
        longToken.redeem(shares);

        longToken.unpause();

        vm.prank(trader2);
        longToken.mint(1000 * 1e6);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(trader1);
        vm.expectRevert();
        longVault.pause();

        vm.prank(trader1);
        vm.expectRevert();
        longToken.pause();

        vm.prank(trader1);
        vm.expectRevert();
        shortToken.pause();
    }

    // ═══════════════════════════════════════════════════════════════
    //                    EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════

    function testCannotBorrowWithoutLiquidity() public {
        vm.prank(trader1);
        vm.expectRevert("Insufficient liquidity");
        longToken.mint(1000 * 1e6);
    }

    function testSetLeverageRatio() public {
        longToken.setLeverageRatio(30000); // 3x
        assertEq(longToken.leverageRatio(), 30000);
    }

    function testInvalidLeverageRatio() public {
        vm.expectRevert("Invalid leverage");
        longToken.setLeverageRatio(60000); // 6x too high

        vm.expectRevert("Invalid leverage");
        longToken.setLeverageRatio(5000); // 0.5x too low
    }

    function testGetStats() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        (
            uint256 nav,
            uint256 price,
            uint256 collateral,
            uint256 borrowed,
            uint256 underlying,
            uint256 supply
        ) = longToken.getStats();

        assertGt(nav, 0);
        assertEq(price, INITIAL_ETH_PRICE);
        assertEq(collateral, 1000 * 1e6);
        assertEq(borrowed, 1000 * 1e6);
        assertEq(underlying, 1 ether);
        assertGt(supply, 0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    REDEMPTION TESTS
    // ═══════════════════════════════════════════════════════════════

    function testRedeemLongToken() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        uint256 shares = longToken.mint(1000 * 1e6);

        uint256 usdcBefore = usdc.balanceOf(trader1);

        // Update swap router price to match (for accurate redemption)
        swapRouter.setPrice(SWAP_PRICE);

        vm.prank(trader1);
        uint256 returned = longToken.redeem(shares);

        assertGt(returned, 0);
        assertEq(longToken.balanceOf(trader1), 0);
        assertGt(usdc.balanceOf(trader1), usdcBefore);
    }

    function testRedeemShortToken() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        uint256 shares = shortToken.mint(1000 * 1e6);

        uint256 usdcBefore = usdc.balanceOf(trader1);

        vm.prank(trader1);
        uint256 returned = shortToken.redeem(shares);

        assertGt(returned, 0);
        assertEq(shortToken.balanceOf(trader1), 0);
        assertGt(usdc.balanceOf(trader1), usdcBefore);
    }

    function testRedeemLongWithProfit() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        vm.prank(trader1);
        uint256 shares = longToken.mint(1000 * 1e6);

        // Price goes up 10%
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 110 / 100));
        swapRouter.setPrice(SWAP_PRICE * 110 / 100);

        vm.prank(trader1);
        uint256 returned = longToken.redeem(shares);

        // Should get more than initial deposit (profit)
        assertGt(returned, 1000 * 1e6);
    }

    function testRedeemShortWithProfit() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        uint256 shares = shortToken.mint(1000 * 1e6);

        // Price goes DOWN 10% - good for shorts
        oracle.setPrice(int256(INITIAL_ETH_PRICE * 90 / 100));
        swapRouter.setPrice(SWAP_PRICE * 90 / 100);

        vm.prank(trader1);
        uint256 returned = shortToken.redeem(shares);

        // Should get more than initial deposit (profit)
        assertGt(returned, 1000 * 1e6);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    MULTI-TRADER TESTS
    // ═══════════════════════════════════════════════════════════════

    function testMultipleLongTraders() public {
        vm.prank(lp1);
        longVault.deposit(100000 * 1e6, lp1);

        // Trader 1 mints
        vm.prank(trader1);
        uint256 shares1 = longToken.mint(1000 * 1e6);

        // Trader 2 mints
        vm.prank(trader2);
        uint256 shares2 = longToken.mint(2000 * 1e6);

        assertEq(longToken.totalCollateral(), 3000 * 1e6);
        assertEq(longToken.totalBorrowed(), 3000 * 1e6);
        // 3000 collateral + 3000 borrowed = 6000 USDC swapped
        // At $2000/ETH: 6000 / 2000 = 3 ETH
        assertEq(longToken.totalUnderlying(), 3 ether);

        // Shares proportional to deposits
        assertEq(shares2, shares1 * 2);
    }

    function testMultipleShortTraders() public {
        vm.prank(lp1);
        shortVault.deposit(100 ether, lp1);

        vm.prank(trader1);
        uint256 shares1 = shortToken.mint(1000 * 1e6);

        vm.prank(trader2);
        uint256 shares2 = shortToken.mint(2000 * 1e6);

        assertEq(shortToken.totalCollateral(), 3000 * 1e6);
        assertEq(shortToken.totalBorrowed(), 3 ether); // 3x $2000 worth
        assertEq(shortToken.totalStableHeld(), 9000 * 1e6); // 3000 collateral + 6000 from selling 3 ETH

        assertEq(shares2, shares1 * 2);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    LP VAULT TESTS
    // ═══════════════════════════════════════════════════════════════

    function testVaultUtilizationLimit() public {
        vm.prank(lp1);
        longVault.deposit(10000 * 1e6, lp1);

        // Try to mint too much (would exceed 90% utilization)
        // Minting 10000 USDC would borrow 10000 USDC (2x leverage)
        // 10000 / 10000 = 100% > 90% max utilization
        vm.prank(trader1);
        vm.expectRevert("Exceeds max utilization");
        longToken.mint(10000 * 1e6);
    }

    function testVaultInterestAccrual() public {
        vm.prank(lp1);
        longVault.deposit(10000 * 1e6, lp1);

        vm.prank(trader1);
        longToken.mint(1000 * 1e6);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);
        longVault.accrueInterest();

        // Total assets should include accrued interest
        assertGt(longVault.totalAssets(), 10000 * 1e6);
    }

    function testShortVaultBorrowRepay() public {
        vm.prank(lp1);
        shortVault.deposit(10 ether, lp1);

        uint256 vaultBalanceBefore = weth.balanceOf(address(shortVault));

        vm.prank(trader1);
        shortToken.mint(1000 * 1e6);

        // Vault should have less WETH (lent out)
        assertLt(weth.balanceOf(address(shortVault)), vaultBalanceBefore);
        assertEq(shortVault.totalBorrowed(), 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SLIPPAGE TESTS
    // ═══════════════════════════════════════════════════════════════

    function testSetSlippageTolerance() public {
        longToken.setSlippageTolerance(200); // 2%
        assertEq(longToken.slippageTolerance(), 200);

        shortToken.setSlippageTolerance(300); // 3%
        assertEq(shortToken.slippageTolerance(), 300);
    }

    function testSlippageToleranceTooHigh() public {
        vm.expectRevert("Too high");
        longToken.setSlippageTolerance(1100); // 11% - too high
    }

    function testSetPoolFee() public {
        longToken.setPoolFee(500); // 0.05%
        assertEq(longToken.poolFee(), 500);
    }

    function testSetOracle() public {
        MockChainlinkOracle newOracle = new MockChainlinkOracle(3000 * 1e8, 8);
        longToken.setOracle(address(newOracle));
        assertEq(longToken.getPrice(), 3000 * 1e8);
    }
}
