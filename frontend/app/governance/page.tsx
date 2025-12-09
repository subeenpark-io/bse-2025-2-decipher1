"use client";

import { useState } from "react";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { parseAbi } from "viem";
import { ChevronDown, Loader2 } from "lucide-react";
import { StatCard } from "@/components/shared";
import { ProposalList, CreateProposal } from "@/components/governance";
import {
  useGovernanceParams,
  useVotingPower,
  useIndexFundStats,
  formatTokenAmount,
} from "@/hooks";
import { CONTRACTS } from "@/lib/contracts";
import { FUND_FACTORY_ABI, ERC20_ABI } from "@/lib/abis";

export default function GovernancePage() {
  const [selectedFund, setSelectedFund] = useState<string>(CONTRACTS.INDEX_FUND);
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

  const { isConnected } = useAccount();

  // Get all funds from factory
  const { data: fundsData, isLoading: fundsLoading } = useReadContract({
    address: CONTRACTS.FUND_FACTORY as `0x${string}`,
    abi: parseAbi(FUND_FACTORY_ABI),
    functionName: "getAllFunds",
  });

  const funds = (fundsData as string[]) || [];

  // Get fund names and symbols for selector
  const fundInfoContracts = funds.flatMap((fundAddress) => [
    {
      address: fundAddress as `0x${string}`,
      abi: parseAbi(ERC20_ABI),
      functionName: "name" as const,
    },
    {
      address: fundAddress as `0x${string}`,
      abi: parseAbi(ERC20_ABI),
      functionName: "symbol" as const,
    },
  ]);

  const { data: fundInfoData } = useReadContracts({
    contracts: fundInfoContracts,
    query: { enabled: funds.length > 0 },
  });

  const fundOptions = funds.map((address, index) => ({
    address,
    name: (fundInfoData?.[index * 2]?.result as string) || `Fund ${index + 1}`,
    symbol: (fundInfoData?.[index * 2 + 1]?.result as string) || "FUND",
  }));

  const selectedFundInfo = fundOptions.find((f) => f.address === selectedFund);
  const selectedFundName = selectedFundInfo?.name || "Select Fund";
  const selectedFundSymbol = selectedFundInfo?.symbol || "FUND";

  // Use the selected fund's governance address (currently using default governance)
  // In future, this should query the fund's governance address
  const governanceAddress = CONTRACTS.FUND_GOVERNANCE;

  const { votingPower, isLoading: votingPowerLoading } = useVotingPower(governanceAddress);
  const {
    votingPeriod,
    quorumPercent,
    proposalThreshold,
    proposalCount,
    isLoading: paramsLoading,
  } = useGovernanceParams(governanceAddress);
  const { totalSupply } = useIndexFundStats(selectedFund);

  // Calculate voting power percentage
  const votingPowerPercent =
    votingPower && totalSupply && totalSupply > BigInt(0)
      ? (Number(votingPower) / Number(totalSupply)) * 100
      : 0;

  // Format voting period
  const formatDuration = (seconds: bigint | undefined): string => {
    if (!seconds) return "0";
    const s = Number(seconds);
    if (s < 3600) return `${Math.floor(s / 60)} minutes`;
    if (s < 86400) return `${Math.floor(s / 3600)} hours`;
    return `${Math.floor(s / 86400)} days`;
  };

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-3xl font-bold gradient-text">Governance</h1>
          <p className="mt-2 text-foreground-muted">
            Participate in protocol decisions with your fund tokens
          </p>
        </div>
        <CreateProposal governanceAddress={governanceAddress} fundSymbol={selectedFundSymbol} />
      </div>

      {/* Fund Selector */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">Select Fund</h2>
        <div className="relative">
          <button
            onClick={() => setIsDropdownOpen(!isDropdownOpen)}
            className="glass-card flex w-full items-center justify-between p-4 text-left transition-all hover:bg-white/10"
          >
            <div>
              <p className="font-medium">{selectedFundName}</p>
              <p className="text-sm text-foreground-muted">
                {selectedFund.slice(0, 6)}...{selectedFund.slice(-4)}
              </p>
            </div>
            <ChevronDown
              className={`h-5 w-5 text-foreground-muted transition-transform ${
                isDropdownOpen ? "rotate-180" : ""
              }`}
            />
          </button>

          {isDropdownOpen && (
            <div className="absolute z-10 mt-2 w-full rounded-xl border border-white/10 bg-bg-card shadow-lg">
              {fundsLoading ? (
                <div className="flex items-center justify-center p-4">
                  <Loader2 className="h-5 w-5 animate-spin text-accent-purple" />
                </div>
              ) : fundOptions.length === 0 ? (
                <div className="p-4 text-center text-foreground-muted">
                  No funds available
                </div>
              ) : (
                fundOptions.map((fund) => (
                  <button
                    key={fund.address}
                    onClick={() => {
                      setSelectedFund(fund.address);
                      setIsDropdownOpen(false);
                    }}
                    className={`w-full p-4 text-left transition-all hover:bg-white/5 ${
                      selectedFund === fund.address
                        ? "bg-accent-purple/10"
                        : ""
                    }`}
                  >
                    <p className="font-medium">{fund.name}</p>
                    <p className="text-sm text-foreground-muted">
                      {fund.address.slice(0, 6)}...{fund.address.slice(-4)}
                    </p>
                  </button>
                ))
              )}
            </div>
          )}
        </div>
      </section>

      {/* User Stats */}
      {isConnected && (
        <section>
          <h2 className="mb-4 text-lg font-semibold">Your Voting Power</h2>
          <div className="glass-card p-6">
            <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm text-foreground-muted">Voting Power</p>
                <p className="mt-1 text-3xl font-bold">
                  {formatTokenAmount(votingPower)} {selectedFundSymbol}
                </p>
                <p className="mt-1 text-sm text-foreground-muted">
                  {votingPowerPercent.toFixed(2)}% of total supply
                </p>
              </div>
              <div className="h-px w-full bg-white/10 sm:h-16 sm:w-px" />
              <div>
                <p className="text-sm text-foreground-muted">
                  Proposal Threshold
                </p>
                <p className="mt-1 text-xl font-bold">
                  {formatTokenAmount(proposalThreshold)} {selectedFundSymbol}
                </p>
                <p className="mt-1 text-sm text-foreground-muted">
                  Minimum to create proposals
                </p>
              </div>
            </div>
          </div>
        </section>
      )}

      {/* Governance Parameters */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">Governance Parameters</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            title="Total Proposals"
            value={proposalCount?.toString() || "0"}
            isLoading={paramsLoading}
          />
          <StatCard
            title="Voting Period"
            value={formatDuration(votingPeriod)}
            isLoading={paramsLoading}
          />
          <StatCard
            title="Quorum"
            value={`${quorumPercent?.toString() || "0"}%`}
            subtitle="Of total supply"
            isLoading={paramsLoading}
          />
          <StatCard
            title="Proposal Threshold"
            value={formatTokenAmount(proposalThreshold)}
            subtitle={`${selectedFundSymbol} required`}
            isLoading={paramsLoading}
          />
        </div>
      </section>

      {/* Proposals List */}
      <ProposalList governanceAddress={governanceAddress} />

      {/* How it works */}
      <section>
        <h2 className="mb-4 text-lg font-semibold">How Governance Works</h2>
        <div className="glass-card p-6">
          <div className="grid gap-6 md:grid-cols-4">
            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-purple/20">
                <span className="text-lg font-bold text-accent-purple">1</span>
              </div>
              <h3 className="font-medium">Hold Fund Tokens</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                Your voting power equals your {selectedFundSymbol} token balance in the fund.
              </p>
            </div>

            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-cyan/20">
                <span className="text-lg font-bold text-accent-cyan">2</span>
              </div>
              <h3 className="font-medium">Create Proposals</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                Users with enough {selectedFundSymbol} can create proposals for fund changes.
              </p>
            </div>

            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-blue/20">
                <span className="text-lg font-bold text-accent-blue">3</span>
              </div>
              <h3 className="font-medium">Vote</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                Cast your vote for or against proposals during the voting period.
              </p>
            </div>

            <div>
              <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-lg bg-accent-pink/20">
                <span className="text-lg font-bold text-accent-pink">4</span>
              </div>
              <h3 className="font-medium">Execute</h3>
              <p className="mt-1 text-sm text-foreground-muted">
                Passed proposals can be executed to implement the changes.
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
