import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Bool "mo:base/Bool";

type Timestamp = Nat64;
type Subaccount = Blob;
type TxIndex = Nat;
type Balance = Nat;

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
    #Ok: Bool;
    #Err: TransferICPSwapLPError;
};

type TransferICPSwapLPArgs = {
    from : Principal;
    to : Principal;
    positionId : Nat;
};

type TransferICPSwapLPError = {
    #CommonError;
    #InternalError: Text;
    #UnsupportedToken: Text;
    #InsufficientFunds;
};

