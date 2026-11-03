use agreement_registry_contract::CyberAgreementRegistry;
use agreement_registry_contract::agreement::{Agreement, consent_hash, MAX_PARTIES};
use aztec::{
    authwit::auth::compute_authwit_message_hash,
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::{test_environment::{CallPrivateOptions, TestEnvironment}, txe_oracles},
};

global TERMS_COMMITMENT: Field = 0x1234;

// Private authwits need an account contract, so the parties are contract accounts. The settler is any account.
// A TXE contract account keeps its signing key in a note. So the settler call gets the scopes of the parties. The
// local network run uses initializerless accounts and a settler PXE without these scopes.
unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let alice = env.create_contract_account();
    let bob = env.create_contract_account();
    let settler = env.create_light_account();
    let registry = env.deploy("@agreement_registry_contract/CyberAgreementRegistry").without_initializer();
    (env, registry, alice, bob, settler)
}

fn two_party(alice: AztecAddress, bob: AztecAddress) -> Agreement {
    let mut parties = [AztecAddress::zero(); MAX_PARTIES];
    parties[0] = alice;
    parties[1] = bob;
    Agreement { terms_commitment: TERMS_COMMITMENT, expiry: 0, party_count: 2, parties }
}

// The party signs the consent hash offchain. The registry is the consumer.
unconstrained fn consent(env: TestEnvironment, registry: AztecAddress, party: AztecAddress, agreement: Agreement) {
    let inner_hash = consent_hash(agreement.id(), party);
    let (chain_id, version) = env.utility_context(|context| (context.chain_id(), context.version()));
    txe_oracles::add_authwit(party, compute_authwit_message_hash(registry, chain_id, version, inner_hash));
}

unconstrained fn finalize<let N: u32>(
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

unconstrained fn is_finalized(env: TestEnvironment, registry: AztecAddress, agreement: Agreement) -> bool {
    env.execute_utility(CyberAgreementRegistry::at(registry).is_finalized(agreement))
}

#[test]
unconstrained fn settler_finalizes_after_all_parties_consent() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);
    assert(!is_finalized(env, registry, agreement));

    let agreement_id = finalize(env, registry, settler, [alice, bob], agreement);

    assert_eq(agreement_id, env.execute_utility(CyberAgreementRegistry::at(registry).agreement_id(agreement)));
    assert_eq(
        consent_hash(agreement_id, bob),
        env.execute_utility(CyberAgreementRegistry::at(registry).consent_hash_of(agreement, bob)),
    );
    assert(is_finalized(env, registry, agreement));
}

#[test]
unconstrained fn single_party_agreement() {
    let (env, registry, alice, _, settler) = setup();
    let mut parties = [AztecAddress::zero(); MAX_PARTIES];
    parties[0] = alice;
    let agreement = Agreement { terms_commitment: TERMS_COMMITMENT, expiry: 0, party_count: 1, parties };
    consent(env, registry, alice, agreement);

    let _ = finalize(env, registry, settler, [alice], agreement);

    assert(is_finalized(env, registry, agreement));
}

#[test]
unconstrained fn future_expiry_is_accepted() {
    let (env, registry, alice, bob, settler) = setup();
    let mut agreement = two_party(alice, bob);
    agreement.expiry = env.last_block_timestamp() + 3600;
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);

    assert(is_finalized(env, registry, agreement));
}

#[test]
unconstrained fn other_terms_give_other_agreement() {
    let (env, registry, alice, bob, _) = setup();
    let agreement = two_party(alice, bob);
    let mut other = agreement;
    other.terms_commitment = TERMS_COMMITMENT + 1;

    let first_id = env.execute_utility(CyberAgreementRegistry::at(registry).agreement_id(agreement));
    let other_id = env.execute_utility(CyberAgreementRegistry::at(registry).agreement_id(other));

    assert(first_id != other_id);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_one_party_did_not_consent() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_consent_is_for_other_agreement() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    let mut other = agreement;
    other.terms_commitment = TERMS_COMMITMENT + 1;
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, other);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_finalized_twice() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "terms commitment is zero")]
unconstrained fn revert_if_terms_commitment_is_zero() {
    let (env, registry, alice, bob, settler) = setup();
    let mut agreement = two_party(alice, bob);
    agreement.terms_commitment = 0;

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "invalid party count")]
unconstrained fn revert_if_party_count_is_zero() {
    let (env, registry, alice, bob, settler) = setup();
    let mut agreement = two_party(alice, bob);
    agreement.party_count = 0;

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "invalid party count")]
unconstrained fn revert_if_party_count_is_above_max() {
    let (env, registry, alice, bob, settler) = setup();
    let mut agreement = two_party(alice, bob);
    agreement.party_count = MAX_PARTIES + 1;

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "party is zero address")]
unconstrained fn revert_if_party_is_zero() {
    let (env, registry, alice, _, settler) = setup();
    let agreement = two_party(alice, AztecAddress::zero());

    let _ = finalize(env, registry, settler, [alice], agreement);
}

#[test(should_fail_with = "duplicate party")]
unconstrained fn revert_if_party_is_duplicate() {
    let (env, registry, alice, _, settler) = setup();
    let agreement = two_party(alice, alice);

    let _ = finalize(env, registry, settler, [alice], agreement);
}

#[test(should_fail_with = "unused party slot is not zero")]
unconstrained fn revert_if_unused_slot_is_set() {
    let (env, registry, alice, bob, settler) = setup();
    let mut agreement = two_party(alice, bob);
    agreement.parties[2] = AztecAddress::from_field(0x99);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

unconstrained fn withdraw(env: TestEnvironment, registry: AztecAddress, party: AztecAddress, agreement: Agreement) {
    env.call_private(party, CyberAgreementRegistry::at(registry).withdraw_consent(agreement));
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_finalized_after_withdraw() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);
    withdraw(env, registry, bob, agreement);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_withdrawn_after_finalize() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);
    let _ = finalize(env, registry, settler, [alice, bob], agreement);

    withdraw(env, registry, bob, agreement);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_withdrawn_twice() {
    let (env, registry, alice, bob, _) = setup();
    let agreement = two_party(alice, bob);
    withdraw(env, registry, bob, agreement);

    withdraw(env, registry, bob, agreement);
}

#[test]
unconstrained fn withdraw_blocks_only_its_agreement() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    let mut other = agreement;
    other.terms_commitment = TERMS_COMMITMENT + 1;
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);
    withdraw(env, registry, bob, other);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);

    assert(is_finalized(env, registry, agreement));
}

#[test]
unconstrained fn non_party_withdraw_does_not_block() {
    let (env, registry, alice, bob, settler) = setup();
    let agreement = two_party(alice, bob);
    consent(env, registry, alice, agreement);
    consent(env, registry, bob, agreement);
    withdraw(env, registry, settler, agreement);

    let _ = finalize(env, registry, settler, [alice, bob], agreement);

    assert(is_finalized(env, registry, agreement));
}
