"use client";

import { useReadContracts, useAccount } from "wagmi";
import { Loader2, CheckCircle, XCircle, Clock, PlayCircle } from "lucide-react";
import { useGovernanceParams } from "@/hooks";
import { VoteCard } from "./VoteCard";

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

type ProposalStatus = "active" | "passed" | "failed" | "executed" | "canceled";

function getProposalStatus(proposal: Proposal): ProposalStatus {
  if (proposal.canceled) return "canceled";
  if (proposal.executed) return "executed";

  const now = BigInt(Math.floor(Date.now() / 1000));
  if (now < proposal.endTime) return "active";

  const totalVotes = proposal.forVotes + proposal.againstVotes;
  if (totalVotes === BigInt(0)) return "failed";

  const forPercent = (Number(proposal.forVotes) / Number(totalVotes)) * 100;
  return forPercent > 50 ? "passed" : "failed";
}

function StatusBadge({ status }: { status: ProposalStatus }) {
  const config = {
    active: { color: "bg-accent-blue/20 text-accent-blue", icon: Clock, label: "Active" },
    passed: { color: "bg-success/20 text-success", icon: CheckCircle, label: "Passed" },
    failed: { color: "bg-error/20 text-error", icon: XCircle, label: "Failed" },
    executed: { color: "bg-accent-purple/20 text-accent-purple", icon: PlayCircle, label: "Executed" },
    canceled: { color: "bg-foreground-muted/20 text-foreground-muted", icon: XCircle, label: "Canceled" },
  };

  const { color, icon: Icon, label } = config[status];

  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2 py-1 text-xs font-medium ${color}`}>
      <Icon className="h-3 w-3" />
      {label}
    </span>
  );
}

interface ProposalListProps {
  governanceAddress: string;
}

export function ProposalList({ governanceAddress }: ProposalListProps) {
  const { proposalCount, isLoading: paramsLoading } = useGovernanceParams(governanceAddress);
  const { address } = useAccount();

  // Build contracts array for fetching all proposals
  const proposalIds = proposalCount
    ? Array.from({ length: Number(proposalCount) }, (_, i) => BigInt(i))
    : [];

  const getProposalAbi = [
    {
      name: "getProposal",
      type: "function",
      stateMutability: "view",
      inputs: [{ name: "proposalId", type: "uint256" }],
      outputs: [
        {
          name: "",
          type: "tuple",
          components: [
            { name: "id", type: "uint256" },
            { name: "description", type: "string" },
            { name: "proposer", type: "address" },
            { name: "forVotes", type: "uint256" },
            { name: "againstVotes", type: "uint256" },
            { name: "startTime", type: "uint256" },
            { name: "endTime", type: "uint256" },
            { name: "executed", type: "bool" },
            { name: "canceled", type: "bool" },
          ],
        },
      ],
    },
  ] as const;

  const proposalContracts = proposalIds.flatMap((id) => [
    {
      address: governanceAddress as `0x${string}`,
      abi: getProposalAbi,
      functionName: "getProposal" as const,
      args: [id],
    },
  ]);

  const { data: proposalsData, isLoading: proposalsLoading } = useReadContracts({
    contracts: proposalContracts,
    query: { enabled: proposalIds.length > 0 },
  });

  // Parse proposals data
  const proposals: Proposal[] = (proposalsData || [])
    .map((result) => {
      if (!result.result) return null;
      const p = result.result as unknown as Proposal;
      return p;
    })
    .filter((p): p is Proposal => p !== null);

  // Separate active and past proposals
  const activeProposals = proposals.filter((p) => getProposalStatus(p) === "active");
  const pastProposals = proposals
    .filter((p) => getProposalStatus(p) !== "active")
    .reverse(); // Most recent first

  const isLoading = paramsLoading || proposalsLoading;

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-accent-purple" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Active Proposals */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">Active Proposals</h2>
        {activeProposals.length === 0 ? (
          <div className="glass-card p-8 text-center text-foreground-muted">
            No active proposals
          </div>
        ) : (
          <div className="space-y-4">
            {activeProposals.map((proposal) => (
              <VoteCard key={proposal.id.toString()} proposal={proposal} governanceAddress={governanceAddress} />
            ))}
          </div>
        )}
      </section>

      {/* Past Proposals */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">Past Proposals</h2>
        {pastProposals.length === 0 ? (
          <div className="glass-card p-8 text-center text-foreground-muted">
            No past proposals
          </div>
        ) : (
          <div className="space-y-3">
            {pastProposals.map((proposal) => {
              const status = getProposalStatus(proposal);
              const totalVotes = proposal.forVotes + proposal.againstVotes;
              const forPercent =
                totalVotes > BigInt(0)
                  ? (Number(proposal.forVotes) / Number(totalVotes)) * 100
                  : 0;

              return (
                <div
                  key={proposal.id.toString()}
                  className="glass-card flex items-center justify-between p-4"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="text-sm text-foreground-muted">
                        #{proposal.id.toString()}
                      </span>
                      <StatusBadge status={status} />
                    </div>
                    <p className="mt-1 font-medium">{proposal.description}</p>
                    <p className="mt-1 text-sm text-foreground-muted">
                      By {proposal.proposer.slice(0, 6)}...{proposal.proposer.slice(-4)}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm text-foreground-muted">Final Result</p>
                    <p className="font-medium">
                      {forPercent.toFixed(1)}% For / {(100 - forPercent).toFixed(1)}% Against
                    </p>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}
