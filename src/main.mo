import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Debug "mo:base/Debug";

import T "Types";

actor {

  // Log messages (stable)
  stable var stable_log : [Text] = [];

  // Log messages  
  var log : T.Log = Buffer.fromArray<Text>(stable_log);

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
        let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";

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
        let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";

        if (Principal.toText(caller) == sneed_governance_id) {

          let sneed_defi_id = "ok64y-uiaaa-aaaag-qdcbq-cai";

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
        let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
        
        if (Principal.toText(caller) == sneed_governance_id) {

          let from = Principal.fromText("ok64y-uiaaa-aaaag-qdcbq-cai"); // this canister

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
        let sneed_governance_id = "fi3zi-fyaaa-aaaaq-aachq-cai";
        
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

  // Clear log
  // This method may only be called by the Sneed DAO Governance Canister, via approved DAO proposal.
  public shared ({ caller }) func clear_log() : async () { 
    
    // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
    assert Principal.toText(caller) == "fi3zi-fyaaa-aaaaq-aachq-cai";

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

  // System Function //
  // Runs after the canister is upgraded
  system func postupgrade() {

    // Clear persistent state (stashed away transient state) after upgrading the canister
    stable_log := [];

  };

};
