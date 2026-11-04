use crate::CyberAgreementRegistry;
use crate::test::utils::{deploy_auth, deploy_registry};
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{address::AztecAddress, contract_class_id::ContractClassId},
    test::helpers::test_environment::TestEnvironment,
};
use borg_auth_v2_contract::BorgAuthV2;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let auth = deploy_auth(&mut env, root);
    let registry = deploy_registry(&mut env, auth);
    (env, auth, registry, root)
}

// Any class id. The TXE rejects all of them, see `root_can_upgrade`.
unconstrained fn new_class_id(env: TestEnvironment, auth: AztecAddress) -> ContractClassId {
    env.utility_context(|_| get_contract_instance(auth).original_contract_class_id)
}

unconstrained fn transfer_root(env: TestEnvironment, auth: AztecAddress, root: AztecAddress, nominee: AztecAddress) {
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));
    env.call_public(nominee, BorgAuthV2::at(auth).accept_root_transfer());
}

// The TXE does not publish contract classes. So the protocol registry rejects the new class with
// "New contract class is not registered". This message shows that the registry auth check passed and that the
// registry called `ContractInstanceRegistry.update`.
#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn root_can_upgrade() {
    let (env, auth, registry, root) = setup();

    env.call_public(root, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn new_root_can_upgrade_after_transfer() {
    let (mut env, auth, registry, root) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(new_root, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn old_root_cannot_upgrade_after_transfer() {
    let (mut env, auth, registry, root) = setup();
    let new_root = env.create_light_account();
    transfer_root(env, auth, root, new_root);

    env.call_public(root, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn non_root_cannot_upgrade() {
    let (mut env, auth, registry, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn pending_nominee_cannot_upgrade() {
    let (mut env, auth, registry, root) = setup();
    let nominee = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(auth).propose_root_transfer(nominee));

    env.call_public(nominee, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "auth does not match the immutables hash")]
unconstrained fn root_of_another_auth_cannot_upgrade() {
    let (mut env, auth, registry, _) = setup();
    let other = env.create_light_account();
    let other_auth = deploy_auth(&mut env, other);

    env.call_public(other, CyberAgreementRegistry::at(registry).update_to(other_auth, new_class_id(env, auth)));
}
