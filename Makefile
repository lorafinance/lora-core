.PHONY: testnet testnet-broadcast

testnet:
	. .env && forge script script/DeployTestnet.s.sol:DeployScript --rpc-url $$TESTNET_RPC_URL --private-keys $$TESTNET_DEPLOYER_PRIVATE_KEY --private-keys $$TESTNET_LP_PRIVATE_KEY -v

testnet-broadcast:
	. .env && forge script script/DeployTestnet.s.sol:DeployScript --rpc-url $$TESTNET_RPC_URL --private-keys $$TESTNET_DEPLOYER_PRIVATE_KEY --private-keys $$TESTNET_LP_PRIVATE_KEY --broadcast -vv