"use client";

import { useEffect } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseAbi } from "viem";
import toast from "react-hot-toast";
import { ThumbsUp, ThumbsDown, Clock, PlayCircle } from "lucide-react";
import { TransactionButton } from "@/components/shared/TransactionButton";
import { FUND_GOVERNANCE_ABI } from "@/lib/abis";
import { formatTokenAmount, parseError } from "@/hooks";

interface Proposal {
  id: bigint;
  description: string;
  proposer: string;
  forVotes: bigint;
  againstVotes: bigint;
  startTime: bigint;
  endTime: bigint;
  executed: boolean;
  canceled: boolean;
}

interface VoteCardProps {
  proposal: Proposal;
  governanceAddress: string;
}

export function VoteCard({ proposal, governanceAddress }: VoteCardProps) {
  const { address, isConnected } = useAccount();

  // Check if user has voted
  const { data: hasVoted } = useReadContract({
    address: governanceAddress as `0x${string}`,
    abi: parseAbi([
      "function hasVoted(uint256 proposalId, address account) view returns (bool)",
    ]),
    functionName: "hasVoted",
    args: address ? [proposal.id, address] : undefined,
    query: { enabled: !!address },
  });

  // Vote For
  const {
    writeContract: voteFor,
    isPending: isVotingFor,
    data: voteForHash,
    error: voteForError,
  } = useWriteContract();

  const { isLoading: isVoteForConfirming, isSuccess: isVoteForSuccess, error: voteForReceiptError } = useWaitForTransactionReceipt({
    hash: voteForHash,
  });

  // Vote Against
  const {
    writeContract: voteAgainst,
    isPending: isVotingAgainst,
    data: voteAgainstHash,
    error: voteAgainstError,
  } = useWriteContract();

  const { isLoading: isVoteAgainstConfirming, isSuccess: isVoteAgainstSuccess, error: voteAgainstReceiptError } = useWaitForTransactionReceipt({
    hash: voteAgainstHash,
  });

  // Execute
  const {
    writeContract: execute,
    isPending: isExecuting,
    data: executeHash,
    error: executeError,
  } = useWriteContract();

  const { isLoading: isExecuteConfirming, isSuccess: isExecuteSuccess, error: executeReceiptError } = useWaitForTransactionReceipt({
    hash: executeHash,
  });

  // Handle errors
  useEffect(() => {
    if (voteForError) {
      toast.error(parseError(voteForError), { duration: 5000 });
    }
  }, [voteForError]);

  useEffect(() => {
    if (voteForReceiptError) {
      toast.error(parseError(voteForReceiptError), { duration: 5000 });
    }
  }, [voteForReceiptError]);

  useEffect(() => {
    if (voteAgainstError) {
      toast.error(parseError(voteAgainstError), { duration: 5000 });
    }
  }, [voteAgainstError]);

  useEffect(() => {
    if (voteAgainstReceiptError) {
      toast.error(parseError(voteAgainstReceiptError), { duration: 5000 });
    }
  }, [voteAgainstReceiptError]);

  useEffect(() => {
    if (executeError) {
      toast.error(parseError(executeError), { duration: 5000 });
    }
  }, [executeError]);

  useEffect(() => {
    if (executeReceiptError) {
      toast.error(parseError(executeReceiptError), { duration: 5000 });
    }
  }, [executeReceiptError]);

  // Handle success
  useEffect(() => {
    if (isVoteForSuccess) {
      toast.success("Vote for confirmed!");
    }
  }, [isVoteForSuccess]);

  useEffect(() => {
    if (isVoteAgainstSuccess) {
      toast.success("Vote against confirmed!");
    }
  }, [isVoteAgainstSuccess]);

  useEffect(() => {
    if (isExecuteSuccess) {
      toast.success("Proposal executed successfully!");
    }
  }, [isExecuteSuccess]);

  const handleVote = (support: boolean) => {
    const fn = support ? voteFor : voteAgainst;
    fn({
      address: governanceAddress as `0x${string}`,
      abi: parseAbi(FUND_GOVERNANCE_ABI),
      functionName: "vote",
      args: [proposal.id, support],
    });
  };

  const handleExecute = () => {
    execute({
      address: governanceAddress as `0x${string}`,
      abi: parseAbi(FUND_GOVERNANCE_ABI),
      functionName: "execute",
      args: [proposal.id],
    });
  };

  // Calculate voting stats
  const totalVotes = proposal.forVotes + proposal.againstVotes;
  const forPercent =
    totalVotes > BigInt(0)
      ? (Number(proposal.forVotes) / Number(totalVotes)) * 100
      : 50;
  const againstPercent = 100 - forPercent;

  // Calculate time remaining
  const now = BigInt(Math.floor(Date.now() / 1000));
  const timeRemaining = Number(proposal.endTime - now);
  const isActive = now < proposal.endTime;
  const isPassed = !isActive && forPercent > 50 && totalVotes > BigInt(0);
  const canExecute = isPassed && !proposal.executed && !proposal.canceled;

  const formatTimeRemaining = (seconds: number): string => {
    if (seconds <= 0) return "Ended";
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m remaining`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h remaining`;
    return `${Math.floor(seconds / 86400)}d remaining`;
  };

  const isVoting =
    isVotingFor || isVoteForConfirming || isVotingAgainst || isVoteAgainstConfirming;

  return (
    <div className="glass-card p-6">
      {/* Header */}
      <div className="mb-4 flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-sm text-foreground-muted">
              Proposal #{proposal.id.toString()}
            </span>
            {isActive && (
              <span className="flex items-center gap-1 text-sm text-accent-blue">
                <Clock className="h-3 w-3" />
                {formatTimeRemaining(timeRemaining)}
              </span>
            )}
          </div>
          <h3 className="mt-1 text-lg font-semibold">{proposal.description}</h3>
          <p className="mt-1 text-sm text-foreground-muted">
            Proposed by {proposal.proposer.slice(0, 6)}...
            {proposal.proposer.slice(-4)}
          </p>
        </div>
      </div>

      {/* Voting Progress */}
      <div className="mb-4">
        <div className="mb-2 flex justify-between text-sm">
          <span className="text-success">For: {forPercent.toFixed(1)}%</span>
          <span className="text-error">Against: {againstPercent.toFixed(1)}%</span>
        </div>
        <div className="flex h-3 overflow-hidden rounded-full bg-white/10">
          <div
            className="bg-success transition-all"
            style={{ width: `${forPercent}%` }}
          />
          <div
            className="bg-error transition-all"
            style={{ width: `${againstPercent}%` }}
          />
        </div>
        <div className="mt-2 flex justify-between text-xs text-foreground-muted">
          <span>{formatTokenAmount(proposal.forVotes)} votes</span>
          <span>{formatTokenAmount(proposal.againstVotes)} votes</span>
        </div>
      </div>

      {/* Actions */}
      {isConnected && (
        <div className="border-t border-white/10 pt-4">
          {isActive ? (
            hasVoted ? (
              <div className="rounded-lg bg-white/5 p-3 text-center text-sm text-foreground-muted">
                You have already voted on this proposal
              </div>
            ) : (
              <div className="flex gap-3">
                <TransactionButton
                  onClick={() => handleVote(true)}
                  isLoading={isVotingFor || isVoteForConfirming}
                  loadingText="Voting..."
                  disabled={isVoting}
                >
                  <ThumbsUp className="h-4 w-4" />
                  Vote For
                </TransactionButton>
                <TransactionButton
                  onClick={() => handleVote(false)}
                  isLoading={isVotingAgainst || isVoteAgainstConfirming}
                  loadingText="Voting..."
                  disabled={isVoting}
                  variant="secondary"
                >
                  <ThumbsDown className="h-4 w-4" />
                  Vote Against
                </TransactionButton>
              </div>
            )
          ) : canExecute ? (
            <TransactionButton
              onClick={handleExecute}
              isLoading={isExecuting || isExecuteConfirming}
              loadingText="Executing..."
            >
              <PlayCircle className="h-4 w-4" />
              Execute Proposal
            </TransactionButton>
          ) : (
            <div className="rounded-lg bg-white/5 p-3 text-center text-sm text-foreground-muted">
              {proposal.executed
                ? "This proposal has been executed"
                : proposal.canceled
                  ? "This proposal was canceled"
                  : "Voting has ended"}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
