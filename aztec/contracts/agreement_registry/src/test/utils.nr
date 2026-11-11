use crate::agreement::{Agreement, consent_hash, MAX_PARTIES};
use crate::CyberAgreementRegistry;
use aztec::{
    authwit::auth::compute_authwit_message_hash,
    protocol::{address::AztecAddress, hash::poseidon2_hash, traits::ToField},
    test::helpers::{test_environment::{CallPrivateOptions, DeployOptions, TestEnvironment}, txe_oracles},
};
use borg_auth_v2_contract::{BorgAuthV2, roles::{MAX_INITIAL_MEMBERS, Member}};

pub(crate) global TERMS_COMMITMENT: Field = 0x1234;

// Private authwits need an account contract, so the parties are contract accounts. The settler is any account.
// A TXE contract account keeps its signing key in a note. So the settler call gets the scopes of the parties. The
// local network run uses initializerless accounts and a settler PXE without these scopes.
pub(crate) unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let alice = env.create_contract_account();
    let bob = env.create_contract_account();
    let settler = env.create_light_account();
    let auth = deploy_auth(&mut env, settler);
    let registry = deploy_registry(&mut env, auth);
    (env, registry, alice, bob, settler)
}

pub(crate) unconstrained fn deploy_auth(env: &mut TestEnvironment, root: AztecAddress) -> AztecAddress {
    env.deploy("@borg_auth_v2_contract/BorgAuthV2").with_public_initializer(
        root,
        BorgAuthV2::interface().constructor(root, [Member::empty(); MAX_INITIAL_MEMBERS]),
    )
}

// The registry has no initializer. Its immutables hash holds the auth address.
pub(crate) unconstrained fn deploy_registry(env: &mut TestEnvironment, auth: AztecAddress) -> AztecAddress {
    env
        .deploy_opts(
            DeployOptions::new().with_immutables_hash(poseidon2_hash([auth.to_field()])),
            "CyberAgreementRegistry",
        )
        .without_initializer()
}

pub(crate) fn two_party(alice: AztecAddress, bob: AztecAddress) -> Agreement {
    let mut parties = [AztecAddress::zero(); MAX_PARTIES];
    parties[0] = alice;
    parties[1] = bob;
    Agreement { terms_commitment: TERMS_COMMITMENT, expiry: 0, party_count: 2, parties }
}

// The party signs the consent hash offchain. The registry is the consumer.
pub(crate) unconstrained fn consent(env: TestEnvironment, registry: AztecAddress, party: AztecAddress, agreement: Agreement) {
    let inner_hash = consent_hash(agreement.id(), party);
    let (chain_id, version) = env.utility_context(|context| (context.chain_id(), context.version()));
    txe_oracles::add_authwit(party, compute_authwit_message_hash(registry, chain_id, version, inner_hash));
}

pub(crate) unconstrained fn finalize<let N: u32>(
    env: TestEnvironment,
    registry: AztecAddress,
    from: AztecAddress,
    scopes: [AztecAddress; N],
    agreement: Agreement,
) -> Field {
    env.call_private_opts(
        from,
        CallPrivateOptions::new().with_additional_scopes(scopes),
        CyberAgreementRegistry::at(registry).finalize(agreement),
    )
}

pub(crate) unconstrained fn is_finalized(env: TestEnvironment, registry: AztecAddress, agreement: Agreement) -> bool {
    env.execute_utility(CyberAgreementRegistry::at(registry).is_finalized(agreement))
}
