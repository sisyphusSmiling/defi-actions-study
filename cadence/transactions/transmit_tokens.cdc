import "FungibleToken"
import "TransmitTokensWorkflow"

/// Executes a token transmission, optionally checking the expected amount of tokens transmitted. Doing so executes the
/// DeFiActionsworkflow configured within the Transmitter.
///
/// @param storagePath: the storage path of the stored Transmitter
/// @param expectedAmount: the expected amount of tokens to be transmitted, if nil, the transaction will not check the amount
///
transaction(storagePath: StoragePath, expectedAmount: UFix64?) {

    let transmitter: auth(FungibleToken.Withdraw)&TransmitTokensWorkflow.Transmitter
    var actualAmount: UFix64

    prepare(signer: auth(BorrowValue) &Account) {
        // reference the authorized Transmitter from storage
        self.transmitter = signer.storage.borrow<auth(FungibleToken.Withdraw)&TransmitTokensWorkflow.Transmitter>(
            from: storagePath
        ) ?? panic("Could not borrow reference to the Transmitter at \(storagePath)")
        self.actualAmount = 0.0
    }

    execute {
        // execute the token transmission
        self.actualAmount = self.transmitter.transmitTokens()
        log("Transmitted \(self.actualAmount) tokens")
    }

    post {
        expectedAmount == nil || self.actualAmount == expectedAmount!:
        "Transmitted amount \(self.actualAmount) does not match expected amount \(expectedAmount!)"
    }
}
