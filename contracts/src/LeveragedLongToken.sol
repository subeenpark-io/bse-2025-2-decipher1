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

/// @title LeveragedLongToken - 2x Daily Leveraged Long Token
/// @notice Provides 2x daily leveraged LONG exposure to an underlying asset
/// @dev For 2x LONG: deposit USDC → borrow more USDC from LP vault → swap all to underlying
///
/// Example (ETH 2x Long):
/// 1. User deposits $1000 USDC
/// 2. Contract borrows $1000 USDC from LP vault (which holds USDC from LPs)
/// 3. Contract swaps $2000 USDC → ~1 ETH via Uniswap
/// 4. User has 2x ETH exposure on $1000 capital
/// 5. If ETH +10%, user gains +20%. If ETH -10%, user loses -20%
contract LeveragedLongToken is
    ERC20Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice The LP vault we borrow USDC from
    LPVault public lpVault;

    /// @notice Collateral/borrow token (USDC) - same as LP vault asset
    IERC20 public stableToken;

    /// @notice Underlying token (e.g., WETH) - what we buy for long exposure
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

    /// @notice Total stable borrowed from LP vault
    uint256 public totalBorrowed;

    /// @notice Total underlying held (from swaps)
    uint256 public totalUnderlying;

    /// @notice Minimum rebalance interval
    uint256 public constant MIN_REBALANCE_INTERVAL = 20 hours;

    /// @notice Slippage tolerance for swaps (100 = 1%)
    uint256 public slippageTolerance;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant BASIS_POINTS = 10000;

    uint8 public underlyingDecimals;
    uint8 public stableDecimals;
    uint8 public oracleDecimals;

    event Minted(address indexed user, uint256 stableIn, uint256 shares, uint256 underlyingBought);
    event Redeemed(address indexed user, uint256 shares, uint256 stableReturned);
    event Rebalanced(uint256 timestamp, uint256 oldNav, uint256 newNav);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the leveraged long token
    /// @param _name Token name (e.g., "ETH 2x Daily Long")
    /// @param _symbol Token symbol (e.g., "ETH2X")
    /// @param _lpVault LP vault holding USDC
    /// @param _underlyingToken Underlying token (WETH)
    /// @param _swapRouter Uniswap V3 swap router
    /// @param _oracle Chainlink price feed
    /// @param _poolFee Uniswap pool fee tier
    /// @param _leverageRatio Leverage in basis points (20000 = 2x)
    function initialize(
        string memory _name,
        string memory _symbol,
        address _lpVault,
        address _underlyingToken,
        address _swapRouter,
        address _oracle,
        uint24 _poolFee,
        uint256 _leverageRatio
    ) external initializer {
        require(_lpVault != address(0), "Invalid vault");
        require(_underlyingToken != address(0), "Invalid underlying");
        require(_swapRouter != address(0), "Invalid router");
        require(_oracle != address(0), "Invalid oracle");
        require(_leverageRatio >= BASIS_POINTS && _leverageRatio <= 50000, "Invalid leverage");

        __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        lpVault = LPVault(_lpVault);
        stableToken = IERC20(lpVault.asset()); // LP vault's asset is what we borrow
        underlyingToken = IERC20(_underlyingToken);
        swapRouter = ISwapRouter(_swapRouter);
        oracle = IChainlinkAggregator(_oracle);
        poolFee = _poolFee;
        leverageRatio = _leverageRatio;
        slippageTolerance = 100; // 1% default

        underlyingDecimals = ERC20Upgradeable(_underlyingToken).decimals();
        stableDecimals = ERC20Upgradeable(address(stableToken)).decimals();
        oracleDecimals = oracle.decimals();

        // Initialize NAV at 1 stable unit
        navPerShare = 10 ** stableDecimals;
        lastRebalancePrice = _getPrice();
        lastRebalanceTime = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    USER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Mint leveraged long tokens by depositing stablecoin
    /// @param stableAmount Amount of stable (USDC) to deposit
    /// @return shares Amount of leveraged token shares minted
    function mint(uint256 stableAmount) external nonReentrant whenNotPaused returns (uint256 shares) {
        require(stableAmount > 0, "Zero amount");

        // Transfer stable from user
        stableToken.safeTransferFrom(msg.sender, address(this), stableAmount);

        // Calculate shares based on current NAV
        uint256 currentNav = getCurrentNav();
        shares = (stableAmount * PRECISION) / currentNav;

        // Calculate how much to borrow for leverage
        // For 2x: borrow same amount as deposited
        uint256 borrowAmount = (stableAmount * (leverageRatio - BASIS_POINTS)) / BASIS_POINTS;

        // Borrow from LP vault
        if (borrowAmount > 0) {
            lpVault.borrow(borrowAmount);
            totalBorrowed += borrowAmount;
        }

        // Total stable to swap = deposit + borrowed
        uint256 totalToSwap = stableAmount + borrowAmount;

        // Swap stable → underlying
        uint256 underlyingReceived = _swapStableToUnderlying(totalToSwap);
        totalUnderlying += underlyingReceived;

        totalCollateral += stableAmount;
        _mint(msg.sender, shares);

        emit Minted(msg.sender, stableAmount, shares, underlyingReceived);
    }

    /// @notice Redeem leveraged tokens for stablecoin
    /// @param shares Amount of shares to redeem
    /// @return stableReturned Amount of stable returned
    function redeem(uint256 shares) external nonReentrant whenNotPaused returns (uint256 stableReturned) {
        require(shares > 0, "Zero shares");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");

        uint256 supply = totalSupply();
        require(supply > 0, "No supply");

        // Calculate proportional underlying to sell
        uint256 proportionalUnderlying = (totalUnderlying * shares) / supply;
        uint256 proportionalBorrowed = (totalBorrowed * shares) / supply;
        uint256 proportionalCollateral = (totalCollateral * shares) / supply;

        // Swap underlying → stable
        uint256 stableReceived = 0;
        if (proportionalUnderlying > 0) {
            stableReceived = _swapUnderlyingToStable(proportionalUnderlying);
            totalUnderlying -= proportionalUnderlying;
        }

        // Repay borrowed amount to LP vault
        if (proportionalBorrowed > 0 && stableReceived >= proportionalBorrowed) {
            stableToken.forceApprove(address(lpVault), proportionalBorrowed);
            lpVault.repay(proportionalBorrowed);
            totalBorrowed -= proportionalBorrowed;
            stableReceived -= proportionalBorrowed;
        }

        // Update state
        totalCollateral -= proportionalCollateral;
        _burn(msg.sender, shares);

        // Return remaining stable to user
        stableReturned = stableReceived;
        if (stableReturned > 0) {
            stableToken.safeTransfer(msg.sender, stableReturned);
        }

        emit Redeemed(msg.sender, shares, stableReturned);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SWAP FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Swap stable → underlying via Uniswap V3
    function _swapStableToUnderlying(uint256 stableAmount) internal returns (uint256 underlyingReceived) {
        if (stableAmount == 0) return 0;

        stableToken.forceApprove(address(swapRouter), stableAmount);

        // Calculate minimum output with slippage
        uint256 price = _getPrice();
        uint256 expectedUnderlying = (stableAmount * (10 ** underlyingDecimals) * (10 ** oracleDecimals))
            / (price * (10 ** stableDecimals));
        uint256 minOut = (expectedUnderlying * (BASIS_POINTS - slippageTolerance)) / BASIS_POINTS;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(stableToken),
            tokenOut: address(underlyingToken),
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: stableAmount,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        underlyingReceived = swapRouter.exactInputSingle(params);
    }

    /// @notice Swap underlying → stable via Uniswap V3
    function _swapUnderlyingToStable(uint256 underlyingAmount) internal returns (uint256 stableReceived) {
        if (underlyingAmount == 0) return 0;

        underlyingToken.forceApprove(address(swapRouter), underlyingAmount);

        // Calculate minimum output with slippage
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

        // Calculate leveraged return based on price change
        int256 priceChange = int256(currentPrice) - int256(lastRebalancePrice);
        int256 percentChange = (priceChange * int256(PRECISION)) / int256(lastRebalancePrice);
        int256 leveragedReturn = (int256(leverageRatio) * percentChange) / int256(BASIS_POINTS);

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
        int256 leveragedReturn = (int256(leverageRatio) * percentChange) / int256(BASIS_POINTS);

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
            uint256 underlyingHeld,
            uint256 supply
        )
    {
        return (getCurrentNav(), _getPrice(), totalCollateral, totalBorrowed, totalUnderlying, totalSupply());
    }

    // ═══════════════════════════════════════════════════════════════
    //                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function setLeverageRatio(uint256 _leverageRatio) external onlyOwner {
        require(_leverageRatio >= BASIS_POINTS && _leverageRatio <= 50000, "Invalid leverage");
        leverageRatio = _leverageRatio;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance <= 1000, "Too high"); // Max 10%
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
