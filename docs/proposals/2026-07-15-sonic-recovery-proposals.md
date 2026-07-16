# Sonic LP Recovery — Proposal Commands

Four proposals in two waves, ~8 days. Design rationale: `docs/superpowers/specs/2026-07-15-sonic-lp-recovery-design.md`.

| Wave | Proposal | Effect |
|---|---|---|
| 1 (day 0) | **P1** Upgrade ok64 | Adds operator-callable Sonic methods |
| 1 (day 0) | **P2** Add `transfer_sonic_lp_position` (id 3005) | Registers the transfer function |
| 1 (day 0) | **P3** Execute `withdraw_sonic` (id 3004) | 40.69 ICP → SNS ICP treasury |
| 2 (day ~4) | **P4** Execute `transfer_sonic_lp_position` (id 3005) | LP position 2 → ok64 |

P1, P2 and P3 are independent — submit all three on day 0. **P4 must wait until P1 and P2 have executed.**

## Build artifacts

| | |
|---|---|
| wasm | `.dfx/ic/canisters/sneed_defi/sneed_defi.wasm` |
| sha256 | `8d10b95bd649d3078743971ff59689d3a3c60176f2d97d7ed140875f70257b02` |
| size | 398,332 bytes |
| built with | dfx 0.31.0 |
| command | `dfx build --network ic sneed_defi` |

Voters reproduce with:

```bash
git clone https://github.com/icsneed/sneed_defi && cd sneed_defi
git checkout <commit>
dfx build --network ic sneed_defi
sha256sum .dfx/ic/canisters/sneed_defi/sneed_defi.wasm
```

**Pin dfx 0.31.0 when verifying.** The previous upgrade proposal pinned no version, and the source as it stood could not be compiled by any current dfx at all (moc now requires explicit `transient`/`persistent` declarations). This upgrade fixes that, so the build is reproducible again.

### Persistence-mode note for reviewers

The wasm is built with `--enhanced-orthogonal-persistence` (declared in `dfx.json`). Without that explicit flag the Motoko runtime **refuses** an implicit migration from classical persistence and the upgrade would trap:

> *"Detected implicit upgrade from classical orthogonal persistence to enhanced orthogonal persistence. Recompile with explicit flag `--enhanced-orthogonal-persistence` and redeploy to enable this irreversible migration."*

The deployed canister's persistence mode cannot be read remotely (`motoko:compiler` metadata is private), so the flag is set to make the upgrade succeed either way. If the canister is already enhanced, the flag is a no-op. **The migration is irreversible.** The blast radius is nil: the only stable state is `stable var stable_log : [Text]`, which `postupgrade` clears anyway.

The public interface is a strict superset of the deployed one — verified with `didc check new.did deployed.did`. The validators for existing functions 3_003 and 3_004 are unchanged.

## Before you submit

Generate the argument files (they are gitignored; the upgrade arg is ~1.2MB):

```bash
dfx build --network ic sneed_defi
python3 scripts/make_proposal_args.py
```

**Re-verify P3's amount.** It must exactly match governance's unused ICP balance in the pool:

```bash
dfx canister --network ic call ni6i4-cqaaa-aaaak-qtsbq-cai \
  getUserUnusedBalance '(principal "fi3zi-fyaaa-aaaaq-aachq-cai")' --query
```

Expected `balance1 = 4_069_574_490`. If it differs, edit `STRANDED_ICP_E8S` in `scripts/make_proposal_args.py` and regenerate.

> **Do not claim position 2's fees before P4 executes.** A claim credits `fi3zi`, which changes this balance and invalidates P3's amount. The runbook claims *after* the transfer, as ok64.

**Check that function id 3005 is still free:**

```bash
dfx canister --network ic call fi3zi-fyaaa-aaaaq-aachq-cai list_nervous_system_functions --query \
  | grep -o "id = 3_00[0-9]"
```

If 3005 is taken, change `NEW_FUNCTION_ID` in the script and regenerate (P2 and P4 both use it).

## Wave 1 — submit on day 0

Replace `<your-identity>` with the `icp` identity controlling neuron `b8aea533...e06ddf43` (controller `tv3bj-a6dzs-…-6qe`).

### P1 — Upgrade the Sneed DeFi canister

```bash
icp canister call --network ic fi3zi-fyaaa-aaaaq-aachq-cai manage_neuron \
  --args-file proposal_args/p1_upgrade.did \
  --identity <your-identity>
```

### P2 — Add the `transfer_sonic_lp_position` generic function

