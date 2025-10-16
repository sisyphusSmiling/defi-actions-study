import "FungibleToken"
import "MetadataViews"
import "FungibleTokenMetadataViews"

/// Configures the signer's account with the Vault identified by the given identifier.
///
/// @param vaultIdentifier: the identifier of the Vault to configure
///
transaction(vaultIdentifier: String) {

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {

        let vaultData = MetadataViews.resolveContractViewFromTypeIdentifier(
                resourceTypeIdentifier: vaultIdentifier,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as? FungibleTokenMetadataViews.FTVaultData ?? panic("Could not resolve origin Vault data for type \(vaultIdentifier)")

        // Return early if the account already stores a ExampleToken Vault
        if signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath) != nil {
            return
        }

        let vault <- vaultData.createEmptyVault()

        // Create a new Vault and put it in storage
        signer.storage.save(<-vault, to: vaultData.storagePath)

        // Create a public capability to the Vault that exposes the Vault interfaces
        let vaultCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(
            vaultData.storagePath
        )
        signer.capabilities.publish(vaultCap, at: vaultData.metadataPath)

        // Create a public Capability to the Vault's Receiver functionality
        let receiverCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(
            vaultData.storagePath
        )
        signer.capabilities.publish(receiverCap, at: vaultData.receiverPath)
    }
}
