  module {
    
    public type Account = {
        owner : Principal;
        subaccount : ?Subaccount;
    };

  public type Subaccount = Blob;

  public type SupportedStandard = {
      name : Text;
      url : Text;
  };

  public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text; #Array : [Value]; #Map: [(Text, Value)] };

  public type Balance = Nat;


  public type Timestamp = Nat64;

  public type TimeError = {
      #TooOld;
      #CreatedInFuture : { ledger_time : Timestamp };
  };

  public type TxIndex = Nat;

  public type TransferError = TimeError or {
        #BadFee : { expected_fee : Balance };
        #BadBurn : { min_burn_amount : Balance };
        #InsufficientFunds : { balance : Balance };
        #Duplicate : { duplicate_of : TxIndex };
        #TemporarilyUnavailable;
        #GenericError : { error_code : Nat; message : Text };
    };
    
    public type TransferResult = {
        #Ok : TxIndex;
        #Err : TransferError;
    };

  public type TransferArgs = {
        from_subaccount : ?Subaccount;
        to : Account;
        amount : Balance;
        fee : ?Balance;
        memo : ?Blob;

        /// The time at which the transaction was created.
        /// If this is set, the canister will check for duplicate transactions and reject them.
        created_at_time : ?Nat64;
    };


  public type service = actor {
    icrc1_balance_of : shared query Account -> async Nat;
    icrc1_decimals : shared query () -> async Nat8;
    icrc1_fee : shared query () -> async Nat;
    icrc1_metadata : shared query () -> async [(Text, Value)];
    icrc1_minting_account : shared query () -> async ?Account;
    icrc1_name : shared query () -> async Text;
    icrc1_supported_standards : shared query () -> async [SupportedStandard];
    icrc1_symbol : shared query () -> async Text;
    icrc1_total_supply : shared query () -> async Nat;
    icrc1_transfer : shared TransferArgs -> async TransferResult;
  };
};
