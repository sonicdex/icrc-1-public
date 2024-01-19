import os

from ic.principal import Principal
from pocket_ic import PocketIC

CANDID_PATH = os.environ.get("DFX_CANDID_PATH", ".dfx/local/canisters/icrc1/icrc1.did")
WASM_PATH = os.environ.get("DFX_WASM_PATH", ".dfx/local/canisters/icrc1/icrc1.wasm")
candid = open(CANDID_PATH).read()
wasm = open(WASM_PATH, "rb").read()

pic = PocketIC()

canister = pic.create_and_install_canister_with_candid(
    candid=candid,
    wasm_module=bytes(wasm),
    init_args={
        "totalSupply": 10000000000000,
        "decimals": 8,
        "fee": 1000,
        "name": "ICRC1",
        "symbol": "ICRC1",
        "metadata": None,
        "owner": Principal.anonymous().to_str(),
    });