use crate::CyberAgreementRegistry;
use crate::test::utils::{deploy_auth, deploy_registry};
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{address::AztecAddress, contract_class_id::ContractClassId},
    test::helpers::test_environment::TestEnvironment,
};
use borg_auth_contract::BorgAuth;

unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_light_account();
    let auth = deploy_auth(&mut env, owner);
    let registry = deploy_registry(&mut env, auth);
    (env, auth, registry, owner)
}

// Any class id. The TXE rejects all of them, see `owner_can_upgrade`.
unconstrained fn new_class_id(env: TestEnvironment, auth: AztecAddress) -> ContractClassId {
    env.utility_context(|_| get_contract_instance(auth).original_contract_class_id)
}

// The owner swap: the old owner gives the role to the new owner, and the new owner removes the old owner.
unconstrained fn swap_owner(env: TestEnvironment, auth: AztecAddress, old_owner: AztecAddress, new_owner: AztecAddress) {
    env.call_public(old_owner, BorgAuth::at(auth).update_role(new_owner, BorgAuth::OWNER_ROLE));
    env.call_public(new_owner, BorgAuth::at(auth).update_role(old_owner, 0));
}

// The TXE does not publish contract classes. So the protocol registry rejects the new class with
// "New contract class is not registered". This message shows that the registry auth check passed and that the
// registry called `ContractInstanceRegistry.update`.
// The TXE does not publish contract classes. So the protocol registry rejects the new class with
// "New contract class is not registered". This message shows that the registry auth check passed and that the
// registry called `ContractInstanceRegistry.update`.
#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn owner_can_upgrade() {
    let (env, auth, registry, owner) = setup();

    env.call_public(owner, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn new_owner_can_upgrade_after_swap() {
    let (mut env, auth, registry, owner) = setup();
    let new_owner = env.create_light_account();
    swap_owner(env, auth, owner, new_owner);

    env.call_public(new_owner, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn old_owner_cannot_upgrade_after_swap() {
    let (mut env, auth, registry, owner) = setup();
    let new_owner = env.create_light_account();
    swap_owner(env, auth, owner, new_owner);

    env.call_public(owner, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn non_owner_cannot_upgrade() {
    let (mut env, auth, registry, _) = setup();
    let other = env.create_light_account();

    env.call_public(other, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "BorgAuth: not authorized")]
unconstrained fn admin_cannot_upgrade() {
    let (mut env, auth, registry, owner) = setup();
    let admin = env.create_light_account();
    env.call_public(owner, BorgAuth::at(auth).update_role(admin, BorgAuth::ADMIN_ROLE));

    env.call_public(admin, CyberAgreementRegistry::at(registry).update_to(auth, new_class_id(env, auth)));
}

#[test(should_fail_with = "auth does not match the immutables hash")]
unconstrained fn owner_of_another_auth_cannot_upgrade() {
    let (mut env, auth, registry, _) = setup();
    let other = env.create_light_account();
    let other_auth = deploy_auth(&mut env, other);

    env.call_public(other, CyberAgreementRegistry::at(registry).update_to(other_auth, new_class_id(env, auth)));
}
