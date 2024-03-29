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
