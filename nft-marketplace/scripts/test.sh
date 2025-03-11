#!/bin/bash

# Load environment variables and contract addresses
NETWORK="testnet"
WALLET="wallet"
KEYRING_FLAG="--keyring-backend test"
export COREUM_CHAIN_ID="coreum-testnet-1"
export COREUM_DENOM="utestcore"
export COREUM_NODE="https://full-node.testnet-1.coreum.dev:26657"
export COREUM_CHAIN_ID_ARGS="--chain-id=$COREUM_CHAIN_ID"
export COREUM_NODE_ARGS="--node=$COREUM_NODE"

# Load contract addresses
if [ ! -f contract_addresses.json ]; then
    echo "contract_addresses.json not found!"
    exit 1
fi

NFT_CONTRACT=$(jq -r '.nft_contract' contract_addresses.json)
CW20_CONTRACT=$(jq -r '.cw20_contract' contract_addresses.json)
MARKETPLACE_CONTRACT=$(jq -r '.marketplace_contract' contract_addresses.json)
WALLET_ADDRESS=$(cored keys show $WALLET $KEYRING_FLAG -a $COREUM_CHAIN_ID_ARGS)

echo "Testing NFT Marketplace functionality..."

# 1. Mint an NFT
echo "Minting NFT..."
cored tx wasm execute $NFT_CONTRACT '{
  "mint": {
    "token_id": "1",
    "owner": "'$WALLET_ADDRESS'",
    "token_uri": "https://example.com/nft/1"
  }
}' --from $WALLET $KEYRING_FLAG $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS -y --gas auto --gas-adjustment 1.3

# 2. Query NFT info
echo "Querying NFT info..."
cored query wasm contract-state smart $NFT_CONTRACT '{
  "nft_info": {
    "token_id": "1"
  }
}' $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS

# 3. List NFT for sale
echo "Approving NFT for marketplace..."
cored tx wasm execute $NFT_CONTRACT '{
  "approve": {
    "spender": "'$MARKETPLACE_CONTRACT'",
    "token_id": "1"
  }
}' --from $WALLET $KEYRING_FLAG $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS -y --gas auto --gas-adjustment 1.3

echo "Listing NFT on marketplace..."
cored tx wasm execute $MARKETPLACE_CONTRACT '{
  "list_token": {
    "token_id": "1",
    "price": "1000000"
  }
}' --from $WALLET $KEYRING_FLAG $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS -y --gas auto --gas-adjustment 1.3

# 4. Query marketplace listings
echo "Querying marketplace listings..."
cored query wasm contract-state smart $MARKETPLACE_CONTRACT '{
  "get_listings": {}
}' $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS

# 5. Check CW20 token balance
echo "Checking CW20 token balance..."
cored query wasm contract-state smart $CW20_CONTRACT '{
  "balance": {
    "address": "'$WALLET_ADDRESS'"
  }
}' $COREUM_NODE_ARGS $COREUM_CHAIN_ID_ARGS 