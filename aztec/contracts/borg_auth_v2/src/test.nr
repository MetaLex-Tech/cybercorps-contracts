use crate::BorgAuthV2;
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{address::AztecAddress, contract_class_id::ContractClassId},
    test::helpers::test_environment::TestEnvironment,
};

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let auth = env.deploy("BorgAuthV2").with_public_initializer(root, BorgAuthV2::interface().constructor(root));
    (env, auth, root)
}

unconstrained fn can_upgrade(env: TestEnvironment, auth: AztecAddress, account: AztecAddress) -> bool {
    env.view_public(BorgAuthV2::at(auth).has_permission(BorgAuthV2::APPROVE_UPGRADE, account))
}

unconstrained fn transfer_root(env: TestEnvironment, auth: AztecAddress, root: AztecAddress, nominee: AztecAddress) {
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));
    env.call_public(nominee, BorgAuthV2::at(auth).accept_root_transfer());
}

#[test]
unconstrained fn initializer_sets_the_root() {
    let (mut env, auth, root) = setup();
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
        BorgAuthV2::interface().constructor(AztecAddress::zero()),
    );
}

#[test(should_fail_with = "duplicate")]
unconstrained fn second_initialize_fails() {
    let (env, auth, root) = setup();

    env.call_public(root, BorgAuthV2::at(auth).constructor(root));
}

#[test]
unconstrained fn root_has_no_unknown_permission() {
    let (env, auth, root) = setup();

    assert(!env.view_public(BorgAuthV2::at(auth).has_permission(2, root)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn require_permission_fails_for_a_non_root() {
    let (mut env, auth, _) = setup();
    let other = env.create_light_account();

    env.view_public(BorgAuthV2::at(auth).require_permission(BorgAuthV2::APPROVE_UPGRADE, other));
}

#[test]
unconstrained fn root_transfer_moves_the_permission() {
    let (mut env, auth, root) = setup();
    let new_root = env.create_light_account();

    transfer_root(env, auth, root, new_root);

    assert_eq(env.view_public(BorgAuthV2::at(auth).root_authority()), new_root);
    assert_eq(env.view_public(BorgAuthV2::at(auth).pending_root_authority()), AztecAddress::zero());
    assert(can_upgrade(env, auth, new_root));
    assert(!can_upgrade(env, auth, root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn old_root_cannot_propose_after_transfer() {
    let (mut env, auth, root) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn non_root_cannot_propose() {
    let (mut env, auth, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuthV2::at(auth).propose_root_transfer(other));
}

#[test(should_fail_with = "BorgAuthV2: nominee is root")]
unconstrained fn root_cannot_nominate_itself() {
    let (env, auth, root) = setup();

    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(root));
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn non_nominee_cannot_accept() {
    let (mut env, auth, root) = setup();
    let nominee = env.create_light_account();
    let other = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));

    env.call_public(other, BorgAuthV2::at(auth).accept_root_transfer());
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn replaced_nominee_cannot_accept() {
    let (mut env, auth, root) = setup();
    let first = env.create_light_account();
    let second = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(first));
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(second));

    env.call_public(first, BorgAuthV2::at(auth).accept_root_transfer());
}

#[test(should_fail_with = "BorgAuthV2: unauthorized")]
unconstrained fn cancelled_nominee_cannot_accept() {
    let (mut env, auth, root) = setup();
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
    let (env, auth, root) = setup();

    env.call_public(root, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn non_root_cannot_upgrade() {
    let (mut env, auth, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn old_root_cannot_upgrade_after_transfer() {
    let (mut env, auth, root) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(root, BorgAuthV2::at(auth).update_to(any_class_id(env, auth)));
}
