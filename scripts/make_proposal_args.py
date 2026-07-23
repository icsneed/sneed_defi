#!/usr/bin/env python3
"""Generate the Candid argument file for a Sneed DeFi deploy proposal.

The proposal embeds a ~400KB wasm, which is far too large to paste on a
command line, so the argument is written to a file and passed to
`icp canister call` with --args-file.

Usage:
    NEURON_ID="<64 hex chars: your neuron's 32-byte subaccount>" \
    TITLE="Upgrade Sneed DeFi canister" \
    SUMMARY="What this deploy changes and why." \
    python3 scripts/make_proposal_args.py [--reinstall]

Any of NEURON_ID, TITLE and SUMMARY that are not supplied via the environment
are prompted for interactively (only the missing ones). This makes the script
usable both from a shell one-liner and by simply running it and answering the
prompts.

By default the proposal deploys the wasm as an upgrade (mode 3). Pass
--reinstall to deploy in reinstall mode (mode 2) instead, which wipes all
canister state.

Writes proposal_args/deploy_upgrade.did (or deploy_reinstall.did).
The wasm sha256 is appended to the summary automatically.
"""

import argparse
import hashlib
import os
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
WASM = REPO / ".icp" / "cache" / "artifacts" / "sneed_defi"
OUT = REPO / "proposal_args"

# The proposing neuron's subaccount (its 32-byte "neuron id") is supplied at
# runtime via the NEURON_ID environment variable as 64 hex characters, so a
# fresh clone can use this script with its own neuron.

SNEED_DEFI = "ok64y-uiaaa-aaaag-qdcbq-cai"

REPO_URL = "https://github.com/icsneed/sneed_defi"

# CanisterInstallMode values used by UpgradeSnsControlledCanister.
MODE_REINSTALL = 2
MODE_UPGRADE = 3


def prompt_required(name: str, prompt_text: str) -> str:
    """Return the env value for ``name`` if set, else prompt for it.

    A value present in the environment is used as-is. When it is missing the
    user is prompted (interactively or from piped stdin) and re-prompted until
    they enter something non-empty. If stdin is exhausted with no value, error
    out rather than hang.
    """
    value = os.environ.get(name, "")
    if value.strip():
        return value
    while True:
        try:
            entered = input(f"{prompt_text}: ").strip()
        except EOFError:
            print(f"error: {name} not set and no input available", file=sys.stderr)
            print(f'Set it in the environment, e.g. {name}="..."', file=sys.stderr)
            sys.exit(1)
        if entered:
            return entered
        print(f"{name} cannot be empty.", file=sys.stderr)


def parse_neuron_id(neuron_hex: str):
    """Parse a neuron subaccount, returning 32 bytes or ``None`` if invalid.

    On failure the reason is printed to stderr so callers can either re-prompt
    (interactive) or exit (value came from the environment).
    """
    neuron_hex = neuron_hex.strip().lower()
    try:
        neuron_bytes = bytes.fromhex(neuron_hex)
    except ValueError:
        print(f"error: neuron id must be hex characters, got: {neuron_hex!r}", file=sys.stderr)
        return None
    if len(neuron_bytes) != 32:
        print(
            f"error: neuron id must be 32 bytes (64 hex chars), got {len(neuron_bytes)} bytes",
            file=sys.stderr,
        )
        return None
    return neuron_bytes


def prompt_neuron_id() -> bytes:
    """Return the proposing neuron's 32-byte subaccount.

    Uses NEURON_ID from the environment when set (erroring hard if it is
    malformed), otherwise prompts and re-prompts until a valid value is entered.
    """
    from_env = os.environ.get("NEURON_ID", "")
    if from_env.strip():
        neuron_bytes = parse_neuron_id(from_env)
        if neuron_bytes is None:
            sys.exit(1)
        return neuron_bytes
    while True:
        try:
            entered = input("Neuron id (64 hex chars): ")
        except EOFError:
            print("error: NEURON_ID not set and no input available", file=sys.stderr)
            print('Set it in the environment, e.g. NEURON_ID="<64 hex chars>"', file=sys.stderr)
            sys.exit(1)
        neuron_bytes = parse_neuron_id(entered)
        if neuron_bytes is not None:
            return neuron_bytes


def candid_blob(data: bytes) -> str:
    """Render bytes as a Candid blob literal."""
    return 'blob "' + "".join(f"\\{b:02x}" for b in data) + '"'


def candid_text(text: str) -> str:
    """Render a Python string as a quoted Candid text literal."""
    escaped = (
        text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    )
    return f'"{escaped}"'


def proposal(subaccount: str, title: str, summary: str, action: str) -> str:
    return f"""(
  record {{
    subaccount = {subaccount};
    command = opt variant {{
      MakeProposal = record {{
        title = {candid_text(title)};
        url = "{REPO_URL}";
        summary = {candid_text(summary)};
        action = opt variant {{
{action}
        }};
      }}
    }};
  }}
)
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the Candid argument file for a proposal that "
        f"deploys the sneed_defi wasm to {SNEED_DEFI}."
    )
    parser.add_argument(
        "--reinstall",
        action="store_true",
        help="deploy in reinstall mode, wiping all canister state "
        "(default: upgrade mode)",
    )
    args = parser.parse_args()

    # Fail fast on the build artifact before prompting for anything.
    if not WASM.exists():
        print(f"error: wasm not found at {WASM}", file=sys.stderr)
        print("Run: icp build sneed_defi", file=sys.stderr)
        return 1

    title = prompt_required("TITLE", "Proposal title")
    summary = prompt_required("SUMMARY", "Proposal summary")
    neuron_bytes = prompt_neuron_id()

    wasm_bytes = WASM.read_bytes()
    wasm_hash = hashlib.sha256(wasm_bytes).hexdigest()
    OUT.mkdir(exist_ok=True)

    mode = MODE_REINSTALL if args.reinstall else MODE_UPGRADE
    mode_name = "reinstall" if args.reinstall else "upgrade"
    full_summary = f"{summary}\n\nwasm sha256: {wasm_hash}"

    action = f"""          UpgradeSnsControlledCanister = record {{
            canister_id = opt principal "{SNEED_DEFI}";
            new_canister_wasm = {candid_blob(wasm_bytes)};
            canister_upgrade_arg = null;
            chunked_canister_wasm = null;
            mode = opt ({mode} : int32);
          }}"""

    out_file = OUT / f"deploy_{mode_name}.did"
    out_file.write_text(proposal(candid_blob(neuron_bytes), title, full_summary, action))

    print(f"wasm:        {WASM}")
    print(f"wasm sha256: {wasm_hash}")
    print(f"wasm bytes:  {len(wasm_bytes)}")
    print(f"mode:        {mode_name} ({mode})")
    print()
    print(f"wrote {out_file.relative_to(REPO)} ({out_file.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
