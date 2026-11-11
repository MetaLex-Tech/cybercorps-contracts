use crate::cert::Config;
use crate::LedgerEntryToken;
use crate::test::utils::{class_config, deploy_auth, deploy_token, pass_role_delay};
use aztec::{
    oracle::get_contract_instance::get_contract_instance,
    protocol::{address::AztecAddress, contract_class_id::ContractClassId},
    test::helpers::test_environment::TestEnvironment,
};
use borg_auth_v2_contract::BorgAuthV2;

unconstrained fn setup() -> (TestEnvironment, Config, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let officer = env.create_light_account();
    let auth = deploy_auth(&mut env, root, root, officer);
    let config = class_config(auth);
    let token = deploy_token(&mut env, config);
    (env, config, token, root, officer)
}

// Any class id. The TXE rejects all of them, see `root_can_upgrade`.
unconstrained fn new_class_id(env: TestEnvironment, auth: AztecAddress) -> ContractClassId {
    env.utility_context(|_| get_contract_instance(auth).original_contract_class_id)
}

// The TXE does not publish contract classes. So the protocol registry rejects the new class with
// "New contract class is not registered". This message shows that the private auth check passed and that the token
// enqueued `ContractInstanceRegistry.update`.
#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn root_can_upgrade() {
    let (env, config, token, root, _) = setup();

    env.call_private(root, LedgerEntryToken::at(token).update_to(config, new_class_id(env, config.auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn officer_cannot_upgrade() {
    let (env, config, token, _, officer) = setup();

    env.call_private(officer, LedgerEntryToken::at(token).update_to(config, new_class_id(env, config.auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn non_root_cannot_upgrade() {
    let (mut env, config, token, _, _) = setup();
    let other = env.create_light_account();

    env.call_private(other, LedgerEntryToken::at(token).update_to(config, new_class_id(env, config.auth)));
}

#[test(should_fail_with = "config does not match the immutables hash")]
unconstrained fn root_of_another_auth_cannot_upgrade() {
    let (mut env, config, token, _, _) = setup();
    let other = env.create_light_account();
    let other_auth = deploy_auth(&mut env, other, other, other);

    env.call_private(other, LedgerEntryToken::at(token).update_to(class_config(other_auth), new_class_id(env, config.auth)));
}

#[test(should_fail_with = "New contract class is not registered")]
unconstrained fn new_root_can_upgrade_after_the_delay() {
    let (mut env, config, token, root, _) = setup();
    let new_root = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(config.auth).propose_root_transfer(new_root));
    env.call_public(new_root, BorgAuthV2::at(config.auth).accept_root_transfer());
    pass_role_delay(env);

    env.call_private(new_root, LedgerEntryToken::at(token).update_to(config, new_class_id(env, config.auth)));
}

#[test(should_fail_with = "BorgAuthV2: permission denied")]
unconstrained fn new_root_cannot_upgrade_before_the_delay() {
    let (mut env, config, token, root, _) = setup();
    let new_root = env.create_light_account();
    env.call_public(root, BorgAuthV2::at(config.auth).propose_root_transfer(new_root));
    env.call_public(new_root, BorgAuthV2::at(config.auth).accept_root_transfer());

    env.call_private(new_root, LedgerEntryToken::at(token).update_to(config, new_class_id(env, config.auth)));
}
