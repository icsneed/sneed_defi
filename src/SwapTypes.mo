import Nat "mo:base/Nat";
module {

public type ClaimArgs = { 
  positionId : Nat;
};

public type UserPositionInfo = {
  tickUpper : Int;
  tokensOwed0 : Nat;
  tokensOwed1 : Nat;
  feeGrowthInside1LastX128 : Nat;
  liquidity : Nat;
  feeGrowthInside0LastX128 : Nat;
  tickLower : Int;
};

public type WithdrawArgs = { 
  fee : Nat; 
  token : Text; 
  amount : Nat 
};

public type WithdrawResult = { 
  #ok : Nat; 
  #err : Error 
};

public type GetUserPositionIdsByPrincipalResult = { 
  #ok : [Nat]; 
  #err : Error 
};

public type GetUserPositionResult = { 
  #ok : UserPositionInfo; 
  #err : Error 
};

public type ClaimResult = {
  #ok : { 
    amount0 : Nat; 
    amount1 : Nat 
  };
  #err : Error;
};

public type Token = { 
  address : Text; 
  standard : Text 
};

public type GetPoolArgs = { 
  fee : Nat; 
  token0 : Token; 
  token1 : Token 
};

public type PoolData = {
  fee : Nat;
  key : Text;
  tickSpacing : Int;
  token0 : Token;
  token1 : Token;
  canisterId : Principal;
};

public type Error = {
  #CommonError;
  #InternalError : Text;
  #UnsupportedToken : Text;
  #InsufficientFunds;
};

type GetPoolsResult = { 
  #ok : [PoolData]; 
  #err : Error 
};

public type GetPoolResult = { 
  #ok : PoolData; 
  #err : Error 
};

public type PoolService = actor {
  getPool : shared query (GetPoolArgs) -> async (GetPoolResult);
  getPools : shared query () -> async (GetPoolsResult) ;
};

//speculative
public type RemoveResult = {
  #ok: {
     amount0 : Nat; 
    amount1 : Nat;
  };
  #err: Text;
};

type DepositArgs = { fee : Nat; token : Text; amount : Nat };


type MintArgs = 
  {
   amount0Desired: Text;
   amount1Desired: Text;
   fee: Nat;
   tickLower: Int;
   tickUpper: Int;
   token0: Text;
   token1: Text;
 };

type Result =  { #ok : Nat; #err : Error };


type MetadataResult = 
  {
   #err: Error;
   #ok: PoolMetadata;
 };

type UnusedBalanceResult = {
  #ok :  { balance0 : Nat; balance1 : Nat };
  #err : Error;
};

type SwapArgs =  {
  amountIn : Text;
  zeroForOne : Bool;
  amountOutMinimum : Text;
};

type DecreaseLiquidityArgs = { liquidity : Text; positionId : Nat };

type DecreaseLiquidityResult =  {
  #ok : { amount0 : Nat; amount1 : Nat };
  #err : Error;
};

type PoolMetadata =  
  {
   fee: Nat;
   key: Text;
   liquidity: Nat;
   maxLiquidityPerTick: Nat;
   nextPositionId: Nat;
   sqrtPriceX96: Nat;
   tick: Int;
   token0: Token;
   token1: Token;
 };


public type PositionService = actor {
  claim : shared (ClaimArgs) -> async (ClaimResult);
  getUserPosition : shared query (Nat) -> async (GetUserPositionResult) ;
  getUserPositionIdsByPrincipal : shared query (Principal) -> async (GetUserPositionIdsByPrincipalResult);
  withdraw : shared (WithdrawArgs) -> async (WithdrawResult);

  deposit : (DepositArgs) -> async (Result);
  depositFrom : (DepositArgs) -> async (Result);
  getUserUnusedBalance : query(Principal) -> async (UnusedBalanceResult);
  metadata: query () ->  async (MetadataResult);
  mint: (MintArgs) -> async (Result);

  swap : (SwapArgs) -> async (Result);
  decreaseLiquidity : (DecreaseLiquidityArgs) -> async (DecreaseLiquidityResult);

};

}
