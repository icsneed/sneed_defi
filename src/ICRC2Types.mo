module {
  public type Account = {
        owner : Principal;
        subaccount : ?Subaccount;
  };

  public type Subaccount = Blob;

  public type ApproveArgs = {
      from_subaccount : ?Blob;
      spender : Account;
      amount : Nat;
      expected_allowance : ?Nat;
      expires_at : ?Nat64;
      fee : ?Nat;
      memo : ?Blob;
      created_at_time : ?Nat64;
  };

  public type ApproveError = {
      #BadFee :  { expected_fee : Nat };
      // The caller does not have enough funds to pay the approval fee.
      #InsufficientFunds :  { balance : Nat };
      // The caller specified the [expected_allowance] field, and the current
      // allowance did not match the given value.
      #AllowanceChanged :  { current_allowance : Nat };
      // The approval request expired before the ledger had a chance to apply it.
      #Expired :  { ledger_time : Nat64; };
      #TooOld;
      #CreatedInFuture:  { ledger_time : Nat64 };
      #Duplicate :  { duplicate_of : Nat };
      #TemporarilyUnavailable;
      #GenericError :  { error_code : Nat; message : Text };
  };

  public type TransferFromError =  {
      #BadFee :  { expected_fee : Nat };
      #BadBurn :  { min_burn_amount : Nat };
      // The [from] account does not hold enough funds for the transfer.
      #InsufficientFunds :  { balance : Nat };
      // The caller exceeded its allowance.
      #InsufficientAllowance :  { allowance : Nat };
      #TooOld;
      #CreatedInFuture:  { ledger_time : Nat64 };
      #Duplicate :  { duplicate_of : Nat };
      #TemporarilyUnavailable;
      #GenericError :  { error_code : Nat; message : Text };
  };

  public type TransferFromArgs =  {
      spender_subaccount : ?Blob;
      from : Account;
      to : Account;
      amount : Nat;
      fee : ?Nat;
      memo : ?Blob;
      created_at_time : ?Nat64;
  };

  public type AllowanceArgs =  {
      account : Account;
      spender : Account;
  };

  public type Allowance =  {
    allowance : Nat;
    expires_at : ?Nat64;
  };


  public type service = actor {
    icrc2_approve : (ApproveArgs) -> async ({ #Ok : Nat; #Err : ApproveError });
    icrc2_transfer_from : (TransferFromArgs) -> async  { #Ok : Nat; #Err : TransferFromError };
    icrc2_allowance : query (AllowanceArgs) -> async (Allowance);
  };
};
