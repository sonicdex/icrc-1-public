import Text "mo:base/Text";
import Nat "mo:base/Nat";


module {
  public type AccountId = Blob;
  public type Address = Text;
  public type From = Address;
  public type To = Address;
  public type Spender = Address;
  public type Decider = Address;
  public type Amount = Nat;
  public type Sa = [Nat8];
  public type Nonce = Nat;
  public type Data = Blob;
  public type Timeout = Nat32;
  public type Allowance = { remaining : Nat; spender : AccountId };
  public type Callback = shared TxnRecord -> async ();
  public type ExecuteType = { #sendAll; #send : Nat; #fallback };
  public type Gas = { #token : Nat; #cycles : Nat; #noFee };
  public type Metadata = { content : Text; name : Text };
  public type CoinSeconds = { coinSeconds: Nat; updateTime: Int };
  public type Operation = {
    #transfer : { action : { #burn; #mint; #send } };
  };
  public type Time = Int;
  public type Transaction = {
    to : AccountId;
    value : Nat;
    data : ?Blob;
    from : AccountId;
    operation : Operation;
  };
  public type Txid = Blob;
  public type TxnQueryRequest = {
    #txnCount : { owner : Address };
    #lockedTxns : { owner : Address };
    #lastTxids : { owner : Address };
    #lastTxidsGlobal;
    #getTxn : { txid : Txid };
    #txnCountGlobal;
    #getEvents: { owner: ?Address; };
  };
  public type TxnQueryResponse = {
    #txnCount : Nat;
    #lockedTxns : { txns : [TxnRecord]; lockedBalance : Nat };
    #lastTxids : [Txid];
    #lastTxidsGlobal : [Txid];
    #getTxn : ?TxnRecord;
    #txnCountGlobal : Nat;
    #getEvents: [TxnRecord];
  };
  public type TxnRecord = {
    gas : Gas;
    transaction : Transaction;
    txid : Txid;
    nonce : Nat;
    timestamp : Time;
    msgCaller : ?Principal;
    caller : AccountId;
    index : Nat;
  };
  public type TxnResult = {
    #ok : Txid;
    #err : {
      code : {
        #UndefinedError;
        #InsufficientBalance;
      };
      message : Text;
    };
  };
  public func toTxid(n : Nat) : Txid {
      Text.encodeUtf8(Nat.toText(n));
  };

  public type InitArgs = {
      totalSupply: Nat;
      decimals: Nat8;
      fee: Nat;
      name: ?Text;
      symbol: ?Text;
      metadata: ?[Metadata];
      owner: Principal;
  };

  public type UpgradeArgs = {};
  public type CanisterArgs = {
     initArgs : InitArgs;
     upgradeArgs : ?UpgradeArgs;
  };
  
};