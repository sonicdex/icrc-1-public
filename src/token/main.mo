
import Prim "mo:⛔";
import Trie "mo:base/Trie";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Int32 "mo:base/Int32";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Time "mo:base/Time";
import TokenTypes "./lib/Internals";
import AID "./lib/AID";
import Hex "./lib/Hex";
import Binary "./lib/Binary";
import SHA224 "./lib/SHA224";
import DRC202 "./lib/DRC202";
import ICRC1 "./lib/ICRC1";
import Internals "lib/Internals";

shared(msg) actor class ICRC1Canister(args: Internals.CanisterArgs) = this {

    type Metadata = TokenTypes.Metadata;
    type Gas = TokenTypes.Gas;
    type Address = TokenTypes.Address;
    type AccountId = TokenTypes.AccountId;
    type Txid = TokenTypes.Txid;
    type TxnResult = TokenTypes.TxnResult;
    type Operation = TokenTypes.Operation;
    type Transaction = TokenTypes.Transaction;
    // follows ic.house supported structure
    type TxnRecord = TokenTypes.TxnRecord;
    type From = Address;
    type To = Address;
    type Amount = Nat;
    type Sa = [Nat8];
    type Data = Blob;
    type Timeout = Nat32;

    /*
    * account functions
    */
    private func _getAccountId(_address: Address): AccountId{
        switch (AID.accountHexToAccountBlob(_address)){
            case(?(a)){
                return a;
            };
            case(_){
                var p = Principal.fromText(_address);
                var a = AID.principalToAccountBlob(p, null);
                return a;
            };
        };
    };


    /*
    * Config 
    */
    private stable var FEE_TO: AccountId = _getAccountId(Principal.toText(args.initArgs.owner));
    private let MAX_MEMORY: Nat = 23*1024*1024*1024; // 23G

    /* 
    * State Variables 
    */
    private var standard_: Text = "icrc1";
    private stable var name_: Text = Option.get(args.initArgs.name, "");
    private stable var symbol_: Text = Option.get(args.initArgs.symbol, "");
    private stable let decimals__: Nat8 = args.initArgs.decimals; // make decimals immutable across upgrades
    private stable var totalSupply_: Nat = args.initArgs.totalSupply;
    private stable var fee_: Nat = args.initArgs.fee;
    private stable var metadata_: [Metadata] = Option.get(args.initArgs.metadata, []);
    private stable var index: Nat = 0;
    private stable var balances: Trie.Trie<AccountId, Nat> = Trie.empty();
    private var drc202 = DRC202.DRC202({EN_DEBUG = false; MAX_CACHE_TIME = 3 * 30 * 24 * 3600 * 1000000000; MAX_CACHE_NUMBER_PER = 100; MAX_STORAGE_TRIES = 2; }, standard_);
    private stable var drc202_lastStorageTime : Time.Time = 0;

    /* 
    * Local Functions
    */
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };

    private func _getAccountIdFromPrincipal(_p: Principal, _sa: ?[Nat8]): AccountId{
        var a = AID.principalToAccountBlob(_p, _sa);
        return a;
    }; 
    private stable let owner_: AccountId = _getAccountId(Principal.toText(args.initArgs.owner));
    private stable let owner_account: Account = { owner = args.initArgs.owner; subaccount = null; };

    private func _getBalance(_a: AccountId): Nat{
        switch(Trie.get(balances, keyb(_a), Blob.equal)){
            case(?(balance)){
                return balance;
            };
            case(_){
                return 0;
            };
        };
    };
    private func _setBalance(_a: AccountId, _v: Nat): (){
        let originalValue = _getBalance(_a);
        let now = Time.now();
        if(_v == 0){
            balances := Trie.remove(balances, keyb(_a), Blob.equal).0;
        } else {
            balances := Trie.put(balances, keyb(_a), Blob.equal, _v).0;
            if (_v < fee_ / 2){
                balances := Trie.remove(balances, keyb(_a), Blob.equal).0;
            };
        };
    };
    
    private func _checkFee(_caller: AccountId, _amount: Nat): Bool{
        if(fee_ > 0) {
            return _getBalance(_caller) >= fee_ + _amount;
        };
        return true;
    };
    private func _chargeFee(_caller: AccountId): Bool{
        if(fee_ > 0) {
            if (_getBalance(_caller) >= fee_){
                ignore _send(_caller, FEE_TO, fee_, false);
                return true;
            } else {
                return false;
            };
        };
        return true;
    };
    private func _send(_from: AccountId, _to: AccountId, _value: Nat, _isCheck: Bool): Bool{
        var balance_from = _getBalance(_from);
        if (balance_from >= _value){
            if (not(_isCheck)) { 
                balance_from -= _value;
                _setBalance(_from, balance_from);
                var balance_to = _getBalance(_to);
                balance_to += _value;
                _setBalance(_to, balance_to);
            };
            return true;
        } else {
            return false;
        };
    };
    private func _mint(_to: AccountId, _value: Nat): Bool{
        var balance_to = _getBalance(_to);
        balance_to += _value;
        _setBalance(_to, balance_to);
        totalSupply_ += _value;
        return true;
    };
    private func _burn(_from: AccountId, _value: Nat, _isCheck: Bool): Bool{
        var balance_from = _getBalance(_from);
        if (balance_from >= _value){
            if (not(_isCheck)) {
                balance_from -= _value;
                _setBalance(_from, balance_from);
                totalSupply_ -= _value;
            };
            return true;
        } else {
            return false;
        };
    };

    private func _transfer(_msgCaller: Principal, _sa: ?[Nat8], _from: AccountId, _to: AccountId, _value: Nat, _data: ?Blob, 
    _operation: Operation): (result: TxnResult) {
        var callerPrincipal = _msgCaller;
        let caller = _getAccountIdFromPrincipal(_msgCaller, _sa);
        let from = _from;
        let to = _to;
        let value = _value; 
        var allowed: Nat = 0; // *
        var spendValue = _value;
        var effectiveFee : Internals.Gas = #token(fee_);
        let data = Option.get(_data, Blob.fromArray([]));

        if (data.size() > 2048){
            // drc202 limitations
            return #err({ code=#UndefinedError; message="The length of _data must be less than 2 KB"; });
        };
        switch(_operation){
            case(#transfer(operation)){
                switch(operation.action){
                    case(#mint){ effectiveFee := #noFee;};
                    case(_){};
                };
            };
            case(_){};
        };
        let nonce = index;
        let txid = drc202.generateTxid(Principal.fromActor(this), caller, nonce);
        var txn: TxnRecord = {
            msgCaller = ?_msgCaller; 
            caller = caller;
            timestamp = Time.now();
            index = index;
            nonce = nonce;
            txid = txid;
            gas = effectiveFee;
            transaction = {
                from = from;
                to = to;
                value = value; 
                operation = _operation;
                data = _data;
            };
        };
        switch(_operation){
            case(#transfer(operation)){
                switch(operation.action){
                    case(#send){
                        if (not(_send(from, to, value, true))){
                            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
                        };
                        ignore _send(from, to, value, false);
                        var as: [AccountId] = [from, to];
                        drc202.pushLastTxn(as, txid);
                    };
                    case(#mint){
                        ignore _mint(to, value);
                        var as: [AccountId] = [to];
                        drc202.pushLastTxn(as, txid); 
                        as := AID.arrayAppend(as, [caller]);
                    };
                    case(#burn){
                        if (not(_burn(from, value, true))){
                            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
                        };
                        ignore _burn(from, value, false);
                        var as: [AccountId] = [from];
                        drc202.pushLastTxn(as, txid);
                    };
                };
            };
        };
        // insert for drc202 record
        drc202.put(txn);
        index += 1;
        return #ok(txid);
    };

    private func _transferFrom(__caller: Principal, _from: AccountId, _to: AccountId, _value: Amount, _sa: ?Sa, _data: ?Data) : 
    (result: TxnResult) {
        let from = _from;
        let to = _to;
        let operation: Operation = #transfer({ action = #send; });
        // check fee
        if(not(_checkFee(from, _value))){
            return #err({ code=#InsufficientBalance; message="Insufficient Balance"; });
        };
        // transfer
        let res = _transfer(__caller, _sa, from, to, _value, _data, operation);
        // charge fee
        switch(res){
            case(#ok(v)){ ignore _chargeFee(from); return res; };
            case(#err(v)){ return res; };
        };
    };

    public query func historySize() : async Nat {
        return index;
    };

    // icrc1 standard (https://github.com/dfinity/ICRC-1)
    type Value = ICRC1.Value;
    type Subaccount = ICRC1.Subaccount;
    type Account = ICRC1.Account;
    type TransferArgs = ICRC1.TransferArgs;
    type TransferError = ICRC1.TransferError;
    
    private func _icrc1_get_account(_a: Account) : Blob{
        var sub: ?[Nat8] = null;
        switch(_a.subaccount){
            case(?(_sub)){ sub := ?(Blob.toArray(_sub)) };
            case(_){};
        };
        return _getAccountIdFromPrincipal(_a.owner, sub);
    };

    private func _icrc1_receipt(_result: TxnResult, _a: AccountId) : { #Ok: Nat; #Err: TransferError; }{
        switch(_result){
            case(#ok(txid)){
                switch(drc202.get(txid)){
                    case(?(txn)){ return #Ok(txn.index) };
                    case(_){ return #Ok(0) };
                };
            };
            case(#err(err)){
                switch(err.code){
                    case(#UndefinedError) { return #Err(#GenericError({ error_code = 999; message = err.message })) };
                    case(#InsufficientBalance) { return #Err(#InsufficientFunds({ balance = _getBalance(_a); })) };
                };
            };
        };
    };

    private func _toSaNat8(_sa: ?Blob) : ?[Nat8]{
        switch(_sa){
            case(?(sa)){ return ?Blob.toArray(sa); };
            case(_){ return null; };
        }
    };
    private let PERMITTED_DELAY: Int = 180_000_000_000; // 3 minutes
    private func _icrc1_time_check(_created_at_time: ?Nat64) : 
    { #Ok; #TransferErr: TransferError; }{
        switch(_created_at_time){
            case(?(created_at_time)){
                if (Nat64.toNat(created_at_time) + PERMITTED_DELAY < Time.now()){
                    return #TransferErr(#TooOld);
                };
                return #Ok;
            };
            case(_){
                return #Ok;
            };
        };
    };
    public query func icrc1_supported_standards() : async [{ name : Text; url : Text }]{
        return [
            {name = "ICRC-1"; url = "https://github.com/dfinity/ICRC-1"},
        ];
    };
    public query func icrc1_minting_account() : async ?Account{
        return ?owner_account;
    };
    public query func icrc1_name() : async Text{
        return name_;
    };
    public query func icrc1_symbol() : async Text{
        return symbol_;
    };
    public query func icrc1_decimals() : async Nat8{
        return decimals__;
    };
    public query func icrc1_fee() : async Nat{
        return fee_;
    };
    public query func icrc1_metadata() : async [(Text, Value)]{
        let md1: [(Text, Value)] = [("icrc1:symbol", #Text(symbol_)), ("icrc1:name", #Text(name_)), ("icrc1:decimals", #Nat(Nat8.toNat(decimals__))), 
        ("icrc1:fee", #Nat(fee_)), ("icrc1:total_supply", #Nat(totalSupply_)), ("icrc1:max_memo_length", #Nat(2048))];
        var md2: [(Text, Value)] = Array.map<Metadata, (Text, Value)>(metadata_, func (item: Metadata) : (Text, Value) {
            if (item.name == "logo"){
                ("icrc1:"#item.name, #Text(item.content))
            }else{
                ("drc20:"#item.name, #Text(item.content))
            }
        });
        return AID.arrayAppend(md1, md2);
    };
    public query func icrc1_total_supply() : async Nat{
        return totalSupply_;
    };
    public query func icrc1_balance_of(_owner: Account) : async (balance: Nat){
        return _getBalance(_icrc1_get_account(_owner));
    };
    public shared(msg) func icrc1_transfer(_args: TransferArgs) : async ({ #Ok: Nat; #Err: TransferError; }) {
        switch(_args.fee){
            case(?(icrc1_fee)){
                if (icrc1_fee < fee_){ return #Err(#BadFee({ expected_fee = fee_ })) };
            };
            case(_){};
        };
        let from = _icrc1_get_account({ owner = msg.caller; subaccount = _args.from_subaccount; });
        let sub = _toSaNat8(_args.from_subaccount);
        let to = _icrc1_get_account(_args.to);
        let data = _args.memo;
        switch(_icrc1_time_check(_args.created_at_time)){
            case(#TransferErr(err)){ return #Err(err); };
            case(_){};
        };
        let res = _transferFrom(msg.caller, from, to, _args.amount, sub, data);

        // Store data to the DRC202 scalable bucket, requires a 20 second interval to initiate a batch store, and may be rejected if you store frequently.
        if (Time.now() > drc202_lastStorageTime + 20*1000000000) { 
            drc202_lastStorageTime := Time.now();
            ignore drc202.store(); 
        };
        return _icrc1_receipt(res, from);
    };

    // drc202
    public query func drc202_getConfig() : async DRC202.Setting{
        return drc202.getConfig();
    };

    public query func drc202_canisterId() : async Principal{
        return drc202.drc202CanisterId();
    };
    /// returns events
    public query func drc202_events(_account: ?DRC202.Address) : async [DRC202.TxnRecord]{
        switch(_account){
            case(?(account)){ return drc202.getEvents(?_getAccountId(account)); };
            case(_){return drc202.getEvents(null);}
        };
    };
    /// returns txn record. It's an query method that will try to find txn record in token canister cache.
    public query func drc202_txn(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        return drc202.get(_txid);
    };
    /// returns txn record. It's an update method that will try to find txn record in the DRC202 canister if the record does not exist in this canister.
    public shared func drc202_txn2(_txid: DRC202.Txid) : async (txn: ?DRC202.TxnRecord){
        switch(drc202.get(_txid)){
            case(?(txn)){ return ?txn; };
            case(_){
                return await drc202.get2(Principal.fromActor(this), _txid);
            };
        };
    };
    /// returns drc202 pool
    public query func drc202_pool() : async [(DRC202.Txid, Nat)]{
        return drc202.getPool();
    };

    /* 
    * Genesis
    */
    private stable var genesisCreated: Bool = false;
    if (not(genesisCreated)){
        balances := Trie.put(balances, keyb(owner_), Blob.equal, totalSupply_).0;
        var txn: TxnRecord = {
            txid = Blob.fromArray([0:Nat8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
            msgCaller = ?msg.caller;
            caller = AID.principalToAccountBlob(msg.caller, null);
            timestamp = Time.now();
            index = index;
            nonce = 0;
            gas = #noFee;
            transaction = {
                from = AID.blackhole();
                to = owner_;
                value = totalSupply_; 
                operation = #transfer({ action = #mint; });
                data = null;
            };
        };
        index += 1;
        drc202.put(txn);
        drc202.pushLastTxn([owner_], txn.txid);
        genesisCreated := true;
    };

    private stable var __drc202Data: [DRC202.DataTemp] = [];
    private stable var __drc202DataNew: ?DRC202.DataTemp = null;

    system func preupgrade() {
        __drc202DataNew := ?drc202.getData();
    };
    system func postupgrade() {
        switch(__drc202DataNew){
            case(?(data)){
                drc202.setData(data);
                __drc202Data := [];
                __drc202DataNew := null;
            };
            case(_){
                if (__drc202Data.size() > 0){
                    drc202.setData(__drc202Data[0]);
                    __drc202Data := [];
                };
            };
        };
    };

};
