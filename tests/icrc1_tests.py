import os
import unittest

import ic
from pocket_ic import PocketIC

build_dir = os.environ.get('build_dir', '.dfx/local/canisters/icrc1')

class ICRC1LedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pic = PocketIC()
        self.user_a = ic.Principal(b"UserA")
        self.user_b = ic.Principal(b"UserB")
        self.owner = ic.Principal(b"Owner")

        with open(
            os.path.join(build_dir, "icrc1.did"), "r", encoding="utf-8"
        ) as candid_file:
            candid = candid_file.read()

        # constraints
        self.SUPPLY = 10000000000000
        self.FEE = 1000
        self.DECIMALS = 8
        self.NAME = "ICRC1"
        self.SYMBOL = "ICRC1"
        self.USER_A_AMOUNT = 10000
        # Specify the init args for the ledger canister.
        init_args = {
         'initArgs': {
            'totalSupply': self.SUPPLY,
            'decimals': self.DECIMALS,
            'fee': self.FEE,
            'name': self.NAME,
            'symbol': self.SYMBOL,
            'metadata': [],
            'owner': self.owner.to_str(),
         },
         'upgradeArgs': None
        }
        with open(os.path.join(build_dir, "icrc1.wasm"), "rb") as wasm_file:
            wasm_module = wasm_file.read()

        self.ledger: ic.Canister = self.pic.create_and_install_canister_with_candid(
            candid, wasm_module, init_args
        )
        # transfers test amount to user_a
        self.pic.set_sender(self.owner)
        self.ledger.icrc1_transfer(
            {
                "from_subaccount": [],
                "to": self.user_a,
                "amount": self.USER_A_AMOUNT,
                "fee": [],
                "memo": [],
                "created_at_time": [],
            },
        ) # should be replaced by pytest fixtures
        return super().setUp()

    def test_get_name(self):
        res = self.ledger.icrc1_name()
        self.assertEqual(res, [self.NAME])

    def test_get_decimals(self):
        res = self.ledger.icrc1_symbol()
        self.assertEqual(res, ["ICRC1"])

    def test_get_fee(self):
        res = self.ledger.icrc1_fee()
        self.assertEqual(res, [self.FEE])

    def test_get_total_supply(self):
        res = self.ledger.icrc1_total_supply()
        self.assertEqual(res, [self.SUPPLY])

    def test_transfer(self):
        self.pic.set_sender(self.user_a)

        receiver = {"owner": self.user_b.to_str(), "subaccount": []}
        res = self.ledger.icrc1_transfer(
            {
                "from_subaccount": [],
                "to": receiver,
                "amount": 42,
                "fee": [],
                "memo": [],
                "created_at_time": [],
            },
        )
        self.assertTrue("Ok" in res[0])

        self.pic.set_anonymous_sender()

        res = self.ledger.icrc1_balance_of(
            {"owner": self.user_a.to_str(), "subaccount": []}
        )
        # owner_balance - transfer_amount - transfer_fee
        self.assertEqual(res, [self.USER_A_AMOUNT - 42 - self.FEE])
        res = self.ledger.icrc1_balance_of(
            {"owner": self.user_b.to_str(), "subaccount": []}
        )
        # user_b_balance + transfer_amount
        self.assertEqual(res, [42])

    def test_tx_fee_credit(self):
        self.pic.set_anonymous_sender()
        receiver = {"owner": self.user_b.to_str(), "subaccount": []}
        owner_balance = self.ledger.icrc1_balance_of({
            "owner": self.owner.to_str(),
            "subaccount": []
        })
        self.pic.set_sender(self.user_a)
        _ = self.ledger.icrc1_transfer({
            "from_subaccount": [],
            "to": receiver,
            "amount": 42,
            "fee": [],
            "memo": [],
            "created_at_time": [],
        })
        self.pic.set_anonymous_sender()
        owner_balance2 = self.ledger.icrc1_balance_of({
            "owner": self.owner.to_str(),
            "subaccount": []
        })
        self.assertEqual(owner_balance2[0], owner_balance[0] + self.FEE)

    def test_get_balance_of(self):
        res = self.ledger.icrc1_balance_of(
            {"owner": self.user_a.to_str(), "subaccount": []}
        )
        self.assertEqual(res, [self.USER_A_AMOUNT])
        res = self.ledger.icrc1_balance_of(
            {"owner": self.owner.to_str(), "subaccount": []}
        )
        self.assertEqual(res, [self.SUPPLY - self.USER_A_AMOUNT])


if __name__ == "__main__":
    unittest.main()
