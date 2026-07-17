# Sonic LP Position Recovery — Design

**Date:** 2026-07-15
**Status:** Approved for planning
**Goal:** Move Sneed DAO's Sonic LP position 2 under the `sneed_defi` canister (ok64) and withdraw the tokens and fees, using as few DAO proposals as possible.

## Summary

Position 2 in the Sonic SNEED/ICP pool is owned by the Sneed DAO governance canister. We transfer it to ok64 via a single governance proposal, then perform all remaining operations (claim, decrease liquidity, withdraw) by direct calls to ok64 from an authorized operator PID — no further proposals.

In parallel, and on the same timeline, we sweep the 40.70 ICP already stranded in Sonic under the governance principal straight into the SNS ICP treasury, using the generic function the DAO has *already registered*. Four proposals total, two waves, ~8 days.

**A critical finding reframes the outcome: the Sonic pool is insolvent.** It cannot honour the full claim. This design recovers what the pool actually holds and leaves the remainder as an open claim.

## Live state (verified on-chain 2026-07-15)

| Canister | ID |
|---|---|
| Sonic SNEED/ICP pool (active) | `ni6i4-cqaaa-aaaak-qtsbq-cai` |
| Sneed DAO governance | `fi3zi-fyaaa-aaaaq-aachq-cai` |
| Sneed DeFi canister (this repo) | `ok64y-uiaaa-aaaag-qdcbq-cai` |
| SNEED ledger (token0) | `hvgxa-wqaaa-aaaaq-aacia-cai`, fee 1,000, 8 decimals |
| ICP ledger (token1) | `ryjl3-tyaaa-aaaaa-aaaba-cai`, fee 10,000, 8 decimals |
| Operator PID | `tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe` |

Pool: fee tier 3000, current tick 23,976, total liquidity 339,301,279,969, `available = true`.

Position 2: owner `fi3zi` (`checkOwnerOfUserPosition` → `ok true`), liquidity **339,138,795,889** (~99.95% of pool), range tick 12,660–26,520 (in range), `tokensOwed0 = 301,641,723`, `tokensOwed1 = 3,195,932,904`.

Position 2 token value via SwapCalculator (`phr2m-oyaaa-aaaag-qjuoq-cai`): `amount0 = 12,214,407,804` (122.14 SNEED), `amount1 = 485,910,640,019` (4,859.11 ICP).

## The insolvency

Sonic's `getTokenBalance()` — the reserve view it checks withdrawals against — matches the ledgers exactly:

| | Pool holds | Total obligations (positions + unused balances) | Shortfall |
|---|---|---|---|
| SNEED | 5.56 | ~136.06 | **~130.5** |
| ICP | 1,877.05 | ~5,009.53 | **~3,132** |

Ruled out as explanations:
- **Old pre-migration canister** `3xwpq-ziaaa-aaaah-qcn4a-cai`: holds 1.80 SNEED, 0.0001 ICP. Not there.
- **WICP**: `getWICPMigrationSwitch` → `ok 0`; WICP balance of pool → 0. Not there.
- **Mistransfer balance**: rejects with "Please use deposit and withdraw instead".
- **Other LPs' funds**: position 2 is 99.95% of pool liquidity. The shortfall is overwhelmingly the DAO's.

This is already causing live failures. `getTransferLogs` shows principal `abgpi-…` repeatedly failing `withdraw` of ~13.8 SNEED on day 20,649 (2026-07-13) with `#InsufficientFunds({balance = 570_543_837})`.

**Consequence:** `decreaseLiquidity` is internal bookkeeping and will succeed, crediting ok64 with the full ~122 SNEED + ~4,859 ICP. `withdraw` pays from real reserves and will only honour ~1,877 ICP and ~5.5 SNEED. The rest becomes an unsecured claim against an insolvent pool.

**Reserves below obligations means withdrawals are first-come-first-served.** Speed is a design goal, not a preference.

### Correction to the prior diagnosis

The earlier theory was that governance's ICP withdraw "landed somewhere unusable." **This is disproven.** Two pieces of evidence:

1. The withdraw never completed. 40.70 ICP still sits in `fi3zi`'s Sonic unused balance today (`balance1 = 4_069_574_490`), so nothing ever landed anywhere.
2. Had it completed, the destination would have been fine. Sonic's `withdraw` credits `{owner = caller, subaccount = null}` (confirmed in `getTransferLogs`: `to = <caller>`, `fromSubaccount = null`). For `fi3zi` that is the **SNS ICP treasury**, which currently holds **7,379.58 ICP** and is spendable by the native `TransferSnsTreasuryFunds` proposal (function id 9).

Consequences:

- The 40.70 ICP is safe to sweep with governance as the caller. It lands in the DAO treasury. This is now **P3**, not deferred work.
- Routing the *position* proceeds to ok64 regardless. Not because `fi3zi` is a bad destination, but because only ok64 can operate a position it owns, and ok64's default subaccount is reachable by the existing governance-only `deploy_icrc1_tokens` (`from_subaccount = null`).

## Proposal plan — 4 proposals, 2 waves (~8 days)

