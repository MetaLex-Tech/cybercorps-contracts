mod test;

use aztec::macros::aztec;

/// The permission list for MetaLeX contracts, like the EVM `BorgAuthV2`. The state is public.
///
/// This version has the root and one permission, `APPROVE_UPGRADE`. A later version adds the roles and the other
/// permissions of the EVM contract by an upgrade. Each new version must keep the storage variables in this order and
/// add new variables after them. It must also keep `require_permission` and the permission values, because other
/// contracts call it.
///
/// To stop all upgrades of this contract, upgrade it to a version that has no `update_to`.
#[aztec]
pub contract BorgAuthV2 {
    use aztec::{
        macros::{functions::{external, initializer, internal, view}, storage::storage},
        protocol::{
            address::AztecAddress, constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
        },
        state_vars::PublicMutable,
    };
    use contract_instance_registry::ContractInstanceRegistry;

    /// The EVM uses the keccak256 of the name. A bytes32 does not fit in a Field, so each permission is a number.
    pub global APPROVE_UPGRADE: Field = 1;

    #[storage]
    struct Storage<Context> {
        root_authority: PublicMutable<AztecAddress, Context>,
        pending_root_authority: PublicMutable<AztecAddress, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(root: AztecAddress) {
        assert(!root.is_zero(), "BorgAuthV2: zero address");
        self.storage.root_authority.write(root);
    }

    /// Root alone holds `APPROVE_UPGRADE`.
    #[internal("public")]
    fn holds(permission: Field, account: AztecAddress) -> bool {
        (permission == APPROVE_UPGRADE) & (account == self.storage.root_authority.read())
    }

    #[external("public")]
    #[view]
    fn has_permission(permission: Field, account: AztecAddress) -> bool {
        self.internal.holds(permission, account)
    }

    #[external("public")]
    #[view]
    fn require_permission(permission: Field, account: AztecAddress) {
        assert(self.internal.holds(permission, account), "BorgAuthV2: permission denied");
    }

    #[external("public")]
    #[view]
    fn root_authority() -> AztecAddress {
        self.storage.root_authority.read()
    }

    #[external("public")]
    #[view]
    fn pending_root_authority() -> AztecAddress {
        self.storage.pending_root_authority.read()
    }

    /// A zero nominee cancels the proposal. The root itself is never zero.
    #[external("public")]
    fn propose_root_transfer(nominee: AztecAddress) {
        let root = self.storage.root_authority.read();
        assert(self.msg_sender() == root, "BorgAuthV2: unauthorized");
        assert(nominee != root, "BorgAuthV2: nominee is root");
        self.storage.pending_root_authority.write(nominee);
    }

    #[external("public")]
    fn accept_root_transfer() {
        let nominee = self.storage.pending_root_authority.read();
        assert(!nominee.is_zero() & (self.msg_sender() == nominee), "BorgAuthV2: unauthorized");
        self.storage.root_authority.write(nominee);
        self.storage.pending_root_authority.write(AztecAddress::zero());
    }

    /// Schedules an upgrade of this contract to `new_class_id`. The upgrade takes effect after the default upgrade
    /// delay.
    #[external("public")]
    fn update_to(new_class_id: ContractClassId) {
        assert(self.internal.holds(APPROVE_UPGRADE, self.msg_sender()), "BorgAuthV2: permission denied");
        self.call(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(new_class_id));
    }
}
