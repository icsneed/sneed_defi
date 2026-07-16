# Sonic LP Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add operator-callable Sonic pool operations to the `sneed_defi` canister (ok64) so that, once LP position 2 is transferred to it, tokens and fees can be recovered without further DAO proposals.

**Architecture:** Four new public methods on the existing `main.mo` actor, gated by a hardcoded two-principal allowlist (Sneed governance + operator PID), plus one query validator used by a new SNS generic function. Sonic's interface is declared as a typed actor in `poolTypes.mo`. A local mock Sonic pool provides integration tests, since the real pool holds live funds.

**Tech Stack:** Motoko, dfx 0.31.0, `icp` CLI 1.0.2 for proposal submission, `didc` 0.6.1 for candid encoding.

## Global Constraints

- **Sonic pool:** `ni6i4-cqaaa-aaaak-qtsbq-cai`
- **Sneed governance:** `fi3zi-fyaaa-aaaaq-aachq-cai`
- **This canister (ok64):** `ok64y-uiaaa-aaaag-qdcbq-cai`
- **Operator PID:** `tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe`
- **SNEED ledger (token0):** `hvgxa-wqaaa-aaaaq-aacia-cai`, fee `1_000`
- **ICP ledger (token1):** `ryjl3-tyaaa-aaaaa-aaaba-cai`, fee `10_000`
- **Position id:** `2`; liquidity to remove: `"339138795889"`
- **Do NOT modify** `validate_claim_fees_sonic_lp_position`, `validate_decrease_liquidity_sonic_lp_position`, or `validate_withdraw_sonic_lp`. They are live validators for registered SNS functions 3_003 and 3_004. Changing their signatures breaks those functions.
- Variant tags crossing the wire to Sonic must be lowercase `ok` / `err`. The SNS validator return type uses uppercase `#Ok` / `#Err` (`T.ValidationResult`). These are different and both are correct in their place.
- Follow the existing `main.mo` pattern for every new method: `log_msg` on entry, `try`/`catch`, `log_msg` on result, `#err(#InternalError(...))` on failure.
- Build with `dfx build --check sneed_defi`. There is no test framework in this repo; integration tests run against a local mock canister.

---

### Task 1: Fix the build under dfx 0.31.0

The repo does not currently compile: moc bundled with dfx 0.31.0 rejects the implicitly-transient `log` buffer. This must be fixed before anything else, and is semantically a no-op.

**Files:**
- Modify: `src/main.mo:22`

**Interfaces:**
- Consumes: nothing
- Produces: a compiling baseline

- [ ] **Step 1: Confirm the build fails**

Run: `cd /home/sparky/repos/sneed/sneed_defi && dfx build --check sneed_defi 2>&1 | tail -3`
Expected: `type error [M0219], this declaration is currently implicitly transient, please declare it explicitly 'transient'`

- [ ] **Step 2: Add the explicit `transient` keyword**

In `src/main.mo`, change line 22 from:

```motoko
  var log : T.Log = Buffer.fromArray<Text>(stable_log);
```

to:

```motoko
  transient var log : T.Log = Buffer.fromArray<Text>(stable_log);
```

- [ ] **Step 3: Verify the build passes**

Run: `dfx build --check sneed_defi 2>&1 | tail -3`
Expected: no `M0219` error. A `M0142` deprecation warning from `Types.mo` is pre-existing and acceptable.

- [ ] **Step 4: Commit**

```bash
git add src/main.mo
git commit -m "Declare log buffer explicitly transient for moc 0.31"
```

---

### Task 2: Declare Sonic's interface and result types

**Files:**
- Modify: `src/poolTypes.mo`

**Interfaces:**
- Consumes: existing `ClaimArgs`, `DecreaseLiquidityArgs`, `WithdrawArgs`
- Produces: `Pool.SonicError`, `Pool.SonicAmounts`, `Pool.SonicAmountsResult`, `Pool.SonicNatResult`, `Pool.SonicUnusedBalance`, `Pool.SonicUnusedBalanceResult`, `Pool.SonicTokenBalance`, `Pool.SonicToken`, `Pool.SonicPoolMetadata`, `Pool.SonicMetadataResult`, `Pool.SonicPool`

