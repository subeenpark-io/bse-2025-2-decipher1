# Project TODO

## Overview

Decentralized index fund protocol on Base Sepolia:
- Contracts: Solidity + Foundry (ERC-4626, UUPS upgradeable, Uniswap V3)
- Frontend: Next.js/React (placeholder only)
- Status: Prototype - contracts functional, frontend non-existent

---

## Critical Issues

1. **Price Oracle Missing** (IndexFund.sol:146-151)
   - totalAssets() sums raw balances without price conversion
   - Need Chainlink integration (2-3 days)

2. **Frontend Non-Functional(Resolved)** (app/page.tsx) 
   - No Web3 integration, wallet connection, or contract interactions
   - Requires wagmi/viem setup (2-4 weeks)

3. **Unsafe Low-Level Call** (IndexFund.sol:110)
   - Using raw call() to swap router
   - Use typed interface calls (1 day)

4. **No Pause Mechanism** (Resolved)
   - Added PausableUpgradeable to IndexFund.sol
   - pause()/unpause() owner functions with whenNotPaused on deposit/mint/withdraw/redeem/rebalance

## High Priority

5. **Test Coverage Gaps**
   - Empty rebalance test, no swap execution tests
   - Missing edge cases (2-3 days)

6. **No Governance Timelock**
   - Proposals execute immediately
   - Add 2-7 day delay (2 days)

7. **Approval Pattern Issue** (IndexFund.sol:103-107)
   - safeIncreaseAllowance() may fail on repeated calls
   - Reset to 0 first (1 day)

## Nice to Have

8. **TypeChain Integration** - Generate TS types from ABIs (1 day)
9. **Version Tracking** - Add version fields to upgradeable contracts (1 day)
10. **Documentation** - Architecture diagrams, deployment guides (3-5 days)

## Quick Reference

**Core Contracts**: IndexFund.sol, FundFactory.sol, FundGovernance.sol
**Test Coverage**: Basic tests present, missing edge cases and integration tests
**Scripts**: Deploy, Rebalance, CollectFees (all optimized)
**Frontend**: Placeholder only - needs complete rebuild

