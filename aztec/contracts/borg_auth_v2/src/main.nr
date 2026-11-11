pub mod roles;
mod test;

use aztec::macros::aztec;

/// The permission list for MetaLeX contracts, like the EVM `BorgAuthV2`. Each company has its own instance, and the
/// company owner is its root.
///
/// The root is in public state. Only public functions read it, for `APPROVE_UPGRADE`.
///
/// The roles are in `DelayedPublicMutable`, so that private functions can read them with
/// `require_permission_private`. A role change takes effect after `ROLE_DELAY`, publicly and privately. The
/// constructor names the root and the initial members. They hold their roles from the start, so a new company can
/// issue at once.
///
/// Each new version must keep the storage variables in this order and add new variables after them. It must also keep
/// `require_permission`, `require_permission_private` and the permission values, because other contracts call them.
///
/// To stop all upgrades of this contract, upgrade it to a version that has no `update_to`.
#[aztec]
pub contract BorgAuthV2 {
    use aztec::{
        macros::{functions::{external, initializer, internal, view}, storage::storage},
        protocol::{
            address::AztecAddress,
            constants::{CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS, MAX_TX_LIFETIME},
            contract_class_id::ContractClassId,
        },
        state_vars::{DelayedPublicMutable, Map, PublicImmutable, PublicMutable},
    };
    use contract_instance_registry::ContractInstanceRegistry;
    use crate::roles::{InitialRoles, MAX_INITIAL_MEMBERS, Member, MEMBER_ROLES, OFFICER, permits, ROOT, roles_of, with_role};

    /// The EVM uses the keccak256 of the name. A bytes32 does not fit in a Field, so each permission is a number.
    pub global APPROVE_UPGRADE: Field = crate::roles::APPROVE_UPGRADE;
    pub global ISSUE_SECURITIES: Field = crate::roles::ISSUE_SECURITIES;
    pub global ADMINISTER_CERTIFICATES: Field = crate::roles::ADMINISTER_CERTIFICATES;

    /// aztec-nr gives this delay as the best for privacy: a private read then does not shorten the tx lifetime.
    global ROLE_DELAY: u64 = MAX_TX_LIFETIME;

    #[storage]
    struct Storage<Context> {
        root_authority: PublicMutable<AztecAddress, Context>,
        pending_root_authority: PublicMutable<AztecAddress, Context>,
        /// The constructor root. It holds `ROOT` at once, without a write to `roles`.
        initial_root: PublicImmutable<AztecAddress, Context>,
        roles: Map<AztecAddress, DelayedPublicMutable<u32, ROLE_DELAY, Context>, Context>,
        /// The constructor members. Each holds its roles at once, without a write to `roles`.
        ///
        /// A write to `roles` takes effect only after `ROLE_DELAY`. So the constructor keeps the initial roles here,
        /// and private functions can read them at once. They apply to an account until its first role change.
        initial_members: PublicImmutable<[Member; MAX_INITIAL_MEMBERS], Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(root: AztecAddress, members: [Member; MAX_INITIAL_MEMBERS]) {
        assert(!root.is_zero(), "BorgAuthV2: zero address");
        for member in members {
            assert(member.roles & !MEMBER_ROLES == 0, "BorgAuthV2: unknown roles");
        }
        self.storage.root_authority.write(root);
        self.storage.initial_root.initialize(root);
        self.storage.initial_members.initialize(members);
    }

    /// Root holds `APPROVE_UPGRADE` at once. The other permissions come from the current roles.
    #[internal("public")]
    fn holds(permission: Field, account: AztecAddress) -> bool {
        if permission == APPROVE_UPGRADE {
            account == self.storage.root_authority.read()
        } else {
            let stored = self.storage.roles.at(account).get_current_value();
            permits(roles_of(account, self.internal.initial_roles(), stored), permission)
        }
    }

    /// An instance of an older class has no initial roles.
    #[internal("public")]
    fn initial_roles() -> InitialRoles {
        let root = if self.storage.initial_root.is_initialized() {
            self.storage.initial_root.read()
        } else {
            AztecAddress::zero()
        };
        let members = if self.storage.initial_members.is_initialized() {
            self.storage.initial_members.read()
        } else {
            [Member::empty(); MAX_INITIAL_MEMBERS]
        };
        InitialRoles { root, members }
    }

    /// Changes one role bit of `account`, on top of the last scheduled value. It takes effect after `ROLE_DELAY`.
    #[internal("public")]
    fn schedule_role(account: AztecAddress, role: u32, enabled: bool) {
        let roles = self.storage.roles.at(account);
        let (stored, _) = roles.get_scheduled_value();
        roles.schedule_value_change(with_role(roles_of(account, self.internal.initial_roles(), stored), role, enabled));
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

    /// The private check. It reads the roles, so `APPROVE_UPGRADE` follows a root transfer after `ROLE_DELAY`.
    #[external("private")]
    #[view]
    fn require_permission_private(permission: Field, account: AztecAddress) {
        let stored = self.storage.roles.at(account).get_current_value();
        let initial =
            InitialRoles { root: self.storage.initial_root.read(), members: self.storage.initial_members.read() };
        let roles = roles_of(account, initial, stored);
        assert(permits(roles, permission), "BorgAuthV2: permission denied");
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

    /// Grants or revokes `OFFICER`. It takes effect after `ROLE_DELAY`.
    #[external("public")]
    fn set_officer(account: AztecAddress, enabled: bool) {
        assert(self.msg_sender() == self.storage.root_authority.read(), "BorgAuthV2: unauthorized");
        assert(!account.is_zero(), "BorgAuthV2: zero address");
        self.internal.schedule_role(account, OFFICER, enabled);
    }

    /// A zero nominee cancels the proposal. The root itself is never zero.
    #[external("public")]
    fn propose_root_transfer(nominee: AztecAddress) {
        let root = self.storage.root_authority.read();
        assert(self.msg_sender() == root, "BorgAuthV2: unauthorized");
        assert(nominee != root, "BorgAuthV2: nominee is root");
        self.storage.pending_root_authority.write(nominee);
    }

    /// The public root changes at once. The `ROOT` role moves after `ROLE_DELAY`.
    #[external("public")]
    fn accept_root_transfer() {
        let nominee = self.storage.pending_root_authority.read();
        assert(!nominee.is_zero() & (self.msg_sender() == nominee), "BorgAuthV2: unauthorized");
        let old_root = self.storage.root_authority.read();
        self.storage.root_authority.write(nominee);
        self.storage.pending_root_authority.write(AztecAddress::zero());
        self.internal.schedule_role(old_root, ROOT, false);
        self.internal.schedule_role(nominee, ROOT, true);
    }

    /// Schedules an upgrade of this contract to `new_class_id`. The upgrade takes effect after the default upgrade
    /// delay.
    #[external("public")]
    fn update_to(new_class_id: ContractClassId) {
        assert(self.internal.holds(APPROVE_UPGRADE, self.msg_sender()), "BorgAuthV2: permission denied");
        self.call(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(new_class_id));
    }
}