These mirror Sonic's candid exactly. `SonicPoolMetadata` deliberately declares only `token0`/`token1`: Candid lets a receiver ignore extra record fields, so a subset decodes safely. Variants must list every tag, so `SonicError` lists all four.

- [ ] **Step 1: Append the types**

Add to `src/poolTypes.mo` inside the `module { ... }` block, after the existing types:

```motoko
    // Sonic swap pool interface (ni6i4-cqaaa-aaaak-qtsbq-cai).
    // Tags must match Sonic's candid exactly: lowercase ok / err.

    public type SonicError = {
        #CommonError;
        #InsufficientFunds;
        #InternalError : Text;
        #UnsupportedToken : Text;
    };

    public type SonicAmounts = {
        amount0 : Nat;
        amount1 : Nat;
    };

    public type SonicAmountsResult = {
        #ok : SonicAmounts;
        #err : SonicError;
    };

    public type SonicNatResult = {
        #ok : Nat;
        #err : SonicError;
    };

    public type SonicUnusedBalance = {
        balance0 : Nat;
        balance1 : Nat;
    };

    public type SonicUnusedBalanceResult = {
        #ok : SonicUnusedBalance;
        #err : SonicError;
    };

    public type SonicTokenBalance = {
        token0 : Nat;
        token1 : Nat;
    };

    public type SonicToken = {
        address : Text;
        standard : Text;
    };

    // Subset of Sonic's PoolMetadata. Candid ignores the extra fields.
    public type SonicPoolMetadata = {
        token0 : SonicToken;
        token1 : SonicToken;
    };

    public type SonicMetadataResult = {
        #ok : SonicPoolMetadata;
        #err : SonicError;
    };

    public type SonicPool = actor {
        claim : (args : ClaimArgs) -> async SonicAmountsResult;
        decreaseLiquidity : (args : DecreaseLiquidityArgs) -> async SonicAmountsResult;
        withdraw : (args : WithdrawArgs) -> async SonicNatResult;
        getUserUnusedBalance : (account : Principal) -> async SonicUnusedBalanceResult;
        getTokenBalance : () -> async SonicTokenBalance;
        metadata : () -> async SonicMetadataResult;
    };
```

- [ ] **Step 2: Verify it compiles**

Run: `dfx build --check sneed_defi 2>&1 | tail -3`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/poolTypes.mo
git commit -m "Add Sonic pool interface and result types"
```

---

### Task 3: Add the operator allowlist and the transfer validator

**Files:**
- Modify: `src/main.mo`

**Interfaces:**
- Consumes: `T.ValidationResult`
- Produces: `is_sonic_operator(caller : Principal) : Bool`, `sonic_pool_id : Text`, and the public query `validate_transfer_sonic_lp_position(from : Principal, to : Principal, position_id : Nat) : async T.ValidationResult`

`validate_transfer_sonic_lp_position` is the validator for SNS proposal P2. Its candid signature `(principal, principal, nat) -> (variant { Ok : text; Err : text })` must match Sonic's `transferPosition(from, to, positionId)` positionally.

- [ ] **Step 1: Add the allowlist helper**

In `src/main.mo`, immediately after the `log` declaration (line ~22), add:

```motoko
  // Principals permitted to drive the Sonic recovery operations.
  // These methods can only move funds from Sonic into this canister; they
  // cannot send tokens to the caller. Sonic's withdraw always credits the
  // calling canister, so recovered funds land on ok64, where the
  // governance-only deploy_icrc1_tokens controls them.
  transient let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
  transient let sonic_operator_id = "tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe";

  private func is_sonic_operator(caller : Principal) : Bool {
    let c = Principal.toText(caller);
    c == sneed_governance_id or c == sonic_operator_id;
  };
```

- [ ] **Step 2: Add the validator next to the other Sonic validators**

In `src/main.mo`, directly after `validate_withdraw_sonic_lp` (ends ~line 422), add:

```motoko
  // SNS generic function validation method for the Sonic transferPosition call.
  // Target of the generic function is the Sonic pool canister itself; this
  // canister only validates. Argument order must match
  // transferPosition(from, to, positionId).
  public query ({ caller }) func validate_transfer_sonic_lp_position(
    from : Principal,
    to : Principal,
    position_id : Nat) : async T.ValidationResult {

      let msg : Text = "from: " # Principal.toText(from) #
        ", to: " # Principal.toText(to) #
        ", position_id: " # debug_show(position_id);

      log_msg("validate_transfer_sonic_lp_position called by " #
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);
  };
