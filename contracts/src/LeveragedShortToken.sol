// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IChainlinkAggregator.sol";
import "./utils/ReentrancyGuardUpgradeable.sol";
import "./LPVault.sol";

/// @title LeveragedShortToken - 2x Daily Leveraged Short Token
/// @notice Provides 2x daily leveraged SHORT exposure to an underlying asset
/// @dev For 2x SHORT: deposit USDC → borrow underlying from LP vault → sell for USDC
///
/// Example (ETH 2x Short):
/// 1. User deposits $1000 USDC
/// 2. Contract borrows 1 ETH ($2000) from LP vault (which holds WETH from LPs)
/// 3. Contract sells 1 ETH → $2000 USDC via Uniswap
/// 4. Contract now holds $3000 USDC, owes 1 ETH
/// 5. If ETH -10%, debt worth $1800, NAV = $3000 - $1800 = $1200 (+20%)
/// 6. If ETH +10%, debt worth $2200, NAV = $3000 - $2200 = $800 (-20%)
contract LeveragedShortToken is
    ERC20Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice The LP vault we borrow underlying from
    LPVault public lpVault;

    /// @notice Stable token for collateral (USDC)
    IERC20 public stableToken;

    /// @notice Underlying token (e.g., WETH) - what we borrow and short
    IERC20 public underlyingToken;

    /// @notice Uniswap V3 swap router
    ISwapRouter public swapRouter;

    /// @notice Price oracle for underlying/USD
    IChainlinkAggregator public oracle;

    /// @notice Uniswap pool fee (3000 = 0.3%)
    uint24 public poolFee;

    /// @notice Target leverage ratio (20000 = 2x)
    uint256 public leverageRatio;

    /// @notice NAV per share (scaled by 1e18)
    uint256 public navPerShare;

    /// @notice Reference price at last rebalance
    uint256 public lastRebalancePrice;

    /// @notice Timestamp of last rebalance
    uint256 public lastRebalanceTime;

    /// @notice Total stable deposited as collateral
    uint256 public totalCollateral;

    /// @notice Total underlying borrowed from LP vault (debt in underlying units)
    uint256 public totalBorrowed;

    /// @notice Total stable held (collateral + proceeds from selling borrowed underlying)
    uint256 public totalStableHeld;

    /// @notice Minimum rebalance interval
    uint256 public constant MIN_REBALANCE_INTERVAL = 20 hours;

    /// @notice Slippage tolerance for swaps (100 = 1%)
    uint256 public slippageTolerance;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;

    uint8 public underlyingDecimals;
    uint8 public stableDecimals;
    uint8 public oracleDecimals;

    event Minted(address indexed user, uint256 stableIn, uint256 shares, uint256 underlyingBorrowed);
    event Redeemed(address indexed user, uint256 shares, uint256 stableReturned);
    event Rebalanced(uint256 timestamp, uint256 oldNav, uint256 newNav);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the leveraged short token
    /// @param _name Token name (e.g., "ETH 2x Daily Short")
    /// @param _symbol Token symbol (e.g., "ETH-2X")
    /// @param _lpVault LP vault holding underlying (WETH)
    /// @param _stableToken Stable token for collateral (USDC)
    /// @param _swapRouter Uniswap V3 swap router
    /// @param _oracle Chainlink price feed
    /// @param _poolFee Uniswap pool fee tier
    /// @param _leverageRatio Leverage in basis points (20000 = 2x)
    function initialize(
        string memory _name,
        string memory _symbol,
        address _lpVault,
        address _stableToken,
        address _swapRouter,
        address _oracle,
        uint24 _poolFee,
        uint256 _leverageRatio
    ) external initializer {
        require(_lpVault != address(0), "Invalid vault");
        require(_stableToken != address(0), "Invalid stable");
        require(_swapRouter != address(0), "Invalid router");
        require(_oracle != address(0), "Invalid oracle");
        require(_leverageRatio >= BASIS_POINTS && _leverageRatio <= 50000, "Invalid leverage");

        __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        lpVault = LPVault(_lpVault);
        underlyingToken = IERC20(lpVault.asset()); // LP vault's asset is what we borrow (WETH)
        stableToken = IERC20(_stableToken);
        swapRouter = ISwapRouter(_swapRouter);
        oracle = IChainlinkAggregator(_oracle);
        poolFee = _poolFee;
        leverageRatio = _leverageRatio;
        slippageTolerance = 100; // 1% default

        underlyingDecimals = ERC20Upgradeable(address(underlyingToken)).decimals();
        stableDecimals = ERC20Upgradeable(_stableToken).decimals();
        oracleDecimals = oracle.decimals();

        // Initialize NAV at 1 stable unit
        navPerShare = 10 ** stableDecimals;
        lastRebalancePrice = _getPrice();
        lastRebalanceTime = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    USER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Mint leveraged short tokens by depositing stablecoin
    /// @param stableAmount Amount of stable (USDC) to deposit
    /// @return shares Amount of leveraged token shares minted
    function mint(uint256 stableAmount) external nonReentrant whenNotPaused returns (uint256 shares) {
        require(stableAmount > 0, "Zero amount");

        // Transfer stable from user
        stableToken.safeTransferFrom(msg.sender, address(this), stableAmount);

        // Calculate shares based on current NAV
        uint256 currentNav = getCurrentNav();
        shares = (stableAmount * PRECISION) / currentNav;

        // Calculate how much underlying to borrow for 2x short exposure
        // For 2x short with $1000 collateral, we want $2000 short exposure
        // So borrow $2000 worth of ETH
        uint256 price = _getPrice();
        uint256 exposureUsd = (stableAmount * leverageRatio) / BASIS_POINTS;
        uint256 underlyingToBorrow = (exposureUsd * (10 ** underlyingDecimals) * (10 ** oracleDecimals))
            / (price * (10 ** stableDecimals));

        // Borrow underlying from LP vault
        if (underlyingToBorrow > 0) {
            lpVault.borrow(underlyingToBorrow);
            totalBorrowed += underlyingToBorrow;

            // Sell borrowed underlying for stable
            uint256 stableReceived = _swapUnderlyingToStable(underlyingToBorrow);
            totalStableHeld += stableReceived;
        }

        totalCollateral += stableAmount;
        totalStableHeld += stableAmount;
        _mint(msg.sender, shares);

        emit Minted(msg.sender, stableAmount, shares, underlyingToBorrow);
    }

    /// @notice Redeem leveraged tokens for stablecoin
    /// @param shares Amount of shares to redeem
    /// @return stableReturned Amount of stable returned
    function redeem(uint256 shares) external nonReentrant whenNotPaused returns (uint256 stableReturned) {
        require(shares > 0, "Zero shares");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");

        uint256 supply = totalSupply();
        require(supply > 0, "No supply");

        // Calculate proportional amounts
        uint256 proportionalBorrowed = (totalBorrowed * shares) / supply;
        uint256 proportionalCollateral = (totalCollateral * shares) / supply;
        uint256 proportionalStableHeld = (totalStableHeld * shares) / supply;

        // Buy back underlying to repay debt
        if (proportionalBorrowed > 0) {
            uint256 stableNeeded = _swapStableToUnderlying(proportionalBorrowed);
            totalStableHeld -= stableNeeded;

            // Repay borrowed underlying to LP vault
            underlyingToken.forceApprove(address(lpVault), proportionalBorrowed);
            lpVault.repay(proportionalBorrowed);
            totalBorrowed -= proportionalBorrowed;
        }

        // Calculate remaining stable to return
        // NAV-based calculation
        uint256 currentNav = getCurrentNav();
        stableReturned = (shares * currentNav) / PRECISION;

        // Cap at available
        uint256 available = stableToken.balanceOf(address(this));
        if (stableReturned > available) {
            stableReturned = available;
        }

        // Update state
        totalCollateral -= proportionalCollateral;
        totalStableHeld = stableToken.balanceOf(address(this)) - stableReturned;
        _burn(msg.sender, shares);

        // Transfer stable to user
        if (stableReturned > 0) {
            stableToken.safeTransfer(msg.sender, stableReturned);
        }

        emit Redeemed(msg.sender, shares, stableReturned);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SWAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Swap underlying → stable via Uniswap V3 (sell short)
    function _swapUnderlyingToStable(uint256 underlyingAmount) internal returns (uint256 stableReceived) {
        if (underlyingAmount == 0) return 0;

        underlyingToken.forceApprove(address(swapRouter), underlyingAmount);

        uint256 price = _getPrice();
        uint256 expectedStable = (underlyingAmount * price * (10 ** stableDecimals))
            / ((10 ** underlyingDecimals) * (10 ** oracleDecimals));
        uint256 minOut = (expectedStable * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(underlyingToken),
            tokenOut: address(stableToken),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: underlyingAmount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        stableReceived = swapRouter.exactInputSingle(params);
    }

    /// @notice Swap stable → underlying via Uniswap V3 (buy to close short)
    /// @return stableSpent Amount of stable spent
    function _swapStableToUnderlying(uint256 underlyingNeeded) internal returns (uint256 stableSpent) {
        if (underlyingNeeded == 0) return 0;

        // Calculate expected stable cost
        uint256 price = _getPrice();
        uint256 expectedCost = (underlyingNeeded * price * (10 ** stableDecimals))
            / ((10 ** underlyingDecimals) * (10 ** oracleDecimals));
        uint256 maxIn = (expectedCost * (BASIS_POINTS + slippageTolerance)) / BASIS_POINTS;

        stableToken.forceApprove(address(swapRouter), maxIn);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(stableToken),
            tokenOut: address(underlyingToken),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: underlyingNeeded,
            amountInMaximum: maxIn,
            sqrtPriceLimitX96: 0
        });

        stableSpent = swapRouter.exactOutputSingle(params);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    REBALANCING
    // ═══════════════════════════════════════════════════════════════

    /// @notice Daily rebalance to maintain leverage ratio
    function rebalance() external nonReentrant whenNotPaused {
        require(block.timestamp >= lastRebalanceTime + MIN_REBALANCE_INTERVAL, "Too soon");
        _rebalance();
    }

    /// @notice Force rebalance (owner only, no time restriction)
    function forceRebalance() external onlyOwner {
        _rebalance();
    }

    function _rebalance() internal {
        uint256 oldNav = navPerShare;
        uint256 currentPrice = _getPrice();

        // For SHORT: inverse relationship - price up = loss, price down = gain
        int256 priceChange = int256(currentPrice) - int256(lastRebalancePrice);
        int256 percentChange = (priceChange * int256(PRECISION)) / int256(lastRebalancePrice);
        // Negative because we're short
        int256 leveragedReturn = -(int256(leverageRatio) * percentChange) / int256(BASIS_POINTS);

        // Update NAV
        int256 newNavSigned = int256(navPerShare) + (int256(navPerShare) * leveragedReturn) / int256(PRECISION);
        uint256 newNav = newNavSigned > 0 ? uint256(newNavSigned) : 1;

        navPerShare = newNav;
        lastRebalancePrice = currentPrice;
        lastRebalanceTime = block.timestamp;

        emit Rebalanced(block.timestamp, oldNav, newNav);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get current NAV (includes unrealized gains/losses)
    function getCurrentNav() public view returns (uint256) {
        if (lastRebalancePrice == 0) return navPerShare;

        uint256 currentPrice = _getPrice();
        int256 priceChange = int256(currentPrice) - int256(lastRebalancePrice);
        int256 percentChange = (priceChange * int256(PRECISION)) / int256(lastRebalancePrice);
        // Negative for short
        int256 leveragedReturn = -(int256(leverageRatio) * percentChange) / int256(BASIS_POINTS);

        int256 currentNav = int256(navPerShare) + (int256(navPerShare) * leveragedReturn) / int256(PRECISION);
        return currentNav > 0 ? uint256(currentNav) : 1;
    }

    function _getPrice() internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
        require(answer > 0, "Invalid price");
        require(updatedAt > 0, "Stale price");

        if (block.chainid != 1) {
            require(block.timestamp - updatedAt <= 24 hours, "Price too stale");
        } else {
            require(block.timestamp - updatedAt <= 1 hours, "Price too stale");
        }

        return uint256(answer);
    }

    function getPrice() external view returns (uint256) {
        return _getPrice();
    }

    function needsRebalance() external view returns (bool) {
        return block.timestamp >= lastRebalanceTime + MIN_REBALANCE_INTERVAL;
    }

    function getStats()
        external
        view
        returns (
            uint256 currentNav,
            uint256 price,
            uint256 collateral,
            uint256 borrowed,
            uint256 stableHeld,
            uint256 supply
        )
    {
        return (getCurrentNav(), _getPrice(), totalCollateral, totalBorrowed, totalStableHeld, totalSupply());
    }

    // ═══════════════════════════════════════════════════════════════
    //                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function setLeverageRatio(uint256 _leverageRatio) external onlyOwner {
        require(_leverageRatio >= BASIS_POINTS && _leverageRatio <= 50000, "Invalid leverage");
        leverageRatio = _leverageRatio;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance <= 1000, "Too high");
        slippageTolerance = _slippageTolerance;
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        oracle = IChainlinkAggregator(_oracle);
        oracleDecimals = oracle.decimals();
    }

    function setPoolFee(uint24 _poolFee) external onlyOwner {
        poolFee = _poolFee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
