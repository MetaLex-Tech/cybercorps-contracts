use crate::cert::mint_hash;
use crate::LedgerEntryToken;
use crate::test::utils::{
    ASSIGN, authorize, authorize_and_change, authorize_and_mint, cert, change, change_hash_of, class_config,
    COMMON_STOCK, deploy_auth, deploy_token, endorse, is_current, is_recorded, mint, pass_role_delay, possesses, SALT,
    SERIES_NA, setup, UNVOID, UPDATE_DETAILS, VOID,
};
use borg_auth_v2_contract::BorgAuthV2;

#[test]
unconstrained fn officer_mints_with_authwit() {
    let f = setup();
    let first = cert(1, f.alice);
    let token = LedgerEntryToken::at(f.token);
    assert(!is_recorded(f, first, SALT));
    assert(!f.env.execute_utility(token.is_minted(1)));

    let version_id = authorize_and_mint(f, first, SALT);

    assert_eq(version_id, f.env.execute_utility(token.version_id_of(first, SALT)));
    assert_eq(mint_hash(version_id), f.env.execute_utility(token.mint_hash_of(first, SALT)));
    assert_eq(f.config.immutables_hash(), f.env.execute_utility(token.immutables_hash_of(f.config)));
    assert(is_recorded(f, first, SALT));
    assert(is_current(f, first, SALT));
    assert(f.env.execute_utility(token.is_minted(1)));
    assert(!f.env.execute_utility(token.is_minted(2)));
    assert(possesses(f, f.alice, 1));
    assert(!possesses(f, f.bob, 1));
}

#[test]
unconstrained fn other_salt_gives_other_version() {
    let f = setup();
    let first = cert(1, f.alice);
    let token = LedgerEntryToken::at(f.token);

    let first_id = f.env.execute_utility(token.version_id_of(first, SALT));
    let other_id = f.env.execute_utility(token.version_id_of(first, SALT + 1));

    assert(first_id != other_id);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_token_id_is_minted_twice() {
    let f = setup();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);

    let _ = authorize_and_mint(f, cert(1, f.bob), SALT + 1);
}

#[test(should_fail_with = "new cert is voided")]
unconstrained fn revert_if_mint_is_voided() {
    let f = setup();
    let mut first = cert(1, f.alice);
    first.voided = true;

    let _ = authorize_and_mint(f, first, SALT);
}

#[test(should_fail_with = "holder is zero")]
unconstrained fn revert_if_holder_is_zero() {
    let f = setup();
    let first = cert(1, std::mem::zeroed());

    let _ = authorize_and_mint(f, first, SALT);
}

#[test]
unconstrained fn update_details_replaces_the_version() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut second = first;
    second.units = 2000;
    second.details_hash = 0xd2;

    let _ = authorize_and_change(f, UPDATE_DETAILS, first, SALT, second, SALT + 1);

    assert(is_recorded(f, first, SALT));
    assert(!is_current(f, first, SALT));
    assert(is_current(f, second, SALT + 1));
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_superseded_version_is_updated() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut second = first;
    second.units = 2000;
    let _ = authorize_and_change(f, UPDATE_DETAILS, first, SALT, second, SALT + 1);
    let mut third = first;
    third.units = 3000;

    let _ = authorize_and_change(f, UPDATE_DETAILS, first, SALT, third, SALT + 2);
}

#[test(should_fail_with = "reading an unknown nullifier")]
unconstrained fn revert_if_old_version_is_not_recorded() {
    let f = setup();
    let first = cert(1, f.alice);
    let mut second = first;
    second.units = 2000;

    let _ = authorize_and_change(f, UPDATE_DETAILS, first, SALT, second, SALT + 1);
}

#[test(should_fail_with = "holder changed")]
unconstrained fn revert_if_update_details_changes_holder() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut second = first;
    second.holder = f.bob;

    let _ = authorize_and_change(f, UPDATE_DETAILS, first, SALT, second, SALT + 1);
}

#[test(should_fail_with = "token id changed")]
unconstrained fn revert_if_change_moves_token_id() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);

    let _ = authorize_and_change(f, ASSIGN, first, SALT, cert(2, f.bob), SALT + 1);
}

#[test]
unconstrained fn void_then_unvoid() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut voided = first;
    voided.voided = true;

    let _ = authorize_and_change(f, VOID, first, SALT, voided, SALT + 1);
    assert(!is_current(f, first, SALT));
    assert(is_current(f, voided, SALT + 1));

    let _ = authorize_and_change(f, UNVOID, voided, SALT + 1, first, SALT + 2);
    assert(!is_current(f, voided, SALT + 1));
    assert(is_current(f, first, SALT + 2));
}

#[test(should_fail_with = "void status does not allow the action")]
unconstrained fn revert_if_unvoid_of_valid_cert() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);

    let _ = authorize_and_change(f, UNVOID, first, SALT, first, SALT + 1);
}

#[test(should_fail_with = "units changed")]
unconstrained fn revert_if_void_changes_units() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut voided = first;
    voided.voided = true;
    voided.units = 1;

    let _ = authorize_and_change(f, VOID, first, SALT, voided, SALT + 1);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_new_version_is_already_recorded() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut voided = first;
    voided.voided = true;
    let _ = authorize_and_change(f, VOID, first, SALT, voided, SALT + 1);

    let _ = authorize_and_change(f, UNVOID, voided, SALT + 1, first, SALT);
}

