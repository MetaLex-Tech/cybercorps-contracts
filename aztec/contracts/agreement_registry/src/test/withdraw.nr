use crate::agreement::Agreement;
use crate::CyberAgreementRegistry;
use crate::test::utils::{consent, finalize, is_finalized, setup, TERMS_COMMITMENT, two_party};
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};

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
