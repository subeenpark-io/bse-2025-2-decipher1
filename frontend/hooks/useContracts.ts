"use client";

import { useReadContract, useReadContracts, useAccount } from "wagmi";
import { formatEther, formatUnits, parseAbi } from "viem";
import { CONTRACTS } from "@/lib/contracts";
import {
  LP_VAULT_ABI,
  LEVERAGED_LONG_TOKEN_ABI,
  LEVERAGED_SHORT_TOKEN_ABI,
  INDEX_FUND_ABI,
  ERC20_ABI,
} from "@/lib/abis";

export type LeverageType = "long" | "short";

// LP Vault hooks - supports both Long (USDC) and Short (WETH) vaults
export function useLPVaultStats(type: LeverageType = "long") {
  const vaultAddress = type === "long" ? CONTRACTS.LP_VAULT_LONG : CONTRACTS.LP_VAULT_SHORT;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "totalAssets",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "totalSupply",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "totalBorrowed",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "availableLiquidity",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "utilizationRate",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "interestRate",
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "paused",
      },
    ],
  });

  return {
    totalAssets: data?.[0]?.result as bigint | undefined,
    totalSupply: data?.[1]?.result as bigint | undefined,
    totalBorrowed: data?.[2]?.result as bigint | undefined,
    availableLiquidity: data?.[3]?.result as bigint | undefined,
    utilizationRate: data?.[4]?.result as bigint | undefined,
    interestRate: data?.[5]?.result as bigint | undefined,
    paused: data?.[6]?.result as boolean | undefined,
    vaultAddress,
    assetSymbol: type === "long" ? "USDC" : "WETH",
    assetDecimals: type === "long" ? 6 : 18,
    isLoading,
    error,
  };
}

export function useLPVaultUserPosition(type: LeverageType = "long") {
  const { address } = useAccount();
  const vaultAddress = type === "long" ? CONTRACTS.LP_VAULT_LONG : CONTRACTS.LP_VAULT_SHORT;
  const decimals = type === "long" ? 6 : 18;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: vaultAddress as `0x${string}`,
        abi: parseAbi(LP_VAULT_ABI),
        functionName: "convertToAssets",
        args: [BigInt(10 ** decimals)], // 1 share worth in asset decimals
      },
    ],
    query: {
      enabled: !!address,
    },
  });

  const shares = data?.[0]?.result as bigint | undefined;
  const sharePrice = data?.[1]?.result as bigint | undefined;
  const assetsValue =
    shares && sharePrice ? (shares * sharePrice) / BigInt(10 ** decimals) : undefined;

  return {
    shares,
    sharePrice,
    assetsValue,
    vaultAddress,
    assetDecimals: decimals,
    isLoading,
    error,
  };
}

// Leveraged Token hooks - supports both Long and Short
export function useLeveragedTokenStats(type: LeverageType = "long") {
  const tokenAddress = type === "long" ? CONTRACTS.ETH2X_LONG : CONTRACTS.ETH2X_SHORT;
  const abi = type === "long" ? LEVERAGED_LONG_TOKEN_ABI : LEVERAGED_SHORT_TOKEN_ABI;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "totalSupply",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "getCurrentNav",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "leverageRatio",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "needsRebalance",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "paused",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "lastRebalanceTime",
      },
      {
        address: tokenAddress as `0x${string}`,
        abi: parseAbi(abi),
        functionName: "getPrice",
      },
    ],
  });

  return {
    totalSupply: data?.[0]?.result as bigint | undefined,
    currentNAV: data?.[1]?.result as bigint | undefined,
    leverageRatio: data?.[2]?.result as bigint | undefined,
    needsRebalance: data?.[3]?.result as boolean | undefined,
    paused: data?.[4]?.result as boolean | undefined,
    lastRebalanceTime: data?.[5]?.result as bigint | undefined,
    oraclePrice: data?.[6]?.result as bigint | undefined,
    tokenAddress,
    tokenSymbol: type === "long" ? "ETH2X" : "ETH-2X",
    isLoading,
    error,
  };
}

