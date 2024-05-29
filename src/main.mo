import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Debug "mo:base/Debug";

import T "Types";
import ST "SwapTypes";
import ICRC2Types "ICRC2Types";

shared (deployer) actor class SNEEDFi() = this {

  stable var snsGovernance : Principal = if(deployer.caller == Principal.fromText("fi3zi-fyaaa-aaaaq-aachq-cai")){
    Principal.fromText("fi3zi-fyaaa-aaaaq-aachq-cai");
  } else {
    deployer.caller;
  };
  //after upgrade, set this to Principal.fromText("fi3zi-fyaaa-aaaaq-aachq-cai");

  //when ready for production, set this to 4mmnk-kiaaa-aaaag-qbllq-cai
  stable var ICPSwapFactoryPrincipal = if(deployer.caller == Principal.fromText("fi3zi-fyaaa-aaaaq-aachq-cai")){
   "4mmnk-kiaaa-aaaag-qbllq-cai";
  } else {
    "ososz-6iaaa-aaaag-ak5ua-cai";
  };


  func dappCanister() : Principal {
    Principal.fromActor(this);
  };

  // Send the specified amount of ICRC1 tokens.   
  public shared ({ caller }) func send_icrc1_tokens(
    amount_e8s : T.Balance,                 // amount to be sent.
    icrc1_ledger_canister_id : Principal,   // the Principal id of the ledger canister of the icrc1 token to be sent.
    to_account : T.Account,                 // the account that the icrc1 token should be sent to 
    fee : ?T.Balance,                       // the expected fee (set to null when sending to burn account!)
    memo : ?Blob,
    from_subaccount : ?Blob)                           // an optional memo to send with the icrc1 transfer transaction
    : async T.TransferResult {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      let transfer_args : T.TransferArgs = {
        from_subaccount = from_subaccount;
        to = to_account;
        amount = amount_e8s;
        fee = fee;
        memo = memo;
        created_at_time = null;
      };

      let icrc1_ledger_canister = actor (Principal.toText(icrc1_ledger_canister_id)) : actor {
        icrc1_transfer(args : T.TransferArgs) : async T.TransferResult;
      };  

      await icrc1_ledger_canister.icrc1_transfer(transfer_args);

  };

  public query({caller}) func stats() : async {
    snsGovernance : Principal;
    dappCanister : Principal;
   }{
    {
      snsGovernance = snsGovernance;
      dappCanister = dappCanister();
      ICPSwapFactoryPrincipal = ICPSwapFactoryPrincipal;
    };
  };

  // SNS generic function validation method for send_icrc1_tokens 
  public query({caller}) func validate_send_icrc1_tokens(
    amount_e8s : T.Balance,                 
    icrc1_ledger_canister_id : Principal,   
    to_account : T.Account,                  
    fee : ?T.Balance,                       
    memo : ?Blob,
    from_subaccount: ?Blob) : async T.ValidationResult {

      if(caller != snsGovernance) return #Err("Only the govenrnace canister can call swap_withdraw.");

      let msg:Text = "amount: " # debug_show(amount_e8s) #  
      ", icrc1_ledger_canister_id: " # Principal.toText(icrc1_ledger_canister_id) # 
      ", to_account: " # debug_show(to_account) #  
      ", fee: " # debug_show(fee) #  
      ", memo: " # debug_show(memo) #
      ", from_subaccount: " # debug_show(from_subaccount);

      #Ok(msg);
  };
  public type SwapWithdrawToken = {
    address : Text; 
    standard : Text;
    fee : Nat;
    additional_amount : ?Nat;
  };

  public type SwapPositionRequest = {
    amount0Desired: Nat;
    amount1Desired: Nat;
    fee: Nat;
    tickLower: Int;
    tickUpper: Int;
    token0: Principal;
    token0fee: Nat;
    token1: Principal;
    token1fee: Nat;
  };

  public type SwapRequest = {
    token0: Principal;
    token0fee: Nat;
    token1: Principal;
    token1fee: Nat;
    amountIn : Nat;
    zeroForOne : Bool;
    amountOutMinimum : Nat;
  };

  public type ManageICPSwapRequest = {
    #WithdrawFees: SwapFeeWithdrawRequest;
    #WithdrawPosition : SwapWithdrawRequest;
    #CreatePosition : SwapPositionRequest;
    #Swap : SwapRequest;
  };

  public type ManageICPSwapResponse = {
    #WithdrawFees: Result.Result<[(ST.WithdrawResult, ST.WithdrawResult)], Text>;
    #WithdrawPosition : Result.Result<[(ST.WithdrawResult, ST.WithdrawResult)], Text>;
    #CreatePosition : Result.Result<Nat, Text>;
    #Swap : Result.Result<Nat, Text>;
  };

  public type SwapFeeWithdrawRequest = {
    pool: {
      token0 : SwapWithdrawToken;
      token1 : SwapWithdrawToken;
    };
    feeMinMultiple: Nat;
  };

  public type SwapWithdrawRequest = {
    pool: {
      token0 : SwapWithdrawToken;
      token1 : SwapWithdrawToken;
    };
  };

  // Manage Positions on ICPSwap  
  public shared ({ caller }) func manage_icpswap(request : ManageICPSwapRequest)
    : async ManageICPSwapResponse {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      switch(request){
        case(#WithdrawFees(request)){
          return #WithdrawFees(await* swap_fee_withdraw(caller, request));
        };
        case(#WithdrawPosition(request)){
          return #WithdrawPosition(await* swap_position_withdraw(caller, request));
        };
        case(#CreatePosition(request)){
          return #CreatePosition(await* swap_position_create(caller, request));
        };
        case(#Swap(request)){
          return #Swap(await* swap(caller, request));
        };
      };
  };

  


  // withdraw fees to the canister   
  private func swap_fee_withdraw(caller: Principal, request : SwapFeeWithdrawRequest)
    : async* Result.Result<[(ST.WithdrawResult, ST.WithdrawResult)], Text> {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      let results = Buffer.Buffer<(ST.WithdrawResult, ST.WithdrawResult)>(1);

      let swapService : ST.PoolService = actor(ICPSwapFactoryPrincipal);

      let #ok(pools) = await swapService.getPools() else return #err("swap service is offline");

      label eachPool for(thisPool in pools.vals()){

        if(thisPool.token0.address != request.pool.token0.address or thisPool.token1.address != request.pool.token1.address) continue eachPool;
        
        let thisCanister = thisPool.canisterId;

        let positionService : ST.PositionService = actor(Principal.toText(thisCanister));

        let #ok(positions) = await positionService.getUserPositionIdsByPrincipal(dappCanister()) else continue eachPool;

        label eachPosition for(thisPosition in positions.vals()){

          let #ok(position) = await positionService.getUserPosition(thisPosition) else continue eachPosition;

          
          //claim the tokens
          let claim : { 
            amount0 : Nat; 
            amount1 : Nat 
          } = if(position.tokensOwed0 > 0 or position.tokensOwed1 > 0){
            
            switch(await positionService.claim({
            positionId = thisPosition
            })){
              case(#ok(val)) val;
              case(#err(err)) {
                //TODO:  how to report this error
                {amount0 = 0 : Nat; amount1 = 0 : Nat};
              };
            };
          } else {
            {amount0 = 0: Nat; amount1 = 0:Nat};
          };


          let total0 = claim.amount0 + (switch(request.pool.token0.additional_amount: ?Nat){
            case(null) 0;
            case(?val) val;
          });

          let total1 = claim.amount0 + (switch(request.pool.token1.additional_amount : ?Nat){
            case(null) 0;
            case(?val) val;
          });

          

          let claimed0 : ST.WithdrawResult  = if(total0 > request.pool.token0.fee * request.feeMinMultiple){
            await positionService.withdraw({
              fee = request.pool.token0.fee;
              token = request.pool.token0.address;
              amount = total0;
            })

          } else #err(#InsufficientFunds);

          let claimed1 : ST.WithdrawResult  = if(total1 > request.pool.token1.fee * request.feeMinMultiple){
            await positionService.withdraw({
              fee = request.pool.token1.fee;
              token = request.pool.token1.address;
              amount = total1;
            })  
          } else #err(#InsufficientFunds);

          results.add(claimed0,claimed1);
        };
        return #ok(Buffer.toArray(results));
      };

      Debug.trap("Could Not Find Pool");
  };

  // withdraw positions to the canister   
  private func swap_position_withdraw(caller: Principal, request : SwapWithdrawRequest)
    : async* Result.Result<[(ST.WithdrawResult, ST.WithdrawResult)], Text> {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      let results = Buffer.Buffer<(ST.WithdrawResult, ST.WithdrawResult)>(1);

      let swapService : ST.PoolService = actor(ICPSwapFactoryPrincipal);

      let #ok(pools) = await swapService.getPools() else return #err("swap service is offline");

      label eachPool for(thisPool in pools.vals()){

        if(thisPool.token0.address != request.pool.token0.address or thisPool.token1.address != request.pool.token1.address) continue eachPool;
        
        let thisCanister = thisPool.canisterId;

        let positionService : ST.PositionService = actor(Principal.toText(thisCanister));

        let #ok(positions) = await positionService.getUserPositionIdsByPrincipal(dappCanister()) else continue eachPool;

        label eachPosition for(thisPosition in positions.vals()){

          let #ok(position) = await positionService.getUserPosition(thisPosition) else continue eachPosition;

          
          //claim the tokens
          let claim : { 
            amount0 : Nat; 
            amount1 : Nat 
          } = if(position.tokensOwed0 > 0 or position.tokensOwed1 > 0){
            
            switch(await positionService.decreaseLiquidity({
            positionId = thisPosition;
            liquidity = Nat.toText(position.liquidity);
            })){
              case(#ok(val)) val;
              case(#err(err)) {
                //TODO:  how to report this error
                {amount0 = 0 : Nat; amount1 = 0 : Nat};
              };
            };
          } else {
            {amount0 = 0: Nat; amount1 = 0:Nat};
          };


          let total0 = claim.amount0 + (switch(request.pool.token0.additional_amount: ?Nat){
            case(null) 0;
            case(?val) val;
          });

          let total1 = claim.amount0 + (switch(request.pool.token1.additional_amount : ?Nat){
            case(null) 0;
            case(?val) val;
          });

          

          let claimed0 : ST.WithdrawResult  = if(total0 > request.pool.token0.fee){
            await positionService.withdraw({
              fee = request.pool.token0.fee;
              token = request.pool.token0.address;
              amount = total0;
            })

          } else #err(#InsufficientFunds);

          let claimed1 : ST.WithdrawResult  = if(total1 > request.pool.token1.fee){
            await positionService.withdraw({
              fee = request.pool.token1.fee;
              token = request.pool.token1.address;
              amount = total1;
            })  
          } else #err(#InsufficientFunds);

          results.add(claimed0,claimed1);
        };


        return #ok(Buffer.toArray(results));
      };

      Debug.trap("Could not find pool.");
  };


  // create a new position  
  private func swap_position_create(caller: Principal, request : SwapPositionRequest)
    : async* Result.Result<Nat, Text> {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      let results = Buffer.Buffer<(ST.WithdrawResult, ST.WithdrawResult)>(1);

      let swapService : ST.PoolService = actor(ICPSwapFactoryPrincipal);

      let #ok(pools) = await swapService.getPools() else return #err("swap service is offline");

      label eachPool for(thisPool in pools.vals()){

        if(thisPool.token0.address != Principal.toText(request.token0) or thisPool.token1.address != Principal.toText(request.token1)) continue eachPool;
        
        let thisCanister = thisPool.canisterId;

        let positionService : ST.PositionService = actor(Principal.toText(thisCanister));

        let #ok(metadata) = await positionService.metadata() else continue eachPool;

        let token0Service : ICRC2Types.service = actor(Principal.toText(request.token0));

        let token1Service : ICRC2Types.service = actor(Principal.toText(request.token1));

        let token0approve = token0Service.icrc2_approve({
            from_subaccount = null;
            spender = {
              owner = thisPool.canisterId;
              subaccount = null;
            };
            amount = request.amount0Desired;
            expected_allowance = null;
            expires_at = ?Nat64.fromNat((Int.abs(Time.now()) + 3600000000000)); //one hour
            fee = ?request.token0fee;
            memo = null;
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        });

        let token1approve = token1Service.icrc2_approve({
            from_subaccount = null;
            spender = {
              owner = thisPool.canisterId;
              subaccount = null;
            };
            amount = request.amount1Desired;
            expected_allowance = null;
            expires_at = ?Nat64.fromNat((Int.abs(Time.now()) + 3600000000000)); //one hour
            fee = ?request.token1fee;
            memo = null;
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
        });

        let approvals = switch(await token0approve, await token1approve){
          case(#ok(tx0),#ok(tx1)){
            (tx0, tx1);
          };
          case(_,_){
            Debug.trap("approvals failed");
          };
        };


        let token0deposit = positionService.depositFrom({
            token = Principal.toText(request.token0);
            fee = request.token0fee;
            amount = request.amount0Desired
        });

       let token1deposit = positionService.depositFrom({
            token = Principal.toText(request.token1);
            fee = request.token1fee;
            amount = request.amount1Desired
        });

        let deposits = switch(await token0deposit, await token1deposit){
          case(#ok(tx0),#ok(tx1)){
            (tx0, tx1);
          };
          case(_,_){
            Debug.trap("approvals failed");
          };
        };


        let #ok(mint) = await positionService.mint({

          amount0Desired = Nat.toText(request.amount0Desired);
          amount1Desired = Nat.toText(request.amount1Desired);
          fee = metadata.fee;
          tickLower = request.tickLower;
          tickUpper = request.tickUpper;
          token0 = Principal.toText(request.token0);
          token1 = Principal.toText(request.token0);
        }) else return #err("mint failed");


          
         return #ok(mint);
      };

      Debug.trap("Did not find the pool");
  };

  // do a swap
  // warning: Due to the architecture of ICPSwap and the public nature of a governance proposal, it is likely that this swap will be front run.
  //future versions could put in a timer to add some randomness to execution flow.
  private func swap(caller: Principal, request : SwapRequest)
    : async* Result.Result<Nat, Text> {

      if(caller != snsGovernance) Debug.trap("Only the govenrnace canister can call swap_withdraw.");

      let results = Buffer.Buffer<(ST.WithdrawResult, ST.WithdrawResult)>(1);

      let swapService : ST.PoolService = actor(ICPSwapFactoryPrincipal);

      let #ok(pools) = await swapService.getPools() else return #err("swap service is offline");

      label eachPool for(thisPool in pools.vals()){

        if(thisPool.token0.address != Principal.toText(request.token0) or thisPool.token1.address != Principal.toText(request.token1)) continue eachPool;
        
        let thisCanister = thisPool.canisterId;

        let positionService : ST.PositionService = actor(Principal.toText(thisCanister));

        let #ok(metadata) = await positionService.metadata() else continue eachPool;

        

        if(request.zeroForOne){
          let token0Service : ICRC2Types.service = actor(Principal.toText(request.token0));

          let #ok(approvetx) = await token0Service.icrc2_approve({
            from_subaccount = null;
            spender = {
              owner = thisPool.canisterId;
              subaccount = null;
            };
            amount = request.amountIn;
            expected_allowance = null;
            expires_at = ?Nat64.fromNat((Int.abs(Time.now()) + 3600000000000)); //one hour
            fee = ?request.token0fee;
            memo = null;
            created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
          }) else return #err("approve failed");

          let #ok(token0deposit) = await positionService.depositFrom({
              token = Principal.toText(request.token0);
              fee = request.token0fee;
              amount = request.amountIn
          }) else return #err("deposit from failed");

        } else {
          let token1Service : ICRC2Types.service = actor(Principal.toText(request.token1));

           let #ok(approvetx) = await token1Service.icrc2_approve({
              from_subaccount = null;
              spender = {
                owner = thisPool.canisterId;
                subaccount = null;
              };
              amount = request.amountIn;
              expected_allowance = null;
              expires_at = ?Nat64.fromNat((Int.abs(Time.now()) + 3600000000000)); //one hour
              fee = ?request.token1fee;
              memo = null;
              created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
          }) else return #err("approve failed");

          let #ok(token1deposit) = await positionService.depositFrom({
            token = Principal.toText(request.token1);
            fee = request.token1fee;
            amount = request.amountIn
          }) else return #err("deposit from failed");
        };


        let #ok(swap) = await positionService.swap({

          amountIn = Nat.toText(request.amountIn);
          zeroForOne = request.zeroForOne;
          amountOutMinimum = Nat.toText(request.amountOutMinimum);
        }) else return #err("swap failed");


        let #ok(withdraw) = await positionService.withdraw({
          fee = if(request.zeroForOne){
            request.token1fee;
          } else {
            request.token0fee;
          };
          token = if(request.zeroForOne){
            Principal.toText(request.token1);
          } else {
            Principal.toText(request.token0);
          };
          amount = swap;
        }) else return #err("withdraw failed");


          
         return #ok(withdraw);
      };

      Debug.trap("Did not find the pool");
  };

  // SNS generic function validation method for swap_withdrawl 
  public query(msg) func validate_manage_icpswap(request : ManageICPSwapRequest) : async T.ValidationResult {
      if(msg.caller != snsGovernance) Debug.trap("Only the govenrnace canister can call manage_icpswap.");
      let validate_message: Text = switch(request){
        case(#WithdrawFees(request)){
          "The canister will withdraw fees from the ICPSwap pool using the following token canisters: " # debug_show(request);
        };
        case(#WithdrawPosition(request)){
          "The canister will withdraw positions from the ICPSwap pool using the following token canisters: " # debug_show(request);
        };
        case(#CreatePosition(request)){
          "The canister will create a new position in the ICPSwap pool using the following token canisters and amounts: " # debug_show(request);
        };
        case(#Swap(request)){
          "The canister will swap tokens in the ICPSwap pool using the following token canisters and amounts: " # debug_show(request);
        };
      };
      #Ok(validate_message);
  };

  // SNS generic function validation method for swap_withdrawl 
  public query(msg) func validate_icpswap_position_transfer(from: Principal, to: Principal) : async T.ValidationResult {
      if(msg.caller != snsGovernance) return #Err("Only the govenrnace canister can call validate_swap_withdraw.");

      if(from != snsGovernance) return #Err("Only the govenrnace canister can be the transfer from.");

      if(to != dappCanister()) return #Err("You can only transfer items to the sneed dapp canister.");

      let validate_message: Text = "This will transfer an icpSwap position from " # debug_show(from) # " to " # debug_show(to);

      #Ok(validate_message);
  };

  public shared(msg) func update_sns_governance(new_canister: Principal): async (){
    if(msg.caller != snsGovernance) Debug.trap("Only the govenrnace canister can call update_sns_governance.");

    snsGovernance := new_canister;
  };

  // SNS generic function validation method for swap_withdrawl 
  public query(msg) func validate_update_sns_governance(new_canister: Principal) : async T.ValidationResult {
      if(msg.caller != snsGovernance) return #Err("Only the govenrnace canister can call update_sns_governance.");

      let validate_message: Text = "The sns governance canister will be updated to " # debug_show(new_canister);
      #Ok(validate_message);
  };

  public shared(msg) func update_icpswap_factory(new_canister: Text): async (){
    if(msg.caller != snsGovernance) Debug.trap("Only the govenrnace canister can call update_sns_governance.");

    ICPSwapFactoryPrincipal := new_canister;
  };

  // SNS generic function validation method for swap_withdrawl 
  public query(msg) func validate_update_icpswap_factory(new_canister: Text) : async T.ValidationResult {
      if(msg.caller != snsGovernance) return #Err("Only the govenrnace canister can call validate_update_icpswap_factory.");

      let validate_message: Text = "The icpswap canister will be updated to " # debug_show(new_canister);
      #Ok(validate_message);
  };

  private func PrincipalToSubaccount(p : Principal) : [Nat8] {
      let a = Array.init<Nat8>(32, 0);
      let pa = Principal.toBlob(p);
      a[0] := Nat8.fromNat(pa.size());

      var pos = 1;
      for (x in pa.vals()) {
        a[pos] := x;
        pos := pos + 1;
      };

      Array.freeze(a);
  };
 
};
