pub mod agreement;

use aztec::macros::aztec;

/// A private agreement registry. The chain keeps no agreement data. It keeps nullifiers only, and these do not show
/// the agreement, the parties or the terms.
#[aztec]
pub contract CyberAgreementRegistry {
    use aztec::{
        authwit::auth::{assert_inner_hash_valid_authwit, compute_authwit_nullifier},
        macros::functions::external,
        oracle::nullifiers::check_nullifier_exists,
        protocol::address::AztecAddress,
    };
    use crate::agreement::{
        Agreement, consent_hash, finalized_nullifier, MAX_PARTIES, padding_nullifier, terms_commitment,
    };

    /// Records that all parties signed `agreement`.
    ///
    /// Each party signs offchain with a private authwit for `consent_hash(agreement_id, party)`. Any account can then
    /// send this call, for example the MetaLeX settler.
    #[external("private")]
    fn finalize(agreement: Agreement) -> Field {
        agreement.assert_valid();

        // The network drops the tx if it is not mined before the expiry.
        if agreement.expiry != 0 {
            self.context.set_expiration_timestamp(agreement.expiry);
        }

        let agreement_id = agreement.id();
        // Each slot adds one nullifier, so the tx does not show the party count.
        for i in 0..MAX_PARTIES {
            if i < agreement.party_count {
                let party = agreement.parties[i];
                assert_inner_hash_valid_authwit(self.context, party, consent_hash(agreement_id, party));
            } else {
                self.context.push_nullifier_unsafe(padding_nullifier(agreement_id, i));
            }
        }
        // A second finalize gives the same nullifier, so the tx fails.
        self.context.push_nullifier_unsafe(finalized_nullifier(agreement_id));

        agreement_id
    }

    /// Withdraws the consent of the caller to `agreement`. After this, `finalize` of `agreement` fails, because it
    /// emits the same authwit nullifier.
    ///
    /// The withdraw tx must be mined before the finalize tx. If both are pending, the sequencer decides the order.
    #[external("private")]
    fn withdraw_consent(agreement: Agreement) {
        let signer = self.msg_sender();
        self.context.push_nullifier_unsafe(compute_authwit_nullifier(signer, consent_hash(agreement.id(), signer)));
    }

    #[external("utility")]
    unconstrained fn terms_commitment_of(terms_hash: Field, salt: Field) -> Field {
        terms_commitment(terms_hash, salt)
    }

    #[external("utility")]
    unconstrained fn agreement_id(agreement: Agreement) -> Field {
        agreement.id()
    }

    /// The message hash that `signer` authorizes to sign `agreement`.
    #[external("utility")]
    unconstrained fn consent_hash_of(agreement: Agreement, signer: AztecAddress) -> Field {
        consent_hash(agreement.id(), signer)
    }

    /// Asks the node if the agreement is finalized. The node sees the queried nullifier.
    #[external("utility")]
    unconstrained fn is_finalized(agreement: Agreement) -> bool {
        check_nullifier_exists(finalized_nullifier(agreement.id()))
    }
}
