module {
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