export function useLeveragedTokenUserPosition(type: LeverageType = "long") {
  const { address } = useAccount();
  const tokenAddress = type === "long" ? CONTRACTS.ETH2X_LONG : CONTRACTS.ETH2X_SHORT;
  const abi = type === "long" ? LEVERAGED_LONG_TOKEN_ABI : LEVERAGED_SHORT_TOKEN_ABI;

  const { data, isLoading, error } = useReadContract({
    address: tokenAddress as `0x${string}`,
    abi: parseAbi(abi),
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  });

  return {
    balance: data as bigint | undefined,
    tokenAddress,
    tokenSymbol: type === "long" ? "ETH2X" : "ETH-2X",
    isLoading,
    error,
  };
}

// Legacy aliases for backwards compatibility
export function useETH2XStats() {
  return useLeveragedTokenStats("long");
}

export function useETH2XUserPosition() {
  return useLeveragedTokenUserPosition("long");
}

// Index Fund hooks
export function useIndexFundStats(fundAddress?: string) {
  const address = (fundAddress || CONTRACTS.INDEX_FUND) as `0x${string}`;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "totalAssets",
      },
      {
        address,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "totalSupply",
      },
      {
        address,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "managementFeeRate",
      },
      {
        address,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "convertToAssets",
        args: [BigInt(1e18)], // 1 share price
      },
      {
        address,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "accruedFees",
      },
    ],
    query: { enabled: !!address },
  });

  return {
    totalAssets: data?.[0]?.result as bigint | undefined,
    totalSupply: data?.[1]?.result as bigint | undefined,
    managementFeeRate: data?.[2]?.result as bigint | undefined,
    sharePrice: data?.[3]?.result as bigint | undefined,
    accruedFees: data?.[4]?.result as bigint | undefined,
    isLoading,
    error,
  };
}

export function useIndexFundAllocations(fundAddress?: string) {
  const address = (fundAddress || CONTRACTS.INDEX_FUND) as `0x${string}`;

  const { data, isLoading, error } = useReadContract({
    address,
    abi: parseAbi(INDEX_FUND_ABI),
    functionName: "getAllocations",
    query: { enabled: !!address },
  });

  const result = data as [string[], bigint[]] | undefined;

  return {
    tokens: result?.[0] || [],
    weights: result?.[1] || [],
    isLoading,
    error,
  };
}

export function useIndexFundUserPosition(fundAddress?: string) {
  const { address } = useAccount();
  const fundAddr = (fundAddress || CONTRACTS.INDEX_FUND) as `0x${string}`;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: fundAddr,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "balanceOf",
        args: address ? [address] : undefined,
      },
      {
        address: fundAddr,
        abi: parseAbi(INDEX_FUND_ABI),
        functionName: "convertToAssets",
        args: [BigInt(1e18)], // 1 share
      },
    ],
    query: {
      enabled: !!address && !!fundAddr,
    },
  });

  const shares = data?.[0]?.result as bigint | undefined;
  const sharePrice = data?.[1]?.result as bigint | undefined;
  const assetsValue =
    shares && sharePrice ? (shares * sharePrice) / BigInt(1e18) : undefined;

  return {
    shares,
    sharePrice,
    assetsValue,
    isLoading,
    error,
  };
}

// ETH Price from Oracle
export function useETHPrice() {
  const { data, isLoading, error } = useReadContract({
    address: CONTRACTS.ETH_USD_ORACLE as `0x${string}`,
    abi: parseAbi([
      "function latestAnswer() view returns (int256)",
      "function decimals() view returns (uint8)",
    ]),
    functionName: "latestAnswer",
  });

  // Chainlink price feeds typically have 8 decimals
  const price = data ? Number(data) / 1e8 : undefined;

  return {
    price,
    isLoading,
    error,
  };
}

