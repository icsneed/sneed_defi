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

// Minimal ICRC1 ledger interface: read the fee, snapshot a balance, and
// forward a transfer. Used by the LP fee harvester to route claimed fees.
type ICRC1Ledger = actor {
    icrc1_fee : () -> async Balance;
    icrc1_balance_of : (Account) -> async Balance;
    icrc1_transfer : (TransferArgs) -> async TransferResult;
};

// A liquidity position enrolled in automatic fee harvesting, identified by
// its pool (swap canister) and the ICPSwap position id within that pool.
type ClaimPosition = {
    pool : Principal;
    position_id : Nat;
};

// Result of one harvest cycle. Logged and returned so operators can see
// exactly what moved. `errors` lists per-step failures; empty when clean.
//
// ICPSwap's claim auto-withdraws fees to the harvest subaccount out of band, so
// a cycle FORWARDS whatever has already settled in that subaccount, then CLAIMS
// new fees (forwarded by the delayed job / next cycle). The harvest-subaccount
// balance is the source of truth; there is no in-canister forward queue.
type HarvestSummary = {
    positions_seen : Nat;         // enrolled positions considered this cycle
    positions_harvested : Nat;    // positions where claimToSubaccount succeeded
    claimed_icp : Nat;            // ICP claimed this cycle (settles async, forwarded later)
    claimed_sneed : Nat;          // SNEED claimed this cycle (settles async, forwarded later)
    forwarded_icp : Nat;          // ICP sent to the ICP vector this cycle (net of fee)
    forwarded_sneed : Nat;        // SNEED sent to the SNEED vector this cycle (net of fee)
    harvest_balance_icp : Nat;    // ICP seen in the harvest subaccount during the forward phase
    harvest_balance_sneed : Nat;  // SNEED seen in the harvest subaccount during the forward phase
    icp_forward_tx : ?TxIndex;    // ledger tx index of the ICP forward, if it happened
    sneed_forward_tx : ?TxIndex;  // ledger tx index of the SNEED forward, if it happened
    errors : [Text];
};

// Read-only view of the current harvest schedule, harvest account and positions.
// `harvest_account` is exposed so operators can read its live ICP/SNEED balance
// directly on the ledgers (a query cannot make inter-canister balance calls).
type ClaimConfigView = {
    active : Bool;
    cadence_seconds : Nat;
    min_icp : Balance;
    min_sneed : Balance;
    harvest_account : Account;
    positions : [ClaimPosition];
};