```

- [ ] **Step 3: Verify the candid signature is what the SNS needs**

Run: `dfx build --check sneed_defi 2>&1 | tail -2 && grep -n "validate_transfer_sonic_lp_position" .dfx/local/canisters/sneed_defi/sneed_defi.did`
Expected: build clean, and the did shows `validate_transfer_sonic_lp_position: (principal, principal, nat) -> (ValidationResult) query;`

- [ ] **Step 4: Commit**

```bash
git add src/main.mo
git commit -m "Add Sonic operator allowlist and transferPosition validator"
```

---

### Task 4: Add claim and decrease-liquidity operations

**Files:**
- Modify: `src/main.mo`

**Interfaces:**
- Consumes: `is_sonic_operator`, `Pool.SonicPool`, `Pool.SonicAmountsResult`
- Produces: `sonic_claim_position_fees(lp_canister_id : Principal, position_id : Nat) : async Pool.SonicAmountsResult`, `sonic_decrease_liquidity(lp_canister_id : Principal, position_id : Nat, liquidity : Text) : async Pool.SonicAmountsResult`

- [ ] **Step 1: Add both methods**

In `src/main.mo`, after `validate_transfer_sonic_lp_position`, add:

```motoko
  // Claim (collect) accumulated fees for a Sonic LP position owned by this canister.
  // Credits this canister's unused balance inside the Sonic pool.
  public shared ({ caller }) func sonic_claim_position_fees(
    lp_canister_id : Principal,
    position_id : Nat)
    : async Pool.SonicAmountsResult {

      log_msg("sonic_claim_position_fees called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", position_id: " # debug_show(position_id));

      if (not is_sonic_operator(caller)) {
        let err_msg = "sonic_claim_position_fees ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.SonicPool = actor (Principal.toText(lp_canister_id));

        let result = await lp_canister.claim({ positionId = position_id });

        log_msg("sonic_claim_position_fees, called claim of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "sonic_claim_position_fees ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };

  // Decrease (remove) liquidity from a Sonic LP position owned by this canister.
  // Credits this canister's unused balance inside the Sonic pool.
  // Pass the position's full liquidity to withdraw from it completely.
  public shared ({ caller }) func sonic_decrease_liquidity(
    lp_canister_id : Principal,
    position_id : Nat,
    liquidity : Text)
    : async Pool.SonicAmountsResult {

      log_msg("sonic_decrease_liquidity called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", position_id: " # debug_show(position_id) #
        ", liquidity: " # liquidity);

      if (not is_sonic_operator(caller)) {
        let err_msg = "sonic_decrease_liquidity ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.SonicPool = actor (Principal.toText(lp_canister_id));

        let result = await lp_canister.decreaseLiquidity({
          positionId = position_id;
          liquidity = liquidity;
        });

        log_msg("sonic_decrease_liquidity, called decreaseLiquidity of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "sonic_decrease_liquidity ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };
```

- [ ] **Step 2: Verify it compiles**

Run: `dfx build --check sneed_defi 2>&1 | tail -3`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/main.mo
git commit -m "Add Sonic claim and decrease liquidity operations"
```

---

### Task 5: Add withdraw and withdraw-max operations

**Files:**
- Modify: `src/main.mo` (add `import Nat "mo:base/Nat";`)

**Interfaces:**
- Consumes: `is_sonic_operator`, `Pool.SonicPool`, `Pool.SonicNatResult`
- Produces: `sonic_withdraw(lp_canister_id : Principal, token : Text, fee : Nat, amount : Nat) : async Pool.SonicNatResult`, `sonic_withdraw_max(lp_canister_id : Principal, token : Text, fee : Nat) : async Pool.SonicNatResult`

`sonic_withdraw_max` exists because the pool is insolvent and cannot honour the full claim. It withdraws `min(amount owed to ok64, reserves the pool actually holds)`, so a call always takes the maximum currently available instead of failing outright. It resolves whether `token` is token0 or token1 by matching the address from `metadata()` — never by assuming an order.

- [ ] **Step 1: Add the `Nat` import**

In `src/main.mo`, add after `import Nat8 "mo:base/Nat8";`:

```motoko
import Nat "mo:base/Nat";
```

- [ ] **Step 2: Add both methods**

In `src/main.mo`, after `sonic_decrease_liquidity`, add:

```motoko
  // Withdraw an exact amount of a token from this canister's unused balance in
  // a Sonic pool. Sonic credits the calling canister, so funds land on ok64.
  public shared ({ caller }) func sonic_withdraw(
    lp_canister_id : Principal,
    token : Text,
    fee : Nat,
    amount : Nat)
    : async Pool.SonicNatResult {

      log_msg("sonic_withdraw called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", token: " # token #
        ", fee: " # debug_show(fee) #
        ", amount: " # debug_show(amount));

      if (not is_sonic_operator(caller)) {
        let err_msg = "sonic_withdraw ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.SonicPool = actor (Principal.toText(lp_canister_id));

        let result = await lp_canister.withdraw({
          token = token;
          fee = fee;
          amount = amount;
        });

        log_msg("sonic_withdraw, called withdraw of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "sonic_withdraw ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };

  // Withdraw as much of a token as is currently possible: the lesser of what
  // this canister is owed and what the pool actually holds. The Sonic pool is
  // insolvent, so an exact-amount withdraw of the full claim fails; this takes
  // whatever is available and can be re-run as reserves return.
  public shared ({ caller }) func sonic_withdraw_max(
    lp_canister_id : Principal,
    token : Text,
    fee : Nat)
    : async Pool.SonicNatResult {

      log_msg("sonic_withdraw_max called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", token: " # token #
        ", fee: " # debug_show(fee));

      if (not is_sonic_operator(caller)) {
        let err_msg = "sonic_withdraw_max ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.SonicPool = actor (Principal.toText(lp_canister_id));
        let self = Principal.fromText(sneed_defi_id);

        // Resolve whether the requested token is token0 or token1 by address.
        let meta = await lp_canister.metadata();
        let is_token0 = switch (meta) {
          case (#ok(m)) {
            if (m.token0.address == token) { true }
            else if (m.token1.address == token) { false }
            else {
              let err_msg = "sonic_withdraw_max ERROR: token " # token #
                " is not in pool " # Principal.toText(lp_canister_id);
              log_msg(err_msg);
              return #err(#UnsupportedToken(token));
            };
          };
          case (#err(e)) {
            let err_msg = "sonic_withdraw_max ERROR: metadata failed: " # debug_show(e);
            log_msg(err_msg);
            return #err(e);
          };
        };

        // What we are owed.
        let unused = await lp_canister.getUserUnusedBalance(self);
        let owed = switch (unused) {
          case (#ok(b)) { if (is_token0) { b.balance0 } else { b.balance1 } };
          case (#err(e)) {
            let err_msg = "sonic_withdraw_max ERROR: getUserUnusedBalance failed: " # debug_show(e);
            log_msg(err_msg);
            return #err(e);
          };
        };

        // What the pool actually holds.
        let held_balance = await lp_canister.getTokenBalance();
        let held = if (is_token0) { held_balance.token0 } else { held_balance.token1 };

        let amount = Nat.min(owed, held);

        log_msg("sonic_withdraw_max, token: " # token #
          ", is_token0: " # debug_show(is_token0) #
          ", owed: " # debug_show(owed) #
          ", held: " # debug_show(held) #
          ", withdrawing: " # debug_show(amount));

        // A withdrawal at or below the ledger fee nets nothing.
        if (amount <= fee) {
          let err_msg = "sonic_withdraw_max ERROR: available amount " #
            debug_show(amount) # " does not exceed fee " # debug_show(fee);
          log_msg(err_msg);
          return #err(#InsufficientFunds);
        };

        let result = await lp_canister.withdraw({
          token = token;
          fee = fee;
          amount = amount;
        });

        log_msg("sonic_withdraw_max, called withdraw of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "sonic_withdraw_max ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };
```

Note: `sneed_defi_id` is currently a local `let` inside `deploy_icrc1_tokens_to_icpswap`. Promote it to an actor-level constant next to `sneed_governance_id`:

```motoko
  transient let sneed_defi_id = "ok64y-uiaaa-aaaag-qdcbq-cai";
```

and delete the local shadowing declaration inside `deploy_icrc1_tokens_to_icpswap`.

- [ ] **Step 3: Verify it compiles**

Run: `dfx build --check sneed_defi 2>&1 | tail -3`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/main.mo
git commit -m "Add Sonic withdraw and withdraw-max operations"
```

---

### Task 6: Mock Sonic pool and integration tests

The real pool holds live funds, so behaviour is verified against a local mock implementing the same interface. This covers the two places a bug costs money: the allowlist, and `sonic_withdraw_max`'s token resolution and `min` arithmetic.

**Files:**
- Create: `test/sonic_mock.mo`
- Modify: `dfx.json`
- Create: `test/run_tests.sh`

**Interfaces:**
- Consumes: everything from Tasks 3–5
- Produces: a passing local test run

- [ ] **Step 1: Write the mock**

Create `test/sonic_mock.mo`:

```motoko
import Principal "mo:base/Principal";

// Local stand-in for the Sonic swap pool. Models the insolvency: internal
// accounting (unused balances) exceeds real reserves (token balances).
actor {

  type Error = {
    #CommonError;
    #InsufficientFunds;
    #InternalError : Text;
    #UnsupportedToken : Text;
  };

  type Amounts = { amount0 : Nat; amount1 : Nat };
  type AmountsResult = { #ok : Amounts; #err : Error };
  type NatResult = { #ok : Nat; #err : Error };
  type UnusedBalance = { balance0 : Nat; balance1 : Nat };
  type UnusedBalanceResult = { #ok : UnusedBalance; #err : Error };
  type Token = { address : Text; standard : Text };
  type PoolMetadata = { token0 : Token; token1 : Token };
  type MetadataResult = { #ok : PoolMetadata; #err : Error };

  // token0 = SNEED, token1 = ICP, matching the real pool.
  let token0_address = "hvgxa-wqaaa-aaaaq-aacia-cai";
  let token1_address = "ryjl3-tyaaa-aaaaa-aaaba-cai";

  // Owed to the caller (generous) vs actually held (scarce) — the insolvency.
  var owed0 : Nat = 12_214_407_804;   // 122.14 SNEED
  var owed1 : Nat = 485_910_640_019;  // 4859.11 ICP
  var held0 : Nat = 556_420_283;      // 5.56 SNEED
  var held1 : Nat = 187_704_991_578;  // 1877.05 ICP

  var last_withdraw_amount : Nat = 0;

  public query func metadata() : async MetadataResult {
    #ok({
      token0 = { address = token0_address; standard = "ICRC2" };
      token1 = { address = token1_address; standard = "ICRC2" };
    });
  };

  public query func getUserUnusedBalance(_account : Principal) : async UnusedBalanceResult {
    #ok({ balance0 = owed0; balance1 = owed1 });
  };

  public func getTokenBalance() : async { token0 : Nat; token1 : Nat } {
    { token0 = held0; token1 = held1 };
  };

  public func claim(args : { positionId : Nat }) : async AmountsResult {
    if (args.positionId != 2) { return #err(#InternalError("no such position")) };
    #ok({ amount0 = 301_641_723; amount1 = 3_195_932_904 });
  };

  public func decreaseLiquidity(args : { positionId : Nat; liquidity : Text }) : async AmountsResult {
    if (args.positionId != 2) { return #err(#InternalError("no such position")) };
    if (args.liquidity != "339138795889") { return #err(#InternalError("unexpected liquidity")) };
    #ok({ amount0 = 12_214_407_804; amount1 = 485_910_640_019 });
  };

  public func withdraw(args : { token : Text; fee : Nat; amount : Nat }) : async NatResult {
    let held = if (args.token == token0_address) { held0 } else { held1 };
    if (args.amount > held) { return #err(#InsufficientFunds) };
    last_withdraw_amount := args.amount;
    #ok(args.amount);
  };

  // Test helper: what amount did sonic_withdraw_max actually request?
  public query func last_withdraw() : async Nat { last_withdraw_amount };
}
```

- [ ] **Step 2: Register the mock as a local-only canister**

In `dfx.json`, add a second canister. It has no entry in `canister_ids.json`, so it exists only on a local replica:

```json
{
  "canisters": {
    "sneed_defi": {
      "main": "src/main.mo",
      "type": "motoko"
    },
    "sonic_mock": {
      "main": "test/sonic_mock.mo",
      "type": "motoko"
    }
  },
  "defaults": {
    "build": {
      "args": "",
      "packtool": ""
    }
  },
  "output_env_file": ".env",
  "version": 1
}
```

- [ ] **Step 3: Write the test script**

Create `test/run_tests.sh`:

```bash
#!/usr/bin/env bash
# Integration tests for the Sonic recovery methods, run against a local mock pool.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

dfx start --clean --background >/dev/null 2>&1 || true
trap 'dfx stop >/dev/null 2>&1 || true' EXIT

dfx deploy sonic_mock >/dev/null
dfx deploy sneed_defi >/dev/null
MOCK=$(dfx canister id sonic_mock)

# The local default identity is NOT on the allowlist, so it must be rejected.
OUT=$(dfx canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized caller was not rejected"
pass "unauthorized caller rejected"

OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized withdraw_max was not rejected"
pass "unauthorized withdraw_max rejected"

# Re-deploy with the local identity added to the allowlist, to exercise the happy path.
LOCAL_PID=$(dfx identity get-principal)
sed -i.bak "s|transient let sonic_operator_id = \".*\";|transient let sonic_operator_id = \"$LOCAL_PID\";|" src/main.mo
dfx deploy sneed_defi --mode reinstall --yes >/dev/null

OUT=$(dfx canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | grep -q "301_641_723" || fail "claim did not return expected amounts: $OUT"
pass "claim succeeds for authorized caller"

OUT=$(dfx canister call sneed_defi sonic_decrease_liquidity "(principal \"$MOCK\", 2:nat, \"339138795889\")")
echo "$OUT" | grep -q "485_910_640_019" || fail "decrease_liquidity unexpected: $OUT"
pass "decrease_liquidity succeeds for authorized caller"

# ICP: owed 485_910_640_019, held 187_704_991_578 -> must withdraw the held amount.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | grep -q "187_704_991_578" || fail "withdraw_max ICP did not clamp to reserves: $OUT"
pass "withdraw_max clamps ICP to available reserves"

# SNEED: proves token0/token1 are resolved by address, not by position.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"hvgxa-wqaaa-aaaaq-aacia-cai\", 1000:nat)")
echo "$OUT" | grep -q "556_420_283" || fail "withdraw_max SNEED resolved wrong token: $OUT"
pass "withdraw_max resolves SNEED as token0 by address"

# A token that is not in the pool must be rejected, not silently treated as token1.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"aaaaa-aa\", 1000:nat)")
echo "$OUT" | grep -q "UnsupportedToken" || fail "unknown token not rejected: $OUT"
pass "withdraw_max rejects a token not in the pool"

mv src/main.mo.bak src/main.mo
echo "All tests passed."
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `chmod +x test/run_tests.sh && ./test/run_tests.sh`
Expected: every line prints `PASS:`, ending with `All tests passed.` If the run aborts early, `src/main.mo.bak` may remain — restore it with `mv src/main.mo.bak src/main.mo` before continuing.

- [ ] **Step 5: Confirm the operator PID was restored**

Run: `grep -n "sonic_operator_id" src/main.mo`
Expected: shows `tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe`, NOT a local principal. This must be correct before building the proposal wasm.

- [ ] **Step 6: Commit**

```bash
git add test/sonic_mock.mo test/run_tests.sh dfx.json
git commit -m "Add local Sonic mock and integration tests for recovery methods"
```

---

### Task 7: Build the proposal wasm and record its hash

**Files:**
- Create: `docs/superpowers/plans/build-artifacts.md`

**Interfaces:**
- Consumes: the finished `main.mo`
- Produces: a wasm path + sha256 for proposal P1

- [ ] **Step 1: Verify the allowlist one final time**

Run: `grep -n "sneed_governance_id = \|sonic_operator_id = " src/main.mo`
Expected: exactly `fi3zi-fyaaa-aaaaq-aachq-cai` and `tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe`.

- [ ] **Step 2: Build**

Run: `dfx build --network ic sneed_defi 2>&1 | tail -2`
Expected: builds clean.

- [ ] **Step 3: Record the hash**

Run: `sha256sum .dfx/ic/canisters/sneed_defi/sneed_defi.wasm && ls -l .dfx/ic/canisters/sneed_defi/sneed_defi.wasm`

Write the path, sha256, and `dfx --version` into `docs/superpowers/plans/build-artifacts.md` so voters can reproduce the build.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/build-artifacts.md
git commit -m "Record proposal wasm hash and build environment"
```

---

### Task 8: Write the proposal submission commands

**Files:**
- Create: `docs/proposals/2026-07-15-sonic-recovery-proposals.md`

**Interfaces:**
- Consumes: the wasm hash from Task 7
- Produces: copy-pasteable `icp` commands for P1–P4

The operator's neuron id is `\b8\ae\a5\33\37\14\02\07\6b\65\55\75\9f\b4\23\6e\cc\a1\65\50\8d\e0\57\f5\ec\dc\63\43\e0\6d\df\43` (controller `tv3bj-…`). Proposals are submitted with `icp canister call --network ic fi3zi-fyaaa-aaaaq-aachq-cai manage_neuron '(record { subaccount = blob "…"; command = opt variant { MakeProposal = … } })' --identity <name>`.

- [ ] **Step 1: Verify P3's amount is still current**

Run: `dfx canister --network ic call ni6i4-cqaaa-aaaak-qtsbq-cai getUserUnusedBalance '(principal "fi3zi-fyaaa-aaaaq-aachq-cai")' --query`
Expected: `balance1 = 4_069_574_490`. If it differs, use the new value in P3's payload — the amount must be exact.

- [ ] **Step 2: Encode the generic-function payloads**

P3 (`withdraw_sonic`, function 3_004) payload is a `WithdrawArgs` record:

```bash
didc encode '(record { token = "ryjl3-tyaaa-aaaaa-aaaba-cai"; fee = 10_000 : nat; amount = 4_069_574_490 : nat })'
```

P4 (`transfer_sonic_lp_position`) payload is `transferPosition`'s three positional args:

```bash
didc encode '(principal "fi3zi-fyaaa-aaaaq-aachq-cai", principal "ok64y-uiaaa-aaaag-qdcbq-cai", 2 : nat)'
```

Record both hex blobs in the doc.

- [ ] **Step 3: Write the four proposal commands**

Document P1 (UpgradeSnsControlledCanister for ok64), P2 (AddGenericNervousSystemFunction), P3 (ExecuteGenericNervousSystemFunction id 3_004), P4 (ExecuteGenericNervousSystemFunction, the new id). Include for each: what it does, the exact command, and the expected result.

P2's function definition:
- `target_canister_id`: `ni6i4-cqaaa-aaaak-qtsbq-cai`, `target_method_name`: `transferPosition`
- `validator_canister_id`: `ok64y-uiaaa-aaaag-qdcbq-cai`, `validator_method_name`: `validate_transfer_sonic_lp_position`
- `topic`: `TreasuryAssetManagement`
- pick an unused function id (existing ids in the 3_00x range end at 3_004; use `3_005`)

State in the doc that P1, P2 and P3 are submitted together on day 0, and P4 only after P1 and P2 have executed.

- [ ] **Step 4: Commit**

```bash
git add docs/proposals/2026-07-15-sonic-recovery-proposals.md
git commit -m "Add Sonic recovery proposal submission commands"
```

---

## Self-Review

**Spec coverage:**
- Authorization model → Task 3
- `sonic_claim_position_fees`, `sonic_decrease_liquidity` → Task 4
- `sonic_withdraw`, `sonic_withdraw_max` → Task 5
- `validate_transfer_sonic_lp_position` → Task 3
- New poolTypes → Task 2
- Do-not-touch existing validators → Global Constraints; no task modifies them
- P1–P4 → Tasks 7 and 8
- Runbook → spec; executed after P4 lands, not part of this plan
- Build reproducibility → Task 7

**Gap found and closed:** the spec did not mention that the repo fails to compile on dfx 0.31.0. Added as Task 1.

**Type consistency:** `Pool.SonicAmountsResult` (Tasks 2, 4), `Pool.SonicNatResult` (Tasks 2, 5), `Pool.SonicPool` (Tasks 2, 4, 5), `is_sonic_operator` (Tasks 3, 4, 5), `sneed_defi_id` (Task 5, promoted to actor scope) all match across tasks.
