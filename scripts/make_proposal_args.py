#!/usr/bin/env python3
"""Generate Candid argument files for the Sonic recovery proposals.

The upgrade proposal embeds a ~400KB wasm, which is far too large to paste on a
command line, so each proposal's argument is written to a file and passed to
`icp canister call` with --args-file.

Usage:
    python3 scripts/make_proposal_args.py

Writes proposal_args/p1_upgrade.did, p2_add_function.did, p3_withdraw_icp.did,
p4_transfer_position.did.
"""

import hashlib
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
WASM = REPO / ".dfx" / "ic" / "canisters" / "sneed_defi" / "sneed_defi.wasm"
OUT = REPO / "proposal_args"

# The operator's neuron, controlled by tv3bj-a6dzs-...-6qe.
NEURON_ID = (
    r"\b8\ae\a5\33\37\14\02\07\6b\65\55\75\9f\b4\23\6e"
    r"\cc\a1\65\50\8d\e0\57\f5\ec\dc\63\43\e0\6d\df\43"
)

SNEED_DEFI = "ok64y-uiaaa-aaaag-qdcbq-cai"
GOVERNANCE = "fi3zi-fyaaa-aaaaq-aachq-cai"
SONIC_POOL = "ni6i4-cqaaa-aaaak-qtsbq-cai"
ICP_LEDGER = "ryjl3-tyaaa-aaaaa-aaaba-cai"

# Existing generic function ids end at 3_004; take the next free slot.
NEW_FUNCTION_ID = 3005
WITHDRAW_SONIC_FUNCTION_ID = 3004

# Governance's unused ICP balance in the Sonic pool. Must be exact.
# Re-verify before submitting; see the proposals doc.
STRANDED_ICP_E8S = 4_069_574_490

REPO_URL = "https://github.com/icsneed/sneed_defi"


def candid_blob(data: bytes) -> str:
    """Render bytes as a Candid blob literal."""
    return 'blob "' + "".join(f"\\{b:02x}" for b in data) + '"'


def didc_encode(candid_text: str) -> bytes:
    """Encode Candid text to bytes via didc."""
    result = subprocess.run(
        ["didc", "encode", candid_text],
        capture_output=True,
        text=True,
        check=True,
    )
    return bytes.fromhex(result.stdout.strip())


def proposal(title: str, summary: str, action: str) -> str:
    return f"""(
  record {{
    subaccount = blob "{NEURON_ID}";
    command = opt variant {{
      MakeProposal = record {{
        title = "{title}";
        url = "{REPO_URL}";
        summary = "{summary}";
        action = opt variant {{
{action}
        }};
      }}
    }};
  }}
)
"""


def main() -> int:
    if not WASM.exists():
        print(f"error: wasm not found at {WASM}", file=sys.stderr)
        print("Run: dfx build --network ic sneed_defi", file=sys.stderr)
        return 1

    wasm_bytes = WASM.read_bytes()
    wasm_hash = hashlib.sha256(wasm_bytes).hexdigest()
    OUT.mkdir(exist_ok=True)

    # --- P1: upgrade the sneed_defi canister -------------------------------
    p1_summary = (
        "Upgrade the Sneed DeFi canister (ok64y-uiaaa-aaaag-qdcbq-cai) to add "
        "operator-callable Sonic pool operations, so that LP position 2 can be "
        "withdrawn once it is transferred to this canister. "
        f"wasm sha256: {wasm_hash}"
    )
    # mode 3 = upgrade
    p1_action = f"""          UpgradeSnsControlledCanister = record {{
            canister_id = opt principal "{SNEED_DEFI}";
            new_canister_wasm = {candid_blob(wasm_bytes)};
            canister_upgrade_arg = null;
            chunked_canister_wasm = null;
            mode = opt (3 : int32);
          }}"""
    (OUT / "p1_upgrade.did").write_text(
        proposal("Upgrade Sneed DeFi canister for Sonic LP recovery", p1_summary, p1_action)
    )

    # --- P2: register the transferPosition generic function -----------------
    p2_summary = (
        "Register a generic function that calls transferPosition on the Sonic "
        f"SNEED/ICP pool ({SONIC_POOL}). The pool requires the position owner to "
        "be the caller, so only this DAO's governance canister can move LP "
        "position 2. Validation is performed by the Sneed DeFi canister."
    )
    p2_action = f"""          AddGenericNervousSystemFunction = record {{
            id = {NEW_FUNCTION_ID} : nat64;
            name = "transfer_sonic_lp_position";
            description = opt "Transfers a Sonic LP position from one principal to another.";
            function_type = opt variant {{
              GenericNervousSystemFunction = record {{
                topic = opt variant {{ TreasuryAssetManagement }};
                target_canister_id = opt principal "{SONIC_POOL}";
                target_method_name = opt "transferPosition";
                validator_canister_id = opt principal "{SNEED_DEFI}";
                validator_method_name = opt "validate_transfer_sonic_lp_position";
              }}
            }};
          }}"""
    (OUT / "p2_add_function.did").write_text(
        proposal("Add Sonic transferPosition generic function", p2_summary, p2_action)
    )

    # --- P3: sweep the stranded ICP into the SNS treasury -------------------
    p3_payload = didc_encode(
        f'(record {{ token = "{ICP_LEDGER}"; fee = 10_000 : nat; '
        f"amount = {STRANDED_ICP_E8S} : nat }})"
    )
    p3_summary = (
        f"Withdraw {STRANDED_ICP_E8S / 1e8:.8f} ICP that is currently stranded in the "
        f"Sonic SNEED/ICP pool ({SONIC_POOL}) under this DAO's governance principal. "
        "These are previously claimed fees that were never withdrawn. Sonic credits "
        "the caller, so the ICP lands in the SNS ICP treasury."
    )
    p3_action = f"""          ExecuteGenericNervousSystemFunction = record {{
            function_id = {WITHDRAW_SONIC_FUNCTION_ID} : nat64;
            payload = {candid_blob(p3_payload)};
          }}"""
    (OUT / "p3_withdraw_icp.did").write_text(
        proposal("Withdraw stranded ICP from Sonic to the treasury", p3_summary, p3_action)
    )

    # --- P4: transfer LP position 2 to the Sneed DeFi canister --------------
    p4_payload = didc_encode(
        f'(principal "{GOVERNANCE}", principal "{SNEED_DEFI}", 2 : nat)'
    )
    p4_summary = (
        f"Transfer Sonic LP position 2 from the governance canister ({GOVERNANCE}) "
        f"to the Sneed DeFi canister ({SNEED_DEFI}), so that the position's tokens "
        "and fees can be withdrawn. Sonic's withdraw credits the calling canister, "
        "so funds recovered by the DeFi canister land there, under the DAO's control "
        "via deploy_icrc1_tokens."
    )
    p4_action = f"""          ExecuteGenericNervousSystemFunction = record {{
            function_id = {NEW_FUNCTION_ID} : nat64;
            payload = {candid_blob(p4_payload)};
          }}"""
    (OUT / "p4_transfer_position.did").write_text(
        proposal("Transfer Sonic LP position 2 to the Sneed DeFi canister", p4_summary, p4_action)
    )

    print(f"wasm:        {WASM}")
    print(f"wasm sha256: {wasm_hash}")
    print(f"wasm bytes:  {len(wasm_bytes)}")
    print()
    for f in sorted(OUT.iterdir()):
        print(f"wrote {f.relative_to(REPO)} ({f.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
