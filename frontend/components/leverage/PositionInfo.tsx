"use client";

import { useAccount } from "wagmi";
import {
  useLeveragedTokenUserPosition,
  useLeveragedTokenStats,
  useETHPrice,
  formatTokenAmount,
  formatUSD,
  type LeverageType,
} from "@/hooks";
import { TrendingUp, TrendingDown } from "lucide-react";

interface PositionInfoProps {
  type: LeverageType;
}

export function PositionInfo({ type }: PositionInfoProps) {
  const { isConnected } = useAccount();
  const { balance, tokenSymbol } = useLeveragedTokenUserPosition(type);
  const { currentNAV } = useLeveragedTokenStats(type);
  const { price: ethPrice } = useETHPrice();

  const isLong = type === "long";
  const directionLabel = isLong ? "Long" : "Short";
  const directionIcon = isLong ? <TrendingUp className="h-4 w-4" /> : <TrendingDown className="h-4 w-4" />;
  const directionColor = isLong ? "text-success" : "text-error";

  if (!isConnected) {
    return (
      <div className="glass-card p-6">
        <h3 className="mb-4 text-lg font-semibold">Your Position</h3>
        <p className="text-center text-foreground-muted">
          Connect wallet to view your position
        </p>
      </div>
    );
  }

  const hasPosition = balance && balance > BigInt(0);

  // Calculate position value in USDC
  // NAV is stored in 6 decimals (USDC), balance is 18 decimals
  const positionValue =
    balance && currentNAV
      ? (Number(balance) * Number(currentNAV)) / 1e24
      : 0;

  // Calculate leverage exposure in USD
  const leverageExposure = positionValue * 2;

  // Calculate ETH exposure
  const ethExposure = ethPrice ? leverageExposure / ethPrice : 0;

  return (
    <div className="glass-card p-6">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="text-lg font-semibold">Your Position</h3>
        <span className={`flex items-center gap-1 text-sm font-medium ${directionColor}`}>
          {directionIcon}
          {directionLabel}
        </span>
      </div>

      {!hasPosition ? (
        <div className="text-center text-foreground-muted">
          <p>No position yet</p>
          <p className="mt-1 text-sm">Mint {tokenSymbol} to get started</p>
        </div>
      ) : (
        <div className="space-y-4">
          {/* Balance */}
          <div className="flex items-center justify-between">
            <span className="text-foreground-muted">{tokenSymbol} Balance</span>
            <span className="text-xl font-bold">
              {formatTokenAmount(balance)} {tokenSymbol}
            </span>
          </div>

          {/* Position Value */}
          <div className="flex items-center justify-between">
            <span className="text-foreground-muted">Position Value</span>
            <span className="font-medium">{formatUSD(positionValue)}</span>
          </div>

          {/* Divider */}
          <div className="border-t border-white/10" />

          {/* Leverage Exposure */}
          <div className={`rounded-lg p-4 ${isLong ? 'bg-success/10' : 'bg-error/10'}`}>
            <div className="flex items-center justify-between">
              <span className="text-sm text-foreground-muted">
                2x {directionLabel} Exposure
              </span>
              <span className={`font-bold ${directionColor}`}>
                {formatUSD(leverageExposure)}
              </span>
            </div>
            <div className="mt-2 flex items-center justify-between text-sm">
              <span className="text-foreground-muted">ETH Equivalent</span>
              <span>{ethExposure.toFixed(4)} ETH</span>
            </div>
          </div>

          {/* Risk Warning */}
          <div className="rounded-lg bg-warning/10 p-3">
            <p className="text-xs text-warning">
              2x {directionLabel.toLowerCase()} leverage amplifies both gains and losses.
              {isLong
                ? " ETH price increase = profit, decrease = loss."
                : " ETH price decrease = profit, increase = loss."}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
