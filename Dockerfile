FROM node:lts

ARG MEGA_TESTNET_V2_RPC_URL

WORKDIR /app

RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

RUN git clone https://github.com/superfluid-finance/protocol-monorepo.git
WORKDIR /app/protocol-monorepo
RUN yarn install
RUN yarn build-for-contracts-dev || true

WORKDIR /app/protocol-monorepo/packages/ethereum-contracts

COPY docker/truffle-config.js .
COPY docker/.env.example ./.env

RUN anvil --fork-url $MEGA_TESTNET_V2_RPC_URL --silent &

ENV RELEASE_VERSION=v1

RUN cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545

RUN CREATE_NEW_RESOLVER=1 npx truffle exec --network mega-testnet-v2 ops-scripts/deploy-framework.js

