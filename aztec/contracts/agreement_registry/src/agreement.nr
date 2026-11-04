use aztec::{
    authwit::auth::compute_inner_authwit_hash,
    protocol::{
        address::AztecAddress,
        hash::{poseidon2_hash_bytes, poseidon2_hash_with_separator},
        traits::{Deserialize, Serialize, ToField},
    },
};

// Each party adds one authwit check to the finalize tx.
pub global MAX_PARTIES: u32 = 4;

global TERMS_COMMITMENT_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.terms.v1".as_bytes()) };
global AGREEMENT_ID_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.id.v1".as_bytes()) };
global CONSENT_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.consent.v1".as_bytes()) };
global FINALIZED_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.finalized.v1".as_bytes()) };
global PADDING_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.padding.v1".as_bytes()) };

/// The onchain view of an agreement. The legal text and the field values stay offchain.
///
/// `terms_commitment` hides the terms. Only holders of the salt can open it, so the settler can finalize without
/// the terms.
#[derive(Eq, Serialize, Deserialize)]
pub struct Agreement {
    pub terms_commitment: Field,
    // Zero means no expiry.
    pub expiry: u64,
    pub party_count: u32,
    // Slots at and after `party_count` must be zero.
    pub parties: [AztecAddress; MAX_PARTIES],
}

impl Agreement {
    pub fn id(self) -> Field {
        let mut inputs = [0; 3 + MAX_PARTIES];
        inputs[0] = self.terms_commitment;
        inputs[1] = self.expiry as Field;
        inputs[2] = self.party_count as Field;
        for i in 0..MAX_PARTIES {
            inputs[3 + i] = self.parties[i].to_field();
        }
        poseidon2_hash_with_separator(inputs, AGREEMENT_ID_DOMAIN)
    }

    /// One agreement has one valid encoding, so one set of terms gives one id.
    pub fn assert_valid(self) {
        assert(self.terms_commitment != 0, "terms commitment is zero");
        assert((self.party_count >= 1) & (self.party_count <= MAX_PARTIES), "invalid party count");
        for i in 0..MAX_PARTIES {
            if i < self.party_count {
                assert(!self.parties[i].is_zero(), "party is zero address");
                for j in 0..i {
                    assert(self.parties[i] != self.parties[j], "duplicate party");
                }
            } else {
                assert(self.parties[i].is_zero(), "unused party slot is not zero");
            }
        }
    }
}

/// Binds the terms to the salt. `terms_hash` is the hash of the canonical document.
pub fn terms_commitment(terms_hash: Field, salt: Field) -> Field {
    poseidon2_hash_with_separator([terms_hash, salt], TERMS_COMMITMENT_DOMAIN)
}

/// The message that `signer` authorizes to consent to `agreement_id`. It holds the signer, so each party signs a
/// different message.
pub fn consent_hash(agreement_id: Field, signer: AztecAddress) -> Field {
    compute_inner_authwit_hash([CONSENT_DOMAIN, agreement_id, signer.to_field()])
}

/// The nullifier that records that all parties signed `agreement_id`.
pub fn finalized_nullifier(agreement_id: Field) -> Field {
    poseidon2_hash_with_separator([agreement_id], FINALIZED_DOMAIN)
}

/// Fills an unused party slot, so the tx has the same nullifier count for each party count.
pub fn padding_nullifier(agreement_id: Field, slot: u32) -> Field {
    poseidon2_hash_with_separator([agreement_id, slot as Field], PADDING_DOMAIN)
}