#[test]
unconstrained fn assign_records_new_holder() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut assigned = first;
    assigned.holder = f.bob;
    assigned.details_hash = 0xd2;

    let _ = authorize_and_change(f, ASSIGN, first, SALT, assigned, SALT + 1);

    assert(!is_current(f, first, SALT));
    assert(is_current(f, assigned, SALT + 1));
    assert(possesses(f, f.alice, 1));
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_assign_has_no_endorsement() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut assigned = first;
    assigned.holder = f.bob;
    authorize(f.env, f.token, f.officer, change_hash_of(f, ASSIGN, first, SALT, assigned, SALT + 1));

    let _ = change(f, ASSIGN, f.officer, first, SALT, assigned, SALT + 1);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_endorsement_names_other_holder() {
    let mut f = setup();
    let carol = f.env.create_contract_account();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut assigned = first;
    assigned.holder = f.bob;
    authorize(f.env, f.token, f.officer, change_hash_of(f, ASSIGN, first, SALT, assigned, SALT + 1));
    endorse(f, first, SALT, carol);

    let _ = change(f, ASSIGN, f.officer, first, SALT, assigned, SALT + 1);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn revert_if_signer_is_not_an_officer() {
    let mut f = setup();
    let other = f.env.create_contract_account();
    let first = cert(1, f.alice);
    authorize(f.env, f.token, other, f.env.execute_utility(LedgerEntryToken::at(f.token).mint_hash_of(first, SALT)));

    let _ = mint(f, other, first, SALT);
}

#[test(should_fail_with = "Message not authorized by account")]
unconstrained fn revert_if_other_account_authorizes() {
    let mut f = setup();
    let other = f.env.create_contract_account();
    let first = cert(1, f.alice);
    authorize(f.env, f.token, other, f.env.execute_utility(LedgerEntryToken::at(f.token).mint_hash_of(first, SALT)));

    let _ = mint(f, f.officer, first, SALT);
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_authwit_is_for_other_action() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    let mut second = first;
    second.holder = f.bob;
    authorize(f.env, f.token, f.officer, change_hash_of(f, UPDATE_DETAILS, first, SALT, second, SALT + 1));

    let _ = change(f, ASSIGN, f.officer, first, SALT, second, SALT + 1);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_authwit_is_replayed() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);

    let _ = mint(f, f.officer, first, SALT);
}

#[test]
unconstrained fn granted_officer_acts_after_the_delay() {
    let mut f = setup();
    let carol = f.env.create_contract_account();
    f.env.call_public(f.root, BorgAuthV2::at(f.config.auth).set_officer(carol, true));
    pass_role_delay(f.env);
    let first = cert(1, f.alice);
    authorize(f.env, f.token, carol, f.env.execute_utility(LedgerEntryToken::at(f.token).mint_hash_of(first, SALT)));

    let _ = mint(f, carol, first, SALT);

    assert(is_current(f, first, SALT));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn revert_if_granted_officer_acts_before_the_delay() {
    let mut f = setup();
    let carol = f.env.create_contract_account();
    f.env.call_public(f.root, BorgAuthV2::at(f.config.auth).set_officer(carol, true));
    let first = cert(1, f.alice);
    authorize(f.env, f.token, carol, f.env.execute_utility(LedgerEntryToken::at(f.token).mint_hash_of(first, SALT)));

    let _ = mint(f, carol, first, SALT);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn revert_if_revoked_officer_acts_after_the_delay() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);
    f.env.call_public(f.root, BorgAuthV2::at(f.config.auth).set_officer(f.officer, false));
    pass_role_delay(f.env);
    let mut voided = first;
    voided.voided = true;

    let _ = authorize_and_change(f, VOID, first, SALT, voided, SALT + 1);
}

#[test]
unconstrained fn class_of_returns_the_committed_type_and_series() {
    let f = setup();

    let (security_type, security_series) =
        f.env.view_private(f.settler, LedgerEntryToken::at(f.token).class_of(f.config));

    assert_eq(security_type, COMMON_STOCK);
    assert_eq(security_series, SERIES_NA);
}

#[test(should_fail_with = "config does not match the immutables hash")]
unconstrained fn revert_if_class_of_gets_other_type() {
    let f = setup();
    let mut config = f.config;
    config.security_type = COMMON_STOCK + 2;

    let _ = f.env.view_private(f.settler, LedgerEntryToken::at(f.token).class_of(config));
}

#[test(should_fail_with = "config does not match the immutables hash")]
unconstrained fn revert_if_config_has_other_series() {
    let mut f = setup();
    f.config.security_series = SERIES_NA + 1;

    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);
}

#[test(should_fail_with = "config does not match the immutables hash")]
unconstrained fn revert_if_config_has_other_blinding() {
    let mut f = setup();
    f.config.blinding = f.config.blinding + 1;

    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);
}

#[test(should_fail_with = "config does not match the immutables hash")]
unconstrained fn revert_if_config_names_other_auth() {
    let mut f = setup();
    let other_root = f.env.create_contract_account();
    let other_auth = deploy_auth(&mut f.env, f.settler, other_root, other_root);
    f.config = class_config(other_auth);
    f.officer = other_root;

    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);
}

#[test]
unconstrained fn same_auth_and_other_type_is_another_class() {
    let mut f = setup();
    let mut preferred = f.config;
    preferred.security_type = COMMON_STOCK + 2;
    let other = deploy_token(&mut f.env, preferred);

    assert(other != f.token);
}
