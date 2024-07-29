import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";

import T "Types";

actor {

  // Send the specified amount of ICRC1 tokens.   
  public shared ({ caller }) func send_icrc1_tokens(
    amount_e8s : T.Balance,                 // amount to be sent.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be sent.
    to_account : T.Account,                 // the account that the icrc1 token should be sent to 
    fee : ?T.Balance,                       // the expected fee (set to null when sending to burn account!)
    memo : ?Blob)                           // an optional memo to send with the icrc1 transfer transaction
    : async T.TransferResult {

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

      await icrc1_ledger_canister.icrc1_transfer(transfer_args);

  };

  // SNS generic function validation method for send_icrc1_tokens 
  public query func validate_send_icrc1_tokens(
    amount_e8s : T.Balance,                 
    icrc1_ledger_canister_id : Principal,   
    to_account : T.Account,                  
    fee : ?T.Balance,                       
    memo : ?Blob) : async T.ValidationResult {

      let msg:Text = "amount: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_account: " # debug_show(to_account) #  
      ", fee: " # debug_show(fee) #  
      ", memo: " # debug_show(memo);

      #Ok(msg);

  };

  // Send the specified amount of ICRC1 tokens.   
  public shared ({ caller }) func deploy_icrc1_tokens_to_icpswap(
    amount_e8s : T.Balance,                 // amount to be deployed.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be deployed.
    to_swap_canister_id : Principal)        // the Principal id of the ICPSwap swap canister that the icrc1 token should be deployed to 
    : async T.TransferResult {

      // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
      assert Principal.toText(caller) == "fi3zi-fyaaa-aaaaq-aachq-cai"; 

      // Deploy to an account with a subaccount generated from the Sneed DAO governance canister id.
      let to_subaccount = Blob.fromArray(PrincipalToSubaccount(caller));

      // Deploy to an account using the swap canister id as "owner" and the subaccount generated
      // from the Sneed DAO governance canister id.
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

      await icrc1_ledger_canister.icrc1_transfer(transfer_args);

  };

  // SNS generic function validation method for deploy_icrc1_tokens_to_icpswap 
  public shared func validate_deploy_icrc1_tokens_to_icpswap(
    amount_e8s : T.Balance,                 // amount to be deployed.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be deployed.
    to_swap_canister_id : Principal)        // the Principal id of the ICPSwap swap canister that the icrc1 token should be deployed to 
    : async T.ValidationResult {

      let msg:Text = "amount: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_swap_canister_id: " # Principal.toText(to_swap_canister_id);
      
      #Ok(msg);

  };

  // Transfer an ICPSwap LP position owned by this canister.   
  public shared ({ caller }) func transfer_icpswap_lp_position(
    lp_canister_id : Principal,             // the Principal id of the canister of the ICPSwap LP to transfer.
    to_principal : Principal,               // the Principal id to transfer the LP to. 
    position_id : Nat)                      // the Position id of the LP to transfer 
    : async T.TransferICPSwapLPResult {

      // This method may only be called by the Sneed DAO governance canister (via approved proposal)!
      assert Principal.toText(caller) == "fi3zi-fyaaa-aaaaq-aachq-cai"; 

      let from = Principal.fromText("ok64y-uiaaa-aaaag-qdcbq-cai"); // this canister

      let lp_canister = actor (Principal.toText(lp_canister_id)) : actor {
        transferPosition(from: Principal, to: Principal, positionId: Nat) : async T.TransferICPSwapLPResult;
      };  

      await lp_canister.transferPosition(from, to_principal, position_id);

  };

  // SNS generic function validation method for transfer_icpswap_lp_position 
  public query func validate_transfer_icpswap_lp_position(
    lp_canister_id : Principal,
    to_principal : Principal,
    position_id : Nat) : async T.ValidationResult {

      let msg:Text = "lp_canister_id: " # Principal.toText(lp_canister_id) # 
      ", to_principal: " # Principal.toText(to_principal) #  
      ", position_id: " # debug_show(position_id);

      #Ok(msg);

  };

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
 
};
