# Index Fund Contracts

Decentralized index fund smart contracts built with Foundry, OpenZeppelin, and Uniswap V3.

## Overview

This project implements a decentralized index fund platform with:
- **Multi-token index funds** using ERC-4626 standard
- **Leveraged ETFs** (2x long/short) with LP vaults for liquidity
- **Share-based governance** for fund management
- **Automated rebalancing** with Uniswap V3
- **Chainlink oracles** for price feeds
- **Management fees** with continuous accrual
- **UUPS upgradeability** for all contracts

## Contracts

### Core Contracts

- **IndexFund.sol** - ERC-4626 vault holding multiple tokens with target allocations
- **FundFactory.sol** - Factory for deploying and managing index funds
- **FundGovernance.sol** - Governance system with share-based voting

### Leveraged ETF Contracts

- **LPVault.sol** - ERC-4626 vault for liquidity providers to deposit assets and earn interest
- **LeveragedLongToken.sol** - 2x daily leveraged long token (e.g., ETH2X)
- **LeveragedShortToken.sol** - 2x daily leveraged short token (e.g., ETH-2X)

### Key Features

- Multi-token portfolios with configurable allocations
- Deposit/withdraw in base asset (e.g., USDC)
- Admin rebalancing via Uniswap V3
- Management fee collection (e.g., 2% annual)
- Governance proposals for fund creation, delisting, and allocation updates
- UUPS proxy pattern for upgradeability

## Setup

### Prerequisites

- Foundry installed in WSL
- Private key for deployment
- Base Sepolia RPC URL

### Installation

```bash
# Install dependencies (run in WSL)
cd /mnt/d/projects/bsu/contracts
~/.foundry/bin/forge install
```

### Environment Variables

Create a `.env` file:

```bash
PRIVATE_KEY=0xyour_private_key_here
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
ETHERSCAN_API_KEY=your_api_key_here
```

## Testing

```bash
# Run all tests (in WSL)
~/.foundry/bin/forge test

# Run with verbosity
~/.foundry/bin/forge test -vvv

# Run specific test
~/.foundry/bin/forge test --match-test testDeposit
```

## Deployment

### Deploy to Base Sepolia

```bash
# Run deployment script (in WSL)
~/.foundry/bin/forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# Deployment addresses saved to: deployments/base-sepolia.json
```

## Admin Operations

### Rebalance Fund

```bash
# Rebalance specific fund
~/.foundry/bin/forge script script/Rebalance.s.sol:RebalanceScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --sig "run(address)" <FUND_ADDRESS>
```

### Collect Fees

```bash
# Collect fees for all funds
~/.foundry/bin/forge script script/CollectFees.s.sol:CollectFeesScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --sig "run(address)" <FACTORY_ADDRESS>
```

## Architecture

### Upgradeability

All contracts use UUPS (Universal Upgradeable Proxy Standard):
- Logic in implementation contract
- State in proxy contract
- Upgrade authorized by owner only

### Token Flow

1. Users deposit base asset (USDC)
2. Fund mints shares (ERC-4626)
3. Admin rebalances to match target allocations
4. Fees accrue continuously
5. Users can withdraw proportional assets

### Governance

1. Share holders create proposals
2. Voting weighted by share ownership
3. Quorum and majority required
4. Successful proposals executed by anyone

## Leveraged ETF Architecture

### 2x Long Token (ETH2X)

The long token provides 2x leveraged exposure to price increases:

1. User deposits USDC as collateral
2. Contract borrows equal USDC from LP vault (for 2x leverage)
3. All USDC swapped to underlying (e.g., WETH) via Uniswap V3
4. User receives shares representing their leveraged position

**Example**: $1000 USDC deposit → $2000 total exposure → If ETH +10%, user gains +20%

### 2x Short Token (ETH-2X)

The short token provides 2x leveraged exposure to price decreases:

1. User deposits USDC as collateral
2. Contract calculates 2x exposure in underlying terms
3. Borrows underlying (WETH) from LP vault
4. Sells borrowed WETH for USDC
5. User receives shares representing their short position

**Example**: $1000 USDC deposit → Borrow 1 ETH ($2000) → Sell to USDC → If ETH -10%, user gains +20%

### LP Vault

Liquidity providers earn interest by supplying assets to the vault:

- Long vaults hold stablecoin (USDC) - lent to long traders
- Short vaults hold underlying (WETH) - lent to short traders
- 90% max utilization to ensure liquidity for withdrawals
- Interest accrues continuously based on utilization

### Daily Rebalancing

Leveraged tokens require daily rebalancing to maintain target leverage:

- Rebalance window: every 20+ hours
- NAV recalculated based on oracle price changes
- Owner can force rebalance anytime

## Security

- OpenZeppelin battle-tested contracts
- Reentrancy guards on critical functions
- Access control (Ownable)
- Pausable emergency stop for all contracts
- Slippage protection on swaps
- Fee limits (max 10%)
- Oracle staleness checks (1 hour mainnet, 24 hours testnet)

## Base Sepolia Addresses

### Uniswap V3
- SwapRouter: `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4`
- Quoter: `0xC5290058841028F1614F3A6F0F5816cAd0df5E27`

### Tokens
- WETH: `0x4200000000000000000000000000000000000006`
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

### Chainlink Oracles
- ETH/USD: `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1`

## Deploying Leveraged ETFs

```bash
# Deploy long and short ETF tokens
forge script script/DeployLeveraged.s.sol:DeployLeveragedScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify

# Deployment addresses saved to: deployments/leveraged-etfs.json
```

## License

MIT
