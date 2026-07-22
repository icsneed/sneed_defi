#!/usr/bin/env bash
# Integration tests for the Sonic recovery methods, run against a local mock pool.
#
# The real pool holds live funds, so behaviour is verified locally. These tests
# cover the two places a bug costs money: the safety-admin allowlist, and
# sonic_withdraw_max's token resolution and min() clamping.
#
# Run: ./test/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }
# Strip digit-grouping underscores so numeric checks are formatting-agnostic.
norm() { tr -d '_'; }

cleanup() {
  # Always restore the real operator PID, even if a test aborts.
  if [ -f ../src/main.mo.testbak ]; then
    mv ../src/main.mo.testbak ../src/main.mo
  fi
  icp network stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting local network..."
icp network stop >/dev/null 2>&1 || true
icp network start -d >/dev/null 2>&1

icp deploy sonic_mock >/dev/null 2>&1
icp deploy sneed_defi >/dev/null 2>&1
MOCK=$(icp canister status sonic_mock --id-only)
echo "Mock pool: $MOCK"
echo

echo "--- Authorization (local identity is NOT on the allowlist) ---"
OUT=$(icp canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized claim was not rejected: $OUT"
pass "unauthorized claim rejected"

OUT=$(icp canister call sneed_defi sonic_decrease_liquidity "(principal \"$MOCK\", 2:nat, \"339138795889\")")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized decrease_liquidity was not rejected: $OUT"
pass "unauthorized decrease_liquidity rejected"

OUT=$(icp canister call sneed_defi sonic_withdraw "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat, 1000000:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized withdraw was not rejected: $OUT"
pass "unauthorized withdraw rejected"

OUT=$(icp canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | grep -q "Not authorized" || fail "unauthorized withdraw_max was not rejected: $OUT"
pass "unauthorized withdraw_max rejected"

# Confirm the rejection was a real gate, not an incidental failure:
# the mock must never have been called.
OUT=$(icp canister call sonic_mock last_withdraw "()")
echo "$OUT" | grep -q "(0 : nat)" || fail "mock was called despite rejection: $OUT"
pass "no unauthorized call reached the pool"
echo

echo "--- Happy path (temporarily allowlist the local identity) ---"
LOCAL_PID=$(icp identity principal)
cp ../src/main.mo ../src/main.mo.testbak
sed -i "s|transient let safety_admins = \[\".*\"\];|transient let safety_admins = [\"$LOCAL_PID\"];|" ../src/main.mo
icp deploy -m reinstall -y sneed_defi >/dev/null 2>&1

OUT=$(icp canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 2:nat)")
echo "$OUT" | norm | grep -q "301641723" || fail "claim did not return expected amounts: $OUT"
pass "claim succeeds for authorized caller"

OUT=$(icp canister call sneed_defi sonic_claim_position_fees "(principal \"$MOCK\", 99:nat)")
echo "$OUT" | grep -q "no such position" || fail "claim of a bad position should error: $OUT"
pass "claim surfaces pool errors verbatim"

OUT=$(icp canister call sneed_defi sonic_decrease_liquidity "(principal \"$MOCK\", 2:nat, \"339138795889\")")
echo "$OUT" | norm | grep -q "485910640019" || fail "decrease_liquidity unexpected: $OUT"
pass "decrease_liquidity succeeds for authorized caller"
echo

echo "--- withdraw_max clamps to real reserves (the insolvency) ---"
# ICP: owed 485_910_640_019 but only 187_704_991_578 held -> must clamp to held.
OUT=$(icp canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat)")
echo "$OUT" | norm | grep -q "187704991578" || fail "withdraw_max ICP did not clamp to reserves: $OUT"
pass "withdraw_max clamps ICP to available reserves"

# An exact-amount withdraw of the full claim must fail, proving the clamp matters.
OUT=$(icp canister call sneed_defi sonic_withdraw "(principal \"$MOCK\", \"ryjl3-tyaaa-aaaaa-aaaba-cai\", 10000:nat, 485910640019:nat)")
echo "$OUT" | grep -q "InsufficientFunds" || fail "full-claim withdraw should fail: $OUT"
pass "exact-amount withdraw of full claim fails as expected"

# SNEED: proves token0/token1 is resolved by address, not by argument order.
OUT=$(icp canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"hvgxa-wqaaa-aaaaq-aacia-cai\", 1000:nat)")
echo "$OUT" | norm | grep -q "556420283" || fail "withdraw_max SNEED resolved the wrong token: $OUT"
pass "withdraw_max resolves SNEED as token0 by address"

# A token not in the pool must be rejected, not silently treated as token1.
OUT=$(icp canister call sneed_defi sonic_withdraw_max "(principal \"$MOCK\", \"aaaaa-aa\", 1000:nat)")
echo "$OUT" | grep -q "UnsupportedToken" || fail "unknown token was not rejected: $OUT"
pass "withdraw_max rejects a token not in the pool"
echo

echo "All tests passed."
