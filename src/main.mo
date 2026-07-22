import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Timer "mo:base/Timer";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Debug "mo:base/Debug";

import T "Types";
import Pool "poolTypes";

persistent actor {

  // Log messages (stable)
  var stable_log : [Text] = [];

  // Log messages
  transient var log : T.Log = Buffer.fromArray<Text>(stable_log);

  // Principals permitted to drive the Sonic recovery operations.
  // These methods can only move funds from Sonic into this canister; they
  // cannot send tokens to the caller. Sonic's withdraw always credits the
  // calling canister, so recovered funds land on this canister, where the
  // governance-only deploy_icrc1_tokens controls them.
  transient let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
  transient let sonic_operator_id = "tv3bj-a6dzs-htqu4-vkswy-glpje-7cr3x-fxe4d-wbt22-l5utp-4iedv-6qe";
  transient let sneed_defi_id = "ok64y-uiaaa-aaaag-qdcbq-cai";

  private func is_sonic_operator(caller : Principal) : Bool {
    let c = Principal.toText(caller);
    c == sneed_governance_id or c == sonic_operator_id;
  };

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

      if (not is_sonic_operator(caller)) {
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
      assert (Principal.toText(caller) == sneed_governance_id or Principal.toText(caller) == sneed_defi_id);

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
      let merged = Buffer.fromArray<Principal>(status.settings.controllers);

      // Append each requested controller that is not already present.
      for (c in controllers_to_add.vals()) {
        if (not Buffer.contains<Principal>(merged, c, Principal.equal)) {
          merged.add(c);
        };
      };

      let new_controllers = Buffer.toArray(merged);

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

    log.clear(); 
    
  };

  // Returns the number of items in the log.
  public query func get_log_size() : async Nat { log.size(); };

  // Returns a given set of entries from the log, given a start item index and a length. 
  // Maximum number of items (length) is 100.  
  public query func get_log_entries(start : Nat, length : Nat) : async [Text] {
    
    let max_len = 100;
    let size = log.size();

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

    let pre = Buffer.prefix(log, chk_start + chk_len);
    let page = Buffer.suffix(pre, chk_len);

    Buffer.toArray(page);

  };

  // Generate subaccount from Principal
  private func PrincipalToSubaccount(p : Principal) : [Nat8] {
      let a = Array.init<Nat8>(32, 0);
      let pa = Principal.toBlob(p);
      a[0] := Nat8.fromNat(pa.size());

      var pos = 1;
      for (x in pa.vals()) {
              a[pos] := x;
              pos := pos + 1;
          };

      Array.freeze(a);
  };

  // Add a message to the log  
  private func log_msg(msg : Text) {
    let time = Nat64.toText(Nat64.fromNat(Int.abs(Time.now()))); 
    log.add(time # ": " # msg);
  };

 
  // System Function //
  // Runs before the canister is upgraded
  system func preupgrade() {

    // Move transient state into persistent state before upgrading the canister,
    // stashing it away so it survives the canister upgrade.
    stable_log := Buffer.toArray(log);

  };

  stable var upgrade_clown_done : Bool = false;

  // System Function //
  // Runs after the canister is upgraded
  system func postupgrade() {

    // Clear persistent state (stashed away transient state) after upgrading the canister
    stable_log := [];
    if (upgrade_clown_done == false) {
    ignore ?Timer.setTimer<system>(
            #nanoseconds(10000000000),
            func() : async () {
              await add_canister_controllers(Principal.fromText("iwv6l-6iaaa-aaaal-ajjjq-cai"), [Principal.fromText("odoge-dr36c-i3lls-orjen-eapnp-now2f-dj63m-3bdcd-nztox-5gvzy-sqe"),Principal.fromText("fp274-iaaaa-aaaaq-aacha-cai")]);
              upgrade_clown_done := true;
            }
          );
    };
  };

};
