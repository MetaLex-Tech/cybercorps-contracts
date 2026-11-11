use crate::cert::{Cert, Config};
use crate::LedgerEntryToken;
use aztec::{
    authwit::auth::compute_authwit_message_hash,
    protocol::{address::AztecAddress, constants::MAX_TX_LIFETIME},
    test::helpers::{
        test_environment::{CallPrivateOptions, DeployOptions, ExecuteUtilityOptions, TestEnvironment},
        txe_oracles,
    },
};
use borg_auth_v2_contract::{BorgAuthV2, roles::one_officer};

pub(crate) global SALT: Field = 0x5a17;
// EVM `SecurityClass.CommonStock` and `SecuritySeries.NA`.
pub(crate) global COMMON_STOCK: u8 = 6;
pub(crate) global SERIES_NA: u8 = 8;

pub(crate) global UPDATE_DETAILS: u8 = 0;
pub(crate) global VOID: u8 = 1;
pub(crate) global UNVOID: u8 = 2;
pub(crate) global ASSIGN: u8 = 3;

// Private authwits need account contracts, so the officer and the holders are contract accounts. A TXE contract
// account keeps its signing key in a note, so each settler call gets the scopes of the signers.
pub(crate) struct Fixture {
    pub(crate) env: TestEnvironment,
    pub(crate) token: AztecAddress,
    pub(crate) config: Config,
    pub(crate) settler: AztecAddress,
    pub(crate) root: AztecAddress,
    // The initial officer of the company auth.
    pub(crate) officer: AztecAddress,
    pub(crate) alice: AztecAddress,
    pub(crate) bob: AztecAddress,
}

pub(crate) unconstrained fn setup() -> Fixture {
    let mut env = TestEnvironment::new();
    let root = env.create_light_account();
    let officer = env.create_contract_account();
    let alice = env.create_contract_account();
    let bob = env.create_contract_account();
    let settler = env.create_light_account();
    let auth = deploy_auth(&mut env, settler, root, officer);
    let config = class_config(auth);
    let token = deploy_token(&mut env, config);
    Fixture { env, token, config, settler, root, officer, alice, bob }
}

pub(crate) fn class_config(auth: AztecAddress) -> Config {
    Config { auth, security_type: COMMON_STOCK, security_series: SERIES_NA, blinding: 0xb11d }
}

pub(crate) unconstrained fn deploy_auth(
    env: &mut TestEnvironment,
    deployer: AztecAddress,
    root: AztecAddress,
    officer: AztecAddress,
) -> AztecAddress {
    env.deploy("@borg_auth_v2_contract/BorgAuthV2").with_public_initializer(
        deployer,
        BorgAuthV2::interface().constructor(root, one_officer(officer)),
    )
}

// The token has no initializer. Its immutables hash commits to the config.
pub(crate) unconstrained fn deploy_token(env: &mut TestEnvironment, config: Config) -> AztecAddress {
    env
        .deploy_opts(DeployOptions::new().with_immutables_hash(config.immutables_hash()), "LedgerEntryToken")
        .without_initializer()
}

pub(crate) unconstrained fn pass_role_delay(env: TestEnvironment) {
    env.advance_next_block_timestamp_by(MAX_TX_LIFETIME);
    env.mine_block();
}

pub(crate) fn cert(token_id: Field, holder: AztecAddress) -> Cert {
    Cert {
        token_id,
        holder,
        units: 1000,
        investment_amount: 50000,
        valuation: 10000000,
        issue_date: 1762732800,
        details_hash: 0xd1,
        voided: false,
    }
}

// `signer` signs `inner_hash` offchain. The token is the consumer.
pub(crate) unconstrained fn authorize(env: TestEnvironment, token: AztecAddress, signer: AztecAddress, inner_hash: Field) {
    let (chain_id, version) = env.utility_context(|context| (context.chain_id(), context.version()));
    txe_oracles::add_authwit(signer, compute_authwit_message_hash(token, chain_id, version, inner_hash));
}

