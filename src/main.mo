import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
import VarArray "mo:core/VarArray";
import List "mo:core/List";
import Time "mo:core/Time";
import Principal "mo:core/Principal";
import Error "mo:core/Error";
import Timer "mo:core/Timer";

import T "Types";
import Pool "poolTypes";

persistent actor {

  // Log messages (stable)
  var stable_log : [Text] = [];

  // Log messages
  transient var log : T.Log = List.fromArray<Text>(stable_log);

  // Safety admins are trusted principals permitted to drive recovery-style
  // operations (e.g. pulling funds out of Sonic back into this canister).
  // They must ONLY be granted access to operations that cannot transfer funds
  // to an arbitrary destination. For example, Sonic's withdraw always credits
  // the calling canister, so recovered funds land on this canister, where the
  // governance-only deploy_icrc1_tokens controls where they ultimately go.
  // Anything capable of sending funds to an arbitrary recipient must remain
  // gated on governance alone, never on safety_admins.
  transient let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
  transient let safety_admins = ["tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe", "d7zib-qo5mr-qzmpb-dtyof-l7yiu-pu52k-wk7ng-cbm3n-ffmys-crbkz-nae"];
  transient let sneed_defi_id = "ok64y-uiaaa-aaaag-qdcbq-cai";

  private func is_safety_admin(caller : Principal) : Bool {
    let c = Principal.toText(caller);
    c == sneed_governance_id or Array.find<Text>(safety_admins, func(a) { a == c }) != null;
  };

  // Generate subaccount from Principal. Moved above the harvest-subaccount
  // constants below: those are `transient let`s that call this eagerly at
  // actor init, which Motoko's definedness check requires to be textually
  // defined first (unlike a call from inside a function body, which is lazy).
  private func PrincipalToSubaccount(p : Principal) : [Nat8] {
      let a = VarArray.repeat<Nat8>(0, 32);
      let pa = Principal.toBlob(p);
      a[0] := Nat8.fromNat(pa.size());

      var pos = 1;
      for (x in pa.vals()) {
              a[pos] := x;
              pos := pos + 1;
          };

      Array.fromVarArray(a);
  };

  // === LP fee harvesting: constants ===
  //
  // Ledger ids for the two tokens we route. A pool's token0/token1 are matched
  // against these by EXACT address, so only genuine SNEED/ICP fees are moved.
  transient let icp_ledger_id = "ryjl3-tyaaa-aaaaa-aaaba-cai";
  transient let sneed_ledger_id = "hvgxa-wqaaa-aaaaq-aacia-cai";

  // Sneed "RLL" neuron-pool-vector destinations. These are the ONLY places the
  // harvester can send funds, and they are compile-time constants: no caller
  // (not even a safety_admin) can change where fees go. The subaccounts were
  // decoded from the ICRC-1 extended textual form and their checksums verified.
  //   ICP:   6jvpj-...-azwnq-cai-m7u3kpi.100000000060...0  (subaccount byte 5 = 6)
  //   SNEED: 6jvpj-...-azwnq-cai-vilbrxq.1000000002d0...0  (subaccount byte 5 = 0x2d = 45)
  transient let rll_vector_owner = Principal.fromText("6jvpj-sqaaa-aaaaj-azwnq-cai");
  transient let rll_icp_subaccount : Blob = Blob.fromArray([1, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  transient let rll_sneed_subaccount : Blob = Blob.fromArray([1, 0, 0, 0, 0, 45, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  transient let rll_icp_dest : T.Account = { owner = rll_vector_owner; subaccount = ?rll_icp_subaccount };
  transient let rll_sneed_dest : T.Account = { owner = rll_vector_owner; subaccount = ?rll_sneed_subaccount };

  // Dedicated destination for auto-withdrawn LP fees. Derived from THIS canister's
  // principal via PrincipalToSubaccount (see below), so it is injective and can
  // never collide with a user subaccount (that would require caller == this
  // canister). Its on-chain balance is the source of truth for "harvested,
  // awaiting forward"; emergency/governance funds sit in the DEFAULT subaccount
  // and are physically unreachable by the forward path.
  transient let harvest_subaccount : Blob =
    Blob.fromArray(PrincipalToSubaccount(Principal.fromText(sneed_defi_id)));
  transient let harvest_account : T.Account =
    { owner = Principal.fromText(sneed_defi_id); subaccount = ?harvest_subaccount };

  // Headroom for ICPSwap's asynchronous claim auto-withdraw to settle before we
  // forward the proceeds. Used by the one-shot delayed forward; not persisted.
  transient let settle_delay_seconds : Nat = 60;

  // Smallest cadence we accept. Timer resolution is roughly the block rate, so a
  // sub-minute cadence buys nothing and risks hammering the pool/ledgers.
  transient let min_cadence_seconds = 60;

  // Pools approved for automatic fee harvesting. Enrollment (and every harvest
  // cycle, as defense in depth) is restricted to these canisters. This is the
  // primary guard against a safety_admin enrolling an attacker-controlled
  // canister and having its fabricated tokens claimed into the harvest subaccount
  // and swept into the RLL vectors: fees can only ever be claimed from a pool on
  // this compile-time list. To start,
  // only the SNEED/ICP pool is approved.
  transient let approved_lp_pools = ["osyzs-xiaaa-aaaag-qc76q-cai"];

  private func is_approved_lp_pool(pool : Principal) : Bool {
    let p = Principal.toText(pool);
    Array.find<Text>(approved_lp_pools, func(a) { a == p }) != null;
  };

  // === LP fee harvesting: state ===
  //
  // Stable (persistent actor => non-transient vars persist across upgrades):
  var claim_positions : [T.ClaimPosition] = [];  // positions enrolled in auto-harvest
  var claim_cadence_seconds : Nat = 0;           // configured cadence (0 until first schedule)
  var claim_min_icp : Nat = 0;                   // per-token minimum before ICP is forwarded
  var claim_min_sneed : Nat = 0;                 // per-token minimum before SNEED is forwarded
  var claim_active : Bool = false;               // whether a recurring harvest is scheduled

  // Transient: timer ids do not survive upgrades; re-armed in postupgrade.
  transient var claim_timer_id : ?Nat = null;

  // Transient reentrancy guard: never run two harvest cycles at once. A slow
  // cycle overlapping the next tick, or a manual run racing the timer, would
  // redundantly re-claim positions and re-scan the harvest subaccount. (It could
  // not double-forward: forward_token drains the real on-chain subaccount balance,
  // so an overlap merely no-ops the second transfer.) do_harvest is trap-free, so
  // this guard is always reset; an upgrade also clears it.
  transient var harvest_running : Bool = false;

  // Deploy the specified amount of ICRC1 tokens from the DeFi canistyer (using the null subaccount).
  // Can only be called by the Sneed DAO governance canister (via approved proposal)!
  public shared ({ caller }) func deploy_icrc1_tokens(
    amount_e8s : T.Balance,                 // amount to be sent.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be sent.
    to_account : T.Account,                 // the account that the icrc1 token should be sent to 
    fee : ?T.Balance,                       // the expected fee (set to null when sending to burn account!)
    memo : ?Blob)                           // an optional memo to send with the icrc1 transfer transaction
    : async T.TransferResult {

      log_msg("deploy_icrc1_tokens called by " # 
        Principal.toText(caller) # 
        " with arguments: " #
        "amount_e8s: " # debug_show(amount_e8s) #  
        ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
        ", to_account: " # debug_show(to_account) #
        ", fee: " # debug_show(fee) #  
        ", memo: " # debug_show(memo));

      try {

        // This method may only be called by the Sneed DAO governance canister (via approved proposal)!

        if (Principal.toText(caller) == sneed_governance_id) {

          let transfer_args : T.TransferArgs = {
            from_subaccount = null;
            to = to_account;
            amount = amount_e8s;
            fee = fee;
            memo = memo;

            created_at_time = null;
          };

          let icrc1_ledger_canister = actor (Principal.toText(icrc1_ledger_canister_id)) : actor {
            icrc1_transfer(args : T.TransferArgs) : async T.TransferResult;
          };  


          log_msg("deploy_icrc1_tokens, calling icrc1_transfer of " # 
            Principal.toText(icrc1_ledger_canister_id) # 
            " with arguments: " # debug_show(transfer_args));

          let result = await icrc1_ledger_canister.icrc1_transfer(transfer_args);

          log_msg("deploy_icrc1_tokens, called icrc1_transfer of " # 
            Principal.toText(icrc1_ledger_canister_id) # 
            " with result: " # debug_show(result));

          result;

        } else {


          let err_msg = "deploy_icrc1_tokens_to_icpswap ERROR: May only be called by " # 
            sneed_governance_id # " (Was called by " # Principal.toText(caller) # ")";

          log_msg(err_msg);

          return #Err(#GenericError({error_code = 1; message = err_msg;}));

        };

      } catch e {

        let err_msg = "deploy_icrc1_tokens ERROR: " # Error.message(e);

        log_msg(err_msg);

        return #Err(#GenericError({error_code = 1; message = err_msg;}));

      }

  };


  // SNS generic function validation method for deploy_icrc1_tokens 
  public query ({ caller }) func validate_deploy_icrc1_tokens(
    amount_e8s : T.Balance,                 
    icrc1_ledger_canister_id : Principal,   
    to_account : T.Account,                  
    fee : ?T.Balance,                       
    memo : ?Blob) : async T.ValidationResult {

      let msg:Text = "amount_e8s: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_account: " # debug_show(to_account) #  
      ", fee: " # debug_show(fee) #  
      ", memo: " # debug_show(memo);

      log_msg("validate_deploy_icrc1_tokens called by " # 
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);

  };


  // Send the specified amount of ICRC1 tokens.   
  public shared ({ caller }) func send_icrc1_tokens(
    amount_e8s : T.Balance,                 // amount to be sent.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be sent.
    to_account : T.Account,                 // the account that the icrc1 token should be sent to 
    fee : ?T.Balance,                       // the expected fee (set to null when sending to burn account!)
    memo : ?Blob)                           // an optional memo to send with the icrc1 transfer transaction
    : async T.TransferResult {

      log_msg("send_icrc1_tokens called by " # 
        Principal.toText(caller) # 
        " with arguments: " #
        "amount_e8s: " # debug_show(amount_e8s) #  
        ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
        ", to_account: " # debug_show(to_account) #
        ", fee: " # debug_show(fee) #  
        ", memo: " # debug_show(memo));

      try {

        let from_subaccount = Blob.fromArray(PrincipalToSubaccount(caller));

        let transfer_args : T.TransferArgs = {
          from_subaccount = ?from_subaccount;
          to = to_account;
          amount = amount_e8s;
          fee = fee;
          memo = memo;

          created_at_time = null;
        };

        let icrc1_ledger_canister = actor (Principal.toText(icrc1_ledger_canister_id)) : actor {
          icrc1_transfer(args : T.TransferArgs) : async T.TransferResult;
        };  


        log_msg("send_icrc1_tokens, calling icrc1_transfer of " # 
          Principal.toText(icrc1_ledger_canister_id) # 
          " with arguments: " # debug_show(transfer_args));

        let result = await icrc1_ledger_canister.icrc1_transfer(transfer_args);

        log_msg("send_icrc1_tokens, called icrc1_transfer of " # 
          Principal.toText(icrc1_ledger_canister_id) # 
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "send_icrc1_tokens ERROR: " # Error.message(e);

        log_msg(err_msg);

        return #Err(#GenericError({error_code = 1; message = err_msg;}));

      }

  };

  // SNS generic function validation method for send_icrc1_tokens 
  public query ({ caller }) func validate_send_icrc1_tokens(
    amount_e8s : T.Balance,                 
    icrc1_ledger_canister_id : Principal,   
    to_account : T.Account,                  
    fee : ?T.Balance,                       
    memo : ?Blob) : async T.ValidationResult {

      let msg:Text = "amount_e8s: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_account: " # debug_show(to_account) #  
      ", fee: " # debug_show(fee) #  
      ", memo: " # debug_show(memo);

      log_msg("validate_send_icrc1_tokens called by " # 
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);

  };

  // Deploy the specified amount of ICRC1 tokens to the specified ICPSwap swap canister,
  // using a subaccount generated from the Sneed DeFi (this) canister's Principal ID.
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  public shared ({ caller }) func deploy_icrc1_tokens_to_icpswap(
    amount_e8s : T.Balance,                 // amount to be deployed.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be deployed.
    to_swap_canister_id : Principal)        // the Principal id of the ICPSwap swap canister that the icrc1 token should be deployed to 
    : async T.TransferResult {

      log_msg("deploy_icrc1_tokens_to_icpswap called by " # 
        Principal.toText(caller) # 
        " with arguments: " #
        "amount_e8s: " # debug_show(amount_e8s) #  
        ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
        ", to_swap_canister_id: " # Principal.toText(to_swap_canister_id));

      try {

        // This method may only be called by the Sneed DAO governance canister (via approved proposal)!

        if (Principal.toText(caller) == sneed_governance_id) {

          // Deploy to an account with a subaccount generated from the Sneed DAO DeFi canister id.
          let to_subaccount = Blob.fromArray(PrincipalToSubaccount(Principal.fromText(sneed_defi_id)));

          // Deploy to an account using the swap canister id as "owner" and the subaccount generated
          // from the Sneed DAO DeFi canister id.
          let to_account : T.Account = {
            owner = to_swap_canister_id;
            subaccount = ?to_subaccount;
          };

          let transfer_args : T.TransferArgs = {
            from_subaccount = null;
            to = to_account;
            amount = amount_e8s;
            fee = null;
            memo = null;

            created_at_time = null;
          };

          let icrc1_ledger_canister = actor (Principal.toText(icrc1_ledger_canister_id)) : actor {
            icrc1_transfer(args : T.TransferArgs) : async T.TransferResult;
          };  

          log_msg("deploy_icrc1_tokens_to_icpswap, calling icrc1_transfer of " # 
            Principal.toText(icrc1_ledger_canister_id) # 
            " with arguments: " # debug_show(transfer_args));

          let result = await icrc1_ledger_canister.icrc1_transfer(transfer_args);

          log_msg("deploy_icrc1_tokens_to_icpswap, called icrc1_transfer of " # 
            Principal.toText(icrc1_ledger_canister_id) # 
            " with result: " # debug_show(result));

          result;

        } else {

          let err_msg = "deploy_icrc1_tokens_to_icpswap ERROR: May only be called by " # 
            sneed_governance_id # " (Was called by " # Principal.toText(caller) # ")";

          log_msg(err_msg);

          return #Err(#GenericError({error_code = 1; message = err_msg;}));

        };

      } catch e {
      
        let err_msg = "deploy_icrc1_tokens_to_icpswap ERROR: " # Error.message(e);

        log_msg(err_msg);

        return #Err(#GenericError({error_code = 1; message = err_msg;}));

      };

  };

  // SNS generic function validation method for deploy_icrc1_tokens_to_icpswap 
  public query ({ caller }) func validate_deploy_icrc1_tokens_to_icpswap(
    amount_e8s : T.Balance,                 // amount to be deployed.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be deployed.
    to_swap_canister_id : Principal)        // the Principal id of the ICPSwap swap canister that the icrc1 token should be deployed to 
    : async T.ValidationResult {

      let msg:Text = "amount_e8s: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_swap_canister_id: " # Principal.toText(to_swap_canister_id);
      
      log_msg("validate_deploy_icrc1_tokens_to_icpswap called by " # 
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);

  };

  // Transfer an ICPSwap LP position owned by this canister.
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  public shared ({ caller }) func transfer_icpswap_lp_position(
    lp_canister_id : Principal,             // the Principal id of the canister of the ICPSwap LP to transfer.
    to_principal : Principal,               // the Principal id to transfer the LP to. 
    position_id : Nat)                      // the Position id of the LP to transfer 
    : async T.TransferICPSwapLPResult {

      log_msg("transfer_icpswap_lp_position called by " # 
        Principal.toText(caller) # 
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) # 
        ", to_principal: " # Principal.toText(to_principal) #  
        ", position_id: " # debug_show(position_id));

      try {

        // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
        
        if (Principal.toText(caller) == sneed_governance_id) {

          let from = Principal.fromText(sneed_defi_id); // this canister

          let lp_canister = actor (Principal.toText(lp_canister_id)) : actor {
            transferPosition(from: Principal, to: Principal, positionId: Nat) : async T.TransferICPSwapLPResult;
          };  

          log_msg("transfer_icpswap_lp_position, calling transferPosition of " # 
            Principal.toText(lp_canister_id) # 
            " with arguments: " #
            "from: " # Principal.toText(from) # 
            ", to: " # Principal.toText(to_principal) #  
            ", position_id: " # debug_show(position_id));

          let result = await lp_canister.transferPosition(from, to_principal, position_id);

          log_msg("transfer_icpswap_lp_position, called transferPosition of " # 
            Principal.toText(lp_canister_id) # 
            " with result: " # debug_show(result));

          result;

        } else {

          let err_msg = "transfer_icpswap_lp_position ERROR: May only be called by " # 
            sneed_governance_id # " (Was called by " # Principal.toText(caller) # ")";

          log_msg(err_msg);

          return #err(#InternalError(err_msg));

        };

      } catch e {
      
        let err_msg = "transfer_icpswap_lp_position ERROR: " # Error.message(e);

        log_msg(err_msg);

        return #err(#InternalError(Error.message(e)));

      };

  };

  // SNS generic function validation method for transfer_icpswap_lp_position 
  public query ({ caller }) func validate_transfer_icpswap_lp_position(
    lp_canister_id : Principal,
    to_principal : Principal,
    position_id : Nat) : async T.ValidationResult {

      let msg:Text = "lp_canister_id: " # Principal.toText(lp_canister_id) # 
      ", to_principal: " # Principal.toText(to_principal) #  
      ", position_id: " # debug_show(position_id);

      log_msg("validate_transfer_icpswap_lp_position called by " #
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);

  };

  // SNS generic function validation method for the ICPSwap transferPosition call.
  // The target of that generic function is the ICPSwap pool canister itself; this
  // canister only validates. The argument order must match ICPSwap's
  // transferPosition(from, to, positionId). Use this validator when transferring a
  // position owned by the Sneed governance canister (from = governance), so that the
  // SNS governance canister is the caller of transferPosition on the pool.
  public query ({ caller }) func validate_transfer_icpswap_pool_position(
    from : Principal,
    to : Principal,
    position_id : Nat) : async T.ValidationResult {

      let msg : Text = "from: " # Principal.toText(from) #
        ", to: " # Principal.toText(to) #
        ", position_id: " # debug_show(position_id);

      log_msg("validate_transfer_icpswap_pool_position called by " #
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);
  };

  // SNS generic function validation method for LP management
  public query ({ caller }) func validate_claim_fees_sonic_lp_position(claimArgs: Pool.SonicClaimArgs) : async T.ValidationResult {

      let msg:Text = "positionId: " # debug_show(claimArgs.positionId);

      log_msg("validate_claim_fees_sonic_lp_position called by " # 
        Principal.toText(caller) # " with arguments: " # msg);
      
      #Ok(msg);
  };
  public query ({ caller }) func validate_decrease_liquidity_sonic_lp_position(decreaseLiquidityArgs: Pool.SonicDecreaseLiquidityArgs) : async T.ValidationResult {

      let msg:Text = "positionId: " # debug_show(decreaseLiquidityArgs.positionId) #
        ", liquidity: " # debug_show(decreaseLiquidityArgs.liquidity);

      log_msg("validate_decrease_liquidity_sonic_lp_position called by " # 
        Principal.toText(caller) # " with arguments: " # msg);
      
      #Ok(msg);
  };
  public query ({ caller }) func validate_withdraw_sonic_lp(withdrawArgs: Pool.SonicWithdrawArgs) : async T.ValidationResult {

      let msg:Text = 
        "token: " # debug_show(withdrawArgs.token) #
        ", fee: " # debug_show(withdrawArgs.fee) #
        ", amount: " # debug_show(withdrawArgs.amount);

      log_msg("validate_withdraw_sonic_lp called by " # 
        Principal.toText(caller) # " with arguments: " # msg);
      
      #Ok(msg);
  };

  // SNS generic function validation method for the Sonic transferPosition call.
  // The target of that generic function is the Sonic pool canister itself; this
  // canister only validates. The argument order must match Sonic's
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

      if (not is_safety_admin(caller)) {
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

      if (not is_safety_admin(caller)) {
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

  // Withdraw an exact amount of a token from this canister's unused balance in
  // a Sonic pool. Sonic credits the calling canister, so funds land here.
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

      if (not is_safety_admin(caller)) {
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
  // this canister is owed and what the pool actually holds. The Sonic pool
  // holds less than it owes, so an exact-amount withdraw of the full claim
  // fails; this takes whatever is available and can be re-run as reserves
  // return. Which of the pool's two tokens is requested is resolved by
  // matching the address from metadata, never by assuming an order.
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

      if (not is_safety_admin(caller)) {
        let err_msg = "sonic_withdraw_max ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.SonicPool = actor (Principal.toText(lp_canister_id));
        let self = Principal.fromText(sneed_defi_id);

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

        // What this canister is owed.
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

  // Claim (collect) accumulated fees for an ICPSwap LP position owned by this canister.
  // Credits this canister's unused balance inside the ICPSwap pool.
  public shared ({ caller }) func icpswap_claim(
    lp_canister_id : Principal,
    position_id : Nat)
    : async Pool.ICPSwapAmountsResult {

      log_msg("icpswap_claim called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", position_id: " # debug_show(position_id));

      if (not is_safety_admin(caller)) {
        let err_msg = "icpswap_claim ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.ICPSwapPool = actor (Principal.toText(lp_canister_id));

        let result = await lp_canister.claim({ positionId = position_id });

        log_msg("icpswap_claim, called claim of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "icpswap_claim ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };

  // Decrease (remove) liquidity from an ICPSwap LP position owned by this canister.
  // Credits this canister's unused balance inside the ICPSwap pool.
  // Pass the position's full liquidity to withdraw from it completely.
  public shared ({ caller }) func icpswap_decrease_liquidity(
    lp_canister_id : Principal,
    position_id : Nat,
    liquidity : Text)
    : async Pool.ICPSwapAmountsResult {

      log_msg("icpswap_decrease_liquidity called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", position_id: " # debug_show(position_id) #
        ", liquidity: " # liquidity);

      if (not is_safety_admin(caller)) {
        let err_msg = "icpswap_decrease_liquidity ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.ICPSwapPool = actor (Principal.toText(lp_canister_id));

        let result = await lp_canister.decreaseLiquidity({
          positionId = position_id;
          liquidity = liquidity;
        });

        log_msg("icpswap_decrease_liquidity, called decreaseLiquidity of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "icpswap_decrease_liquidity ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };

  // Withdraw as much of a token as is currently possible from an ICPSwap pool:
  // the lesser of what this canister is owed and what the pool actually holds.
  // If the pool holds less than it owes, an exact-amount withdraw of the full
  // claim fails; this takes whatever is available and can be re-run as reserves
  // return. Which of the pool's two tokens is requested is resolved by matching
  // the address from metadata, never by assuming an order. ICPSwap credits the
  // calling canister, so funds land here.
  public shared ({ caller }) func icpswap_withdraw_max(
    lp_canister_id : Principal,
    token : Text,
    fee : Nat)
    : async Pool.ICPSwapNatResult {

      log_msg("icpswap_withdraw_max called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", token: " # token #
        ", fee: " # debug_show(fee));

      if (not is_safety_admin(caller)) {
        let err_msg = "icpswap_withdraw_max ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(#InternalError(err_msg));
      };

      try {

        let lp_canister : Pool.ICPSwapPool = actor (Principal.toText(lp_canister_id));
        let self = Principal.fromText(sneed_defi_id);

        let meta = await lp_canister.metadata();
        let is_token0 = switch (meta) {
          case (#ok(m)) {
            if (m.token0.address == token) { true }
            else if (m.token1.address == token) { false }
            else {
              let err_msg = "icpswap_withdraw_max ERROR: token " # token #
                " is not in pool " # Principal.toText(lp_canister_id);
              log_msg(err_msg);
              return #err(#UnsupportedToken(token));
            };
          };
          case (#err(e)) {
            let err_msg = "icpswap_withdraw_max ERROR: metadata failed: " # debug_show(e);
            log_msg(err_msg);
            return #err(e);
          };
        };

        // What this canister is owed.
        let unused = await lp_canister.getUserUnusedBalance(self);
        let owed = switch (unused) {
          case (#ok(b)) { if (is_token0) { b.balance0 } else { b.balance1 } };
          case (#err(e)) {
            let err_msg = "icpswap_withdraw_max ERROR: getUserUnusedBalance failed: " # debug_show(e);
            log_msg(err_msg);
            return #err(e);
          };
        };

        // What the pool actually holds.
        let held_balance = await lp_canister.getTokenBalance();
        let held = if (is_token0) { held_balance.token0 } else { held_balance.token1 };

        let amount = Nat.min(owed, held);

        log_msg("icpswap_withdraw_max, token: " # token #
          ", is_token0: " # debug_show(is_token0) #
          ", owed: " # debug_show(owed) #
          ", held: " # debug_show(held) #
          ", withdrawing: " # debug_show(amount));

        // A withdrawal at or below the ledger fee nets nothing.
        if (amount <= fee) {
          let err_msg = "icpswap_withdraw_max ERROR: available amount " #
            debug_show(amount) # " does not exceed fee " # debug_show(fee);
          log_msg(err_msg);
          return #err(#InsufficientFunds);
        };

        let result = await lp_canister.withdraw({
          token = token;
          fee = fee;
          amount = amount;
        });

        log_msg("icpswap_withdraw_max, called withdraw of " #
          Principal.toText(lp_canister_id) #
          " with result: " # debug_show(result));

        result;

      } catch e {

        let err_msg = "icpswap_withdraw_max ERROR: " # Error.message(e);
        log_msg(err_msg);
        return #err(#InternalError(Error.message(e)));

      };

  };

  // Emergency: pull as many tokens as possible out of an ICPSwap position owned
  // by this canister and back onto this canister, in one best-effort call.
  // Sequences claim -> decreaseLiquidity(full) -> withdraw(min(owed, held)) for
  // both tokens. A failure in any step is recorded in `errors` and the call still
  // proceeds to withdraw whatever unused balance exists; it is safe to re-run as
  // pool reserves return. ICPSwap credits the calling canister, so funds land here.
  // Hard stops (unauthorized, metadata unavailable) return #err; every other
  // outcome returns #ok(summary), including partial recovery.
  public shared ({ caller }) func emergency_pull_icpswap_lp(
    lp_canister_id : Principal,
    position_id : Nat)
    : async T.EmergencyPullResult {

      log_msg("emergency_pull_icpswap_lp called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) #
        ", position_id: " # debug_show(position_id));

      if (not is_safety_admin(caller)) {
        let err_msg = "emergency_pull_icpswap_lp ERROR: Not authorized (Was called by " #
          Principal.toText(caller) # ")";
        log_msg(err_msg);
        return #err(err_msg);
      };

      let lp_canister : Pool.ICPSwapPool = actor (Principal.toText(lp_canister_id));
      let self = Principal.fromText(sneed_defi_id);
      let errors = List.empty<Text>();

      // 1. Pool metadata -> token addresses. Hard stop: without these we cannot withdraw.
      let meta : Pool.ICPSwapMetadataResult =
        try { await lp_canister.metadata() }
        catch e { #err(#InternalError(Error.message(e))) };
      let (token0, token1) = switch (meta) {
        case (#ok(m)) { (m.token0.address, m.token1.address) };
        case (#err(e)) {
          let err_msg = "emergency_pull_icpswap_lp ERROR: metadata failed: " # debug_show(e);
          log_msg(err_msg);
          return #err(err_msg);
        };
      };

      // 2. Ledger fees per token (best-effort). A token with an unreadable fee is skipped in step 6.
      let ledger0 = actor (token0) : actor { icrc1_fee : () -> async Nat };
      let ledger1 = actor (token1) : actor { icrc1_fee : () -> async Nat };
      let fee0 : ?Nat =
        try { ?(await ledger0.icrc1_fee()) }
        catch e { List.add(errors, "icrc1_fee(token0) failed: " # Error.message(e)); null };
      let fee1 : ?Nat =
        try { ?(await ledger1.icrc1_fee()) }
        catch e { List.add(errors, "icrc1_fee(token1) failed: " # Error.message(e)); null };

      // 3. Claim fees (best-effort).
      var claimed0 : Nat = 0;
      var claimed1 : Nat = 0;
      let claim_res : Pool.ICPSwapAmountsResult =
        try { await lp_canister.claim({ positionId = position_id }) }
        catch e { #err(#InternalError(Error.message(e))) };
      switch (claim_res) {
        case (#ok(a)) { claimed0 := a.amount0; claimed1 := a.amount1 };
        case (#err(e)) { List.add(errors, "claim failed: " # debug_show(e)) };
      };

      // 4. Remove all liquidity (best-effort). Skip when already zero (supports re-runs).
      var liquidity_removed : Nat = 0;
      var decreased0 : Nat = 0;
      var decreased1 : Nat = 0;
      let pos_res : Pool.ICPSwapUserPositionResult =
        try { await lp_canister.getUserPosition(position_id) }
        catch e { #err(#InternalError(Error.message(e))) };
      switch (pos_res) {
        case (#ok(p)) {
          if (p.liquidity > 0) {
            liquidity_removed := p.liquidity;
            let dec_res : Pool.ICPSwapAmountsResult =
              try {
                await lp_canister.decreaseLiquidity({
                  positionId = position_id;
                  liquidity = Nat.toText(p.liquidity);
                })
              } catch e { #err(#InternalError(Error.message(e))) };
            switch (dec_res) {
              case (#ok(a)) { decreased0 := a.amount0; decreased1 := a.amount1 };
              case (#err(e)) { List.add(errors, "decreaseLiquidity failed: " # debug_show(e)) };
            };
          };
        };
        case (#err(e)) { List.add(errors, "getUserPosition failed: " # debug_show(e)) };
      };

      // 5. Read pool reserves and this canister's unused balance to cap the withdraws.
      let held : ?Pool.ICPSwapTokenBalance =
        try { ?(await lp_canister.getTokenBalance()) }
        catch e { List.add(errors, "getTokenBalance failed: " # Error.message(e)); null };
      let unused : Pool.ICPSwapUnusedBalanceResult =
        try { await lp_canister.getUserUnusedBalance(self) }
        catch e { #err(#InternalError(Error.message(e))) };
      let owed : ?Pool.ICPSwapUnusedBalance = switch (unused) {
        case (#ok(b)) { ?b };
        case (#err(e)) { List.add(errors, "getUserUnusedBalance failed: " # debug_show(e)); null };
      };

      // 6. Withdraw min(owed, held) for each token (best-effort, independent).
      var withdrawn0 : Nat = 0;
      var withdrawn1 : Nat = 0;
      switch (held, owed) {
        case (?h, ?b) {
          switch (fee0) {
            case (?f0) {
              let amt0 = Nat.min(b.balance0, h.token0);
              if (amt0 > f0) {
                let w0 : Pool.ICPSwapNatResult =
                  try { await lp_canister.withdraw({ token = token0; fee = f0; amount = amt0 }) }
                  catch e { #err(#InternalError(Error.message(e))) };
                switch (w0) {
                  case (#ok(n)) { withdrawn0 := n };
                  case (#err(e)) { List.add(errors, "withdraw(token0) failed: " # debug_show(e)) };
                };
              };
            };
            case null {};
          };
          switch (fee1) {
            case (?f1) {
              let amt1 = Nat.min(b.balance1, h.token1);
              if (amt1 > f1) {
                let w1 : Pool.ICPSwapNatResult =
                  try { await lp_canister.withdraw({ token = token1; fee = f1; amount = amt1 }) }
                  catch e { #err(#InternalError(Error.message(e))) };
                switch (w1) {
                  case (#ok(n)) { withdrawn1 := n };
                  case (#err(e)) { List.add(errors, "withdraw(token1) failed: " # debug_show(e)) };
                };
              };
            };
            case null {};
          };
        };
        case (_, _) {}; // reserves or unused balance unavailable; withdraws skipped, errors already recorded
      };

      let summary : T.EmergencyPullSummary = {
        token0 = token0;
        token1 = token1;
        claimed0 = claimed0;
        claimed1 = claimed1;
        liquidity_removed = liquidity_removed;
        decreased0 = decreased0;
        decreased1 = decreased1;
        withdrawn0 = withdrawn0;
        withdrawn1 = withdrawn1;
        errors = List.toArray(errors);
      };

      log_msg("emergency_pull_icpswap_lp completed: " # debug_show(summary));

      #ok(summary);

  };

  // ============================================================================
  // LP fee harvesting -> RLL routing
  //
  // On a timer, claim SNEED/ICP fees from enrolled ICPSwap positions this
  // canister owns and forward each token to its hardcoded Sneed RLL vector.
  // Funds can ONLY ever reach the two compile-time RLL destinations, so the
  // schedule/position controls are safe to expose to safety_admins: no caller
  // input can change where fees go, only which pools are harvested and how often.
  // ============================================================================

  // Build a HarvestSummary that carries only an error (used to reject a call
  // in-band without moving any funds). Moves nothing.
  private func err_summary(msg : Text) : T.HarvestSummary {
    {
      positions_seen = 0;
      positions_harvested = 0;
      claimed_icp = 0;
      claimed_sneed = 0;
      forwarded_icp = 0;
      forwarded_sneed = 0;
      harvest_balance_icp = 0;
      harvest_balance_sneed = 0;
      icp_forward_tx = null;
      sneed_forward_tx = null;
      errors = [msg];
    };
  };

  // Drain the harvest subaccount for one token to its RLL vector. Trap-free and
  // idempotent: reads the REAL subaccount balance every call, so a delayed job
  // overlapping the next cycle's forward can never double-spend (the later run
  // sees ~0). Forwards only when the balance clears `min_amount` and exceeds the
  // ledger fee. Returns (forwarded_net, tx, balance_seen).
  private func forward_token(
    ledger : T.ICRC1Ledger,
    dest : T.Account,
    fee : Nat,
    min_amount : Nat,
    label_ : Text,
    errors : List.List<Text>)
    : async (Nat, ?Nat, Nat) {

    let bal : ?Nat =
      try { ?(await ledger.icrc1_balance_of(harvest_account)) }
      catch e { List.add(errors, "balance_of(" # label_ # ") failed: " # Error.message(e)); null };

    switch (bal) {
      case (?b) {
        if (b < min_amount or b <= fee) { return (0, null, b) };
        let send_amount = b - fee : Nat;
        let res : T.TransferResult =
          try {
            await ledger.icrc1_transfer({
              from_subaccount = ?harvest_subaccount;
              to = dest;
              amount = send_amount;
              fee = ?fee;
              memo = null;
              created_at_time = null;
            })
          } catch e { #Err(#GenericError({ error_code = 1; message = Error.message(e) })) };
        switch (res) {
          case (#Ok(tx)) { (send_amount, ?tx, b) };
          case (#Err(e)) { List.add(errors, "forward(" # label_ # ") failed: " # debug_show(e)); (0, null, b) };
        };
      };
      case null { (0, null, 0) };
    };
  };

  // Delayed one-shot (scheduled at the end of do_harvest). After ICPSwap has had
  // `settle_delay_seconds` to process this cycle's claim auto-withdraws, drain the
  // harvest subaccount to the RLL vectors. Trap-free; no reentrancy guard needed
  // because forward_token reads the real balance (idempotent under overlap).
  private func forward_only_job() : async () {
    let errors = List.empty<Text>();
    let icp_ledger : T.ICRC1Ledger = actor (icp_ledger_id);
    let sneed_ledger : T.ICRC1Ledger = actor (sneed_ledger_id);

    var forwarded_icp : Nat = 0;
    var forwarded_sneed : Nat = 0;
    var icp_tx : ?Nat = null;
    var sneed_tx : ?Nat = null;

    let icp_fee : ?Nat =
      try { ?(await icp_ledger.icrc1_fee()) }
      catch e { List.add(errors, "icrc1_fee(ICP) failed: " # Error.message(e)); null };
    switch (icp_fee) {
      case (?f) {
        let (sent, tx, _bal) = await forward_token(icp_ledger, rll_icp_dest, f, claim_min_icp, "ICP", errors);
        forwarded_icp := sent; icp_tx := tx;
      };
      case null {};
    };

    let sneed_fee : ?Nat =
      try { ?(await sneed_ledger.icrc1_fee()) }
      catch e { List.add(errors, "icrc1_fee(SNEED) failed: " # Error.message(e)); null };
    switch (sneed_fee) {
      case (?f) {
        let (sent, tx, _bal) = await forward_token(sneed_ledger, rll_sneed_dest, f, claim_min_sneed, "SNEED", errors);
        forwarded_sneed := sent; sneed_tx := tx;
      };
      case null {};
    };

    log_msg("delayed forward completed: forwarded_icp=" # debug_show(forwarded_icp) #
      " forwarded_sneed=" # debug_show(forwarded_sneed) #
      " icp_tx=" # debug_show(icp_tx) # " sneed_tx=" # debug_show(sneed_tx) #
      " errors=" # debug_show(List.toArray(errors)));
  };

  // Core harvest logic. Best-effort and trap-free: one failing position or
  // ledger call never aborts the cycle; every failure is recorded in the
  // summary. No caller gate (internal): reached only via the safety-admin
  // public wrapper or the recurring timer.
  //
  // INVARIANT — do_harvest MUST remain trap-free. The transient `harvest_running`
  // guard is set at entry and cleared only at the single normal return point;
  // Motoko has no try/finally, so a trap here would leave the guard stuck `true`
  // and permanently wedge harvesting until the next upgrade. Keep every external
  // call wrapped in try/catch and every subtraction guarded.
  //
  // ICPSwap's claim AUTO-WITHDRAWS the claimed fees to the target subaccount and
  // settles OUT OF BAND (it enqueues the transfer and returns before the tokens
  // arrive), so claim and forward are decoupled across cycles via the harvest
  // subaccount balance:
  //   1. FORWARD whatever has already settled in the harvest subaccount to the
  //      RLL vectors (gated by the per-token minimums).
  //   2. CLAIM this cycle's fees into the harvest subaccount (claimToSubaccount).
  //   3. SCHEDULE a one-shot delayed forward so this cycle's proceeds are routed
  //      once ICPSwap has settled them.
  private func do_harvest() : async T.HarvestSummary {

    // Reentrancy guard: never overlap two cycles.
    if (harvest_running) {
      log_msg("do_harvest skipped: a harvest is already in progress");
      return err_summary("harvest already in progress; skipped");
    };
    harvest_running := true;

    let errors = List.empty<Text>();

    let icp_ledger : T.ICRC1Ledger = actor (icp_ledger_id);
    let sneed_ledger : T.ICRC1Ledger = actor (sneed_ledger_id);

    // Ledger fees (best-effort). A token whose fee is unreadable is not forwarded
    // this cycle; its subaccount balance carries to a later run.
    let icp_fee : ?Nat =
      try { ?(await icp_ledger.icrc1_fee()) }
      catch e { List.add(errors, "icrc1_fee(ICP) failed: " # Error.message(e)); null };
    let sneed_fee : ?Nat =
      try { ?(await sneed_ledger.icrc1_fee()) }
      catch e { List.add(errors, "icrc1_fee(SNEED) failed: " # Error.message(e)); null };

    // === 1. Forward phase: drain the harvest subaccount to the RLL vectors. ===
    // Consumes proceeds that have already settled (earlier cycles' / delayed
    // job's claims). Gated by the per-token minimums.
    var forwarded_icp : Nat = 0;
    var forwarded_sneed : Nat = 0;
    var icp_forward_tx : ?Nat = null;
    var sneed_forward_tx : ?Nat = null;
    var harvest_balance_icp : Nat = 0;
    var harvest_balance_sneed : Nat = 0;

    switch (icp_fee) {
      case (?f) {
        let (sent, tx, bal) =
          await forward_token(icp_ledger, rll_icp_dest, f, claim_min_icp, "ICP", errors);
        forwarded_icp := sent;
        icp_forward_tx := tx;
        harvest_balance_icp := bal;
      };
      case null {};
    };
    switch (sneed_fee) {
      case (?f) {
        let (sent, tx, bal) =
          await forward_token(sneed_ledger, rll_sneed_dest, f, claim_min_sneed, "SNEED", errors);
        forwarded_sneed := sent;
        sneed_forward_tx := tx;
        harvest_balance_sneed := bal;
      };
      case null {};
    };

    // === 2. Claim phase: claim each position's fees into the harvest subaccount. ===
    // ICPSwap's claim auto-withdraws the claimed amount to the given subaccount,
    // settling out of band; the delayed forward (scheduled below) routes it.
    var positions_seen : Nat = 0;
    var positions_harvested : Nat = 0;
    var claimed_icp : Nat = 0;
    var claimed_sneed : Nat = 0;

    label nextpos for (cp in claim_positions.vals()) {
      positions_seen += 1;

      // Defense in depth: only harvest approved pools. Enrollment already enforces
      // this, but claim_positions is stable state that can predate the allowlist.
      if (not is_approved_lp_pool(cp.pool)) {
        List.add(errors, "position " # debug_show(cp.position_id) # " on " #
          Principal.toText(cp.pool) # " is not an approved pool; skipped");
        continue nextpos;
      };

      let pool : Pool.ICPSwapPool = actor (Principal.toText(cp.pool));

      // Identify which side is ICP and which is SNEED by EXACT ledger match. Skip
      // anything that is not exactly a SNEED/ICP pool (never claim an unrecognised
      // pool's tokens into the harvest subaccount). Also used to map the claimed
      // amounts onto the ICP/SNEED sides for the summary.
      let meta : Pool.ICPSwapMetadataResult =
        try { await pool.metadata() }
        catch e { #err(#InternalError(Error.message(e))) };
      let icp_is_token0 = switch (meta) {
        case (#ok(m)) {
          if (m.token0.address == icp_ledger_id and m.token1.address == sneed_ledger_id) { true }
          else if (m.token0.address == sneed_ledger_id and m.token1.address == icp_ledger_id) { false }
          else {
            List.add(errors, "position " # debug_show(cp.position_id) # " on " #
              Principal.toText(cp.pool) # " is not a SNEED/ICP pool; skipped");
            continue nextpos;
          };
        };
        case (#err(e)) {
          List.add(errors, "metadata failed for " # Principal.toText(cp.pool) #
            " position " # debug_show(cp.position_id) # ": " # debug_show(e));
          continue nextpos;
        };
      };

      // Claim accrued fees to the harvest subaccount. ICPSwap auto-withdraws them
      // out of band; forwarded by the delayed job / next cycle.
      let claim_res : Pool.ICPSwapAmountsResult =
        try { await pool.claimToSubaccount({ positionId = cp.position_id; subaccount = harvest_subaccount }) }
        catch e { #err(#InternalError(Error.message(e))) };
      switch (claim_res) {
        case (#ok(a)) {
          positions_harvested += 1;
          let icp_amt   = if (icp_is_token0) { a.amount0 } else { a.amount1 };
          let sneed_amt = if (icp_is_token0) { a.amount1 } else { a.amount0 };
          claimed_icp += icp_amt;
          claimed_sneed += sneed_amt;
        };
        case (#err(e)) {
          List.add(errors, "claim failed for " # Principal.toText(cp.pool) #
            " position " # debug_show(cp.position_id) # ": " # debug_show(e));
        };
      };
    };

    // === 3. Schedule the delayed forward for this cycle's freshly-claimed fees. ===
    // One-shot; not persisted across upgrades (the next cycle's forward phase
    // catches any straggler).
    ignore Timer.setTimer<system>(#seconds settle_delay_seconds, forward_only_job);

    let summary : T.HarvestSummary = {
      positions_seen = positions_seen;
      positions_harvested = positions_harvested;
      claimed_icp = claimed_icp;
      claimed_sneed = claimed_sneed;
      forwarded_icp = forwarded_icp;
      forwarded_sneed = forwarded_sneed;
      harvest_balance_icp = harvest_balance_icp;
      harvest_balance_sneed = harvest_balance_sneed;
      icp_forward_tx = icp_forward_tx;
      sneed_forward_tx = sneed_forward_tx;
      errors = List.toArray(errors);
    };

    harvest_running := false;

    log_msg("do_harvest completed: " # debug_show(summary));
    summary;
  };

  // Recurring timer job. Runs the harvest and discards the summary (it is
  // logged inside do_harvest).
  private func harvest_timer_job() : async () {
    ignore await do_harvest();
  };

  // Run one harvest immediately. Safety-admin gated. Useful for a manual sweep
  // or to test the routing without touching the schedule.
  public shared ({ caller }) func claim_and_route_lp_fees() : async T.HarvestSummary {

    log_msg("claim_and_route_lp_fees called by " # Principal.toText(caller));

    if (not is_safety_admin(caller)) {
      let err_msg = "claim_and_route_lp_fees ERROR: Not authorized (Was called by " #
        Principal.toText(caller) # ")";
      log_msg(err_msg);
      return err_summary(err_msg);
    };

    await do_harvest();
  };

  // (Re)configure the recurring harvest. Safety-admin gated. Cancels any
  // existing timer, runs one harvest immediately, then arms a recurring timer
  // at the given cadence with the given per-token minimum thresholds.
  public shared ({ caller }) func set_lp_fee_claim_schedule(
    cadence_seconds : Nat,        // how often to harvest, in seconds (>= 60)
    min_icp : T.Balance,          // minimum accumulated ICP before it is forwarded
    min_sneed : T.Balance)        // minimum accumulated SNEED before it is forwarded
    : async T.HarvestSummary {

    log_msg("set_lp_fee_claim_schedule called by " # Principal.toText(caller) #
      " with arguments: cadence_seconds: " # debug_show(cadence_seconds) #
      ", min_icp: " # debug_show(min_icp) #
      ", min_sneed: " # debug_show(min_sneed));

    if (not is_safety_admin(caller)) {
      let err_msg = "set_lp_fee_claim_schedule ERROR: Not authorized (Was called by " #
        Principal.toText(caller) # ")";
      log_msg(err_msg);
      return err_summary(err_msg);
    };

    if (cadence_seconds < min_cadence_seconds) {
      let err_msg = "set_lp_fee_claim_schedule ERROR: cadence_seconds " # debug_show(cadence_seconds) #
        " is below the minimum of " # debug_show(min_cadence_seconds);
      log_msg(err_msg);
      return err_summary(err_msg);
    };

    // Stop any previously configured timer.
    switch (claim_timer_id) {
      case (?id) { Timer.cancelTimer(id); claim_timer_id := null };
      case null {};
    };

    // Record the new schedule/thresholds so the immediate run and the recurring
    // timer both use them.
    claim_cadence_seconds := cadence_seconds;
    claim_min_icp := min_icp;
    claim_min_sneed := min_sneed;
    claim_active := true;

    // Run one harvest now, then arm the recurring timer.
    let summary = await do_harvest();

    claim_timer_id := ?Timer.recurringTimer<system>(#seconds cadence_seconds, harvest_timer_job);

    log_msg("set_lp_fee_claim_schedule armed recurring harvest every " #
      debug_show(cadence_seconds) # "s");

    summary;
  };

  // Stop the recurring harvest. Safety-admin gated. Leaves the cadence,
  // thresholds and enrolled positions intact so it can be resumed later.
  public shared ({ caller }) func stop_lp_fee_claim_schedule() : async () {

    log_msg("stop_lp_fee_claim_schedule called by " # Principal.toText(caller));

    assert is_safety_admin(caller);

    switch (claim_timer_id) {
      case (?id) { Timer.cancelTimer(id); claim_timer_id := null };
      case null {};
    };
    claim_active := false;

    log_msg("stop_lp_fee_claim_schedule: recurring harvest stopped");
  };

  // Enroll a position in automatic fee harvesting. Safety-admin gated.
  // Idempotent: adding an already-enrolled (pool, position_id) is a no-op.
  public shared ({ caller }) func add_lp_fee_claim_position(
    pool : Principal,
    position_id : Nat)
    : async [T.ClaimPosition] {

    log_msg("add_lp_fee_claim_position called by " # Principal.toText(caller) #
      " with arguments: pool: " # Principal.toText(pool) #
      ", position_id: " # debug_show(position_id));

    assert is_safety_admin(caller);

    // Only approved pools may be enrolled (see approved_lp_pools). This is the
    // primary guard preventing a safety_admin from routing ok64's funds through
    // an attacker-controlled canister; do_harvest re-checks as defense in depth.
    assert is_approved_lp_pool(pool);

    let exists = Array.find<T.ClaimPosition>(claim_positions, func(p) {
      Principal.equal(p.pool, pool) and p.position_id == position_id
    }) != null;

    if (not exists) {
      claim_positions := Array.concat<T.ClaimPosition>(
        claim_positions, [{ pool = pool; position_id = position_id }]);
      log_msg("add_lp_fee_claim_position: enrolled " # Principal.toText(pool) #
        " position " # debug_show(position_id));
    };

    claim_positions;
  };

  // Remove a position from automatic fee harvesting. Safety-admin gated.
  // Removing a position that is not enrolled is a no-op.
  public shared ({ caller }) func remove_lp_fee_claim_position(
    pool : Principal,
    position_id : Nat)
    : async [T.ClaimPosition] {

    log_msg("remove_lp_fee_claim_position called by " # Principal.toText(caller) #
      " with arguments: pool: " # Principal.toText(pool) #
      ", position_id: " # debug_show(position_id));

    assert is_safety_admin(caller);

    claim_positions := Array.filter<T.ClaimPosition>(claim_positions, func(p) {
      not (Principal.equal(p.pool, pool) and p.position_id == position_id)
    });

    log_msg("remove_lp_fee_claim_position: removed " # Principal.toText(pool) #
      " position " # debug_show(position_id));

    claim_positions;
  };

  // The positions currently enrolled in automatic fee harvesting.
  public query func get_lp_fee_claim_positions() : async [T.ClaimPosition] {
    claim_positions;
  };

  // The current harvest schedule and enrolled positions.
  public query func get_lp_fee_claim_config() : async T.ClaimConfigView {
    {
      active = claim_active;
      cadence_seconds = claim_cadence_seconds;
      min_icp = claim_min_icp;
      min_sneed = claim_min_sneed;
      harvest_account = harvest_account;
      positions = claim_positions;
    };
  };

  // Transfer an ICPSwap LP position owned by this canister.
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  public shared ({ caller }) func transfer_icpex_lp_position(
    lp_canister_id : Principal,             // the Principal id of the canister of the ICPSwap LP to transfer.
    to_principal : Principal)               // the Principal id to transfer the LP to. 
    : async T.TransferICPexLPResult {

      log_msg("transfer_icpex_lp_position called by " # 
        Principal.toText(caller) # 
        " with arguments: " #
        "lp_canister_id: " # Principal.toText(lp_canister_id) # 
        ", to_principal: " # Principal.toText(to_principal));

      try {

        // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
        
        if (Principal.toText(caller) == sneed_governance_id) {

          let icpex_proxy_id = Principal.fromText("2ackz-dyaaa-aaaam-ab5eq-cai");

          let lp_canister = actor (Principal.toText(icpex_proxy_id)) : actor {
            transferLiquidity(pool_addr: Principal, to: Principal, transfer_percent: Nat) : async T.TransferICPexLPResult;
          };  

          let transfer_percent : Nat = 100_0000_0000_0000_0000; // 100%, using 18 decimals of precision

          log_msg("transfer_icpex_lp_position, calling transferLiquidity of " # 
            Principal.toText(icpex_proxy_id) # 
            " with arguments: " #
            "pool_addr: " # Principal.toText(lp_canister_id) # 
            ", to: " # Principal.toText(to_principal) #  
            ", transfer_percent: " # debug_show(transfer_percent));

          let result = await lp_canister.transferLiquidity(lp_canister_id, to_principal, transfer_percent);

          log_msg("transfer_icpex_lp_position, called transferLiquidity of " # 
            Principal.toText(icpex_proxy_id) # 
            " with result: " # debug_show(result));

          result;

        } else {

          let err_msg = "transfer_icpex_lp_position ERROR: May only be called by " # 
            sneed_governance_id # " (Was called by " # Principal.toText(caller) # ")";

          log_msg(err_msg);

          return #Err(err_msg);

        };

      } catch e {
      
        let err_msg = "transfer_icpex_lp_position ERROR: " # Error.message(e);

        log_msg(err_msg);

        return #Err(err_msg);

      };

  };

  // SNS generic function validation method for transfer_icpswap_lp_position 
  public query ({ caller }) func validate_transfer_icpex_lp_position(
    lp_canister_id : Principal,
    to_principal : Principal) : async T.ValidationResult {

      let msg:Text = "lp_canister_id: " # Principal.toText(lp_canister_id) # 
      ", to_principal: " # Principal.toText(to_principal);

      log_msg("validate_transfer_icpex_lp_position called by " # 
        Principal.toText(caller) # " with arguments: " # msg);
      
      #Ok(msg);

  };

  // Add one or more controllers to a canister that this (Sneed DeFi) canister is itself a
  // controller of. This is ADDITIVE: it reads the canister's current controller set via the IC
  // management canister's canister_status, then appends any supplied controllers that are not
  // already present, leaving all existing controllers in place. It never removes controllers.
  //
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  // The caller gate below is load-bearing: it guarantees that any controller change is made only
  // through a visible, votable governance proposal (rendered for voters by the paired
  // validate_add_canister_controllers query). A call originating from this canister's own
  // system functions (e.g. postupgrade) runs with this canister as the caller, NOT the governance
  // canister, so it will trap here by design.
  public shared ({ caller }) func add_canister_controllers(
    canister_id : Principal,          // the canister whose controller set should be added to.
    controllers_to_add : [Principal]) // the controllers to append to the existing set.
    : async () {

      log_msg("add_canister_controllers called by " #
        Principal.toText(caller) #
        " with arguments: " #
        "canister_id: " # Principal.toText(canister_id) #
        ", controllers_to_add: " # debug_show(controllers_to_add));

      // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
      assert (Principal.toText(caller) == sneed_governance_id);

      let ic : actor {
        canister_status : ({ canister_id : Principal }) -> async {
          settings : { controllers : [Principal] };
        };
        update_settings : ({
          canister_id : Principal;
          settings : {
            controllers : ?[Principal];
            compute_allocation : ?Nat;
            memory_allocation : ?Nat;
            freezing_threshold : ?Nat;
          };
        }) -> async ();
      } = actor ("aaaaa-aa");

      // Read the existing controller set so we ADD to it rather than replace it.
      let status = await ic.canister_status({ canister_id = canister_id });
      let merged = List.fromArray<Principal>(status.settings.controllers);

      // Append each requested controller that is not already present.
      for (c in controllers_to_add.vals()) {
        if (not List.contains<Principal>(merged, Principal.equal, c)) {
          List.add(merged, c);
        };
      };

      let new_controllers = List.toArray(merged);

      await ic.update_settings({
        canister_id = canister_id;
        settings = {
          controllers = ?new_controllers;
          compute_allocation = null;
          memory_allocation = null;
          freezing_threshold = null;
        };
      });

      log_msg("add_canister_controllers, controllers of " #
        Principal.toText(canister_id) # " are now " # debug_show(new_controllers));

  };

  // SNS generic function validation method for add_canister_controllers.
  // Renders the action in plain language inside the governance proposal so voters can see
  // exactly which canister is affected and which controllers are being added, before approving.
  public query ({ caller }) func validate_add_canister_controllers(
    canister_id : Principal,
    controllers_to_add : [Principal]) : async T.ValidationResult {

      let msg : Text = "canister_id: " # Principal.toText(canister_id) #
        ", controllers_to_add: " # debug_show(controllers_to_add);

      log_msg("validate_add_canister_controllers called by " #
        Principal.toText(caller) # " with arguments: " # msg);

      #Ok(msg);

  };

  // Clear log
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  public shared ({ caller }) func clear_log() : async () {
    
    // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
    assert Principal.toText(caller) == sneed_governance_id;

    List.clear(log);
    
  };

  // Returns the number of items in the log.
  public query func get_log_size() : async Nat { List.size(log); };

  // Returns a given set of entries from the log, given a start item index and a length. 
  // Maximum number of items (length) is 100.  
  public query func get_log_entries(start : Nat, length : Nat) : async [Text] {
    
    let max_len = 100;
    let size = List.size(log);

    if (size < 1) { return []; };

    var chk_start = start;
    var chk_len = if (length > max_len) { max_len } else { length };

    if (chk_start + chk_len >= size) {
      if (chk_start >= size) {
        chk_start := size - 1;
        chk_len := 1;
      } else {
        chk_len := size - chk_start;
        chk_len := if (chk_len > max_len) { max_len } else { chk_len };
      };
    };

    List.sliceToArray(log, chk_start, chk_start + chk_len);

  };

  // Add a message to the log
  private func log_msg(msg : Text) {
    let time = Nat64.toText(Nat64.fromNat(Int.abs(Time.now()))); 
    List.add(log, time # ": " # msg);
  };

 
  // System Function //
  // Runs before the canister is upgraded
  system func preupgrade() {

    // Move transient state into persistent state before upgrading the canister,
    // stashing it away so it survives the canister upgrade.
    stable_log := List.toArray(log);

  };

  // System Function //
  // Runs after the canister is upgraded
  system func postupgrade() {

    // Clear persistent state (stashed away transient state) after upgrading the canister
    stable_log := [];

    // Timers do not survive upgrades. If a recurring harvest was scheduled,
    // re-arm it from the persisted cadence. No immediate harvest here, to avoid
    // surprise transfers during a deploy — the first fire is one cadence later.
    if (claim_active and claim_cadence_seconds >= min_cadence_seconds) {
      claim_timer_id := ?Timer.recurringTimer<system>(#seconds claim_cadence_seconds, harvest_timer_job);
    };

  };

};
