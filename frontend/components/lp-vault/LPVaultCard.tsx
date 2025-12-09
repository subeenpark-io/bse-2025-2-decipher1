"use client";

import { useState, useEffect } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits, formatUnits, parseAbi } from "viem";
import toast from "react-hot-toast";
import { TokenInput } from "@/components/shared/TokenInput";
import { TransactionButton } from "@/components/shared/TransactionButton";
import { CONTRACTS } from "@/lib/contracts";
import { LP_VAULT_ABI, ERC20_ABI } from "@/lib/abis";
import { useLPVaultUserPosition, formatTokenAmount, parseError } from "@/hooks";

type Tab = "deposit" | "withdraw";

export function LPVaultCard() {
  const [activeTab, setActiveTab] = useState<Tab>("deposit");
  const [amount, setAmount] = useState("");

  const { address, isConnected } = useAccount();
  const { shares, assetsValue, vaultAddress } = useLPVaultUserPosition("long");

  // USDC balance (6 decimals)
  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.USDC as `0x${string}`,
    abi: parseAbi(ERC20_ABI),
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // USDC allowance for LP Vault
  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.USDC as `0x${string}`,
    abi: parseAbi(ERC20_ABI),
    functionName: "allowance",
    args: address ? [address, CONTRACTS.LP_VAULT_LONG as `0x${string}`] : undefined,
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

  // Deposit
  const {
    writeContract: deposit,
    isPending: isDepositing,
    data: depositHash,
    error: depositError,
  } = useWriteContract();

  const { isLoading: isDepositConfirming, isSuccess: isDepositSuccess, error: depositReceiptError } = useWaitForTransactionReceipt({
    hash: depositHash,
  });

  // Withdraw
  const {
    writeContract: withdraw,
    isPending: isWithdrawing,
    data: withdrawHash,
    error: withdrawError,
  } = useWriteContract();

  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess, error: withdrawReceiptError } = useWaitForTransactionReceipt({
    hash: withdrawHash,
  });

  // Handle errors
  useEffect(() => {
    if (approveError) toast.error(parseError(approveError), { duration: 5000 });
  }, [approveError]);

  useEffect(() => {
    if (approveReceiptError) toast.error(parseError(approveReceiptError), { duration: 5000 });
  }, [approveReceiptError]);

  useEffect(() => {
    if (depositError) toast.error(parseError(depositError), { duration: 5000 });
  }, [depositError]);

  useEffect(() => {
    if (depositReceiptError) toast.error(parseError(depositReceiptError), { duration: 5000 });
  }, [depositReceiptError]);

  useEffect(() => {
    if (withdrawError) toast.error(parseError(withdrawError), { duration: 5000 });
  }, [withdrawError]);

  useEffect(() => {
    if (withdrawReceiptError) toast.error(parseError(withdrawReceiptError), { duration: 5000 });
  }, [withdrawReceiptError]);

  // Handle success
  useEffect(() => {
    if (isApproveSuccess) {
      toast.success("Approval confirmed!");
      refetchAllowance();
    }
  }, [isApproveSuccess, refetchAllowance]);

  useEffect(() => {
    if (isDepositSuccess) {
      toast.success("Deposit confirmed!");
      setAmount("");
    }
  }, [isDepositSuccess]);

  useEffect(() => {
    if (isWithdrawSuccess) {
      toast.success("Withdrawal confirmed!");
      setAmount("");
    }
  }, [isWithdrawSuccess]);

  // USDC has 6 decimals
  const parsedAmount = amount ? parseUnits(amount, 6) : BigInt(0);
  const needsApproval =
    activeTab === "deposit" &&
    usdcAllowance !== undefined &&
    parsedAmount > (usdcAllowance as bigint);

  const handleApprove = () => {
    approveUsdc({
      address: CONTRACTS.USDC as `0x${string}`,
      abi: parseAbi(ERC20_ABI),
      functionName: "approve",
      args: [CONTRACTS.LP_VAULT_LONG as `0x${string}`, parsedAmount],
    });
  };

  const handleDeposit = () => {
    if (!address || !parsedAmount) return;

    deposit({
      address: CONTRACTS.LP_VAULT_LONG as `0x${string}`,
      abi: parseAbi(LP_VAULT_ABI),
      functionName: "deposit",
      args: [parsedAmount, address],
    });
  };

  const handleWithdraw = () => {
    if (!address || !parsedAmount) return;

    withdraw({
      address: CONTRACTS.LP_VAULT_LONG as `0x${string}`,
      abi: parseAbi(LP_VAULT_ABI),
      functionName: "withdraw",
      args: [parsedAmount, address, address],
    });
  };

  const handleMaxClick = () => {
    if (activeTab === "deposit" && usdcBalance) {
      setAmount(formatUnits(usdcBalance as bigint, 6));
    } else if (activeTab === "withdraw" && assetsValue) {
      setAmount(formatUnits(assetsValue, 6));
    }
  };

  const isLoading =
    isApproving ||
    isApproveConfirming ||
    isDepositing ||
    isDepositConfirming ||
    isWithdrawing ||
    isWithdrawConfirming;

  return (
    <div className="glass-card p-6">
      {/* Tabs */}
      <div className="mb-6 flex gap-2 rounded-lg bg-white/5 p-1">
        <button
          onClick={() => {
            setActiveTab("deposit");
            setAmount("");
          }}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-all ${
            activeTab === "deposit"
              ? "bg-accent-purple text-white"
              : "text-foreground-muted hover:text-white"
          }`}
        >
          Deposit
        </button>
        <button
          onClick={() => {
            setActiveTab("withdraw");
            setAmount("");
          }}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-all ${
            activeTab === "withdraw"
              ? "bg-accent-purple text-white"
              : "text-foreground-muted hover:text-white"
          }`}
        >
          Withdraw
        </button>
      </div>

      {/* Input */}
      <TokenInput
        value={amount}
        onChange={setAmount}
        symbol="USDC"
        balance={
          activeTab === "deposit"
            ? formatTokenAmount(usdcBalance as bigint | undefined, 6, 2)
            : formatTokenAmount(assetsValue, 6, 2)
        }
        onMax={handleMaxClick}
        disabled={!isConnected}
      />

      {/* Preview */}
      {amount && parseFloat(amount) > 0 && (
        <div className="mt-4 rounded-lg bg-white/5 p-4">
          <div className="flex justify-between text-sm">
            <span className="text-foreground-muted">You will receive</span>
            <span>~{amount} {activeTab === "deposit" ? "lpUSDC" : "USDC"}</span>
          </div>
        </div>
      )}

      {/* Action Button */}
      <div className="mt-6">
        {!isConnected ? (
          <div className="rounded-xl bg-white/5 p-4 text-center text-foreground-muted">
            Connect wallet to continue
          </div>
        ) : activeTab === "deposit" ? (
          needsApproval ? (
            <TransactionButton
              onClick={handleApprove}
              isLoading={isApproving || isApproveConfirming}
              loadingText="Approving..."
              disabled={!amount || parseFloat(amount) <= 0}
            >
              Approve USDC
            </TransactionButton>
          ) : (
            <TransactionButton
              onClick={handleDeposit}
              isLoading={isDepositing || isDepositConfirming}
              loadingText="Depositing..."
              disabled={!amount || parseFloat(amount) <= 0}
            >
              Deposit USDC
            </TransactionButton>
          )
        ) : (
          <TransactionButton
            onClick={handleWithdraw}
            isLoading={isWithdrawing || isWithdrawConfirming}
            loadingText="Withdrawing..."
            disabled={!amount || parseFloat(amount) <= 0}
            variant="secondary"
          >
            Withdraw USDC
          </TransactionButton>
        )}
      </div>

      {/* User Position */}
      {isConnected && shares && shares > BigInt(0) && (
        <div className="mt-6 border-t border-white/10 pt-6">
          <h4 className="mb-3 text-sm font-medium text-foreground-muted">
            Your Position
          </h4>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-foreground-muted">Shares</span>
              <span>{formatTokenAmount(shares, 6, 2)} lpUSDC</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-foreground-muted">Value</span>
              <span>{formatTokenAmount(assetsValue, 6, 2)} USDC</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
