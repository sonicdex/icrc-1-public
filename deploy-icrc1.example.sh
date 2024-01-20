NETWORK="ic"
OWNER=$(dfx --identity icrc1-test identity get-principal)
echo "Deploying on $NETWORK, owner is set as : $OWNER"
dfx --identity icrc1-test deploy icrc1 --network $NETWORK --argument "record { initArgs = record { totalSupply=10000000000000; decimals=8; fee=1000; name=opt \"ICRC1\"; symbol=opt \"ICRC1\"; metadata=null; owner=principal \"$OWNER\";}; upgradeArgs=null}"