The binding constraint: Sonic's `transferPosition` requires the caller to be the owner, so only `fi3zi` can move position 2; governance can only call an external canister through a registered generic function; and an `Execute` proposal cannot reference an unregistered function. `Add` → `Execute` is therefore an irreducible 2-wave chain at 4 days per wave (`initial_voting_period_seconds = 345_600`). The upgrade rides in parallel and does not extend the critical path.

### Wave 1 (submit together, day 0)

**P1 — UpgradeSnsControlledCanister → ok64.** Adds the operator-callable Sonic methods and `validate_transfer_sonic_lp_position`.

**P2 — AddGenericNervousSystemFunction `transfer_sonic_lp_position`.**
- target canister `ni6i4-cqaaa-aaaak-qtsbq-cai`, target method `transferPosition`
- validator canister `ok64y-uiaaa-aaaag-qdcbq-cai`, validator method `validate_transfer_sonic_lp_position`
- topic: `TreasuryAssetManagement` (consistent with 3_003/3_004)

Parallel-safe: `AddGenericNervousSystemFunction` registers a name and does not verify the target/validator method exists. If P2 executes before P1, the function is merely unusable until P1 lands; it is only invoked in wave 2.

**P3 — ExecuteGenericNervousSystemFunction `withdraw_sonic` (function id 3_004)** — sweeps the stranded 40.70 ICP into the SNS ICP treasury.

Payload (`WithdrawArgs`):

```candid
record { token = "ryjl3-tyaaa-aaaaa-aaaba-cai"; fee = 10_000 : nat; amount = 4_069_574_490 : nat }
```

Requires **no upgrade and no new function** — 3_004 is already registered (target `ni6i4` method `withdraw`, validator `ok64` method `validate_withdraw_sonic_lp`), so this is submittable on day 0. Fully independent of P1/P2/P4: governance's Sonic unused balance is keyed by principal and is unaffected by transferring the position. The pool holds 1,877.05 ICP, so it can cover this comfortably.

Two caveats:

- `amount` must be **exact and ≤ the unused balance**. Re-verify `getUserUnusedBalance(fi3zi)` immediately before submitting; if it has changed, update the payload.
- Do **not** claim position 2's fees before the transfer — that would credit `fi3zi` and invalidate this amount. The runbook claims *after* the transfer, as ok64.

The 1,000 SNEED dust (`balance0`) is deliberately left. With a ledger fee of 1,000 the withdrawal nets zero, so it does not justify a proposal.

### Wave 2 (day ~4)

**P4 — ExecuteGenericNervousSystemFunction** `transfer_sonic_lp_position` with `(from = fi3zi-fyaaa-aaaaq-aachq-cai, to = ok64y-uiaaa-aaaag-qdcbq-cai, positionId = 2)`.

### Rejected alternatives

- **Sequential (Upgrade → Add → Execute):** ~12 days. Four days slower in a race, no benefit.
- **Transfer to the operator's personal PID (2 proposals, no upgrade):** still gated by the same Add→Execute chain, so it is *exactly as slow* (~8 days) while placing ~1,877 ICP of DAO funds under a single personal key. Strictly dominated.
- **Reusing existing `validate_transfer_icpswap_lp_position` as P2's validator:** its candid signature `(principal, principal, nat)` happens to match `transferPosition` positionally, which would remove P2's dependency on P1. Rejected: it is misleading to voters reviewing the proposal, and the parallel-safety argument above already removes the dependency.

## Canister changes (`src/main.mo`, `src/poolTypes.mo`)

### Do not touch

`validate_claim_fees_sonic_lp_position`, `validate_decrease_liquidity_sonic_lp_position`, and `validate_withdraw_sonic_lp` are live validators for registered functions **3_003 (`claim_fees_sonic`)** and **3_004 (`withdraw_sonic`)**, which target the Sonic canister directly. Changing their signatures breaks those functions. New methods take distinct names.

### Authorization

```motoko
private let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
private let sonic_operator_id = "tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe";

private func is_sonic_operator(caller : Principal) : Bool {
  let c = Principal.toText(caller);
  c == sneed_governance_id or c == sonic_operator_id;
};
```

Hardcoded constants, removable in any later upgrade. No new stable state.

**Safety property (state this in the P1 proposal text):** none of these methods can send tokens to the caller. Sonic's `withdraw` always credits the *calling canister*, so funds can only land on ok64, where the governance-only `deploy_icrc1_tokens` controls them. The operator PID can pull funds **in**, never **out**. The pre-existing `send_icrc1_tokens` / `deploy_icrc1_tokens` authorization is unchanged.

### New types (`poolTypes.mo`)

Tags must match Sonic's candid exactly (lowercase `ok`/`err`):

```motoko
public type SonicError = {
  #CommonError;
  #InsufficientFunds;
  #InternalError : Text;
  #UnsupportedToken : Text;
};
public type SonicAmountsResult = { #ok : { amount0 : Nat; amount1 : Nat }; #err : SonicError };  // Result_22
public type SonicNatResult = { #ok : Nat; #err : SonicError };                                    // Result
public type SonicUnusedBalance = { balance0 : Nat; balance1 : Nat };
public type SonicTokenBalance = { token0 : Nat; token1 : Nat };
```

