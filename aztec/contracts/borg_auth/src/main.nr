mod test;

use aztec::macros::aztec;

/// A role list for MetaLeX contracts, like the EVM `BorgAuth`. Roles are public state. A higher role includes the
/// lower roles.
#[aztec]
pub contract BorgAuth {
    use aztec::{
        macros::{functions::{external, initializer, view}, storage::storage},
        protocol::address::AztecAddress,
        state_vars::{Map, PublicMutable},
    };

    pub global OWNER_ROLE: u8 = 99;
    pub global ADMIN_ROLE: u8 = 98;
    pub global PRIVILEGED_ROLE: u8 = 97;

    #[storage]
    struct Storage<Context> {
        user_roles: Map<AztecAddress, PublicMutable<u8, Context>, Context>,
    }

    #[initializer]
    #[external("public")]
    fn constructor(owner: AztecAddress) {
        self.storage.user_roles.at(owner).write(OWNER_ROLE);
    }

    /// Sets the role of `user`. Only the owner can call it. To swap owners, the owner gives `OWNER_ROLE` to the new
    /// owner, and the new owner sets the role of the old owner to 0.
    #[external("public")]
    fn update_role(user: AztecAddress, role: u8) {
        assert(self.storage.user_roles.at(self.msg_sender()).read() >= OWNER_ROLE, "BorgAuth: not authorized");
        self.storage.user_roles.at(user).write(role);
    }

    /// Fails if the role of `user` is lower than `role`.
    #[external("public")]
    #[view]
    fn only_role(role: u8, user: AztecAddress) {
        assert(self.storage.user_roles.at(user).read() >= role, "BorgAuth: not authorized");
    }

    #[external("public")]
    #[view]
    fn user_role(user: AztecAddress) -> u8 {
        self.storage.user_roles.at(user).read()
    }
}
