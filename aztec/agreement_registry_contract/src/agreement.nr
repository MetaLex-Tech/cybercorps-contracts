use aztec::protocol::{
    address::AztecAddress,
    hash::{poseidon2_hash_bytes, poseidon2_hash_with_separator},
    traits::{Deserialize, Serialize, ToField},
};

// One private event message holds at most 11 fields. An agreement uses 4 + MAX_PARTIES of them.
pub global MAX_PARTIES: u32 = 4;

global AGREEMENT_ID_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.id.v1".as_bytes()) };
global SIGNATURE_DOMAIN: Field = comptime { poseidon2_hash_bytes("metalex.agreement.signature.v1".as_bytes()) };

/// The onchain view of an agreement. The legal text and the field values stay offchain. `terms_hash` commits to
/// them.
///
/// `salt` is a random secret that the parties share. It keeps the agreement id unknown to everyone else.
#[derive(Eq, Serialize, Deserialize)]
pub struct Agreement {
    pub terms_hash: Field,
    pub salt: Field,
    // Zero means no expiry.
    pub expiry: u64,
    pub party_count: u32,
    // `parties[0]` is the creator. Slots at and after `party_count` must be zero.
    pub parties: [AztecAddress; MAX_PARTIES],
}

impl Agreement {
    pub fn id(self) -> Field {
        let mut inputs = [0; 4 + MAX_PARTIES];
        inputs[0] = self.terms_hash;
        inputs[1] = self.salt;
        inputs[2] = self.expiry as Field;
        inputs[3] = self.party_count as Field;
        for i in 0..MAX_PARTIES {
            inputs[4 + i] = self.parties[i].to_field();
        }
        poseidon2_hash_with_separator(inputs, AGREEMENT_ID_DOMAIN)
    }

    /// One agreement has one valid encoding, so one set of terms gives one id.
    pub fn assert_valid(self) {
        assert(self.terms_hash != 0, "terms hash is zero");
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

/// The nullifier that records the consent of `signer` to `agreement_id`. Only a holder of the agreement id can
/// compute it.
pub fn signature_nullifier(agreement_id: Field, signer: AztecAddress) -> Field {
    poseidon2_hash_with_separator([agreement_id, signer.to_field()], SIGNATURE_DOMAIN)
}
