use crate::BorgAuth;
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let auth = env.deploy("BorgAuth").with_public_initializer(owner, BorgAuth::interface().constructor(owner));
    (env, auth, owner)
}

unconstrained fn role_of(env: TestEnvironment, auth: AztecAddress, user: AztecAddress) -> u8 {
    env.view_public(BorgAuth::at(auth).user_role(user))
}

// The owner swap: the old owner gives the role to the new owner, and the new owner removes the old owner.
unconstrained fn swap_owner(env: TestEnvironment, auth: AztecAddress, old_owner: AztecAddress, new_owner: AztecAddress) {
    env.call_public(old_owner, BorgAuth::at(auth).update_role(new_owner, BorgAuth::OWNER_ROLE));
    env.call_public(new_owner, BorgAuth::at(auth).update_role(old_owner, 0));
}

#[test]
unconstrained fn initializer_sets_the_first_owner() {
    let (mut env, auth, owner) = setup();
    let other = env.create_light_account();

    assert_eq(role_of(env, auth, owner), BorgAuth::OWNER_ROLE);
    assert_eq(role_of(env, auth, other), 0);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn second_initialize_fails() {
    let (env, auth, owner) = setup();

    env.call_public(owner, BorgAuth::at(auth).constructor(owner));
}

#[test]
unconstrained fn only_role_includes_lower_roles() {
    let (mut env, auth, owner) = setup();
    let admin = env.create_light_account();
    let privileged = env.create_light_account();
    env.call_public(owner, BorgAuth::at(auth).update_role(admin, BorgAuth::ADMIN_ROLE));
    env.call_public(owner, BorgAuth::at(auth).update_role(privileged, BorgAuth::PRIVILEGED_ROLE));

    assert_eq(role_of(env, auth, admin), BorgAuth::ADMIN_ROLE);
    env.view_public(BorgAuth::at(auth).only_role(BorgAuth::ADMIN_ROLE, admin));
    env.view_public(BorgAuth::at(auth).only_role(BorgAuth::PRIVILEGED_ROLE, admin));
    env.view_public(BorgAuth::at(auth).only_role(BorgAuth::PRIVILEGED_ROLE, privileged));
    env.view_public(BorgAuth::at(auth).only_role(BorgAuth::ADMIN_ROLE, owner));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn only_role_fails_for_a_lower_role() {
    let (mut env, auth, owner) = setup();
    let privileged = env.create_light_account();
    env.call_public(owner, BorgAuth::at(auth).update_role(privileged, BorgAuth::PRIVILEGED_ROLE));

    env.view_public(BorgAuth::at(auth).only_role(BorgAuth::ADMIN_ROLE, privileged));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn non_owner_cannot_update_role() {
    let (mut env, auth, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuth::at(auth).update_role(other, BorgAuth::OWNER_ROLE));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn admin_cannot_update_role() {
    let (mut env, auth, owner) = setup();
    let admin = env.create_light_account();
    env.call_public(owner, BorgAuth::at(auth).update_role(admin, BorgAuth::ADMIN_ROLE));

    env.call_public(admin, BorgAuth::at(auth).update_role(admin, BorgAuth::OWNER_ROLE));
}

#[test]
unconstrained fn owner_swap_by_grant_and_revoke() {
    let (mut env, auth, owner) = setup();
    let new_owner = env.create_light_account();

    swap_owner(env, auth, owner, new_owner);

    assert_eq(role_of(env, auth, owner), 0);
    assert_eq(role_of(env, auth, new_owner), BorgAuth::OWNER_ROLE);
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn old_owner_cannot_update_role_after_swap() {
    let (mut env, auth, owner) = setup();
    let new_owner = env.create_light_account();
    swap_owner(env, auth, owner, new_owner);

    env.call_public(owner, BorgAuth::at(auth).update_role(owner, BorgAuth::OWNER_ROLE));
}
