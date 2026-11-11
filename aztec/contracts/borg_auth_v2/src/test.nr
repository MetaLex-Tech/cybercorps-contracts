use crate::{BorgAuthV2, roles::{self, MAX_INITIAL_MEMBERS, Member, OFFICER, one_officer, ROOT}};
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{address::AztecAddress, constants::MAX_TX_LIFETIME, contract_class_id::ContractClassId},
    test::helpers::test_environment::TestEnvironment,
};

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let officer = env.create_light_account();
    let auth =
        env.deploy("BorgAuthV2").with_public_initializer(root, BorgAuthV2::interface().constructor(root, one_officer(officer)));
    (env, auth, root, officer)
}

unconstrained fn can_upgrade(env: TestEnvironment, auth: AztecAddress, account: AztecAddress) -> bool {
    env.view_public(BorgAuthV2::at(auth).has_permission(BorgAuthV2::APPROVE_UPGRADE, account))
}

unconstrained fn transfer_root(env: TestEnvironment, auth: AztecAddress, root: AztecAddress, nominee: AztecAddress) {
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));
    env.call_public(nominee, BorgAuthV2::at(auth).accept_root_transfer());
}

// The values of the EVM `CorporateAuth` role constants.
#[test]
fn role_bits_match_the_evm() {
    assert_eq(roles::DIRECTOR, 1);
    assert_eq(roles::OFFICER, 2);
    assert_eq(roles::BOARD_EXECUTOR, 4);
    assert_eq(roles::ISSUANCE_MANAGER, 8);
    assert_eq(roles::DEAL_MANAGER, 16);
    assert_eq(roles::ROUND_MANAGER, 32);
}

#[test]
unconstrained fn initializer_sets_the_root() {
    let (mut env, auth, root, _) = setup();
    let other = env.create_light_account();

    assert_eq(env.view_public(BorgAuthV2::at(auth).root_authority()), root);
    assert(can_upgrade(env, auth, root));
    assert(!can_upgrade(env, auth, other));
    env.view_public(BorgAuthV2::at(auth).require_permission(BorgAuthV2::APPROVE_UPGRADE, root));
}

#[test(should_fail_with = "BorgAuthV2: zero address")]
unconstrained fn zero_root_fails() {
    let mut env = TestEnvironment::new();
    let deployer = env.create_light_account();

    let _ = env.deploy("BorgAuthV2").with_public_initializer(
        deployer,
        BorgAuthV2::interface().constructor(AztecAddress::zero(), one_officer(deployer)),
    );
}

#[test(should_fail_with = "BorgAuthV2: unknown roles")]
unconstrained fn initial_root_role_fails() {
    let mut env = TestEnvironment::new();
    let deployer = env.create_light_account();
    let mut members = one_officer(deployer);
    members[0].roles = OFFICER | ROOT;

    let _ = env.deploy("BorgAuthV2").with_public_initializer(
        deployer,
        BorgAuthV2::interface().constructor(deployer, members),
    );
}

#[test]
unconstrained fn auth_without_initial_members_has_no_officer() {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let auth = env.deploy("BorgAuthV2").with_public_initializer(
        root,
        BorgAuthV2::interface().constructor(root, [Member::empty(); MAX_INITIAL_MEMBERS]),
    );

    assert(!is_officer(env, auth, root));
    assert(!is_officer(env, auth, AztecAddress::zero()));
    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, root);
}

#[test]
unconstrained fn each_initial_member_holds_its_roles() {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let first = env.create_light_account();
    let second = env.create_light_account();
    let mut members = one_officer(first);
    members[2] = Member { account: second, roles: OFFICER };
    let auth = env.deploy("BorgAuthV2").with_public_initializer(
        root,
        BorgAuthV2::interface().constructor(root, members),
    );

    assert(is_officer(env, auth, first));
    assert(is_officer(env, auth, second));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, second);
}

#[test(should_fail_with = "duplicate")]
unconstrained fn second_initialize_fails() {
    let (env, auth, root, officer) = setup();

    env.call_public(root, BorgAuthV2::at(auth).constructor(root, one_officer(officer)));
}