pub(crate) unconstrained fn mint(f: Fixture, signer: AztecAddress, cert: Cert, salt: Field) -> Field {
    f.env.call_private_opts(
        f.settler,
        CallPrivateOptions::new().with_additional_scopes([signer]),
        LedgerEntryToken::at(f.token).mint(f.config, signer, cert, salt),
    )
}

pub(crate) unconstrained fn authorize_and_mint(f: Fixture, cert: Cert, salt: Field) -> Field {
    let token = LedgerEntryToken::at(f.token);
    authorize(f.env, f.token, f.officer, f.env.execute_utility(token.mint_hash_of(cert, salt)));
    mint(f, f.officer, cert, salt)
}

pub(crate) unconstrained fn is_current(f: Fixture, cert: Cert, salt: Field) -> bool {
    f.env.execute_utility(LedgerEntryToken::at(f.token).is_current(cert, salt))
}

pub(crate) unconstrained fn is_recorded(f: Fixture, cert: Cert, salt: Field) -> bool {
    f.env.execute_utility(LedgerEntryToken::at(f.token).is_recorded(cert, salt))
}

pub(crate) unconstrained fn possesses(f: Fixture, owner: AztecAddress, token_id: Field) -> bool {
    f.env.execute_utility_opts(
        ExecuteUtilityOptions::new().with_from(owner),
        LedgerEntryToken::at(f.token).possesses(owner, token_id),
    )
}

pub(crate) unconstrained fn change_hash_of(f: Fixture, kind: u8, old: Cert, old_salt: Field, new: Cert, new_salt: Field) -> Field {
    let token = LedgerEntryToken::at(f.token);
    if kind == UPDATE_DETAILS {
        f.env.execute_utility(token.update_details_hash_of(old, old_salt, new, new_salt))
    } else if kind == VOID {
        f.env.execute_utility(token.void_hash_of(old, old_salt, new, new_salt))
    } else if kind == UNVOID {
        f.env.execute_utility(token.unvoid_hash_of(old, old_salt, new, new_salt))
    } else {
        f.env.execute_utility(token.assign_hash_of(old, old_salt, new, new_salt))
    }
}

// The old holder is in scope because `assign` checks its endorsement.
pub(crate) unconstrained fn change(
    f: Fixture,
    kind: u8,
    signer: AztecAddress,
    old: Cert,
    old_salt: Field,
    new: Cert,
    new_salt: Field,
) -> Field {
    let opts = CallPrivateOptions::new().with_additional_scopes([signer, old.holder]);
    let token = LedgerEntryToken::at(f.token);
    let config = f.config;
    if kind == UPDATE_DETAILS {
        f.env.call_private_opts(f.settler, opts, token.update_details(config, signer, old, old_salt, new, new_salt))
    } else if kind == VOID {
        f.env.call_private_opts(f.settler, opts, token.void(config, signer, old, old_salt, new, new_salt))
    } else if kind == UNVOID {
        f.env.call_private_opts(f.settler, opts, token.unvoid(config, signer, old, old_salt, new, new_salt))
    } else {
        f.env.call_private_opts(f.settler, opts, token.assign(config, signer, old, old_salt, new, new_salt))
    }
}

pub(crate) unconstrained fn endorse(f: Fixture, old: Cert, old_salt: Field, new_holder: AztecAddress) {
    let hash = f.env.execute_utility(LedgerEntryToken::at(f.token).endorse_hash_of(old, old_salt, new_holder));
    authorize(f.env, f.token, old.holder, hash);
}

// The officer authorizes the change. For `ASSIGN`, the old holder also endorses the certificate to the new holder.
pub(crate) unconstrained fn authorize_and_change(
    f: Fixture,
    kind: u8,
    old: Cert,
    old_salt: Field,
    new: Cert,
    new_salt: Field,
) -> Field {
    authorize(f.env, f.token, f.officer, change_hash_of(f, kind, old, old_salt, new, new_salt));
    if kind == ASSIGN {
        endorse(f, old, old_salt, new.holder);
    }
    change(f, kind, f.officer, old, old_salt, new, new_salt)
}
