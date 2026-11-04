use crate::agreement::{Agreement, consent_hash, MAX_PARTIES};
use crate::CyberAgreementRegistry;
use crate::test::utils::{consent, finalize, is_finalized, setup, TERMS_COMMITMENT, two_party};
use aztec::protocol::{address::AztecAddress, traits::FromField};

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