### New methods (`main.mo`)

All follow the existing try/catch + `log_msg` pattern so voters can pattern-match against already-audited code. All are `is_sonic_operator`-gated and return `#err(#InternalError(...))` when unauthorized.

```motoko
sonic_claim_position_fees(lp_canister_id : Principal, position_id : Nat) : async Pool.SonicAmountsResult
  // -> lp.claim({ positionId })

sonic_decrease_liquidity(lp_canister_id : Principal, position_id : Nat, liquidity : Text) : async Pool.SonicAmountsResult
  // -> lp.decreaseLiquidity({ positionId; liquidity })

sonic_withdraw(lp_canister_id : Principal, token : Text, fee : Nat, amount : Nat) : async Pool.SonicNatResult
  // -> lp.withdraw({ token; fee; amount })

sonic_withdraw_max(lp_canister_id : Principal, token : Text, fee : Nat) : async Pool.SonicNatResult
  // withdraws min(amount owed to ok64, reserves the pool actually holds)

validate_transfer_sonic_lp_position(from : Principal, to : Principal, position_id : Nat) : async T.ValidationResult
  // query; echoes args as #Ok(text). Validator for P2.
```

`sonic_withdraw_max` exists because of the insolvency: it reads `getUserUnusedBalance(ok64)` and `getTokenBalance()`, takes the minimum for the requested token, and withdraws that. This grabs the maximum available without guessing and turns "retry until reserves return" into one repeatable call.

```motoko
let owed = await lp.getUserUnusedBalance(ok64);
let held = await lp.getTokenBalance();
// select balance0/token0 for SNEED, balance1/token1 for ICP by matching `token`
let amount = Nat.min(owed_for_token, held_for_token);
if (amount <= fee) { return #err(#InsufficientFunds) };
await lp.withdraw({ token; fee; amount });
```

Note `getTokenBalance` is an update method on Sonic; `getUserUnusedBalance` is a query but is invoked as a replicated call from a canister. Both are awaited normally.

## Runbook after P4 (no proposals)

Executed by the operator PID against ok64. `lp = ni6i4-cqaaa-aaaak-qtsbq-cai`.

1. Verify ownership moved: `checkOwnerOfUserPosition(ok64, 2)` → `ok true`.
2. `sonic_claim_position_fees(lp, 2)` → credits ok64's unused balance (~3.02 SNEED + ~31.96 ICP).
3. `sonic_decrease_liquidity(lp, 2, "339138795889")` → credits ~122.14 SNEED + ~4,859.11 ICP. Position 2 remains, at zero liquidity.
4. `sonic_withdraw_max(lp, "ryjl3-tyaaa-aaaaa-aaaba-cai", 10000)` → ICP to ok64. **Do ICP first — it is the large, contested balance.**
5. `sonic_withdraw_max(lp, "hvgxa-wqaaa-aaaaq-aacia-cai", 1000)` → SNEED to ok64.
6. Re-run steps 4–5 periodically as reserves trickle back. The remaining unused balance is a standing claim.
7. Confirm receipt: `icrc1_balance_of(ok64)` on both ledgers.

Claim before decrease: `claim` is the exact call already proven to work in production (proposal 302).

Expected recovery: **~1,877 ICP of ~4,891, and ~5.5 SNEED of ~125** — subject to what other claimants take first.

## Risks

| Risk | Mitigation |
|---|---|
| Other claimants drain reserves during the ~8-day voting window | Nothing in our control shortens the chain. ICP first in the runbook. |
| Swappers remove ICP from the pool | Accepted; inherent to the race. |
| `decreaseLiquidity` converts a fee-earning position into a non-earning claim against an insolvent pool | Accepted: fees on an insolvent pool are not collectable either. |
| P2 executes before P1 | Harmless; function unusable until P1 lands, only invoked in wave 2. |
| P1 passes, P2 fails | Dangling unused methods on ok64; re-submit P2. |
| P3's `amount` goes stale before execution | Re-verify `getUserUnusedBalance(fi3zi)` before submitting. Do not claim position 2 fees before the transfer, which would credit `fi3zi` and invalidate the amount. |
| Recovered funds sit on ok64 | By design. Governance moves them later via the existing `deploy_icrc1_tokens` (function 3_001). |

## Out of scope

- **The 1,000 SNEED dust** stranded under `fi3zi`. Withdrawing it nets zero against the 1,000 ledger fee.
- Investigating where the ~3,132 ICP went, and any Sonic-team remediation.
- Redeploying the recovered funds (ICPSwap position, treasury, RLL distribution).

## Success criteria

1. `checkOwnerOfUserPosition(ok64, 2)` → `ok true`.
2. Position 2 liquidity = 0.
3. All reserves the pool can pay are on ok64's ledger accounts.
4. Any residue remains a recorded claim under ok64's Sonic unused balance.
5. `getUserUnusedBalance(fi3zi).balance1` = 0, with ~40.69 ICP net of fee added to the SNS ICP treasury.
6. Achieved with exactly 4 proposals.
