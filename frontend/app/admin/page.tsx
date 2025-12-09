"use client";

import { useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseAbi } from "viem";
import toast from "react-hot-toast";
import {
  Shield,
  AlertTriangle,
  Pause,
  Play,
  RefreshCw,
  Coins,
  CheckCircle,
  XCircle,
} from "lucide-react";
import { TransactionButton } from "@/components/shared/TransactionButton";
import { StatCard } from "@/components/shared";
import { CONTRACTS } from "@/lib/contracts";
import { LP_VAULT_ABI, LEVERAGED_LONG_TOKEN_ABI, INDEX_FUND_ABI } from "@/lib/abis";
import {
  useLPVaultStats,
  useETH2XStats,
  useIndexFundStats,
  formatTokenAmount,
  formatPercent,
  parseError,
} from "@/hooks";

function StatusIndicator({ isActive, label }: { isActive: boolean; label: string }) {
  return (
    <div className="flex items-center gap-2">
      {isActive ? (
        <CheckCircle className="h-5 w-5 text-success" />
      ) : (
        <XCircle className="h-5 w-5 text-error" />
      )}
      <span className={isActive ? "text-success" : "text-error"}>
        {isActive ? "Active" : "Paused"}
      </span>
    </div>
  );
}

export default function AdminPage() {
  const { address, isConnected } = useAccount();

  // Check ownership for each contract
  const { data: lpVaultOwner } = useReadContract({
    address: CONTRACTS.LP_VAULT_LONG as `0x${string}`,
    abi: parseAbi(["function owner() view returns (address)"]),
    functionName: "owner",
  });

  const { data: eth2xOwner } = useReadContract({
    address: CONTRACTS.ETH2X_LONG as `0x${string}`,
    abi: parseAbi(["function owner() view returns (address)"]),
    functionName: "owner",
  });

  const { data: indexFundOwner } = useReadContract({
    address: CONTRACTS.INDEX_FUND as `0x${string}`,
    abi: parseAbi(["function owner() view returns (address)"]),
    functionName: "owner",
  });

  const isLPVaultOwner =
    lpVaultOwner && address && lpVaultOwner.toString().toLowerCase() === address.toLowerCase();
  const isETH2XOwner =
    eth2xOwner && address && eth2xOwner.toString().toLowerCase() === address.toLowerCase();
  const isIndexFundOwner =
    indexFundOwner && address && indexFundOwner.toString().toLowerCase() === address.toLowerCase();
  const isAnyOwner = isLPVaultOwner || isETH2XOwner || isIndexFundOwner;

  // Contract stats
  const lpVaultStats = useLPVaultStats();
  const eth2xStats = useETH2XStats();
  const indexFundStats = useIndexFundStats();

  // LP Vault Pause/Unpause
  const {
    writeContract: pauseLPVault,
    isPending: isPausingLP,
    data: pauseLPHash,
    error: pauseLPError,
  } = useWriteContract();

  const { isLoading: isPauseLPConfirming, isSuccess: isPauseLPSuccess, error: pauseLPReceiptError } = useWaitForTransactionReceipt({
    hash: pauseLPHash,
  });

  const {
    writeContract: unpauseLPVault,
    isPending: isUnpausingLP,
    data: unpauseLPHash,
    error: unpauseLPError,
  } = useWriteContract();

  const { isLoading: isUnpauseLPConfirming, isSuccess: isUnpauseLPSuccess, error: unpauseLPReceiptError } = useWaitForTransactionReceipt({
    hash: unpauseLPHash,
  });

  // ETH2X Pause/Unpause
  const {
    writeContract: pauseETH2X,
    isPending: isPausingETH2X,
    data: pauseETH2XHash,
    error: pauseETH2XError,
  } = useWriteContract();

  const { isLoading: isPauseETH2XConfirming, isSuccess: isPauseETH2XSuccess, error: pauseETH2XReceiptError } = useWaitForTransactionReceipt({
    hash: pauseETH2XHash,
  });

  const {
    writeContract: unpauseETH2X,
    isPending: isUnpausingETH2X,
    data: unpauseETH2XHash,
    error: unpauseETH2XError,
  } = useWriteContract();

  const { isLoading: isUnpauseETH2XConfirming, isSuccess: isUnpauseETH2XSuccess, error: unpauseETH2XReceiptError } = useWaitForTransactionReceipt({
    hash: unpauseETH2XHash,
  });

  // ETH2X Rebalance
  const {
    writeContract: rebalanceETH2X,
    isPending: isRebalancingETH2X,
    data: rebalanceETH2XHash,
    error: rebalanceETH2XError,
  } = useWriteContract();

  const { isLoading: isRebalanceETH2XConfirming, isSuccess: isRebalanceETH2XSuccess, error: rebalanceETH2XReceiptError } = useWaitForTransactionReceipt({
    hash: rebalanceETH2XHash,
  });

  // Index Fund Rebalance
  const {
    writeContract: rebalanceIndex,
    isPending: isRebalancingIndex,
    data: rebalanceIndexHash,
    error: rebalanceIndexError,
  } = useWriteContract();

  const { isLoading: isRebalanceIndexConfirming, isSuccess: isRebalanceIndexSuccess, error: rebalanceIndexReceiptError } = useWaitForTransactionReceipt({
    hash: rebalanceIndexHash,
  });

  // Index Fund Collect Fees
  const {
    writeContract: collectFees,
    isPending: isCollecting,
    data: collectHash,
    error: collectError,
  } = useWriteContract();

  const { isLoading: isCollectConfirming, isSuccess: isCollectSuccess, error: collectReceiptError } = useWaitForTransactionReceipt({
    hash: collectHash,
  });

  // Handle errors
  useEffect(() => {
    if (pauseLPError) toast.error(parseError(pauseLPError), { duration: 5000 });
  }, [pauseLPError]);

  useEffect(() => {
    if (pauseLPReceiptError) toast.error(parseError(pauseLPReceiptError), { duration: 5000 });
  }, [pauseLPReceiptError]);

  useEffect(() => {
    if (unpauseLPError) toast.error(parseError(unpauseLPError), { duration: 5000 });
  }, [unpauseLPError]);

  useEffect(() => {
    if (unpauseLPReceiptError) toast.error(parseError(unpauseLPReceiptError), { duration: 5000 });
  }, [unpauseLPReceiptError]);

  useEffect(() => {
    if (pauseETH2XError) toast.error(parseError(pauseETH2XError), { duration: 5000 });
  }, [pauseETH2XError]);

  useEffect(() => {
    if (pauseETH2XReceiptError) toast.error(parseError(pauseETH2XReceiptError), { duration: 5000 });
  }, [pauseETH2XReceiptError]);

  useEffect(() => {
    if (unpauseETH2XError) toast.error(parseError(unpauseETH2XError), { duration: 5000 });
  }, [unpauseETH2XError]);

  useEffect(() => {
    if (unpauseETH2XReceiptError) toast.error(parseError(unpauseETH2XReceiptError), { duration: 5000 });
  }, [unpauseETH2XReceiptError]);

  useEffect(() => {
    if (rebalanceETH2XError) toast.error(parseError(rebalanceETH2XError), { duration: 5000 });
  }, [rebalanceETH2XError]);

  useEffect(() => {
    if (rebalanceETH2XReceiptError) toast.error(parseError(rebalanceETH2XReceiptError), { duration: 5000 });
  }, [rebalanceETH2XReceiptError]);

  useEffect(() => {
    if (rebalanceIndexError) toast.error(parseError(rebalanceIndexError), { duration: 5000 });
  }, [rebalanceIndexError]);

  useEffect(() => {
    if (rebalanceIndexReceiptError) toast.error(parseError(rebalanceIndexReceiptError), { duration: 5000 });
  }, [rebalanceIndexReceiptError]);

  useEffect(() => {
    if (collectError) toast.error(parseError(collectError), { duration: 5000 });
  }, [collectError]);

  useEffect(() => {
    if (collectReceiptError) toast.error(parseError(collectReceiptError), { duration: 5000 });
  }, [collectReceiptError]);

  // Handle success
  useEffect(() => {
    if (isPauseLPSuccess) toast.success("LP Vault paused!");
  }, [isPauseLPSuccess]);

  useEffect(() => {
    if (isUnpauseLPSuccess) toast.success("LP Vault unpaused!");
  }, [isUnpauseLPSuccess]);

  useEffect(() => {
    if (isPauseETH2XSuccess) toast.success("ETH2X paused!");
  }, [isPauseETH2XSuccess]);

  useEffect(() => {
    if (isUnpauseETH2XSuccess) toast.success("ETH2X unpaused!");
  }, [isUnpauseETH2XSuccess]);

  useEffect(() => {
    if (isRebalanceETH2XSuccess) toast.success("ETH2X rebalanced!");
  }, [isRebalanceETH2XSuccess]);

  useEffect(() => {
    if (isRebalanceIndexSuccess) toast.success("Index Fund rebalanced!");
  }, [isRebalanceIndexSuccess]);

  useEffect(() => {
    if (isCollectSuccess) toast.success("Fees collected!");
  }, [isCollectSuccess]);

  // Handlers
  const handlePauseLPVault = () => {
    pauseLPVault({
      address: CONTRACTS.LP_VAULT_LONG as `0x${string}`,
      abi: parseAbi(LP_VAULT_ABI),
      functionName: "pause",
    });
  };

  const handleUnpauseLPVault = () => {
    unpauseLPVault({
      address: CONTRACTS.LP_VAULT_LONG as `0x${string}`,
      abi: parseAbi(LP_VAULT_ABI),
      functionName: "unpause",
    });
  };

  const handlePauseETH2X = () => {
    pauseETH2X({
      address: CONTRACTS.ETH2X_LONG as `0x${string}`,
      abi: parseAbi(LEVERAGED_LONG_TOKEN_ABI),
      functionName: "pause",
    });
  };

  const handleUnpauseETH2X = () => {
    unpauseETH2X({
      address: CONTRACTS.ETH2X_LONG as `0x${string}`,
      abi: parseAbi(LEVERAGED_LONG_TOKEN_ABI),
      functionName: "unpause",
    });
  };

  const handleRebalanceETH2X = () => {
    rebalanceETH2X({
      address: CONTRACTS.ETH2X_LONG as `0x${string}`,
      abi: parseAbi(LEVERAGED_LONG_TOKEN_ABI),
      functionName: "rebalance",
    });
  };

  const handleRebalanceIndex = () => {
    rebalanceIndex({
      address: CONTRACTS.INDEX_FUND as `0x${string}`,
      abi: parseAbi(INDEX_FUND_ABI),
      functionName: "rebalance",
    });
  };

  const handleCollectFees = () => {
    collectFees({
      address: CONTRACTS.INDEX_FUND as `0x${string}`,
      abi: parseAbi(INDEX_FUND_ABI),
      functionName: "collectFees",
    });
  };

  // Check system health
  const utilizationHealthy =
    lpVaultStats.utilizationRate === undefined ||
    Number(lpVaultStats.utilizationRate) < 9000; // < 90%
  const leverageHealthy =
    eth2xStats.leverageRatio === undefined ||
    (Number(eth2xStats.leverageRatio) / 1e18 >= 1.8 &&
      Number(eth2xStats.leverageRatio) / 1e18 <= 2.2);

  if (!isConnected) {
    return (
      <div className="space-y-8">
        <div>
          <h1 className="text-3xl font-bold gradient-text">Admin Controls</h1>
          <p className="mt-2 text-foreground-muted">
            Owner-only controls for emergency and maintenance
          </p>
        </div>
        <div className="glass-card p-8 text-center">
          <AlertTriangle className="mx-auto h-12 w-12 text-warning" />
          <p className="mt-4 text-lg font-medium">Connect Wallet</p>
          <p className="mt-2 text-foreground-muted">
            Please connect your wallet to access admin controls
          </p>
        </div>
      </div>
    );
  }

  if (!isAnyOwner) {
    return (
      <div className="space-y-8">
        <div>
          <h1 className="text-3xl font-bold gradient-text">Admin Controls</h1>
          <p className="mt-2 text-foreground-muted">
            Owner-only controls for emergency and maintenance
          </p>
        </div>
        <div className="glass-card p-8 text-center">
          <Shield className="mx-auto h-12 w-12 text-error" />
          <p className="mt-4 text-lg font-medium">Access Denied</p>
          <p className="mt-2 text-foreground-muted">
            This page is only accessible to contract owners
          </p>
          <p className="mt-4 text-sm text-foreground-muted">
            Connected: {address?.slice(0, 6)}...{address?.slice(-4)}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div>
        <div className="flex items-center gap-3">
          <h1 className="text-3xl font-bold gradient-text">Admin Controls</h1>
          <span className="rounded-full bg-warning/20 px-3 py-1 text-xs font-medium text-warning">
            Owner Only
          </span>
        </div>
        <p className="mt-2 text-foreground-muted">
          Emergency controls and maintenance operations
        </p>
      </div>

      {/* System Health Overview */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">System Health</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            title="LP Vault Status"
            value={lpVaultStats.paused ? "Paused" : "Active"}
            subtitle={lpVaultStats.paused ? "Operations halted" : "Fully operational"}
            isLoading={lpVaultStats.isLoading}
          />
          <StatCard
            title="ETH2X Status"
            value={eth2xStats.paused ? "Paused" : "Active"}
            subtitle={eth2xStats.paused ? "Operations halted" : "Fully operational"}
            isLoading={eth2xStats.isLoading}
          />
          <StatCard
            title="Utilization"
            value={formatPercent(lpVaultStats.utilizationRate)}
            subtitle={utilizationHealthy ? "Healthy" : "High - Monitor"}
            isLoading={lpVaultStats.isLoading}
          />
          <StatCard
            title="ETH2X Leverage"
            value={
              eth2xStats.leverageRatio
                ? `${(Number(eth2xStats.leverageRatio) / 1e18).toFixed(2)}x`
                : "N/A"
            }
            subtitle={leverageHealthy ? "Within range" : "Needs attention"}
            isLoading={eth2xStats.isLoading}
          />
        </div>
      </section>

      {/* LP Vault Controls */}
      {isLPVaultOwner && (
        <section>
          <h2 className="mb-4 text-lg font-semibold">LP Vault Controls</h2>
          <div className="glass-card p-6">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="flex items-center gap-3">
                  <span className="font-medium">LP Vault</span>
                  <StatusIndicator isActive={!lpVaultStats.paused} label="Status" />
                </div>
                <p className="mt-1 text-sm text-foreground-muted">
                  Utilization: {formatPercent(lpVaultStats.utilizationRate)} |
                  TVL: {formatTokenAmount(lpVaultStats.totalAssets)} WETH
                </p>
              </div>
              <div className="flex gap-3">
                {lpVaultStats.paused ? (
                  <TransactionButton
                    onClick={handleUnpauseLPVault}
                    isLoading={isUnpausingLP || isUnpauseLPConfirming}
                    loadingText="Unpausing..."
                  >
                    <Play className="h-4 w-4" />
                    Unpause
                  </TransactionButton>
                ) : (
                  <TransactionButton
                    onClick={handlePauseLPVault}
                    isLoading={isPausingLP || isPauseLPConfirming}
                    loadingText="Pausing..."
                    variant="secondary"
                  >
                    <Pause className="h-4 w-4" />
                    Pause
                  </TransactionButton>
                )}
              </div>
            </div>
          </div>
        </section>
      )}

      {/* ETH2X Controls */}
      {isETH2XOwner && (
        <section>
          <h2 className="mb-4 text-lg font-semibold">ETH2X Controls</h2>
          <div className="glass-card space-y-4 p-6">
            {/* Pause/Unpause */}
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="flex items-center gap-3">
                  <span className="font-medium">ETH2X Token</span>
                  <StatusIndicator isActive={!eth2xStats.paused} label="Status" />
                </div>
                <p className="mt-1 text-sm text-foreground-muted">
                  Leverage:{" "}
                  {eth2xStats.leverageRatio
                    ? `${(Number(eth2xStats.leverageRatio) / 1e18).toFixed(2)}x`
                    : "N/A"}{" "}
                  | Supply: {formatTokenAmount(eth2xStats.totalSupply)} ETH2X
                </p>
              </div>
              <div className="flex gap-3">
                {eth2xStats.paused ? (
                  <TransactionButton
                    onClick={handleUnpauseETH2X}
                    isLoading={isUnpausingETH2X || isUnpauseETH2XConfirming}
                    loadingText="Unpausing..."
                  >
                    <Play className="h-4 w-4" />
                    Unpause
                  </TransactionButton>
                ) : (
                  <TransactionButton
                    onClick={handlePauseETH2X}
                    isLoading={isPausingETH2X || isPauseETH2XConfirming}
                    loadingText="Pausing..."
                    variant="secondary"
                  >
                    <Pause className="h-4 w-4" />
                    Pause
                  </TransactionButton>
                )}
              </div>
            </div>

            {/* Rebalance */}
            <div className="border-t border-white/10 pt-4">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <span className="font-medium">Force Rebalance</span>
                  <p className="mt-1 text-sm text-foreground-muted">
                    Needs rebalance: {eth2xStats.needsRebalance ? "Yes" : "No"}
                  </p>
                </div>
                <TransactionButton
                  onClick={handleRebalanceETH2X}
                  isLoading={isRebalancingETH2X || isRebalanceETH2XConfirming}
                  loadingText="Rebalancing..."
                  variant="secondary"
                >
                  <RefreshCw className="h-4 w-4" />
                  Rebalance
                </TransactionButton>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* Index Fund Controls */}
      {isIndexFundOwner && (
        <section>
          <h2 className="mb-4 text-lg font-semibold">Index Fund Controls</h2>
          <div className="glass-card space-y-4 p-6">
            {/* Rebalance */}
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <span className="font-medium">Portfolio Rebalance</span>
                <p className="mt-1 text-sm text-foreground-muted">
                  Rebalance portfolio to target allocations
                </p>
              </div>
              <TransactionButton
                onClick={handleRebalanceIndex}
                isLoading={isRebalancingIndex || isRebalanceIndexConfirming}
                loadingText="Rebalancing..."
                variant="secondary"
              >
                <RefreshCw className="h-4 w-4" />
                Rebalance
              </TransactionButton>
            </div>

            {/* Collect Fees */}
            <div className="border-t border-white/10 pt-4">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <span className="font-medium">Collect Management Fees</span>
                  <p className="mt-1 text-sm text-foreground-muted">
                    Accrued fees: {formatTokenAmount(indexFundStats.accruedFees)} IDX
                  </p>
                </div>
                <TransactionButton
                  onClick={handleCollectFees}
                  isLoading={isCollecting || isCollectConfirming}
                  loadingText="Collecting..."
                  disabled={!indexFundStats.accruedFees || indexFundStats.accruedFees === BigInt(0)}
                >
                  <Coins className="h-4 w-4" />
                  Collect Fees
                </TransactionButton>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* Warning */}
      <div className="rounded-xl border border-warning/20 bg-warning/10 p-4">
        <div className="flex items-start gap-3">
          <AlertTriangle className="h-5 w-5 flex-shrink-0 text-warning" />
          <div>
            <p className="font-medium text-warning">Caution</p>
            <p className="mt-1 text-sm text-foreground-muted">
              These controls affect the entire protocol. Use with caution and only in
              emergency situations or scheduled maintenance windows. All actions are
              recorded on-chain and cannot be undone.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
