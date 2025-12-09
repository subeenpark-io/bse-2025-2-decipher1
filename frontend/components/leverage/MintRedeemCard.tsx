"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits, parseAbi } from "viem";
import toast from "react-hot-toast";
import { TokenInput } from "@/components/shared/TokenInput";
import { TransactionButton } from "@/components/shared/TransactionButton";
import { CONTRACTS } from "@/lib/contracts";
import { LEVERAGED_LONG_TOKEN_ABI, LEVERAGED_SHORT_TOKEN_ABI, ERC20_ABI } from "@/lib/abis";
import { useLeveragedTokenUserPosition, useLeveragedTokenStats, formatTokenAmount, parseError, type LeverageType } from "@/hooks";

type Tab = "mint" | "redeem";

interface MintRedeemCardProps {
  type: LeverageType;
}

// Format small numbers without scientific notation
function formatSmallNumber(num: number): string {
  if (num === 0) return "0";
  if (num >= 1) {
    return num.toLocaleString(undefined, { maximumFractionDigits: 4 });
  }
  // For small numbers, show enough decimals
  const log = Math.floor(Math.log10(Math.abs(num)));
  const decimals = Math.min(Math.abs(log) + 2, 18);
  return num.toFixed(decimals);
}

export function MintRedeemCard({ type }: MintRedeemCardProps) {
  const [activeTab, setActiveTab] = useState<Tab>("mint");
  const [amount, setAmount] = useState("");

  const { address, isConnected } = useAccount();

  // Get contract addresses and ABIs based on type
  const tokenAddress = type === "long" ? CONTRACTS.ETH2X_LONG : CONTRACTS.ETH2X_SHORT;
  const tokenAbi = type === "long" ? LEVERAGED_LONG_TOKEN_ABI : LEVERAGED_SHORT_TOKEN_ABI;
  const tokenSymbol = type === "long" ? "ETH2X" : "ETH-2X";

  const { balance: tokenBalance } = useLeveragedTokenUserPosition(type);
  const { currentNAV } = useLeveragedTokenStats(type);

  // USDC balance (6 decimals) - both long and short use USDC as collateral
  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.USDC as `0x${string}`,
    abi: parseAbi(ERC20_ABI),
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // USDC allowance for the specific token contract
  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.USDC as `0x${string}`,
    abi: parseAbi(ERC20_ABI),
    functionName: "allowance",
    args: address ? [address, tokenAddress as `0x${string}`] : undefined,
    query: { enabled: !!address },
  });

  // Approve USDC
  const {
    writeContract: approveUsdc,
    isPending: isApproving,
    data: approveHash,
    error: approveError,
  } = useWriteContract();

  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess, error: approveReceiptError } = useWaitForTransactionReceipt({
    hash: approveHash,
  });

  // Mint token
  const {
    writeContract: mint,
    isPending: isMinting,
    data: mintHash,
    error: mintError,
  } = useWriteContract();

  const { isLoading: isMintConfirming, isSuccess: isMintSuccess, error: mintReceiptError } = useWaitForTransactionReceipt({
    hash: mintHash,
  });

  // Redeem token
  const {
    writeContract: redeem,
    isPending: isRedeeming,
    data: redeemHash,
    error: redeemError,
  } = useWriteContract();

  const { isLoading: isRedeemConfirming, isSuccess: isRedeemSuccess, error: redeemReceiptError } = useWaitForTransactionReceipt({
    hash: redeemHash,
  });

  // Handle errors
  useEffect(() => {
    if (approveError) {
      toast.error(parseError(approveError), { duration: 5000 });
    }
  }, [approveError]);

  useEffect(() => {
    if (approveReceiptError) {
      toast.error(parseError(approveReceiptError), { duration: 5000 });
    }
  }, [approveReceiptError]);

  useEffect(() => {
    if (mintError) {
      toast.error(parseError(mintError), { duration: 5000 });
    }
  }, [mintError]);

  useEffect(() => {
    if (mintReceiptError) {
      toast.error(parseError(mintReceiptError), { duration: 5000 });
    }
  }, [mintReceiptError]);

  useEffect(() => {
    if (redeemError) {
      toast.error(parseError(redeemError), { duration: 5000 });
    }
  }, [redeemError]);

  useEffect(() => {
    if (redeemReceiptError) {
      toast.error(parseError(redeemReceiptError), { duration: 5000 });
    }
  }, [redeemReceiptError]);

  // Handle success
  useEffect(() => {
    if (isApproveSuccess) {
      toast.success("Approval confirmed!");
      refetchAllowance();
    }
  }, [isApproveSuccess, refetchAllowance]);

  useEffect(() => {
    if (isMintSuccess) {
      toast.success("Mint confirmed!");
      setAmount("");
    }
  }, [isMintSuccess]);

  useEffect(() => {
    if (isRedeemSuccess) {
      toast.success("Redeem confirmed!");
      setAmount("");
    }
  }, [isRedeemSuccess]);

  // USDC has 6 decimals, tokens have 18 decimals
  const parsedAmount =
    activeTab === "mint"
      ? amount
        ? parseUnits(amount, 6)
        : BigInt(0)
      : amount
        ? parseUnits(amount, 18)
        : BigInt(0);

  const needsApproval =
    activeTab === "mint" &&
    usdcAllowance !== undefined &&
    parsedAmount > (usdcAllowance as bigint);

  // Calculate expected tokens from mint
  // Contract: shares = (stableAmount * PRECISION) / currentNav
  // stableAmount is in 6 decimals (USDC), nav is in 6 decimals, PRECISION is 1e18
  const expectedTokens =
    activeTab === "mint" && amount && currentNAV && Number(currentNAV) > 0
      ? (parseFloat(amount) * 1e6 * 1e18) / Number(currentNAV) / 1e18
      : 0;

  // Calculate expected USDC from redeem
  // Contract: valueInCollateral = (shares * currentNav) / PRECISION
  const expectedUSDC =
    activeTab === "redeem" && amount && currentNAV
      ? (parseFloat(amount) * Number(currentNAV)) / 1e6
      : 0;

  const handleApprove = () => {
    approveUsdc({
      address: CONTRACTS.USDC as `0x${string}`,
      abi: parseAbi(ERC20_ABI),
      functionName: "approve",
      args: [tokenAddress as `0x${string}`, parsedAmount],
    });
  };

  const handleMint = () => {
    if (!address || !parsedAmount) return;

    mint({
      address: tokenAddress as `0x${string}`,
      abi: parseAbi(tokenAbi),
      functionName: "mint",
      args: [parsedAmount],
    });
  };

  const handleRedeem = () => {
    if (!address || !parsedAmount) return;

    redeem({
      address: tokenAddress as `0x${string}`,
      abi: parseAbi(tokenAbi),
      functionName: "redeem",
      args: [parsedAmount],
    });
  };

  const handleMaxClick = () => {
    if (activeTab === "mint" && usdcBalance) {
      setAmount(formatUnits(usdcBalance as bigint, 6));
    } else if (activeTab === "redeem" && tokenBalance) {
      setAmount(formatUnits(tokenBalance, 18));
    }
  };

  const isLoading =
    isApproving ||
    isApproveConfirming ||
    isMinting ||
    isMintConfirming ||
    isRedeeming ||
    isRedeemConfirming;

  // Direction label for exposure description
  const exposureDirection = type === "long" ? "long" : "short";
  const exposureColor = type === "long" ? "text-success" : "text-error";

  return (
    <div className="glass-card p-6">
      {/* Tabs */}
      <div className="mb-6 flex gap-2 rounded-lg bg-white/5 p-1">
        <button
          onClick={() => {
            setActiveTab("mint");
            setAmount("");
          }}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-all ${
            activeTab === "mint"
              ? "bg-accent-purple text-white"
              : "text-foreground-muted hover:text-white"
          }`}
        >
          Mint
        </button>
        <button
          onClick={() => {
            setActiveTab("redeem");
            setAmount("");
          }}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-all ${
            activeTab === "redeem"
              ? "bg-accent-purple text-white"
              : "text-foreground-muted hover:text-white"
          }`}
        >
          Redeem
        </button>
      </div>

      {/* Input */}
      <TokenInput
        value={amount}
        onChange={setAmount}
        symbol={activeTab === "mint" ? "USDC" : tokenSymbol}
        balance={
          activeTab === "mint"
            ? formatTokenAmount(usdcBalance as bigint | undefined, 6, 2)
            : formatTokenAmount(tokenBalance)
        }
        onMax={handleMaxClick}
        disabled={!isConnected}
      />

      {/* Preview */}
      {amount && parseFloat(amount) > 0 && parsedAmount > BigInt(0) && (
        <div className="mt-4 rounded-lg bg-white/5 p-4">
          <div className="flex justify-between text-sm">
            <span className="text-foreground-muted">You will receive</span>
            <span className="text-right break-all">
              ~
              {activeTab === "mint"
                ? `${formatSmallNumber(expectedTokens)} ${tokenSymbol}`
                : `${formatSmallNumber(expectedUSDC)} USDC`}
            </span>
          </div>
          {activeTab === "mint" && (
            <div className="mt-2 flex justify-between text-sm">
              <span className="text-foreground-muted">2x {exposureDirection} exposure</span>
              <span className={`text-right break-all ${exposureColor}`}>
                ${formatSmallNumber(parseFloat(amount) * 2)} worth of ETH
              </span>
            </div>
          )}
        </div>
      )}

      {/* Minimum amount warning */}
      {activeTab === "mint" && amount && parseFloat(amount) > 0 && parsedAmount === BigInt(0) && (
        <div className="mt-4 rounded-lg bg-warning/10 p-3 text-sm text-warning">
          USDC minimum: 0.000001 (6 decimals precision)
        </div>
      )}

      {/* Action Button */}
      <div className="mt-6">
        {!isConnected ? (
          <div className="rounded-xl bg-white/5 p-4 text-center text-foreground-muted">
            Connect wallet to continue
          </div>
        ) : activeTab === "mint" ? (
          needsApproval ? (
            <TransactionButton
              onClick={handleApprove}
              isLoading={isApproving || isApproveConfirming}
              loadingText="Approving..."
              disabled={!amount || parseFloat(amount) <= 0 || parsedAmount === BigInt(0)}
            >
              Approve USDC
            </TransactionButton>
          ) : (
            <TransactionButton
              onClick={handleMint}
              isLoading={isMinting || isMintConfirming}
              loadingText="Minting..."
              disabled={!amount || parseFloat(amount) <= 0 || parsedAmount === BigInt(0)}
            >
              Mint {tokenSymbol}
            </TransactionButton>
          )
        ) : (
          <TransactionButton
            onClick={handleRedeem}
            isLoading={isRedeeming || isRedeemConfirming}
            loadingText="Redeeming..."
            disabled={!amount || parseFloat(amount) <= 0 || parsedAmount === BigInt(0)}
            variant="secondary"
          >
            Redeem
          </TransactionButton>
        )}
      </div>
    </div>
  );
}
