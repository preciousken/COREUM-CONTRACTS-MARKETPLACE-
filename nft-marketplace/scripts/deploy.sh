#!/bin/bash

# Function to set network variables
set_network_variables() {
    local network=$1
    case $network in
        "testnet")
            export COREUM_CHAIN_ID="coreum-testnet-1"
            export COREUM_DENOM="utestcore"
            export COREUM_NODE="https://full-node.testnet-1.coreum.dev:26657"
            export COREUM_VERSION="v4.1.2"
            ;;
        *)
            echo "Invalid network. Using testnet..."
            export COREUM_CHAIN_ID="coreum-testnet-1"
            export COREUM_DENOM="utestcore"
            export COREUM_NODE="https://full-node.testnet-1.coreum.dev:26657"
            export COREUM_VERSION="v4.1.2"
            ;;
    esac

    export COREUM_CHAIN_ID_ARGS="--chain-id=$COREUM_CHAIN_ID"
    export COREUM_NODE_ARGS="--node=$COREUM_NODE"
}

WALLET="wallet"
NETWORK="testnet"
KEYRING_FLAG="--keyring-backend test"

echo "Setting up for Coreum $NETWORK..."
set_network_variables $NETWORK

# Check wallet and balance
echo "Checking wallet..."
WALLET_ADDRESS=$(cored keys show $WALLET $KEYRING_FLAG -a $COREUM_CHAIN_ID_ARGS)
if [ -z "$WALLET_ADDRESS" ]; then
    echo "Error: Wallet not found"
    exit 1
fi
echo "Wallet address: $WALLET_ADDRESS"

echo "Checking balance..."
BALANCE=$(cored query bank balances $WALLET_ADDRESS $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS -o json)
echo "Balance: $BALANCE"

# First optimize the contracts
echo "Optimizing contracts..."
docker run --rm -v "$(pwd)":/code \
  --mount type=volume,source="$(basename "$(pwd)")_cache",target=/target \
  --mount type=volume,source=registry_cache,target=/usr/local/cargo/registry \
  cosmwasm/optimizer:0.15.0

# Deploy NFT contract
echo "Deploying NFT contract..."
NFT_RESULT=$(cored tx wasm store artifacts/nft.wasm \
    --from $WALLET $KEYRING_FLAG --gas auto --gas-adjustment 1.3 -y -b block \
    --output json $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS)
NFT_CODE_ID=$(echo $NFT_RESULT | jq -r '.logs[0].events[-1].attributes[-1].value')
echo "NFT Code ID: $NFT_CODE_ID"

if [ -z "$NFT_CODE_ID" ]; then
    echo "Error deploying NFT contract"
    exit 1
fi

# Deploy CW20 contract
echo "Deploying CW20 contract..."
CW20_RESULT=$(cored tx wasm store artifacts/cw20_impl.wasm \
    --from $WALLET $KEYRING_FLAG --gas auto --gas-adjustment 1.3 -y -b block \
    --output json $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS)
CW20_CODE_ID=$(echo $CW20_RESULT | jq -r '.logs[0].events[-1].attributes[-1].value')
echo "CW20 Code ID: $CW20_CODE_ID"

if [ -z "$CW20_CODE_ID" ]; then
    echo "Error deploying CW20 contract"
    exit 1
fi

# Deploy Marketplace contract
echo "Deploying Marketplace contract..."
MARKETPLACE_RESULT=$(cored tx wasm store artifacts/nft_marketplace.wasm \
    --from $WALLET $KEYRING_FLAG --gas auto --gas-adjustment 1.3 -y -b block \
    --output json $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS)
MARKETPLACE_CODE_ID=$(echo $MARKETPLACE_RESULT | jq -r '.logs[0].events[-1].attributes[-1].value')
echo "Marketplace Code ID: $MARKETPLACE_CODE_ID"

if [ -z "$MARKETPLACE_CODE_ID" ]; then
    echo "Error deploying Marketplace contract"
    exit 1
fi

# Initialize contracts
echo "Initializing contracts..."

# Initialize NFT contract
NFT_INIT='{
  "name": "Test NFT",
  "symbol": "TNFT",
  "minter": "'$WALLET_ADDRESS'"
}'

NFT_INIT_RESULT=$(cored tx wasm instantiate $NFT_CODE_ID "$NFT_INIT" \
    --from $WALLET $KEYRING_FLAG --label "Test NFT" -b block -y \
    --admin $WALLET_ADDRESS \
    $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS --output json)
NFT_CONTRACT=$(echo $NFT_INIT_RESULT | jq -r '.logs[0].events[0].attributes[0].value')
echo "NFT Contract: $NFT_CONTRACT"

# Initialize CW20 contract
CW20_INIT='{
  "name": "Test Token",
  "symbol": "TTOKEN",
  "decimals": 6,
  "initial_balances": [{
    "address": "'$WALLET_ADDRESS'",
    "amount": "1000000000"
  }]
}'

CW20_INIT_RESULT=$(cored tx wasm instantiate $CW20_CODE_ID "$CW20_INIT" \
    --from $WALLET $KEYRING_FLAG --label "Test Token" -b block -y \
    --admin $WALLET_ADDRESS \
    $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS --output json)
CW20_CONTRACT=$(echo $CW20_INIT_RESULT | jq -r '.logs[0].events[0].attributes[0].value')
echo "CW20 Contract: $CW20_CONTRACT"

# Initialize Marketplace contract
MARKETPLACE_INIT='{
  "nft_contract_address": "'$NFT_CONTRACT'",
  "payment_token_address": "'$CW20_CONTRACT'",
  "native_denom": "'$COREUM_DENOM'"
}'

MARKETPLACE_INIT_RESULT=$(cored tx wasm instantiate $MARKETPLACE_CODE_ID "$MARKETPLACE_INIT" \
    --from $WALLET $KEYRING_FLAG --label "NFT Marketplace" -b block -y \
    --admin $WALLET_ADDRESS \
    $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS --output json)
MARKETPLACE_CONTRACT=$(echo $MARKETPLACE_INIT_RESULT | jq -r '.logs[0].events[0].attributes[0].value')
echo "Marketplace Contract: $MARKETPLACE_CONTRACT"

# Save contract addresses
echo "Saving contract addresses..."
echo "{
  \"network\": \"$NETWORK\",
  \"nft_code_id\": \"$NFT_CODE_ID\",
  \"cw20_code_id\": \"$CW20_CODE_ID\",
  \"marketplace_code_id\": \"$MARKETPLACE_CODE_ID\",
  \"nft_contract\": \"$NFT_CONTRACT\",
  \"cw20_contract\": \"$CW20_CONTRACT\",
  \"marketplace_contract\": \"$MARKETPLACE_CONTRACT\"
}" > contract_addresses.json

echo "Deployment completed! Contract addresses saved to contract_addresses.json" 