module {
    public type SonicClaimArgs = ClaimArgs;
    public type SonicDecreaseLiquidityArgs = DecreaseLiquidityArgs;
    public type SonicWithdrawArgs = WithdrawArgs;
    
    public type ICPSwapClaimArgs = ClaimArgs;
    public type ICPSwapWithdrawArgs = WithdrawArgs;

    public type ClaimArgs = {
        positionId: Nat;
    };

    public type DecreaseLiquidityArgs = {
        liquidity: Text;
        positionId: Nat;
    };

    public type WithdrawArgs = {
        fee: Nat;
        token: Text;
        amount: Nat;
    };

    // Sonic swap pool interface (ni6i4-cqaaa-aaaak-qtsbq-cai).
    // Tags must match Sonic's candid exactly: lowercase ok / err.

    public type SonicError = {
        #CommonError;
        #InsufficientFunds;
        #InternalError : Text;
        #UnsupportedToken : Text;
    };

    public type SonicAmounts = {
        amount0 : Nat;
        amount1 : Nat;
    };

    public type SonicAmountsResult = {
        #ok : SonicAmounts;
        #err : SonicError;
    };

    public type SonicNatResult = {
        #ok : Nat;
        #err : SonicError;
    };

    public type SonicUnusedBalance = {
        balance0 : Nat;
        balance1 : Nat;
    };

    public type SonicUnusedBalanceResult = {
        #ok : SonicUnusedBalance;
        #err : SonicError;
    };

    public type SonicTokenBalance = {
        token0 : Nat;
        token1 : Nat;
    };

    public type SonicToken = {
        address : Text;
        standard : Text;
    };

    // Subset of Sonic's PoolMetadata. Candid lets a receiver ignore the
    // remaining fields, so only the token addresses are declared here.
    public type SonicPoolMetadata = {
        token0 : SonicToken;
        token1 : SonicToken;
    };

    public type SonicMetadataResult = {
        #ok : SonicPoolMetadata;
        #err : SonicError;
    };

    public type SonicPool = actor {
        claim : (args : ClaimArgs) -> async SonicAmountsResult;
        decreaseLiquidity : (args : DecreaseLiquidityArgs) -> async SonicAmountsResult;
        withdraw : (args : WithdrawArgs) -> async SonicNatResult;
        getUserUnusedBalance : (account : Principal) -> async SonicUnusedBalanceResult;
        getTokenBalance : () -> async SonicTokenBalance;
        metadata : () -> async SonicMetadataResult;
    };
}