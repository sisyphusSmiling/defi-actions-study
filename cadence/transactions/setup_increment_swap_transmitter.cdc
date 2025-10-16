import "FungibleToken"
import "MetadataViews"
import "FungibleTokenMetadataViews"
import "DeFiActions"
import "FungibleTokenConnectors"
import "SwapConnectors"
import "IncrementFiSwapConnectors"

import "TransmitTokensWorkflow"

/// Sets up a token Transmitter that performs a swap, sourcing funds from the Transmitter's origin connector and
/// swapping via the Transmitter's destination sink connector. Swaps along the path setup in
/// local/setup_emulator.sh - [A.0ae53cb6e3f42a79.FlowToken, A.f8d6e0586b0a20c7.TokenA]
/// 
///
/// @param transmitterStoragePath: the storage path of the stored Transmitter
/// @param maxAmount: the maximum amount of tokens to transmit, if nil, the transmitter will transmit the minimum of the origin's available balance and the destination's capacity
///
transaction(
    transmitterStoragePath: StoragePath,
    maxAmount: UFix64?,
    // swapPath: [String] // Could extend this txn to allow for custom swap paths
) {

    let transmitter: @TransmitTokensWorkflow.Transmitter
    let signer: auth(SaveValue) &Account

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, UnpublishCapability, PublishCapability) &Account) {
        // TODO: remove if allowing custom swap paths via txn args
        let swapPath = ["A.0ae53cb6e3f42a79.FlowToken", "A.f8d6e0586b0a20c7.TokenA"]
        
        // capture the account reference to save in execute
        self.signer = signer

        // construct the in & out vault types from the swap path
        assert(swapPath.length >= 2, message: "Swap path must have at least 2 elements")
        let inIdentifier = swapPath[0].concat(".Vault")
        let outIdentifier = swapPath[swapPath.length - 1].concat(".Vault")
        let inVaultType = CompositeType(inIdentifier) ?? panic("Invalid inVault type \(inIdentifier)")
        let outVaultType = CompositeType(outIdentifier) ?? panic("Invalid outVault type \(outIdentifier)")

        // get the storage data for the token type being transmitted
        let inVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: inVaultType.identifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData ?? panic("Could not resolve origin Vault data")
        let outVaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: outVaultType.identifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData ?? panic("Could not resolve destination Vault data")

        // capture the capabilities for the origin Vault
        let originCapability = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            inVaultData.storagePath
        )

        // set up the out Vault if it doesn't exist
        if signer.storage.type(at: inVaultData.storagePath) == nil {
            signer.storage.save(<-inVaultData.createEmptyVault(), to: inVaultData.storagePath)
            let cap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(outVaultData.storagePath)
            signer.capabilities.unpublish(outVaultData.receiverPath)
            signer.capabilities.unpublish(outVaultData.metadataPath)
            signer.capabilities.publish(cap, at: outVaultData.receiverPath)
            signer.capabilities.publish(cap, at: outVaultData.metadataPath)
        }

        // capture the capabilities for the receiver Vault
        let receiverCapability = signer.capabilities.get<&{FungibleToken.Vault}>(
            outVaultData.receiverPath
        )

        // create a shared unique identifier for the origin and destination connectors
        let uniqueID = DeFiActions.createUniqueIdentifier()
        
        // create the origin connector
        let origin = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: originCapability,
            uniqueID: uniqueID
        )
        // create the swapper connector
        let swapper = IncrementFiSwapConnectors.Swapper(
            path: swapPath,
            inVault: inVaultType,
            outVault: outVaultType,
            uniqueID: uniqueID
        )
        // create the SwapSink's inner Sink connector
        let vaultSink = FungibleTokenConnectors.VaultSink(
            max: 10_000.0,
            depositVault: receiverCapability,
            uniqueID: uniqueID
        )
        // create the SwapSink connector - used as the Transmitter's tokenDestination connector
        let swapSink = SwapConnectors.SwapSink(
            swapper: swapper,
            sink: vaultSink,
            uniqueID: uniqueID
        )
        // create the transmitter
        self.transmitter <- TransmitTokensWorkflow.createTransmitter(
            tokenOrigin: origin,
            tokenDestination: swapSink,
            maxAmount: maxAmount
        )
    }

    pre {
        self.signer.storage.type(at: transmitterStoragePath) == nil:
        "Storage path collision at \(transmitterStoragePath)"
    }

    execute {
        // save the transmitter to storage
        self.signer.storage.save(<-self.transmitter, to: transmitterStoragePath)
    }

    post {
        self.signer.storage.type(at: transmitterStoragePath) == Type<@TransmitTokensWorkflow.Transmitter>():
        "Transmitter was not stored to storage path \(transmitterStoragePath)"
    }
}
