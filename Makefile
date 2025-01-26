-include .env

.PHONY: all test clean deploy install

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

clean :; forge clean

install :; forge install openzeppelin/openzeppelin-contracts --no-commit && forge install foundry-rs/forge-std@1.8.2 --no-commit && forge install smartcontractkit/chainlink --no-commit

test :; forge test

build :; forge build

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1