Target `ni6i4-cqaaa-aaaak-qtsbq-cai` / `transferPosition`, validator `ok64y-uiaaa-aaaag-qdcbq-cai` / `validate_transfer_sonic_lp_position`, topic `TreasuryAssetManagement`.

```bash
icp canister call --network ic fi3zi-fyaaa-aaaaq-aachq-cai manage_neuron \
  --args-file proposal_args/p2_add_function.did \
  --identity <your-identity>
```

Safe to submit alongside P1: `AddGenericNervousSystemFunction` registers a name and does not check that the validator method exists. If P2 executes first, the function is simply unusable until P1 lands, and it is only invoked in wave 2.

### P3 — Withdraw the stranded 40.69 ICP to the treasury

Uses the already-registered function 3004. No upgrade or new function needed.

```bash
icp canister call --network ic fi3zi-fyaaa-aaaaq-aachq-cai manage_neuron \
  --args-file proposal_args/p3_withdraw_icp.did \
  --identity <your-identity>
```

Payload decodes to:

```candid
(record { token = "ryjl3-tyaaa-aaaaa-aaaba-cai"; fee = 10_000 : nat; amount = 4_069_574_490 : nat })
```

## Wave 2 — after P1 and P2 have executed

Confirm both landed first:

```bash
# P1: the new method must exist
dfx canister --network ic metadata ok64y-uiaaa-aaaag-qdcbq-cai candid:service \
  | grep validate_transfer_sonic_lp_position
# P2: the function must be registered
dfx canister --network ic call fi3zi-fyaaa-aaaaq-aachq-cai list_nervous_system_functions --query \
  | grep transfer_sonic_lp_position
```

### P4 — Transfer LP position 2 to the Sneed DeFi canister

```bash
icp canister call --network ic fi3zi-fyaaa-aaaaq-aachq-cai manage_neuron \
  --args-file proposal_args/p4_transfer_position.did \
  --identity <your-identity>
```

Payload decodes to:

```candid
(principal "fi3zi-fyaaa-aaaaq-aachq-cai", principal "ok64y-uiaaa-aaaag-qdcbq-cai", 2 : nat)
```

## After P4 — no more proposals

Called directly by the operator PID `tv3bj-a6dzs-…-6qe`. Substitute your `dfx`/`icp` identity for that principal.

```bash
POOL=ni6i4-cqaaa-aaaak-qtsbq-cai
DEFI=ok64y-uiaaa-aaaag-qdcbq-cai
ICP=ryjl3-tyaaa-aaaaa-aaaba-cai
SNEED=hvgxa-wqaaa-aaaaq-aacia-cai

# 1. Confirm ownership actually moved.
dfx canister --network ic call $POOL checkOwnerOfUserPosition "(principal \"$DEFI\", 2:nat)"
# expect: (variant { ok = true })

# 2. Collect the position's fees (~3.02 SNEED + ~31.96 ICP).
dfx canister --network ic call $DEFI sonic_claim_position_fees "(principal \"$POOL\", 2:nat)"

# 3. Remove all liquidity (~122.14 SNEED + ~4859.11 ICP).
dfx canister --network ic call $DEFI sonic_decrease_liquidity "(principal \"$POOL\", 2:nat, \"339138795889\")"

# 4. ICP first: it is the large, contested balance.
dfx canister --network ic call $DEFI sonic_withdraw_max "(principal \"$POOL\", \"$ICP\", 10000:nat)"

# 5. Then SNEED.
dfx canister --network ic call $DEFI sonic_withdraw_max "(principal \"$POOL\", \"$SNEED\", 1000:nat)"

# 6. Confirm receipt on the ledgers.
dfx canister --network ic call $ICP icrc1_balance_of "(record {owner = principal \"$DEFI\"; subaccount = null})" --query
dfx canister --network ic call $SNEED icrc1_balance_of "(record {owner = principal \"$DEFI\"; subaccount = null})" --query
```

**Expect partial recovery.** The pool holds far less than it owes (~1,877 of ~5,010 ICP; ~5.5 of ~136 SNEED). `sonic_withdraw_max` takes the maximum currently available rather than failing, and is safe to re-run as reserves return. Whatever remains stays as a claim under ok64's unused balance in the pool.

Progress is visible in the canister log:

```bash
dfx canister --network ic call ok64y-uiaaa-aaaag-qdcbq-cai get_log_size --query
dfx canister --network ic call ok64y-uiaaa-aaaag-qdcbq-cai get_log_entries '(0:nat, 20:nat)' --query
```

Recovered funds sit on ok64's default subaccount, under DAO control via the existing governance-only `deploy_icrc1_tokens` (function 3_001).
