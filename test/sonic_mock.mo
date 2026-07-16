import Principal "mo:base/Principal";

// Local stand-in for the Sonic swap pool (ni6i4-cqaaa-aaaak-qtsbq-cai).
// Deliberately models the real pool's insolvency: the internal accounting
// (unused balances) far exceeds the real reserves (token balances), which is
// what makes sonic_withdraw_max necessary.
persistent actor {

  type Error = {
    #CommonError;
    #InsufficientFunds;
    #InternalError : Text;
    #UnsupportedToken : Text;
  };

  type Amounts = { amount0 : Nat; amount1 : Nat };
  type AmountsResult = { #ok : Amounts; #err : Error };
  type NatResult = { #ok : Nat; #err : Error };
  type UnusedBalance = { balance0 : Nat; balance1 : Nat };
  type UnusedBalanceResult = { #ok : UnusedBalance; #err : Error };
  type Token = { address : Text; standard : Text };
  type PoolMetadata = { token0 : Token; token1 : Token };
  type MetadataResult = { #ok : PoolMetadata; #err : Error };

  // token0 = SNEED, token1 = ICP, matching the real pool's ordering.
  transient let token0_address = "hvgxa-wqaaa-aaaaq-aacia-cai";
  transient let token1_address = "ryjl3-tyaaa-aaaaa-aaaba-cai";

  // Owed (generous) vs actually held (scarce): the insolvency, real values.
  var owed0 : Nat = 12_214_407_804; // 122.14 SNEED
  var owed1 : Nat = 485_910_640_019; // 4859.11 ICP
  var held0 : Nat = 556_420_283; // 5.56 SNEED
  var held1 : Nat = 187_704_991_578; // 1877.05 ICP

  var last_withdraw_amount : Nat = 0;

  public query func metadata() : async MetadataResult {
    #ok({
      token0 = { address = token0_address; standard = "ICRC2" };
      token1 = { address = token1_address; standard = "ICRC2" };
    });
  };

  public query func getUserUnusedBalance(_account : Principal) : async UnusedBalanceResult {
    #ok({ balance0 = owed0; balance1 = owed1 });
  };

  public func getTokenBalance() : async { token0 : Nat; token1 : Nat } {
    { token0 = held0; token1 = held1 };
  };

  public func claim(args : { positionId : Nat }) : async AmountsResult {
    if (args.positionId != 2) { return #err(#InternalError("no such position")) };
    #ok({ amount0 = 301_641_723; amount1 = 3_195_932_904 });
  };

  public func decreaseLiquidity(args : { positionId : Nat; liquidity : Text }) : async AmountsResult {
    if (args.positionId != 2) { return #err(#InternalError("no such position")) };
    if (args.liquidity != "339138795889") {
      return #err(#InternalError("unexpected liquidity"));
    };
    #ok({ amount0 = 12_214_407_804; amount1 = 485_910_640_019 });
  };

  // Mirrors the real pool: paying out more than is held fails.
  public func withdraw(args : { token : Text; fee : Nat; amount : Nat }) : async NatResult {
    let held = if (args.token == token0_address) { held0 } else { held1 };
    if (args.amount > held) { return #err(#InsufficientFunds) };
    last_withdraw_amount := args.amount;
    #ok(args.amount);
  };

  // Test helper: the amount the last withdraw actually requested.
  public query func last_withdraw() : async Nat { last_withdraw_amount };
};