#[test]
unconstrained fn root_has_no_unknown_permission() {
    let (env, auth, root, _) = setup();

    assert(!env.view_public(BorgAuthV2::at(auth).has_permission(4, root)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn require_permission_fails_for_a_non_root() {
    let (mut env, auth, _, _) = setup();
    let other = env.create_light_account();

    env.view_public(BorgAuthV2::at(auth).require_permission(BorgAuthV2::APPROVE_UPGRADE, other));
}

#[test]
unconstrained fn root_transfer_moves_the_permission() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();

    transfer_root(env, auth, root, new_root);

    assert_eq(env.view_public(BorgAuthV2::at(auth).root_authority()), new_root);
    assert_eq(env.view_public(BorgAuthV2::at(auth).pending_root_authority()), AztecAddress::zero());
    assert(can_upgrade(env, auth, new_root));
    assert(!can_upgrade(env, auth, root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn old_root_cannot_propose_after_transfer() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn non_root_cannot_propose() {
    let (mut env, auth, _, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuthV2::at(auth).propose_root_transfer(other));
}

#[test(should_fail_with = "BorgAuthV2: nominee is root")]
unconstrained fn root_cannot_nominate_itself() {
    let (env, auth, root, _) = setup();

    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn non_nominee_cannot_accept() {
    let (mut env, auth, root, _) = setup();
    let nominee = env.create_light_account();
    let other = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));

    env.call_public(other, BorgAuthV2::at(auth).accept_root_transfer());
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn replaced_nominee_cannot_accept() {
    let (mut env, auth, root, _) = setup();
    let first = env.create_light_account();
    let second = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(first));
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(second));

    env.call_public(first, BorgAuthV2::at(auth).accept_root_transfer());
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn cancelled_nominee_cannot_accept() {
    let (mut env, auth, root, _) = setup();
    let nominee = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(AztecAddress::zero()));

    env.call_public(nominee, BorgAuthV2::at(auth).accept_root_transfer());
}

// Any class id. The TXE does not publish contract classes, so the protocol registry rejects each new class with
// "New contract class is not registered". This message shows that the auth check passed and that `update_to`
// called `ContractInstanceRegistry.update`.
unconstrained fn any_class_id(env: TestEnvironment, auth: AztecAddress) -> ContractClassId {
    env.utility_context(|_| get_contract_instance(auth).original_contract_class_id)
}

#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn root_can_upgrade() {
    let (env, auth, root, _) = setup();

    env.call_public(root, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn non_root_cannot_upgrade() {
    let (mut env, auth, _, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn old_root_cannot_upgrade_after_transfer() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(root, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}

// The role delay of `BorgAuthV2`.
unconstrained fn pass_role_delay(env: TestEnvironment) {
    env.advance_next_block_timestamp_by(MAX_TX_LIFETIME);
    env.mine_block();
}

unconstrained fn is_officer(env: TestEnvironment, auth: AztecAddress, account: AztecAddress) -> bool {
    env.view_public(BorgAuthV2::at(auth).has_permission(BorgAuthV2::ISSUE_SECURITIES, account))
        & env.view_public(BorgAuthV2::at(auth).has_permission(BorgAuthV2::ADMINISTER_CERTIFICATES, account))
}

unconstrained fn require_private(env: TestEnvironment, auth: AztecAddress, permission: Field, account: AztecAddress) {
    env.view_private(account, BorgAuthV2::at(auth).require_permission_private(permission, account));
}

#[test]
unconstrained fn initial_officer_is_an_officer_at_once() {
    let (mut env, auth, root, officer) = setup();
    let other = env.create_light_account();

    assert(is_officer(env, auth, officer));
    assert(!is_officer(env, auth, root));
    assert(!is_officer(env, auth, other));
    assert(!can_upgrade(env, auth, officer));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
    require_private(env, auth, BorgAuthV2::ADMINISTER_CERTIFICATES, officer);
    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, root);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn root_is_not_a_private_officer() {
    let (env, auth, root, _) = setup();

    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, root);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn initial_officer_cannot_upgrade_privately() {
    let (env, auth, _, officer) = setup();

    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, officer);
}

#[test]
unconstrained fn one_account_can_be_root_and_officer() {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let auth =
        env.deploy("BorgAuthV2").with_public_initializer(owner, BorgAuthV2::interface().constructor(owner, one_officer(owner)));

    assert(is_officer(env, auth, owner));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, owner);
    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, owner);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn other_has_no_private_permission() {
    let (mut env, auth, _, _) = setup();
    let other = env.create_light_account();

    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, other);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn unknown_private_permission_fails() {
    let (env, auth, root, _) = setup();

    require_private(env, auth, 4, root);
}

#[test]
unconstrained fn officer_grant_takes_effect_after_the_delay() {
    let (mut env, auth, root, _) = setup();
    let officer = env.create_light_account();

    env.call_public(root, BorgAuthV2::at(auth).set_officer(officer, true));
    assert(!is_officer(env, auth, officer));

    pass_role_delay(env);
    assert(is_officer(env, auth, officer));
    require_private(env, auth, BorgAuthV2::ADMINISTER_CERTIFICATES, officer);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn officer_grant_is_not_private_before_the_delay() {
    let (mut env, auth, root, _) = setup();
    let officer = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).set_officer(officer, true));

    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn officer_revoke_takes_effect_after_the_delay() {
    let (mut env, auth, root, _) = setup();
    let officer = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).set_officer(officer, true));
    pass_role_delay(env);

    env.call_public(root, BorgAuthV2::at(auth).set_officer(officer, false));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
    pass_role_delay(env);
    assert(!is_officer(env, auth, officer));

    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn root_can_revoke_the_initial_officer() {
    let (env, auth, root, officer) = setup();

    env.call_public(root, BorgAuthV2::at(auth).set_officer(officer, false));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
    pass_role_delay(env);
    assert(!is_officer(env, auth, officer));

    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, officer);
}

#[test]
unconstrained fn root_can_grant_itself_the_officer_role() {
    let (env, auth, root, _) = setup();

    env.call_public(root, BorgAuthV2::at(auth).set_officer(root, true));
    pass_role_delay(env);

    assert(is_officer(env, auth, root));
    require_private(env, auth, BorgAuthV2::ISSUE_SECURITIES, root);
    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, root);
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn non_root_cannot_set_officer() {
    let (mut env, auth, _, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuthV2::at(auth).set_officer(other, true));
}

#[test(should_fail_with = "BorgAuthV2: zero address")]
unconstrained fn officer_cannot_be_zero() {
    let (env, auth, root, _) = setup();

    env.call_public(root, BorgAuthV2::at(auth).set_officer(AztecAddress::zero(), true));
}

#[test]
unconstrained fn root_transfer_moves_the_private_root_after_the_delay() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);
    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, root);

    pass_role_delay(env);

    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, new_root);
    assert(!is_officer(env, auth, root));
    assert(!is_officer(env, auth, new_root));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn new_root_has_no_private_root_before_the_delay() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, new_root);
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn old_root_loses_the_private_root_after_the_delay() {
    let (mut env, auth, root, _) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);
    pass_role_delay(env);

    require_private(env, auth, BorgAuthV2::APPROVE_UPGRADE, root);
}
