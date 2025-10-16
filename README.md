## DeFiActions Study

> A repo demonstrating the use of [DeFiActions connectors](https://github.com/onflow/FlowActions) to create composable workflows

### Getting started

> :information_source: Be sure to [install Flow CLI](https://developers.flow.com/build/cadence/smart-contracts/testing#install-flow-cli) before continuing

Update the FlowActions submodule

```sh
git submodule update --init --recursive
```

Install dependencies

```sh
flow deps install
```

Run emulator

```sh
flow emulator
```

In another terminal window, run the local setup script

```sh
sh local/setup_emulator.sh
```