// ============================================
// INDEX FUND MODULE
// ============================================

export const INDEX_FUND_ABI = [
  // ERC-4626 Standard
  "function deposit(uint256 assets, address receiver) returns (uint256 shares)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)",
  "function mint(uint256 shares, address receiver) returns (uint256 assets)",

  // View functions
  "function balanceOf(address account) view returns (uint256)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",

  // Index Fund specific
  "function getAllocations() view returns (address[] tokens, uint256[] weights)",
  "function getTokens() view returns (address[])",
  "function managementFeeRate() view returns (uint256)",
  "function lastFeeCollection() view returns (uint256)",
  "function accruedFees() view returns (uint256)",

  // Owner functions
  "function collectFees() external",
  "function setAllocations(address[] tokens, uint256[] weights) external",
  "function rebalance() external",
] as const;

export const FUND_FACTORY_ABI = [
  "function getAllFunds() view returns (address[])",
  "function getFundCount() view returns (uint256)",
  "function isFund(address) view returns (bool)",
  "function owner() view returns (address)",
] as const;

// For createFund - uses struct, need JSON ABI
export const FUND_FACTORY_CREATE_ABI = [
  {
    name: "createFund",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" },
      { name: "symbol", type: "string" },
      { name: "asset", type: "address" },
      {
        name: "allocations",
        type: "tuple[]",
        components: [
          { name: "token", type: "address" },
          { name: "targetPercentage", type: "uint256" },
        ],
      },
      { name: "managementFee", type: "uint256" },
    ],
    outputs: [{ name: "fund", type: "address" }],
  },
] as const;

export const FUND_GOVERNANCE_ABI = [
  // Proposal management
  "function propose(string description, bytes calldata) returns (uint256 proposalId)",
  "function vote(uint256 proposalId, bool support) external",
  "function execute(uint256 proposalId) external",
  "function cancel(uint256 proposalId) external",

  // View functions
  "function getProposal(uint256 proposalId) view returns (uint256 id, string description, address proposer, uint256 forVotes, uint256 againstVotes, uint256 startTime, uint256 endTime, bool executed, bool canceled)",
  "function getProposalCount() view returns (uint256)",
  "function hasVoted(uint256 proposalId, address account) view returns (bool)",
  "function getVotingPower(address account) view returns (uint256)",

  // Parameters
  "function votingPeriod() view returns (uint256)",
  "function quorumPercent() view returns (uint256)",
  "function proposalThreshold() view returns (uint256)",
] as const;

// ============================================
// LEVERAGED ETF MODULE
// ============================================

export const LP_VAULT_ABI = [
  // ERC-4626 Standard
  "function deposit(uint256 assets, address receiver) returns (uint256 shares)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256 shares)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256 assets)",

  // View functions
  "function balanceOf(address account) view returns (uint256)",
  "function totalAssets() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function convertToShares(uint256 assets) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",

  // LP Vault specific
  "function totalBorrowed() view returns (uint256)",
  "function availableLiquidity() view returns (uint256)",
  "function utilizationRate() view returns (uint256)",
  "function interestRate() view returns (uint256)",

  // Pausable
  "function paused() view returns (bool)",
  "function pause() external",
  "function unpause() external",
] as const;

export const LEVERAGED_LONG_TOKEN_ABI = [
  // Core functions
  "function mint(uint256 stableAmount) returns (uint256 shares)",
  "function redeem(uint256 shares) returns (uint256 stableReturned)",

  // View functions
  "function balanceOf(address account) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function getCurrentNav() view returns (uint256)",
  "function getPrice() view returns (uint256)",
  "function getStats() view returns (uint256 currentNav, uint256 price, uint256 collateral, uint256 borrowed, uint256 underlyingHeld, uint256 supply)",

  // State variables
  "function leverageRatio() view returns (uint256)",
  "function totalCollateral() view returns (uint256)",
  "function totalBorrowed() view returns (uint256)",
  "function totalUnderlying() view returns (uint256)",
  "function navPerShare() view returns (uint256)",
  "function lastRebalanceTime() view returns (uint256)",
  "function lastRebalancePrice() view returns (uint256)",
  "function slippageTolerance() view returns (uint256)",

  // Rebalancing
  "function needsRebalance() view returns (bool)",
  "function rebalance() external",
  "function forceRebalance() external",

  // Pausable
  "function paused() view returns (bool)",
  "function pause() external",
  "function unpause() external",
] as const;

export const LEVERAGED_SHORT_TOKEN_ABI = [
  // Core functions
  "function mint(uint256 stableAmount) returns (uint256 shares)",
  "function redeem(uint256 shares) returns (uint256 stableReturned)",

  // View functions
  "function balanceOf(address account) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function getCurrentNav() view returns (uint256)",
  "function getPrice() view returns (uint256)",
  "function getStats() view returns (uint256 currentNav, uint256 price, uint256 collateral, uint256 borrowed, uint256 stableHeld, uint256 supply)",

  // State variables
  "function leverageRatio() view returns (uint256)",
  "function totalCollateral() view returns (uint256)",
  "function totalBorrowed() view returns (uint256)",
  "function totalStableHeld() view returns (uint256)",
  "function navPerShare() view returns (uint256)",
  "function lastRebalanceTime() view returns (uint256)",
  "function lastRebalancePrice() view returns (uint256)",
  "function slippageTolerance() view returns (uint256)",

  // Rebalancing
  "function needsRebalance() view returns (bool)",
  "function rebalance() external",
  "function forceRebalance() external",

  // Pausable
  "function paused() view returns (bool)",
  "function pause() external",
  "function unpause() external",
] as const;

// ============================================
// ERC-20 (for approvals)
// ============================================

export const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)",
] as const;
