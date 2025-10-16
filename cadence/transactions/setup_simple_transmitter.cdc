import "FungibleToken"
import "MetadataViews"
import "FungibleTokenMetadataViews"
import "DeFiActions"
import "FungibleTokenConnectors"

import "TransmitTokensWorkflow"

/// Sets up a simple token Transmitter for a given origin and destination type and recipient. Once executed, the
/// the Transmitter can be used to transmit tokens from the origin to the destination by the owner of the Transmitter.
///
/// @param transmitterStoragePath: the storage path of the stored Transmitter
/// @param originType: the type of the origin Vault
/// @param destinationType: the type of the destination Vault
/// @param destinationRecipient: the recipient of the destination Vault
/// @param maxAmount: the maximum amount of tokens to transmit, if nil, the transmitter will transmit the minimum of the origin's available balance and the destination's capacity
///
transaction(
    transmitterStoragePath: StoragePath,
    vaultType: String,
    destinationRecipient: Address,
    maxAmount: UFix64?
) {

    let transmitter: @TransmitTokensWorkflow.Transmitter
    let signer: auth(SaveValue) &Account

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController) &Account) {
        // capture the account reference to save in execute
        self.signer = signer

        // get the storage data for the token type being transmitted
        let vaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: vaultType,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData ?? panic("Could not resolve origin Vault data")

        // capture the capabilities for the origin and destination Vaults
        let originCapability = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            vaultData.storagePath
        )
        let destinationCapability = getAccount(destinationRecipient).capabilities.get<&{FungibleToken.Vault}>(
            vaultData.receiverPath
        )

        // create a shared unique identifier for the origin and destination connectors
        let uniqueID = DeFiActions.createUniqueIdentifier()
        
        // create the origin and destination connectors
        let origin = FungibleTokenConnectors.VaultSinkAndSource(
            min: nil,
            max: nil,
            vault: originCapability,
            uniqueID: uniqueID
        )
        let destinationSink = FungibleTokenConnectors.VaultSink(
            max: nil,
            depositVault: destinationCapability,
            uniqueID: uniqueID
        )

        // create the transmitter
        self.transmitter <- TransmitTokensWorkflow.createTransmitter(
            tokenOrigin: origin,
            tokenDestination: destinationSink,
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
