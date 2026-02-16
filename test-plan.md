# Test & Verification Plan

## 1. Objectives

The goal of testing and verification is to ensure that:

* Compliance rules are **strictly enforced on-chain**
* Unauthorized minting or transfers are impossible
* Administrative controls behave correctly under normal and adverse conditions
* Corporate actions distribute value correctly and safely
* Operational risks are minimized

Testing focuses on **correctness, safety, and invariants**, not UI behavior.

---

## 2. Unit Testing Strategy

### 2.1 ComplianceModule

**Positive Tests**

* Allowlisted investor can receive tokens
* Investor meeting jurisdiction & investor-type requirements can transfer
* Tranche-specific rules are enforced correctly
* `getInvestor()` returns correct compliance data for a registered investor

**Negative Tests**

* Non-allowlisted investor cannot receive tokens
* Frozen investor cannot send or receive tokens
* Jurisdiction mismatch causes transfer revert
* Investor-type mismatch causes transfer revert

**Edge Cases**

* Changing compliance rules after issuance
* Freezing investor with existing balance
* Unfreezing restores transfer ability
* `setInvestor()` preserves existing frozen state — updating jurisdiction or investor type does not unfreeze
* `setTrancheRequirements()` emits `TrancheRequirementUpdated` event

---

### 2.2 AssetToken

**Minting**

* Only ISSUER_ROLE can mint
* Mint updates totalSupply correctly
* Mint to non-allowlisted address fails — compliance enforced via `_update` hook (OZ v5)
* Mint to allowlisted address succeeds even though `from == address(0)` (sender check skipped for mints)
* Mint exceeding `maxSupply` cap reverts
* Mint succeeds when `maxSupply` is 0 (unlimited)

**Transfers**

* Transfers succeed only when ComplianceModule approves
* Batch transfers enforce compliance for each tranche
* Transfers blocked when paused
* `balanceOfAt(account, id, blockNumber)` returns correct historical balance after transfers

**Burning**

* Only issuer can burn
* Burn reduces supply correctly
* Burn does not trigger compliance check on `to` (address(0) exempt)

**Max Supply**

* `setMaxSupply()` restricted to ADMIN_ROLE
* `setMaxSupply()` emits `MaxSupplySet` event
* Minting up to cap succeeds, minting beyond cap reverts
* Changing cap after minting works correctly

**Forced Transfer**

* Only `DEFAULT_ADMIN_ROLE` can call `forceTransfer()`
* Forced transfer bypasses compliance checks (works even if receiver not allowlisted)
* Forced transfer works when contract is paused
* Forced transfer emits `ForcedTransfer` event
* Forced transfer updates balance checkpoints correctly
* `balanceOfAt()` returns correct values after forced transfer

---

### 2.3 IssuanceModule

**Positive**

* Investor can request subscription for a tranche — stored at `subscriptions[investor][trancheId]`
* Investor can have concurrent pending subscriptions in different tranches simultaneously
* Issuer approves via `approveSubscription(investor, trancheId)` — trancheId required
* Approved subscription results in mint
* Investor can cancel a pending (unapproved) subscription via `cancelSubscription(trancheId)`

**Negative**

* Unauthorized approval reverts
* Double approval for same tranche reverts
* Requesting a new subscription while one is pending for the same tranche reverts
* Mint without approval is impossible
* `requestSubscription` with `amount == 0` reverts
* `cancelSubscription` reverts if no pending subscription exists
* `cancelSubscription` reverts if subscription already approved

**Edge**

* Investor can re-request after a subscription is approved
* Investor can re-request after cancelling a subscription
* Approval after compliance rule change (mint may revert if investor no longer compliant)
* Cancellation emits `SubscriptionCancelled` event

---

### 2.4 CorporateActionsModule

**Positive**

* `declareDividend(trancheId, amountPerToken)` creates a new round, increments `currentRound[trancheId]`
* `claimDividend(trancheId, round)` pays based on `balanceOfAt(investor, trancheId, snapshotBlock)` — balance at record date
* Multiple rounds can coexist — declaring round 2 does not affect round 1 claims
* Payout transferred in stablecoin (ERC20), not ETH

**Negative**

* Double claim for same round reverts
* Claim with zero balance at snapshot block fails
* Claim for non-existent round fails (`snapshotBlock == 0`)
* Investor who bought tokens after declaration gets zero payout for that round
* `declareDividend` with `amountPerToken == 0` reverts

**Edge**

* Investor sells tokens after declaration — payout still based on snapshot, not current balance
* Investor transfers tokens between declaration and claim — snapshot balance used correctly
* Second dividend declared before first is fully claimed — both rounds independently claimable

**Reentrancy**

* `claimDividend` is protected by `nonReentrant` modifier (ReentrancyGuard)
* CEI pattern: `claimed` state is updated before external `transfer` call
* Malicious ERC20 token callback cannot re-enter `claimDividend`

---

## 3. Integration Tests

### Full Lifecycle Scenario

