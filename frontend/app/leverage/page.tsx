"use client";

import { useState } from "react";
import { StatCard } from "@/components/shared";
import { MintRedeemCard, PositionInfo, RebalanceStatus } from "@/components/leverage";
import {
  useLeveragedTokenStats,
  useETHPrice,
  formatTokenAmount,
  formatUSD,
  type LeverageType,
} from "@/hooks";
import { TrendingUp, TrendingDown } from "lucide-react";

export default function LeveragePage() {
  const [leverageType, setLeverageType] = useState<LeverageType>("long");

  const {
    totalSupply,
    currentNAV,
    leverageRatio,
    paused,
    tokenSymbol,
    isLoading,
  } = useLeveragedTokenStats(leverageType);

  const { price: ethPrice, isLoading: ethPriceLoading } = useETHPrice();

  const isLong = leverageType === "long";

  // Calculate NAV in USD (NAV is stored in 6 decimals for USDC)
  const navUSD = currentNAV ? Number(currentNAV) / 1e6 : 0;

  // Calculate total market cap
  const totalMarketCap =
    totalSupply && currentNAV
      ? (Number(totalSupply) * Number(currentNAV)) / 1e24
      : 0;

  // Current leverage (stored in basis points, 20000 = 2x)
  const currentLeverage = leverageRatio
    ? (Number(leverageRatio) / 10000).toFixed(2)
    : "2.00";

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div>
        <div className="flex items-center gap-3">
          <h1 className="text-3xl font-bold gradient-text">ETH 2x Leveraged Tokens</h1>
          {paused && (
            <span className="rounded-full bg-error/20 px-3 py-1 text-xs font-medium text-error">
              Paused
            </span>
          )}
        </div>
        <p className="mt-2 text-foreground-muted">
          Get 2x leveraged exposure to ETH price movements with automated rebalancing
        </p>
      </div>

      {/* Long/Short Toggle */}
      <div className="flex justify-center">
        <div className="inline-flex rounded-xl bg-white/5 p-1">
          <button
            onClick={() => setLeverageType("long")}
            className={`flex items-center gap-2 rounded-lg px-6 py-3 text-sm font-medium transition-all ${
              isLong
                ? "bg-success text-white shadow-lg"
                : "text-foreground-muted hover:text-white"
            }`}
          >
            <TrendingUp className="h-4 w-4" />
            Long (ETH2X)
          </button>
          <button
            onClick={() => setLeverageType("short")}
            className={`flex items-center gap-2 rounded-lg px-6 py-3 text-sm font-medium transition-all ${
              !isLong
                ? "bg-error text-white shadow-lg"
                : "text-foreground-muted hover:text-white"
            }`}
          >
            <TrendingDown className="h-4 w-4" />
            Short (ETH-2X)
          </button>
        </div>
      </div>

      {/* Direction Description */}
      <div className={`rounded-xl p-4 ${isLong ? 'bg-success/10 border border-success/20' : 'bg-error/10 border border-error/20'}`}>
        <div className="flex items-center gap-2">
          {isLong ? (
            <>
              <TrendingUp className="h-5 w-5 text-success" />
              <span className="font-medium text-success">2x Long Position</span>
            </>
          ) : (
            <>
              <TrendingDown className="h-5 w-5 text-error" />
              <span className="font-medium text-error">2x Short Position</span>
            </>
          )}
        </div>
        <p className="mt-2 text-sm text-foreground-muted">
          {isLong
            ? "Profit when ETH price goes up. Deposit USDC → Borrow USDC → Buy WETH. 10% ETH increase = 20% profit."
            : "Profit when ETH price goes down. Deposit USDC → Borrow WETH → Sell for USDC. 10% ETH decrease = 20% profit."}
        </p>
      </div>

      {/* Token Stats */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">{tokenSymbol} Stats</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            title="Current NAV"
            value={formatUSD(navUSD)}
            subtitle={`Per ${tokenSymbol} token`}
            isLoading={isLoading}
          />
          <StatCard
            title="Leverage"
            value={`${currentLeverage}x`}
            subtitle="Target: 2.0x"
            isLoading={isLoading}
          />
          <StatCard
            title="Total Supply"
            value={formatTokenAmount(totalSupply)}
            subtitle={`${tokenSymbol} tokens`}
            isLoading={isLoading}
          />
          <StatCard
            title="ETH Price"
            value={formatUSD(ethPrice)}
            isLoading={ethPriceLoading}
          />
        </div>
      </section>

      {/* Main Content */}
      <div className="grid gap-6 lg:grid-cols-3">
        {/* Mint/Redeem Card */}
        <div className="lg:col-span-2">
          <h2 className="mb-4 text-lg font-semibold">Mint / Redeem {tokenSymbol}</h2>
          <MintRedeemCard type={leverageType} />
        </div>

        {/* Position & Rebalance Info */}
        <div className="space-y-6">
          <div>
            <h2 className="mb-4 text-lg font-semibold">Your Position</h2>
            <PositionInfo type={leverageType} />
          </div>
          <div>
            <h2 className="mb-4 text-lg font-semibold">Rebalance</h2>
            <RebalanceStatus type={leverageType} />
          </div>
        </div>
      </div>

      {/* How it works */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">How {isLong ? "Long" : "Short"} Works</h2>
        <div className="glass-card p-6">
          <div className="grid gap-6 md:grid-cols-3">
            <div>
              <div className={`mb-3 flex h-10 w-10 items-center justify-center rounded-lg ${isLong ? 'bg-success/20' : 'bg-error/20'}`}>
                <span className={`text-lg font-bold ${isLong ? 'text-success' : 'text-error'}`}>1</span>
              </div>
              <h3 className="font-medium">Deposit USDC</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                {isLong
                  ? "Mint ETH2X using USDC. Your USDC is used to borrow more USDC and buy WETH for 2x long exposure."
                  : "Mint ETH-2X using USDC. Your USDC is used to borrow WETH and sell it for 2x short exposure."}
              </p>
            </div>

            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-cyan/20">
                <span className="text-lg font-bold text-accent-cyan">2</span>
              </div>
              <h3 className="font-medium">Automatic Rebalancing</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                The protocol automatically rebalances every 20+ hours to maintain 2x leverage, protecting
                against liquidation and volatility decay.
              </p>
            </div>

            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-blue/20">
                <span className="text-lg font-bold text-accent-blue">3</span>
              </div>
              <h3 className="font-medium">Redeem Anytime</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                Redeem your {tokenSymbol} tokens for USDC at any time. Your returns reflect 2x
                the ETH price movement {isLong ? "(same direction)" : "(inverse direction)"}.
              </p>
            </div>
          </div>

          {/* Risk Warning */}
          <div className="mt-6 rounded-lg bg-warning/10 border border-warning/20 p-4">
            <h4 className="font-medium text-warning">Risk Warning</h4>
            <ul className="mt-2 space-y-1 text-sm text-foreground-muted">
              <li>• 2x leverage amplifies both gains and losses</li>
              <li>• {isLong ? "ETH price decrease" : "ETH price increase"} will result in losses</li>
              <li>• Volatility decay may impact long-term performance</li>
              <li>• Interest costs are incurred on borrowed funds</li>
              <li>• Smart contract risk - use at your own discretion</li>
            </ul>
          </div>
        </div>
      </section>
    </div>
  );
}
