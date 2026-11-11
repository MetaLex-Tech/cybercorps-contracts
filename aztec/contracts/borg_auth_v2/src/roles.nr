use aztec::protocol::{address::AztecAddress, traits::{Deserialize, Packable, Serialize}};

/// The permissions of the EVM `BorgAuthV2` table that the Aztec contracts use. Each is a number, not a keccak256.
pub global APPROVE_UPGRADE: Field = 1;
pub global ISSUE_SECURITIES: Field = 2;
pub global ADMINISTER_CERTIFICATES: Field = 3;

/// Role bits in `roles`. The low bits are the role bits of the EVM `CorporateAuth`. The high bits are for this
/// contract only.
pub global DIRECTOR: u32 = 1 << 0;
pub global OFFICER: u32 = 1 << 1;
pub global BOARD_EXECUTOR: u32 = 1 << 2;
pub global ISSUANCE_MANAGER: u32 = 1 << 3;
pub global DEAL_MANAGER: u32 = 1 << 4;
pub global ROUND_MANAGER: u32 = 1 << 5;
/// The EVM root is an address, not a role. Here it is also a role, so that private functions can read it.
pub global ROOT: u32 = 1 << 30;
/// Marks a value that the contract set. While an account has no such value, it holds its initial roles.
pub global SET: u32 = 1 << 31;
/// The roles that the constructor can give. The root gets `ROOT` from its own argument.
pub global MEMBER_ROLES: u32 = OFFICER;

pub global MAX_INITIAL_MEMBERS: u32 = 4;

/// An unused slot has a zero account.
#[derive(Deserialize, Eq, Packable, Serialize)]
pub struct Member {
    pub account: AztecAddress,
    pub roles: u32,
}

impl Member {
    pub fn empty() -> Self {
        Member { account: AztecAddress::zero(), roles: 0 }
    }
}

/// The members argument for a company with one initial officer.
pub fn one_officer(account: AztecAddress) -> [Member; MAX_INITIAL_MEMBERS] {
    let mut members = [Member::empty(); MAX_INITIAL_MEMBERS];
    members[0] = Member { account, roles: OFFICER };
    members
}

/// The constructor arguments. An instance of an older class has none, so all accounts are zero.
#[derive(Deserialize, Serialize)]
pub struct InitialRoles {
    pub root: AztecAddress,
    pub members: [Member; MAX_INITIAL_MEMBERS],
}

pub fn roles_of(account: AztecAddress, initial: InitialRoles, stored: u32) -> u32 {
    if (stored != 0) | account.is_zero() {
        stored
    } else {
        let mut roles = if account == initial.root { ROOT } else { 0 };
        for member in initial.members {
            if member.account == account {
                roles = roles | member.roles;
            }
        }
        roles
    }
}

pub fn with_role(roles: u32, role: u32, enabled: bool) -> u32 {
    let changed = if enabled { roles | role } else { roles & !role };
    changed | SET
}

/// Root holds `APPROVE_UPGRADE`. An officer holds `ISSUE_SECURITIES` and `ADMINISTER_CERTIFICATES`.
pub fn permits(roles: u32, permission: Field) -> bool {
    if permission == APPROVE_UPGRADE {
        roles & ROOT != 0
    } else if (permission == ISSUE_SECURITIES) | (permission == ADMINISTER_CERTIFICATES) {
        roles & OFFICER != 0
    } else {
        false
    }
}
