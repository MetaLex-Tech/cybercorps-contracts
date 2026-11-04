pub mod agreement;
mod test;

use aztec::macros::aztec;

/// A private agreement registry. The chain keeps no agreement data. It keeps nullifiers only, and these do not show
/// the agreement, the parties or the terms.
///
/// The registry has no initializer. Its immutables hash is `poseidon2([auth])`, where `auth` is the `BorgAuth`
/// contract that controls upgrades.
#[aztec]
pub contract CyberAgreementRegistry {
    use aztec::{
        authwit::auth::{assert_inner_hash_valid_authwit, compute_authwit_nullifier},
        macros::functions::external,
        oracle::{
            get_contract_instance::get_contract_instance_immutables_hash_avm, nullifiers::check_nullifier_exists,
        },
        protocol::{
            address::AztecAddress, constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId, hash::poseidon2_hash, traits::ToField,
        },
    };
    use borg_auth_contract::BorgAuth;
    use contract_instance_registry::ContractInstanceRegistry;
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

    /// Schedules an upgrade of this registry to `new_class_id`. Only an owner in `auth` can call it. The upgrade
    /// takes effect after the default upgrade delay.
    ///
    /// Each new class must keep the nullifier formulas. Otherwise the finalized agreements and the withdrawn consents
    /// stop being valid.
    #[external("public")]
    fn update_to(auth: AztecAddress, new_class_id: ContractClassId) {
        assert_eq(
            poseidon2_hash([auth.to_field()]),
            get_contract_instance_immutables_hash_avm(self.address).unwrap(),
            "auth does not match the immutables hash",
        );
        self.view(BorgAuth::at(auth).only_role(BorgAuth::OWNER_ROLE, self.msg_sender()));
        self.call(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(new_class_id));
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
