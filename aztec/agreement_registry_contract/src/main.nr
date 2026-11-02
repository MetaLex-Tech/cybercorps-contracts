pub mod agreement;

use aztec::macros::aztec;

/// A private agreement registry. The chain keeps no agreement data. It keeps only one nullifier per signature and one
/// commitment per event, and these do not show the agreement, the parties or the terms.
#[aztec]
pub contract CyberAgreementRegistry {
    use aztec::{
        macros::{events::event, functions::{authorize_once, external}},
        messages::delivery::MessageDelivery,
        oracle::nullifiers::check_nullifier_exists,
        protocol::address::AztecAddress,
    };
    use crate::agreement::{Agreement, MAX_PARTIES, signature_nullifier};

    /// Tells each party that `signer` signed `agreement`. It carries all the data a party needs to verify and sign.
    #[event]
    struct AgreementSigned {
        agreement: Agreement,
        signer: AztecAddress,
    }

    /// Creates an agreement and records the signature of its creator, `parties[0]`.
    ///
    /// `signer` calls with `authwit_nonce` 0. A delegate calls with an authwit from `signer`.
    #[authorize_once("signer", "authwit_nonce")]
    #[external("private")]
    fn create_bound_contract_and_sign_for(signer: AztecAddress, agreement: Agreement, authwit_nonce: Field) -> Field {
        agreement.assert_valid();
        assert(agreement.parties[0] == signer, "signer is not the creator");

        // The network drops the tx if it is not mined before the expiry.
        if agreement.expiry != 0 {
            self.context.set_expiration_timestamp(agreement.expiry);
        }

        let agreement_id = agreement.id();
        // A second signature or a second creation gives the same nullifier, so the tx fails.
        self.context.push_nullifier_unsafe(signature_nullifier(agreement_id, signer));

        // One event commitment for all parties, so the chain does not show the party count.
        let message = self.emit(AgreementSigned { agreement, signer });
        for i in 0..MAX_PARTIES {
            if i < agreement.party_count {
                message.deliver_to(agreement.parties[i], MessageDelivery::offchain());
            }
        }

        agreement_id
    }

    #[external("utility")]
    unconstrained fn agreement_id(agreement: Agreement) -> Field {
        agreement.id()
    }

    /// Asks the node if the signature exists. The node sees the queried nullifier.
    #[external("utility")]
    unconstrained fn is_signed(agreement: Agreement, signer: AztecAddress) -> bool {
        check_nullifier_exists(signature_nullifier(agreement.id(), signer))
    }
}
