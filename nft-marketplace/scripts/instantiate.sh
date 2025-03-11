#!/bin/bash

# Set up network variables
NETWORK="testnet"
WALLET="wallet"
KEYRING_FLAG="--keyring-backend test"
export COREUM_CHAIN_ID="coreum-testnet-1"
export COREUM_DENOM="utestcore"
export COREUM_NODE="https://full-node.testnet-1.coreum.dev:26657"
export COREUM_CHAIN_ID_ARGS="--chain-id=$COREUM_CHAIN_ID"
export COREUM_NODE_ARGS="--node=$COREUM_NODE"

# Get wallet address
WALLET_ADDRESS=$(cored keys show $WALLET $KEYRING_FLAG -a $COREUM_CHAIN_ID_ARGS)

# Code IDs from your deployment
NFT_CODE_ID="2217"
CW20_CODE_ID="2218"
MARKETPLACE_CODE_ID="2219"

# Initialize NFT contract
echo "Initializing NFT contract..."
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
echo "Initializing CW20 contract..."
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

# Initialize Marketplace contract with native_denom
echo "Initializing Marketplace contract..."
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

echo "Instantiation completed! Contract addresses saved to contract_addresses.json" 