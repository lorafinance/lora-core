FROM node:lts

ARG RPC_URL

WORKDIR /app

RUN apt update && apt install -y jq

RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="/root/.foundry/bin:${PATH}"
RUN foundryup

RUN git clone https://github.com/superfluid-finance/protocol-monorepo.git

WORKDIR /app/protocol-monorepo

RUN yarn install
RUN yarn build-for-contracts-dev

WORKDIR /app/protocol-monorepo/packages/ethereum-contracts

COPY docker/truffle-config.js .
COPY docker/.env.superfluid ./.env

WORKDIR /app/setup

COPY docker/superfluid.sh .
RUN chmod +x superfluid.sh

WORKDIR /app/lora
COPY . .
COPY docker/.env.lora ./.env
