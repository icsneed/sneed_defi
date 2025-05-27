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
}