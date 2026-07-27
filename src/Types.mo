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

// One ledger's share of a harvest cycle. Used for the per-ledger claimed tally.
type TokenAmount = {
    ledger : Principal;
    amount : Balance;
};

// Outcome of one forward attempt: what the harvest subaccount held for this
// ledger, and how much (net of the ledger fee) actually moved to `dest`.
type ForwardResult = {
    ledger       : Principal;
    dest         : Account;
    balance_seen : Balance;
    forwarded    : Balance;   // 0 when the balance was below the forward gate
    tx           : ?TxIndex;
};

// A pool's token pair, captured once at enrollment so the harvest loop never
// needs to call the pool's metadata(). Kept in its own stable var rather than
// as fields on ClaimPosition: extending an existing stable record's shape fails
// `moc --stable-compatible` (M0170) and the upgrade would be rejected.
type PoolTokens = {
    pool   : Principal;
    token0 : Principal;
    token1 : Principal;
};

// Result of one harvest cycle. Logged and returned so operators can see exactly
// what was claimed. `errors` lists per-step failures; empty when clean.
//
// A cycle only CLAIMS: ICPSwap's claim auto-withdraws fees to the harvest
// subaccount out of band, so do_harvest schedules a delayed forward_only_job to
// route the proceeds once they settle. Forward outcomes are therefore reported
// by that job as [ForwardResult] in the log, not here.
type HarvestSummary = {
    positions_seen      : Nat;           // enrolled positions considered this cycle
    positions_harvested : Nat;           // positions where claimToSubaccount succeeded
    claimed             : [TokenAmount]; // per-ledger claimed this cycle (settles async)
    errors              : [Text];
};

// Read-only view of the current harvest schedule, harvest account, registry and
// positions. `harvest_account` is exposed so operators can read its live balances
// directly on the ledgers (a query cannot make inter-canister balance calls).
type ClaimConfigView = {
    active           : Bool;
    cadence_seconds  : Nat;
    min_icp          : Balance;
    min_sneed        : Balance;
    min_fee_multiple : Nat;          // forward gate for tokens other than ICP/SNEED
    harvest_account  : Account;
    tokens           : [Principal];  // ledgers the forward phase sweeps
    pool_tokens      : [PoolTokens]; // pool -> token pair, captured at enrollment
    positions        : [ClaimPosition];
};

