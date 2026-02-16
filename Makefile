.PHONY: testnet testnet-broadcast

testnet:
	. .env && forge script script/DeployTestnet.s.sol:DeployScript --rpc-url $$TESTNET_RPC_URL --private-keys $$TESTNET_DEPLOYER_PRIVATE_KEY --private-keys $$TESTNET_LP_PRIVATE_KEY -v

testnet-broadcast:
	. .env && forge script script/DeployTestnet.s.sol:DeployScript --rpc-url $$TESTNET_RPC_URL --private-keys $$TESTNET_DEPLOYER_PRIVATE_KEY --private-keys $$TESTNET_LP_PRIVATE_KEY --broadcast --skip-simulation --gas-limit 200000000 -vv

testnet-verify:
	. .env && forge script script/DeployTestnet.s.sol:DeployScript --rpc-url $$TESTNET_RPC_URL --private-keys $$TESTNET_DEPLOYER_PRIVATE_KEY --private-keys $$TESTNET_LP_PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $$TESTNET_BLOCKSCOUT_VERIFIER_URL --skip-simulation --gas-limit 200000000 --resume -vv