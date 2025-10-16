import "Burner"
import "FungibleToken"
import "DeFiActions"

/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// THIS CONTRACT IS FOR DEMONSTRATION PURPOSES ONLY AND IS NOT INTENDED FOR PRODUCTION
/// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
///
/// TransmitTokensWorkflow
///
/// A workflow that transmits tokens from a source to a destination based on a maximum amount.
///
access(all) contract TransmitTokensWorkflow {

    /// Transmitter
    ///
    /// A resource that can be used to transmit tokens from a source to a destination
    ///
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

        init (
            tokenOrigin: {DeFiActions.Sink, DeFiActions.Source},
            tokenDestination: {DeFiActions.Sink},
            maxAmount: UFix64?
        ) {
            self.tokenOrigin = tokenOrigin
            self.tokenDestination = tokenDestination
            self.maxAmount = maxAmount
        }

        /// Moves tokens from the tokenOrigin to the tokenDestination based on the maximum amount or the minimum 
        /// available amount. The key unlock by using DeFiActions here is that is allows a single Transmitter to be
        /// useful in executing a wide variety of workflows.
        ///
        /// @return the amount of tokens transmitted
        access(FungibleToken.Withdraw) fun transmitTokens(): UFix64 {
            // assess a non-zero transmission amount
            var transmissionAmount = self._getTransmissionAmount()
            if transmissionAmount == 0.0 {
                return 0.0
            }

            // withdraw tokens from source
            let sourceVault <- self.tokenOrigin.withdrawAvailable(maxAmount: transmissionAmount)
            // double check the amount withdrawn is the same as the transmission amount
            transmissionAmount = sourceVault.balance
            if sourceVault.balance > 0.0 {
                // deposit to inner sink
                let sourceVaultRef = &sourceVault as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
                self.tokenDestination.depositCapacity(from: sourceVaultRef)
            }

            // update transmission amount to the actual amount transferred to the destination
            transmissionAmount = transmissionAmount - sourceVault.balance

            // handle the remaining vault & return
            self._handleRemainingVault(<-sourceVault)
            return transmissionAmount
        }

        /* INTERNAL */
        //
        /// Calculates the amount to transmit as the minimum between the destination's capacity, the origin's available
        /// balance, and the maximum amount (if set).
        ///
        /// @return the amount of tokens to withdraw from the origin
        access(self) fun _getTransmissionAmount(): UFix64 {
            let capacity = self.tokenDestination.minimumCapacity()
            var amount = self.tokenOrigin.minimumAvailable()
            if self.maxAmount != nil {
                amount = amount <= self.maxAmount! ? amount : self.maxAmount! 
            }
            amount = amount <= capacity ? amount : capacity
            return amount
        }

        /// Handles any remaining vault that was withdrawn in excess of what could be handled by the Sink
        ///
        /// @param remainder: the Vault containing the remaining tokens to deposit back into the origin or burn if empty
        access(self) fun _handleRemainingVault(_ remainder: @{FungibleToken.Vault}) {
            if remainder.balance > 0.0 {
                let remainderRef = &remainder as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}
                self.tokenOrigin.depositCapacity(from: remainderRef)
            }
            assert(remainder.balance == 0.0, message: "Could not handle remaining withdrawal amount \(remainder.balance)")
            Burner.burn(<-remainder)
        }
    }

    /// Creates a new Transmitter
    ///
    /// @param tokenOrigin: the source of tokens to transmit
    /// @param tokenDestination: the destination of tokens to transmit
    /// @param maxAmount: the maximum amount of tokens to transmit, if nil, the transmitter will transmit the minimum of the origin's available balance and the destination's capacity
    ///
    /// @return a new Transmitter
    access(all) fun createTransmitter(
        tokenOrigin: {DeFiActions.Sink, DeFiActions.Source},
        tokenDestination: {DeFiActions.Sink},
        maxAmount: UFix64?
    ): @Transmitter {
        return <- create Transmitter(tokenOrigin: tokenOrigin, tokenDestination: tokenDestination, maxAmount: maxAmount)
    }
}
