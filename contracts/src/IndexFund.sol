// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IIndexFund.sol";

/// @title IndexFund - Multi-token index fund implementing ERC-4626
/// @dev UUPS upgradeable, requires price oracle for production use
contract IndexFund is ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable, IIndexFund {
    using SafeERC20 for IERC20;

    TokenAllocation[] private allocations;
    mapping(address => bool) public isAllocatedToken;

    uint256 public managementFee;
    uint256 public lastFeeCollection;
    uint256 public slippageTolerance;

    ISwapRouter public swapRouter;
    address public treasury;

    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        TokenAllocation[] memory _allocations,
        uint256 _managementFee,
        address _swapRouter,
        address _treasury
    ) external initializer {
        require(_managementFee <= 1000, "Fee too high");
        require(_swapRouter != address(0), "Invalid router");
        require(_treasury != address(0), "Invalid treasury");

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Ownable_init(msg.sender);
        __Pausable_init();

        managementFee = _managementFee;
        swapRouter = ISwapRouter(_swapRouter);
        treasury = _treasury;
        lastFeeCollection = block.timestamp;
        slippageTolerance = 100;

        _updateAllocations(_allocations);
    }

    function getAllocations() external view override returns (TokenAllocation[] memory) {
        return allocations;
    }

    function updateAllocations(TokenAllocation[] calldata newAllocations) external override onlyOwner {
        _updateAllocations(newAllocations);
    }

    function _updateAllocations(TokenAllocation[] memory newAllocations) internal {
        uint256 i;
        for (i = 0; i < allocations.length; ++i) {
            isAllocatedToken[allocations[i].token] = false;
        }
        delete allocations;

        uint256 totalPercentage;
        for (i = 0; i < newAllocations.length; ++i) {
            require(newAllocations[i].token != address(0), "Invalid token");
            require(!isAllocatedToken[newAllocations[i].token], "Duplicate token");

            allocations.push(newAllocations[i]);
            isAllocatedToken[newAllocations[i].token] = true;
            totalPercentage += newAllocations[i].targetPercentage;

            emit AllocationUpdated(newAllocations[i].token, newAllocations[i].targetPercentage);
        }

        require(totalPercentage == BASIS_POINTS, "Total must be 100%");
    }

    function rebalance(bytes[] calldata swapData) external override onlyOwner whenNotPaused {
        uint256 totalValue = totalAssets();
        uint256 allocLen = allocations.length;

        for (uint256 i; i < allocLen; ++i) {
            if (i >= swapData.length || swapData[i].length == 0) continue;

            TokenAllocation memory alloc = allocations[i];
            uint256 currentAmount = IERC20(alloc.token).balanceOf(address(this));
            uint256 targetAmount = (totalValue * alloc.targetPercentage) / BASIS_POINTS;

            if (currentAmount > targetAmount) {
                IERC20(alloc.token).safeIncreaseAllowance(address(swapRouter), currentAmount - targetAmount);
            }

            (bool success,) = address(swapRouter).call(swapData[i]);
            require(success, "Swap failed");
        }

        emit Rebalanced(msg.sender, block.timestamp);
    }

    function collectFees() external override {
        uint256 timeSinceLastCollection = block.timestamp - lastFeeCollection;
        if (timeSinceLastCollection == 0) return;

        uint256 supply = totalSupply();
        if (supply == 0) return;

        uint256 feeShares = (supply * managementFee * timeSinceLastCollection) / (SECONDS_PER_YEAR * BASIS_POINTS);

        if (feeShares > 0) {
            _mint(treasury, feeShares);
            emit FeeCollected(feeShares, block.timestamp);
        }

        lastFeeCollection = block.timestamp;
    }

    function getFundInfo() external view override returns (FundInfo memory) {
        return FundInfo({
            name: name(),
            symbol: symbol(),
            allocations: allocations,
            totalAssets: totalAssets(),
            totalShares: totalSupply(),
            managementFee: managementFee,
            lastFeeCollection: lastFeeCollection
        });
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        for (uint256 i; i < allocations.length; ++i) {
            total += IERC20(allocations[i].token).balanceOf(address(this));
        }
        return total;
    }

    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256 assets) {
        assets = super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
    }

    function setSlippageTolerance(uint256 _slippageTolerance) external onlyOwner {
        require(_slippageTolerance <= 1000, "Slippage too high");
        slippageTolerance = _slippageTolerance;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Pause the contract, blocking deposits, withdrawals, and rebalancing
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }
}
