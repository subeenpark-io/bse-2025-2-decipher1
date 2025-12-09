"use client";

import { useState, useEffect } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseAbi, toHex } from "viem";
import toast from "react-hot-toast";
import { Plus, X } from "lucide-react";
import { TransactionButton } from "@/components/shared/TransactionButton";
import { FUND_GOVERNANCE_ABI } from "@/lib/abis";
import { useVotingPower, useGovernanceParams, formatTokenAmount, parseError } from "@/hooks";

interface CreateProposalProps {
  governanceAddress: string;
}

export function CreateProposal({ governanceAddress }: CreateProposalProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [description, setDescription] = useState("");

  const { isConnected } = useAccount();
  const { votingPower } = useVotingPower(governanceAddress);
  const { proposalThreshold } = useGovernanceParams(governanceAddress);

  const canPropose =
    votingPower &&
    proposalThreshold &&
    votingPower >= proposalThreshold;

  // Create proposal
  const {
    writeContract: createProposal,
    isPending: isCreating,
    data: createHash,
    error: createError,
  } = useWriteContract();

  const { isLoading: isCreateConfirming, isSuccess: isCreateSuccess, error: createReceiptError } = useWaitForTransactionReceipt({
    hash: createHash,
  });

  // Handle errors
  useEffect(() => {
    if (createError) {
      toast.error(parseError(createError), { duration: 5000 });
    }
  }, [createError]);

  useEffect(() => {
    if (createReceiptError) {
      toast.error(parseError(createReceiptError), { duration: 5000 });
    }
  }, [createReceiptError]);

  // Handle success
  useEffect(() => {
    if (isCreateSuccess) {
      toast.success("Proposal created successfully!");
      setDescription("");
      setIsOpen(false);
    }
  }, [isCreateSuccess]);

  const handleCreate = () => {
    if (!description.trim()) {
      toast.error("Please enter a description");
      return;
    }

    createProposal({
      address: governanceAddress as `0x${string}`,
      abi: parseAbi(FUND_GOVERNANCE_ABI),
      functionName: "propose",
      args: [description, toHex("")],
    });
  };

  if (!isConnected) {
    return null;
  }

  return (
    <div>
      {!isOpen ? (
        <button
          onClick={() => setIsOpen(true)}
          disabled={!canPropose}
          className="flex items-center gap-2 rounded-xl bg-gradient-to-r from-purple-600 to-blue-600 px-4 py-2 font-semibold text-white transition-all hover:from-purple-500 hover:to-blue-500 hover:shadow-[0_0_20px_rgba(139,92,246,0.4)] disabled:cursor-not-allowed disabled:opacity-50"
        >
          <Plus className="h-4 w-4" />
          Create Proposal
        </button>
      ) : (
        <div className="glass-card p-6">
          <div className="mb-4 flex items-center justify-between">
            <h3 className="text-lg font-semibold">Create New Proposal</h3>
            <button
              onClick={() => setIsOpen(false)}
              className="rounded-lg p-1 hover:bg-white/10"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="space-y-4">
            <div>
              <label className="mb-2 block text-sm font-medium text-foreground-muted">
                Proposal Description
              </label>
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Describe your proposal..."
                rows={4}
                className="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder:text-foreground-muted/50 focus:border-accent-purple focus:outline-none focus:ring-1 focus:ring-accent-purple"
              />
            </div>

            <div className="rounded-lg bg-white/5 p-3 text-sm">
              <div className="flex justify-between">
                <span className="text-foreground-muted">Your voting power</span>
                <span>{formatTokenAmount(votingPower)} IDX</span>
              </div>
              <div className="flex justify-between">
                <span className="text-foreground-muted">Required threshold</span>
                <span>{formatTokenAmount(proposalThreshold)} IDX</span>
              </div>
            </div>

            {!canPropose && (
              <div className="rounded-lg bg-warning/10 p-3 text-sm text-warning">
                You need at least {formatTokenAmount(proposalThreshold)} IDX to create a proposal.
              </div>
            )}

            <div className="flex gap-3">
              <TransactionButton
                onClick={handleCreate}
                isLoading={isCreating || isCreateConfirming}
                loadingText="Creating..."
                disabled={!canPropose || !description.trim()}
              >
                Submit Proposal
              </TransactionButton>
              <button
                onClick={() => setIsOpen(false)}
                className="flex-1 rounded-xl border border-white/10 bg-white/5 px-4 py-3 font-semibold transition-all hover:bg-white/10"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
