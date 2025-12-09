// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _decimals = 18;
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockSwapRouter {
    function exactInputSingle(address, uint256, uint256, address, uint256, address, uint256, uint256)
        external
        returns (uint256)
    {
        return 0;
    }
}

/// @notice Mock Uniswap V3 Swap Router for testing leveraged tokens
/// @dev Simulates swaps using a configurable price
contract MockUniswapRouter {
    IERC20 public tokenA; // e.g., USDC
    IERC20 public tokenB; // e.g., WETH
    uint256 public price; // tokenB price in tokenA units (e.g., 2000 * 1e6 for $2000 USDC per WETH)
    uint8 public tokenADecimals;
    uint8 public tokenBDecimals;

    constructor(address _tokenA, address _tokenB, uint256 _price, uint8 _tokenADecimals, uint8 _tokenBDecimals) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        price = _price;
        tokenADecimals = _tokenADecimals;
        tokenBDecimals = _tokenBDecimals;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    /// @notice Swap exact amount of tokenIn for tokenOut
    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        if (params.tokenIn == address(tokenA)) {
            // Swapping USDC -> WETH: amountOut = amountIn / price
            amountOut = (params.amountIn * (10 ** tokenBDecimals)) / price;
        } else {
            // Swapping WETH -> USDC: amountOut = amountIn * price
            amountOut = (params.amountIn * price) / (10 ** tokenBDecimals);
        }

        require(amountOut >= params.amountOutMinimum, "Slippage");

        // Mint output token to recipient (simulating swap)
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }

    /// @notice Swap tokenIn for exact amount of tokenOut
    function exactOutputSingle(ExactOutputSingleParams calldata params) external returns (uint256 amountIn) {
        if (params.tokenOut == address(tokenB)) {
            // Buying WETH with USDC: amountIn = amountOut * price
            amountIn = (params.amountOut * price) / (10 ** tokenBDecimals);
        } else {
            // Buying USDC with WETH: amountIn = amountOut / price
            amountIn = (params.amountOut * (10 ** tokenBDecimals)) / price;
        }

        require(amountIn <= params.amountInMaximum, "Slippage");

        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(params.tokenOut).mint(params.recipient, params.amountOut);
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }
}

/// @notice Mock Chainlink Price Feed for testing
contract MockChainlinkOracle {
    int256 public price;
    uint8 public decimals;
    uint256 public updatedAt;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound)
    {
        return (1, price, block.timestamp, updatedAt, 1);
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