// Format utilities
export function formatTokenAmount(
  amount: bigint | undefined,
  decimals: number = 18,
  displayDecimals: number = 4
): string {
  if (!amount || amount === BigInt(0)) return "0";
  const formatted = formatUnits(amount, decimals);
  const num = parseFloat(formatted);

  if (num === 0) return "0";

  // For small amounts, show enough decimals to display the value
  if (num < 1) {
    const log = Math.floor(Math.log10(Math.abs(num)));
    const neededDecimals = Math.abs(log) + 2;
    // Cap at 18 decimals (max for ETH-like tokens)
    return num.toFixed(Math.min(neededDecimals, 18));
  }

  return num.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: displayDecimals,
  });
}

export function formatUSD(amount: number | undefined): string {
  if (amount === undefined || amount === 0) return "$0.00";

  // For very small amounts, show more precision
  if (amount > 0 && amount < 0.01) {
    // Find how many decimals we need
    const log = Math.floor(Math.log10(Math.abs(amount)));
    const decimals = Math.min(Math.abs(log) + 2, 10);
    return `$${amount.toFixed(decimals)}`;
  }

  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

export function formatPercent(
  bps: bigint | undefined,
  decimals: number = 2
): string {
  if (!bps) return "0%";
  const percent = Number(bps) / 100; // assuming bps (basis points)
  return `${percent.toFixed(decimals)}%`;
}

// Governance hooks - supports per-fund governance
export function useGovernanceParams(governanceAddress?: string) {
  const govAddr = (governanceAddress || CONTRACTS.FUND_GOVERNANCE) as `0x${string}`;

  const { data, isLoading, error } = useReadContracts({
    contracts: [
      {
        address: govAddr,
        abi: parseAbi([
          "function votingPeriod() view returns (uint256)",
          "function quorumPercent() view returns (uint256)",
          "function proposalThreshold() view returns (uint256)",
          "function getProposalCount() view returns (uint256)",
        ]),
        functionName: "votingPeriod",
      },
      {
        address: govAddr,
        abi: parseAbi([
          "function votingPeriod() view returns (uint256)",
          "function quorumPercent() view returns (uint256)",
          "function proposalThreshold() view returns (uint256)",
          "function getProposalCount() view returns (uint256)",
        ]),
        functionName: "quorumPercent",
      },
      {
        address: govAddr,
        abi: parseAbi([
          "function votingPeriod() view returns (uint256)",
          "function quorumPercent() view returns (uint256)",
          "function proposalThreshold() view returns (uint256)",
          "function getProposalCount() view returns (uint256)",
        ]),
        functionName: "proposalThreshold",
      },
      {
        address: govAddr,
        abi: parseAbi([
          "function votingPeriod() view returns (uint256)",
          "function quorumPercent() view returns (uint256)",
          "function proposalThreshold() view returns (uint256)",
          "function getProposalCount() view returns (uint256)",
        ]),
        functionName: "getProposalCount",
      },
    ],
  });

  return {
    votingPeriod: data?.[0]?.result as bigint | undefined,
    quorumPercent: data?.[1]?.result as bigint | undefined,
    proposalThreshold: data?.[2]?.result as bigint | undefined,
    proposalCount: data?.[3]?.result as bigint | undefined,
    governanceAddress: govAddr,
    isLoading,
    error,
  };
}

export function useVotingPower(governanceAddress?: string) {
  const { address } = useAccount();
  const govAddr = (governanceAddress || CONTRACTS.FUND_GOVERNANCE) as `0x${string}`;

  const { data, isLoading, error } = useReadContract({
    address: govAddr,
    abi: parseAbi([
      "function getVotingPower(address account) view returns (uint256)",
    ]),
    functionName: "getVotingPower",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  return {
    votingPower: data as bigint | undefined,
    governanceAddress: govAddr,
    isLoading,
    error,
  };
}
