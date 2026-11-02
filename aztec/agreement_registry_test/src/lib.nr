use agreement_registry_contract::CyberAgreementRegistry;
use agreement_registry_contract::agreement::{Agreement, MAX_PARTIES};
use aztec::{
    messages::processing::offchain::MAX_OFFCHAIN_MESSAGES_PER_RECEIVE_CALL,
    protocol::{address::AztecAddress, traits::FromField},
    test::helpers::{
        authwit::add_private_authwit_from_call,
        test_environment::{CallPrivateOptions, TestEnvironment},
    },
};

global TERMS_HASH: Field = 0x1234;
global SALT: Field = 0x5678;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let creator = env.create_contract_account();
    let counterparty = env.create_light_account();
    let registry = env.deploy("@agreement_registry_contract/CyberAgreementRegistry").without_initializer();
    (env, registry, creator, counterparty)
}

fn two_party(creator: AztecAddress, counterparty: AztecAddress) -> Agreement {
    let mut parties = [AztecAddress::zero(); MAX_PARTIES];
    parties[0] = creator;
    parties[1] = counterparty;
    Agreement { terms_hash: TERMS_HASH, salt: SALT, expiry: 0, party_count: 2, parties }
}

unconstrained fn create(env: TestEnvironment, registry: AztecAddress, from: AztecAddress, agreement: Agreement) -> Field {
    env.call_private(
        from,
        CyberAgreementRegistry::at(registry).create_bound_contract_and_sign_for(agreement.parties[0], agreement, 0),
    )
}

#[test]
unconstrained fn creator_signs_and_each_party_gets_a_message() {
    let (env, registry, creator, counterparty) = setup();
    let agreement = two_party(creator, counterparty);

    let agreement_id = create(env, registry, creator, agreement);
    let messages = env.offchain_messages();

    assert_eq(agreement_id, env.execute_utility(CyberAgreementRegistry::at(registry).agreement_id(agreement)));
    assert(env.execute_utility(CyberAgreementRegistry::at(registry).is_signed(agreement, creator)));
    assert(!env.execute_utility(CyberAgreementRegistry::at(registry).is_signed(agreement, counterparty)));

    assert_eq(messages.len(), 2);
    assert_eq(messages.get(0).recipient, creator);
    assert_eq(messages.get(1).recipient, counterparty);

    let mut batch: BoundedVec<_, MAX_OFFCHAIN_MESSAGES_PER_RECEIVE_CALL> = BoundedVec::new();
    batch.push(messages.get(1));
    env.execute_utility(CyberAgreementRegistry::at(registry).offchain_receive(batch));
}

#[test]
unconstrained fn single_party_agreement() {
    let (env, registry, creator, _) = setup();
    let mut parties = [AztecAddress::zero(); MAX_PARTIES];
    parties[0] = creator;
    let agreement = Agreement { terms_hash: TERMS_HASH, salt: SALT, expiry: 0, party_count: 1, parties };

    let _ = create(env, registry, creator, agreement);
    let messages = env.offchain_messages();

    assert(env.execute_utility(CyberAgreementRegistry::at(registry).is_signed(agreement, creator)));
    assert_eq(messages.len(), 1);
    assert_eq(messages.get(0).recipient, creator);
}

#[test]
unconstrained fn future_expiry_is_accepted() {
    let (env, registry, creator, counterparty) = setup();
    let mut agreement = two_party(creator, counterparty);
    agreement.expiry = env.last_block_timestamp() + 3600;

    let _ = create(env, registry, creator, agreement);

    assert(env.execute_utility(CyberAgreementRegistry::at(registry).is_signed(agreement, creator)));
}

#[test]
unconstrained fn other_salt_gives_other_agreement() {
    let (env, registry, creator, counterparty) = setup();
    let agreement = two_party(creator, counterparty);
    let mut other = agreement;
    other.salt = SALT + 1;

    let first_id = create(env, registry, creator, agreement);
    let other_id = create(env, registry, creator, other);

    assert(first_id != other_id);
}

// The delegate runs in the PXE of `creator`, for example an app contract that composes this call. The authwit check
// reads the account note of `creator`, so that scope must be available.
#[test]
unconstrained fn delegate_signs_with_authwit() {
    let (mut env, registry, creator, _) = setup();
    let delegate = env.create_light_account();
    let counterparty = env.create_light_account();
    let agreement = two_party(creator, counterparty);
    let call = CyberAgreementRegistry::at(registry).create_bound_contract_and_sign_for(creator, agreement, 1);
    add_private_authwit_from_call(env, creator, delegate, call);

    let _ = env.call_private_opts(delegate, CallPrivateOptions::new().with_additional_scopes([creator]), call);

    assert(env.execute_utility(CyberAgreementRegistry::at(registry).is_signed(agreement, creator)));
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_delegate_has_no_authwit() {
    let (mut env, registry, creator, counterparty) = setup();
    let delegate = env.create_light_account();
    let agreement = two_party(creator, counterparty);

    let _ = env.call_private_opts(
        delegate,
        CallPrivateOptions::new().with_additional_scopes([creator]),
        CyberAgreementRegistry::at(registry).create_bound_contract_and_sign_for(creator, agreement, 1),
    );
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_created_twice() {
    let (env, registry, creator, counterparty) = setup();
    let agreement = two_party(creator, counterparty);

    let _ = create(env, registry, creator, agreement);
    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "signer is not the creator")]
unconstrained fn revert_if_signer_is_not_creator() {
    let (env, registry, creator, counterparty) = setup();
    let agreement = two_party(creator, counterparty);

    let _ = env.call_private(
        counterparty,
        CyberAgreementRegistry::at(registry).create_bound_contract_and_sign_for(counterparty, agreement, 0),
    );
}

#[test(should_fail_with = "terms hash is zero")]
unconstrained fn revert_if_terms_hash_is_zero() {
    let (env, registry, creator, counterparty) = setup();
    let mut agreement = two_party(creator, counterparty);
    agreement.terms_hash = 0;

    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "invalid party count")]
unconstrained fn revert_if_party_count_is_zero() {
    let (env, registry, creator, counterparty) = setup();
    let mut agreement = two_party(creator, counterparty);
    agreement.party_count = 0;

    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "invalid party count")]
unconstrained fn revert_if_party_count_is_above_max() {
    let (env, registry, creator, counterparty) = setup();
    let mut agreement = two_party(creator, counterparty);
    agreement.party_count = MAX_PARTIES + 1;

    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "party is zero address")]
unconstrained fn revert_if_party_is_zero() {
    let (env, registry, creator, _) = setup();
    let agreement = two_party(creator, AztecAddress::zero());

    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "duplicate party")]
unconstrained fn revert_if_party_is_duplicate() {
    let (env, registry, creator, _) = setup();
    let agreement = two_party(creator, creator);

    let _ = create(env, registry, creator, agreement);
}

#[test(should_fail_with = "unused party slot is not zero")]
unconstrained fn revert_if_unused_slot_is_set() {
    let (env, registry, creator, counterparty) = setup();
    let mut agreement = two_party(creator, counterparty);
    agreement.parties[2] = AztecAddress::from_field(0x99);

    let _ = create(env, registry, creator, agreement);
}
