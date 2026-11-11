use aztec::{
    authwit::auth::compute_inner_authwit_hash,
    protocol::{
        address::AztecAddress,
        hash::{poseidon2_hash_bytes, poseidon2_hash_with_separator},
        traits::{Deserialize, Serialize, ToField},
    },
};

global CONFIG_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.let.config.v1".as_bytes()) };
global VERSION_ID_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.let.version.v1".as_bytes()) };
global RECORDED_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.let.recorded.v1".as_bytes()) };
global SUPERSEDED_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.let.superseded.v1".as_bytes()) };
global MINTED_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.let.minted.v1".as_bytes()) };
pub global MINT_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.mint.v1".as_bytes()) };
pub global UPDATE_DETAILS_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.update_details.v1".as_bytes()) };
pub global VOID_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.void.v1".as_bytes()) };
pub global UNVOID_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.unvoid.v1".as_bytes()) };
pub global ASSIGN_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.assign.v1".as_bytes()) };
pub global ENDORSE_ACTION: Field = comptime { poseidon2_hash_bytes("metalex.let.endorse.v1".as_bytes()) };

/// The immutables of one security class. The contract address holds `immutables_hash()`.
///
/// Other contracts can check `security_type` and `security_series` privately, with `class_of`. The values are the
/// numbers of the EVM `SecurityClass` and `SecuritySeries` enums.
#[derive(Eq, Serialize, Deserialize)]
pub struct Config {
    // The company `BorgAuthV2`. Its root approves upgrades. Its officers act on certificates.
    pub auth: AztecAddress,
    pub security_type: u8,
    pub security_series: u8,
    // A random secret. A published instance shows the immutables hash, and without this field the few possible
    // types and series can be tested against it. Never pass it to a public function.
    pub blinding: Field,
}

impl Config {
    pub fn immutables_hash(self) -> Field {
        poseidon2_hash_with_separator(
            [self.auth.to_field(), self.security_type as Field, self.security_series as Field, self.blinding],
            CONFIG_DOMAIN,
        )
    }
}

/// One version of a certificate in the register. The chain keeps no field of it.
///
/// `holder` is the legal owner of record. It is an Aztec account, because `mint` gives it the possession note.
/// `details_hash` is the hash of the offchain strings: the holder name, the officer name and title, and the legal
/// details.
#[derive(Eq, Serialize, Deserialize)]
pub struct Cert {
    pub token_id: Field,
    pub holder: AztecAddress,
    pub units: Field,
    pub investment_amount: Field,
    pub valuation: Field,
    pub issue_date: u64,
    pub details_hash: Field,
    pub voided: bool,
}

impl Cert {
    pub fn assert_valid(self) {
        assert(!self.holder.is_zero(), "holder is zero");
    }

    /// The `salt` hides the version, so only holders of the salt can find its nullifiers.
    pub fn version_id(self, salt: Field) -> Field {
        poseidon2_hash_with_separator(
            [
                self.token_id, self.holder.to_field(), self.units, self.investment_amount, self.valuation,
                self.issue_date as Field, self.details_hash, self.voided as Field, salt,
            ],
            VERSION_ID_DOMAIN,
        )
    }
}

/// Records that the version exists.
pub fn recorded_nullifier(version_id: Field) -> Field {
    poseidon2_hash_with_separator([version_id], RECORDED_DOMAIN)
}

/// Records that a later version replaced this version.
pub fn superseded_nullifier(version_id: Field) -> Field {
    poseidon2_hash_with_separator([version_id], SUPERSEDED_DOMAIN)
}

/// Records that the class used `token_id`.
pub fn minted_nullifier(token_id: Field) -> Field {
    poseidon2_hash_with_separator([token_id], MINTED_DOMAIN)
}

/// The message that the officer authorizes to mint the version `version_id`.
pub fn mint_hash(version_id: Field) -> Field {
    compute_inner_authwit_hash([MINT_ACTION, version_id])
}

/// The message that the officer authorizes to replace the version `old_id` with `next_id` by `action`.
pub fn change_hash(action: Field, old_id: Field, next_id: Field) -> Field {
    compute_inner_authwit_hash([action, old_id, next_id])
}

/// The message that the legal owner of `old_id` authorizes to endorse the certificate to `new_holder`.
pub fn endorse_hash(old_id: Field, new_holder: AztecAddress) -> Field {
    compute_inner_authwit_hash([ENDORSE_ACTION, old_id, new_holder.to_field()])
}

/// Each change keeps the token id and the issue date.
pub fn assert_change(action: Field, old: Cert, next: Cert) {
    assert(old.token_id == next.token_id, "token id changed");
    assert(old.issue_date == next.issue_date, "issue date changed");
    if action == UPDATE_DETAILS_ACTION {
        assert(old.holder == next.holder, "holder changed");
        assert(old.voided == next.voided, "void status changed");
    } else if action == ASSIGN_ACTION {
        assert(old.voided == next.voided, "void status changed");
    } else {
        let voids = action == VOID_ACTION;
        assert(old.voided != voids, "void status does not allow the action");
        assert(next.voided == voids, "new void status is wrong");
        assert(old.holder == next.holder, "holder changed");
        assert(old.units == next.units, "units changed");
        assert(old.investment_amount == next.investment_amount, "investment amount changed");
        assert(old.valuation == next.valuation, "valuation changed");
        assert(old.details_hash == next.details_hash, "details hash changed");
    }
}
