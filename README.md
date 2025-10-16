# DeFiActions Study

> A repo demonstrating the use of [DeFiActions connectors](https://github.com/onflow/FlowActions) to create composable
> workflows

## Getting started

> :information_source: Be sure to [install Flow
> CLI](https://developers.flow.com/build/cadence/smart-contracts/testing#install-flow-cli) before continuing

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

## TransmitTokensWorkflow

The [`TransmitTokensWorkflow`](./cadence/contracts/TransmitTokensWorkflow.cdc) contract defines a simple resource
`Transmitter` that performs a simple function `transmitTokens()`. This method will transfer tokens from a `tokenOrigin:
{DeFiActions.Sink, DeFiActions.Source}` to a `tokenDestination: {DeFiActions.Sink}` up to either the capacity of
`tokenDestination` or the configured `maxAmount`.

```cadence
access(all) resource Transmitter {
    /// Provides tokens to move - composite connector so any excess withdrawals can be re-deposited
    access(self) let tokenOrigin: {DeFiActions.Sink, DeFiActions.Source}
    /// Sink to which source tokens are deposited - a SwapSink would swap into a target denomination
    access(self) let tokenDestination: {DeFiActions.Sink}
    /// The amount of tokens to withdraw from tokenOrigin when executed. If `nil`, transmission amount is whatever
    /// the tokenOrigin reports as available. Note that this is the amount of tokens withdrawn, not a dollar value.
    /// If this were taken to production, it might be considered to include a PriceOracle to ensure a dollar value
    /// is transferred on execution instead of a token amount.
    access(self) let maxAmount: UFix64?

    // ...
}
```

While simple enough on its own, the `Transmitter` along with the executing [`transmit_tokens.cdc`
transaction](./cadence/transactions/transmit_tokens.cdc) can be used to execute a variety of DeFi workflows. The variety
and flexibility of this object is highly configurable by choice of DeFiAction connectors - `tokenOrigin` and
`tokenDestination`.


The following two workflows are just two examples of the sorts of workflows that can be composed and preserved for
future execution with existing DeFiActions connectors.

### Simple Transfer Workflow

The simplest DeFiActions workflow to configure in the `Transmitter` is a token transfer. Run the following commands to
configure a FLOW transfer between accounts:

1. Create a recipient account

    ```sh
    flow accounts create # follow the prompts, naming the account `emulator-recipient`
    ```

1. Configure the `Transmitter` to send `10.0` FLOW from the signing `emulator-account` to the account that was just
   created whenever `Transmitter.transmitTokens()` is called:

    ```sh
    flow transactions send cadence/transactions/setup_simple_transmitter.cdc /storage/SimpleFlowTransmitter \
        'A.0ae53cb6e3f42a79.FlowToken.Vault' \
        0xf3fcd2c1a78f5eee \ # should be the address of the account created in step 1.
        10.0
    ```

1. Now you're ready to run the DeFiActions worfklow stored in the new `Transmitter` resource created & stored in step 2.

    ```sh
    flow transactions send cadence/transactions/transmit_tokens.cdc \
        /storage/SimpleFlowTransmitter \
        10.0
    ```

After executing, you should see events denoting the withdrawal of `10.0` FLOW from `0xf8d6e0586b0a20c7` and a deposit to
the recipient's account `0xf3fcd2c1a78f5eee`.

🎉 You've just composed & executed your first DeFiActions workflow! But we can do a bit better...

### IncrementFi Swap Workflow

Let's up the complexity. We'll withdraw FLOW as we originally did, but this time we'll swap via IncrementFi's AMM
protocol ultimately setting up a swap workflow swapping from FLOW to TokenA.

1. Configure the `Transmitter` to swap `10.0` FLOW to TokenA (executed at the price at time of swap) and deposit the
   resulting TokenA to the same account. The transaction args included in this execution configure the `Transmitter` to
   swap `10.0` at a time until the TokenA balance reached `10_000.0` (or the originating FLOW vault runs out).

    ```sh
    flow transactions send cadence/transactions/setup_increment_swap_transmitter.cdc \
        /storage/SwapFlowTransmitter \
        10.0 \
        10000.0
    ```

1. Now you're ready to execute the workflow. We do this by executing the same transaction as in the simple workflow,
   just on a different `Transmitter` in storage.

    ```sh
    flow transactions send cadence/transactions/transmit_tokens.cdc \
        /storage/SwapFlowTransmitter \
        10.0
    ```

Looking at the resulting events, you'll see a similar FLOW withdrawal of `10.0` tokens originating from
`0xf8d6e0586b0a20c7`. But continuing, you'll notice that along the way, the tokens are swapped into TokenA before
ultimately being deposited to `0xf8d6e0586b0a20c7`.

## Building On Your Base

Now that you've run transactions composing a DeFiActions workflow, stored and then that workflow, it's time for you to
extend this basic example. Here are some ideas for how you might extend the simple `Transmitter` to do even more:

1. **Automate Transmission** - Update `Transmitter` to conform to `FlowScheduledTransactions.TransactionHandler` to it
can be used in [scheduled
transactions](https://developers.flow.com/blockchain-development-tutorials/forte/scheduled-transactions/scheduled-transactions-introduction).
Even better if the execution of a scheduled transaction sets up another future execution. This allows any configured
workflow to be run on a time interval, like an onchain cron job!
1. **Onchain DCA Agent** - Assuming you've refactored `Transmitter` for scheduled & recurring execution per the previous
   point, configure the IncrementFi Swap Workflow to create a dollar-cost averaging workflow, swapping one token for
   another on a time interval.
1. **Compound Staking Rewards** - Create a staking reward `{DeFiActions.Sink, DeFiActions.Source}` and a staking
`{DeFiActions.Sink}` and configure the `Transmitter` so that `transmitTokens()` executes an atomic restaking of rewards.
Coupled with scheduled transactions, you've enabled automated compounding for anyone with your configured `Transmitter`.

## Further Reading

- [Flow Actions Tutorials](https://developers.flow.com/blockchain-development-tutorials/forte/flow-actions)
- [Scheduled Transaction Tutorials](https://developers.flow.com/blockchain-development-tutorials/forte/scheduled-transactions)
- [Flow Actions Repo](https://github.com/onflow/FlowActions)