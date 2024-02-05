import Principal "mo:base/Principal";

import T "Types";

actor {

  // The Sneed SNS governance canister principal
  let sneed_governance_canister_id = Principal.fromText("fi3zi-fyaaa-aaaaq-aachq-cai");

  // The "Sneed DAO" token SNS ledger canister. 
  let sneed_ledger_canister = actor ("hvgxa-wqaaa-aaaaq-aacia-cai") : actor {
    icrc1_transfer(args : T.TransferArgs) : async T.TransferResult;
  };  

  // Burn the specified amount of SNS "Sneed DAO" tokens. 
  // The amount specified must be equal to or smaller than the available 
  // amount of "Sneed DAO" tokens that have been sent to this canister. 
  public shared ({ caller }) func burn_sneed_tokens(amount_e8s : T.Balance) : async T.TransferResult {

      // This function may only be called via a DAO proposal to call this generic function.
      assert caller == sneed_governance_canister_id;

      // The burn account that we will send to (which is the Sneed SNS governance canister)
      let account : T.Account = {
        owner = sneed_governance_canister_id;
        subaccount = null;
      };

      // Create the arguments for the transaction request.
      // A burn is constructed as a transfer request to the 
      // minting/burn account (the SNS goverance canister)
      // and should NOT include any expected fee in the "fee"
      // field (since burns do not use up any fee). 
      let transfer_args : T.TransferArgs = {
        from_subaccount = null;
        to = account;
        amount = amount_e8s;
        fee = null;
        memo = null;

        created_at_time = null;
      };

      // burn the token by transferring it to the sns minting/burning account (the sns governance canister)
      await sneed_ledger_canister.icrc1_transfer(transfer_args);

  };

};
