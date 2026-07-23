#!/usr/bin/env python3
"""Submit a Sneed DeFi canister-upgrade proposal to SNS governance.

Reads the Candid argument file produced by scripts/make_proposal_args.py and
submits it to the SNS governance canister's manage_neuron method via
`icp canister call`.

Usage:
    python3 scripts/submit_proposal.py [--reinstall] [--identity NAME]
                                       [--network NAME] [--yes] [--dry-run]

By default this submits the upgrade proposal (proposal_args/deploy_upgrade.did).
Pass --reinstall to submit the reinstall proposal (deploy_reinstall.did)
instead. Generate the argument file first with scripts/make_proposal_args.py.
"""

import argparse
import pathlib
import shlex
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / "proposal_args"

# The SNS governance canister; its manage_neuron method submits the proposal.
GOVERNANCE = "fi3zi-fyaaa-aaaaq-aachq-cai"

# The canister the proposal upgrades.
SNEED_DEFI = "ok64y-uiaaa-aaaag-qdcbq-cai"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Submit a Sneed DeFi upgrade proposal to SNS governance."
    )
    parser.add_argument(
        "--reinstall",
        action="store_true",
        help="submit the reinstall proposal (deploy_reinstall.did) instead of "
        "the upgrade one",
    )
    parser.add_argument(
        "--identity",
        help="icp identity to submit as (default: icp's currently selected identity)",
    )
    parser.add_argument(
        "--network",
        default="ic",
        help="network to target (default: ic)",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="skip the confirmation prompt",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the icp command without running it",
    )
    args = parser.parse_args()

    mode_name = "reinstall" if args.reinstall else "upgrade"
    did_file = OUT / f"deploy_{mode_name}.did"
    if not did_file.exists():
        print(f"error: argument file not found at {did_file}", file=sys.stderr)
        flag = " --reinstall" if args.reinstall else ""
        print(
            f"Generate it first: python3 scripts/make_proposal_args.py{flag}",
            file=sys.stderr,
        )
        return 1

    cmd = [
        "icp",
        "canister",
        "call",
        GOVERNANCE,
        "manage_neuron",
        "--args-file",
        str(did_file),
        "--network",
        args.network,
    ]
    if args.identity:
        cmd += ["--identity", args.identity]

    print(f"mode:       {mode_name}")
    print(f"args file:  {did_file.relative_to(REPO)} ({did_file.stat().st_size} bytes)")
    print(f"governance: {GOVERNANCE}")
    print(f"upgrades:   {SNEED_DEFI}")
    print(f"network:    {args.network}")
    print(f"identity:   {args.identity or '(icp default)'}")
    print()
    print("command:", shlex.join(cmd))
    print()

    if args.dry_run:
        print("dry run: not submitting")
        return 0

    if not args.yes:
        try:
            answer = input("Submit this proposal? [y/N] ").strip().lower()
        except EOFError:
            answer = ""
        if answer not in ("y", "yes"):
            print("aborted")
            return 1

    try:
        return subprocess.run(cmd).returncode
    except FileNotFoundError:
        print("error: `icp` not found on PATH", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
