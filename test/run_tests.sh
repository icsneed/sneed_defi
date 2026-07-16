#!/usr/bin/env bash
# Integration tests for the Sonic recovery methods, run against a local mock pool.
#
# The real pool holds live funds, so behaviour is verified locally. These tests
# cover the two places a bug costs money: the operator allowlist, and
# sonic_withdraw_max's token resolution and min() clamping.
#
# Run: ./test/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"

export DFX_WARNING=-mainnet_plaintext_identity

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

cleanup() {
  # Always restore the real operator PID, even if a test aborts.
  if [ -f ../src/main.mo.testbak ]; then
    mv ../src/main.mo.testbak ../src/main.mo
  fi
  dfx stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting local replica..."
dfx stop >/dev/null 2>&1 || true
dfx start --clean --background >/dev/null 2>&1

dfx deploy sonic_mock >/dev/null 2>&1
dfx deploy sneed_defi >/dev/null 2>&1
MOCK=$(dfx canister id sonic_mock)
echo "Mock pool: $MOCK"
echo

echo "--- Authorization (local identity is NOT on the allowlist) ---"
OUT=$(dfx canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized claim was not rejected: $OUT"
pass "unauthorized claim rejected"

OUT=$(dfx canister call sneed_defi sonic_decrease_liquidity "(principal \"$MOCK\", 2:nat, \"339138795889\")")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized decrease_liquidity was not rejected: $OUT"
pass "unauthorized decrease_liquidity rejected"

OUT=$(dfx canister call sneed_defi sonic_withdraw "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat, 1000000:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized withdraw was not rejected: $OUT"
pass "unauthorized withdraw rejected"

OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized withdraw_max was not rejected: $OUT"
pass "unauthorized withdraw_max rejected"

# Confirm the rejection was a real gate, not an incidental failure:
# the mock must never have been called.
OUT=$(dfx canister call sonic_mock last_withdraw "()")
echo "$OUT" | grep -q "(0 : nat)" || fail "mock was called despite rejection: $OUT"
pass "no unauthorized call reached the pool"
echo

echo "--- Happy path (temporarily allowlist the local identity) ---"
LOCAL_PID=$(dfx identity get-principal)
cp ../src/main.mo ../src/main.mo.testbak
sed -i "s|transient let sonic_operator_id = \".*\";|transient let sonic_operator_id = \"$LOCAL_PID\";|" ../src/main.mo
dfx deploy sneed_defi --mode reinstall --yes >/dev/null 2>&1

OUT=$(dfx canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | grep -q "301_641_723" || fail "claim did not return expected amounts: $OUT"
pass "claim succeeds for authorized caller"

OUT=$(dfx canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 99:nat)")
echo "$OUT" | grep -q "no such position" || fail "claim of a bad position should error: $OUT"
pass "claim surfaces pool errors verbatim"

OUT=$(dfx canister call sneed_defi sonic_decrease_liquidity "(principal \"$MOCK\", 2:nat, \"339138795889\")")
echo "$OUT" | grep -q "485_910_640_019" || fail "decrease_liquidity unexpected: $OUT"
pass "decrease_liquidity succeeds for authorized caller"
echo

echo "--- withdraw_max clamps to real reserves (the insolvency) ---"
# ICP: owed 485_910_640_019 but only 187_704_991_578 held -> must clamp to held.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | grep -q "187_704_991_578" || fail "withdraw_max ICP did not clamp to reserves: $OUT"
pass "withdraw_max clamps ICP to available reserves"

# An exact-amount withdraw of the full claim must fail, proving the clamp matters.
OUT=$(dfx canister call sneed_defi sonic_withdraw "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat, 485910640019:nat)")
echo "$OUT" | grep -q "InsufficientFunds" || fail "full-claim withdraw should fail: $OUT"
pass "exact-amount withdraw of full claim fails as expected"

# SNEED: proves token0/token1 is resolved by address, not by argument order.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"hvgxa-wqaaa-aaaaq-aacia-cai\", 1000:nat)")
echo "$OUT" | grep -q "556_420_283" || fail "withdraw_max SNEED resolved the wrong token: $OUT"
pass "withdraw_max resolves SNEED as token0 by address"

# A token not in the pool must be rejected, not silently treated as token1.
OUT=$(dfx canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"aaaaa-aa\", 1000:nat)")
echo "$OUT" | grep -q "UnsupportedToken" || fail "unknown token was not rejected: $OUT"
pass "withdraw_max rejects a token not in the pool"
echo

echo "All tests passed."
