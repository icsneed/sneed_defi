import List "mo:core/List";

type Timestamp = Nat64;
type Subaccount = Blob;
type TxIndex = Nat;
type Balance = Nat;

type Log = List.List<Text>;

type Account = {
    owner : Principal;
    subaccount : ?Subaccount;
};

type TimeError = {
    #TooOld;
    #CreatedInFuture : { ledger_time : Timestamp };
};

type TransferError = TimeError or {
    #BadFee : { expected_fee : Balance };
    #BadBurn : { min_burn_amount : Balance };
    #InsufficientFunds : { balance : Balance };
    #Duplicate : { duplicate_of : TxIndex };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
};

type TransferResult = {
    #Ok : TxIndex;
    #Err : TransferError;
};

type TransferArgs = {
    from_subaccount : ?Subaccount;
    to : Account;
    amount : Balance;
    fee : ?Balance;
    memo : ?Blob;
    created_at_time : ?Nat64;
};

type ValidationResult = {
    #Ok: Text;
    #Err :Text;
};

type TransferICPSwapLPResult = {
    #ok: Bool;
    #err: TransferICPSwapLPError;
};

type TransferICPSwapLPError = {
    #CommonError;
    #InternalError: Text;
    #UnsupportedToken: Text;
    #InsufficientFunds;
};

type TransferICPexLPResult = {
    #Ok;
    #Err :Text;
};

type EmergencyPullSummary = {
    token0 : Text;
    token1 : Text;
    claimed0 : Nat;
    claimed1 : Nat;
    liquidity_removed : Nat;
    decreased0 : Nat;
    decreased1 : Nat;
    withdrawn0 : Nat;
    withdrawn1 : Nat;
    errors : [Text];
};

type EmergencyPullResult = {
    #ok : EmergencyPullSummary;
    #err : Text;
};

