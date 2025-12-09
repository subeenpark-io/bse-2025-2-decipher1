// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LPVault - Liquidity Provider Vault for Token Lending
/// @notice LPs deposit tokens (e.g., WBTC) to earn yield from leveraged token borrowers
/// @dev Simple lending vault - LPs earn interest, no delta risk management needed
///
/// How it works:
/// 1. LPs deposit WBTC, receive LP shares
/// 2. Leveraged tokens borrow WBTC to provide user exposure
/// 3. Borrowers pay interest, which accrues to LP shares
/// 4. LPs can withdraw anytime (subject to utilization)
contract LPVault is ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Total tokens currently borrowed by leveraged products
    uint256 public totalBorrowed;

    /// @notice Accumulated interest owed (updated on interactions)
    uint256 public accumulatedInterest;

    /// @notice Last time interest was accrued
    uint256 public lastAccrualTime;

    /// @notice Annual interest rate in basis points (e.g., 500 = 5%)
    uint256 public interestRateBps;

    /// @notice Maximum utilization allowed (e.g., 9000 = 90%)
    uint256 public maxUtilizationBps;

    /// @notice Authorized borrowers (leveraged token contracts)
    mapping(address => bool) public authorizedBorrowers;

    /// @notice Amount borrowed by each borrower
    mapping(address => uint256) public borrowerDebt;

    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed borrower, uint256 principal, uint256 interest);
    event InterestAccrued(uint256 interest, uint256 timestamp);
    event BorrowerAuthorized(address indexed borrower);
    event BorrowerRevoked(address indexed borrower);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the LP vault
    /// @param _asset The token LPs will deposit (e.g., WBTC)
    /// @param _name Vault share name
    /// @param _symbol Vault share symbol
    /// @param _interestRateBps Annual interest rate in basis points
    function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _interestRateBps
    ) external initializer {
        require(_asset != address(0), "Invalid asset");
        require(_interestRateBps <= 5000, "Interest too high"); // Max 50% APY

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Ownable_init(msg.sender);
        __Pausable_init();

        interestRateBps = _interestRateBps;
        maxUtilizationBps = 9000; // 90% max utilization
        lastAccrualTime = block.timestamp;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    LP FUNCTIONS (ERC4626)
    // ═══════════════════════════════════════════════════════════════

    /// @notice Total assets = deposited + accrued interest - borrowed
    /// @dev Borrowed tokens are still "owned" by vault, just lent out
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalBorrowed + accumulatedInterest + _pendingInterest();
    }

    /// @notice Available liquidity for new borrows or withdrawals
    function availableLiquidity() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Current utilization rate in basis points
    function utilizationRate() public view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalBorrowed * BASIS_POINTS) / total;
    }

    /// @notice Override deposit to accrue interest first
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        _accrueInterest();
        return super.deposit(assets, receiver);
    }

    /// @notice Override withdraw to accrue interest and check liquidity
    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _accrueInterest();
        require(assets <= availableLiquidity(), "Insufficient liquidity");
        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Override redeem to accrue interest and check liquidity
    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _accrueInterest();
        uint256 assets = previewRedeem(shares);
        require(assets <= availableLiquidity(), "Insufficient liquidity");
        return super.redeem(shares, receiver, owner);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    BORROWER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Borrow tokens from the vault
    /// @param amount Amount of tokens to borrow
    function borrow(uint256 amount) external whenNotPaused {
        _accrueInterest();

        require(amount > 0, "Zero amount");
        require(amount <= availableLiquidity(), "Insufficient liquidity");

        // Check utilization after borrow
        uint256 newUtilization = ((totalBorrowed + amount) * BASIS_POINTS) / totalAssets();
        require(newUtilization <= maxUtilizationBps, "Exceeds max utilization");

        totalBorrowed += amount;
        borrowerDebt[msg.sender] += amount;

        IERC20(asset()).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    /// @notice Repay borrowed tokens (principal only, interest accrues to LP shares)
    /// @param principalAmount Principal amount being repaid
    /// @dev Interest is not collected per-repayment; it accrues to totalAssets for LP benefit
    function repay(uint256 principalAmount) external whenNotPaused {
        _accrueInterest();

        require(principalAmount > 0, "Zero amount");
        require(principalAmount <= borrowerDebt[msg.sender], "Exceeds debt");

        // Update state
        totalBorrowed -= principalAmount;
        borrowerDebt[msg.sender] -= principalAmount;

        // Transfer principal from borrower (interest stays accrued for LPs)
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), principalAmount);

        emit Repaid(msg.sender, principalAmount, 0);
    }

    /// @notice Repay with explicit interest payment
    /// @param principalAmount Principal to repay
    /// @param interestAmount Interest to pay
    function repayWithInterest(uint256 principalAmount, uint256 interestAmount) external whenNotPaused {
        _accrueInterest();

        require(principalAmount > 0, "Zero amount");
        require(principalAmount <= borrowerDebt[msg.sender], "Exceeds debt");

        // Update state
        totalBorrowed -= principalAmount;
        borrowerDebt[msg.sender] -= principalAmount;

        // Reduce accumulated interest by amount paid
        if (interestAmount > 0 && interestAmount <= accumulatedInterest) {
            accumulatedInterest -= interestAmount;
        }

        // Transfer principal + interest from borrower
        uint256 totalRepayment = principalAmount + interestAmount;
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), totalRepayment);

        emit Repaid(msg.sender, principalAmount, interestAmount);
    }

    /// @notice Get total debt (principal + interest) for a borrower
    function getDebt(address borrower) external view returns (uint256 principal, uint256 interest) {
        principal = borrowerDebt[borrower];
        if (totalBorrowed > 0 && principal > 0) {
            interest = ((accumulatedInterest + _pendingInterest()) * principal) / totalBorrowed;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    INTEREST ACCRUAL
    // ═══════════════════════════════════════════════════════════════

    /// @notice Calculate pending interest since last accrual
    function _pendingInterest() internal view returns (uint256) {
        if (totalBorrowed == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastAccrualTime;
        // interest = borrowed * rate * time / (year * basisPoints)
        return (totalBorrowed * interestRateBps * timeElapsed) / (SECONDS_PER_YEAR * BASIS_POINTS);
    }

    /// @notice Accrue interest to the vault
    function _accrueInterest() internal {
        uint256 pending = _pendingInterest();
        if (pending > 0) {
            accumulatedInterest += pending;
            emit InterestAccrued(pending, block.timestamp);
        }
        lastAccrualTime = block.timestamp;
    }

    /// @notice Public function to accrue interest (can be called by keepers)
    function accrueInterest() external {
        _accrueInterest();
    }

    // ═══════════════════════════════════════════════════════════════
    //                    ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Authorize a leveraged token contract to borrow
    function authorizeBorrower(address borrower) external onlyOwner {
        require(borrower != address(0), "Invalid borrower");
        authorizedBorrowers[borrower] = true;
        emit BorrowerAuthorized(borrower);
    }

    /// @notice Revoke borrower authorization
    function revokeBorrower(address borrower) external onlyOwner {
        authorizedBorrowers[borrower] = false;
        emit BorrowerRevoked(borrower);
    }

    /// @notice Update interest rate
    function setInterestRate(uint256 _interestRateBps) external onlyOwner {
        _accrueInterest();
        require(_interestRateBps <= 5000, "Interest too high");
        interestRateBps = _interestRateBps;
    }

    /// @notice Update max utilization
    function setMaxUtilization(uint256 _maxUtilizationBps) external onlyOwner {
        require(_maxUtilizationBps <= BASIS_POINTS, "Invalid utilization");
        maxUtilizationBps = _maxUtilizationBps;
    }

    /// @notice Pause all vault operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause all vault operations
    function unpause() external onlyOwner {
        _unpause();
    }

    modifier onlyAuthorizedBorrower() {
        require(authorizedBorrowers[msg.sender], "Not authorized");
        _;
    }

    /// @notice UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