1. Admin sets tranche requirements via `ComplianceModule.setTrancheRequirements()`
2. Admin sets max supply via `AssetToken.setMaxSupply(trancheId, cap)`
3. Investor is allowlisted via `ComplianceModule.setInvestor()`
4. `getInvestor()` confirms investor compliance data on-chain
5. Investor calls `requestSubscription(trancheId, amount)`
6. Issuer calls `approveSubscription(investor, trancheId)` — tokens minted via `_update` hook with compliance check, subject to `maxSupply` cap
7. Secondary transfer attempted:

   * Passes when both parties compliant
   * Reverts when receiver not allowlisted
8. Issuer declares dividend: `declareDividend(trancheId, amountPerToken)` — `snapshotBlock` recorded
9. Investor calls `claimDividend(trancheId, round)` — payout based on snapshot balance, paid in stablecoin
10. Admin pauses contract — transfers blocked
11. Admin executes `forceTransfer()` — succeeds even while paused
12. Admin unpauses — normal transfers resume

This test validates **cross-module correctness**.

### Subscription Cancellation Flow

1. Investor requests subscription
2. Investor cancels subscription before approval
3. Investor re-requests subscription
4. Issuer approves — tokens minted

### Frozen State Preservation

1. Investor is allowlisted and frozen
2. Admin calls `setInvestor()` to update jurisdiction
3. Verify investor remains frozen after update
4. Admin explicitly calls `freeze(investor, false)` to unfreeze

---

## 4. Property-Based & Fuzz Testing

### Key Properties to Fuzz

* Random transfer amounts
* Random investor addresses
* Random tranche IDs
* Random order of operations

### Example Properties

* Transfers never succeed to non-allowlisted addresses
* Frozen investors never receive tokens
* Total supply never increases without mint
* Total supply never exceeds `maxSupply` for any tranche (when cap > 0)
* `setInvestor()` never changes frozen state
* Forced transfers always emit `ForcedTransfer` event

---

## 5. Formal Invariants (Explicit)

These invariants should **always hold**:

1. **Compliance Invariant**

   > A token transfer must revert if `ComplianceModule.canTransfer()` returns false.

2. **Mint Authority Invariant**

   > Only addresses with ISSUER_ROLE can mint tokens (via normal mint path).

3. **Pause Invariant**

   > When paused, no token transfers can succeed — except `forceTransfer()`.

4. **Supply Invariant**

   > Sum of all balances for a tranche equals `totalSupply[trancheId]`.

5. **Supply Cap Invariant**

   > `totalSupply[trancheId] <= maxSupply[trancheId]` when `maxSupply[trancheId] > 0`.

6. **Dividend Claim Invariant**

   > An investor can claim at most once per round per tranche — `claimed[trancheId][round][investor]` is set before payout.

7. **Dividend Snapshot Invariant**

   > An investor's dividend payout is always based on their balance at `snapshotBlock`, never their current balance.

8. **Frozen Preservation Invariant**

   > `setInvestor()` never modifies the `frozen` field of an existing investor record.

9. **Forced Transfer Invariant**

   > `forceTransfer()` is the only code path that bypasses compliance checks — restricted to `DEFAULT_ADMIN_ROLE`.

---

## 6. Admin Safety Tests

* Verify roles cannot be accidentally renounced
* Verify paused state blocks all normal transfers
* Verify `forceTransfer()` works during pause
* Verify emergency pause blocks all transfers except forced
* Verify `setInvestor()` preserves frozen state across updates
* Verify role separation: ISSUER_ROLE, COMPLIANCE_ADMIN_ROLE, ADMIN_ROLE, DEFAULT_ADMIN_ROLE

---

## 7. Security Review Checklist

Before deployment:

* [ ] Reentrancy reviewed in payout paths — CEI + ReentrancyGuard verified
* [ ] No external calls before state updates in `claimDividend`
* [ ] All privileged functions role-protected
* [ ] No unbounded loops
* [ ] No PII stored on-chain
* [ ] Events emitted for critical actions
* [ ] `forceTransfer` bypasses compliance intentionally — documented and role-restricted
* [ ] `maxSupply` cap enforced on every mint
* [ ] `setInvestor()` frozen preservation verified
* [ ] All interfaces implemented correctly (`is IAssetToken`, `is IComplianceModule`, etc.)

---

## 8. Manual Testing (Operational)

* Simulate admin key compromise
* Freeze investor during active trading
* Pause during corporate action
* Execute forced transfer during pause
* Cancel subscription and re-subscribe
* Query investor data via `getInvestor()` from backend
* Reconcile backend events vs on-chain logs

---

## 9. Tooling Recommendations (Optional)

* Hardhat / Foundry for unit testing
* Echidna or Foundry fuzzing
* Slither static analysis
* Manual peer review

Tooling is recommended but not required for submission.

---

## 10. Summary

This test & verification strategy ensures:

* Hard compliance guarantees
* Correct asset lifecycle behavior
* Safe operational controls (including forced transfers and supply caps)
* Defense-in-depth security verification (CEI + ReentrancyGuard)
* Frozen state preservation across updates
* High confidence in production readiness

The plan is intentionally practical, focused, and aligned with real-world deployment needs.

---
