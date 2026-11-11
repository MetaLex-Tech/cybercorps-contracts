pub mod cert;
pub mod cert_note;
mod test;

use aztec::macros::aztec;

/// A private ledger entry token for one security class. It keeps two records, as the EVM LET does:
///
/// - The register (legal owner of record): nullifiers only. They do not show the certificate, the holder or the
///   action. An officer of the company `BorgAuthV2` authorizes each change offchain with a private authwit. Any account
///   can then send the call, for example the MetaLeX settler.
/// - Possession: a `CertNote` in the possessor's private set, like an AIP-721 NFT. The possessor, or an account with
///   its authwit, moves it with `transfer`. A transfer does not change the register.
///
/// The contract has no initializer. Its immutables hash commits to the `Config`.
#[aztec]
pub contract LedgerEntryToken {
    use aztec::{
        authwit::auth::assert_inner_hash_valid_authwit,
        macros::{functions::{authorize_once, external, internal, view}, storage::storage},
        messages::delivery::MessageDelivery,
        note::{
            note_getter_options::NoteGetterOptions, note_interface::NoteProperties,
            note_viewer_options::NoteViewerOptions,
        },
        nullifier::utils::compute_nullifier_existence_request,
        oracle::{get_contract_instance::get_contract_instance, nullifiers::check_nullifier_exists},
        protocol::{
            address::AztecAddress, constants::CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS,
            contract_class_id::ContractClassId,
        },
        state_vars::{Owned, PrivateSet},
        utils::comparison::Comparator,
    };
    use borg_auth_v2_contract::BorgAuthV2;
    use contract_instance_registry::ContractInstanceRegistry;
    use crate::cert::{
        ASSIGN_ACTION, assert_change, Cert, change_hash, Config, endorse_hash, mint_hash, minted_nullifier,
        recorded_nullifier, superseded_nullifier, UNVOID_ACTION, UPDATE_DETAILS_ACTION, VOID_ACTION,
    };
    use crate::cert_note::CertNote;

    #[storage]
    struct Storage<Context> {
        possessions: Owned<PrivateSet<CertNote, Context>, Context>,
    }

    /// Records the first version of the certificate `cert.token_id` and gives its holder the possession note. A token
    /// id can be minted once. `signer` must hold `ISSUE_SECURITIES`.
    #[external("private")]
    fn mint(config: Config, signer: AztecAddress, cert: Cert, salt: Field) -> Field {
        self.internal.assert_config(config);
        cert.assert_valid();
        assert(!cert.voided, "new cert is voided");
        let version_id = cert.version_id(salt);
        self.internal.authorize(config, BorgAuthV2::ISSUE_SECURITIES, signer, mint_hash(version_id));
        self.context.push_nullifier_unsafe(minted_nullifier(cert.token_id));
        self.context.push_nullifier_unsafe(recorded_nullifier(version_id));
        self.storage.possessions.at(cert.holder).insert(CertNote { token_id: cert.token_id }).deliver(
            MessageDelivery::onchain_constrained(),
        );
        version_id
    }

    /// Replaces the amounts and the details. The holder and the void status stay the same.
    #[external("private")]
    fn update_details(
        config: Config,
        signer: AztecAddress,
        old: Cert,
        old_salt: Field,
        next: Cert,
        next_salt: Field,
    ) -> Field {
        self.internal.change(UPDATE_DETAILS_ACTION, config, signer, old, old_salt, next, next_salt)
    }

    /// Marks the certificate as voided. All other fields stay the same.
    #[external("private")]
    fn void(config: Config, signer: AztecAddress, old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        self.internal.change(VOID_ACTION, config, signer, old, old_salt, next, next_salt)
    }

    /// Removes the void mark. All other fields stay the same.
    #[external("private")]
    fn unvoid(config: Config, signer: AztecAddress, old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        self.internal.change(UNVOID_ACTION, config, signer, old, old_salt, next, next_salt)
    }

    /// Registers a new legal owner. The old legal owner must endorse the certificate to `next.holder`. The amounts
    /// and the details can also change, as in the EVM `assignCert`. Possession does not move.
    #[external("private")]
    fn assign(config: Config, signer: AztecAddress, old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        let next_id = self.internal.change(ASSIGN_ACTION, config, signer, old, old_salt, next, next_salt);
        assert_inner_hash_valid_authwit(self.context, old.holder, endorse_hash(old.version_id(old_salt), next.holder));
        next_id
    }

    /// Moves possession of `token_id` from `from` to `to`. The register does not change.
    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn transfer(from: AztecAddress, to: AztecAddress, token_id: Field, authwit_nonce: Field) {
        assert(!to.is_zero(), "recipient is zero");
        let notes = self.storage.possessions.at(from).pop_notes(NoteGetterOptions::new()
            .select(CertNote::properties().token_id, Comparator.EQ, token_id)
            .set_limit(1));
        assert(notes.len() == 1, "cert not held");
        self.storage.possessions.at(to).insert(CertNote { token_id }).deliver(MessageDelivery::onchain_constrained());
    }

    /// The security type and series of this class. It fails for a wrong `config`.
    #[external("private")]
    #[view]
    fn class_of(config: Config) -> (u8, u8) {
        self.internal.assert_config(config);
        (config.security_type, config.security_series)
    }

    /// Schedules an upgrade of this class to `new_class_id`. The caller must hold `APPROVE_UPGRADE` in
    /// `config.auth`. The public part receives only `new_class_id`. The instance must be published, and the upgrade
    /// takes effect after the default upgrade delay.
    ///
    /// Each new class must keep the nullifier formulas and the `CertNote`. Otherwise the recorded versions and the
    /// possession notes stop being valid.
    #[external("private")]
    fn update_to(config: Config, new_class_id: ContractClassId) {
        self.internal.assert_config(config);
        self.view(BorgAuthV2::at(config.auth).require_permission_private(
            BorgAuthV2::APPROVE_UPGRADE,
            self.msg_sender(),
        ));
        self.enqueue(ContractInstanceRegistry::at(CONTRACT_INSTANCE_REGISTRY_CONTRACT_ADDRESS).update(new_class_id));
    }

    #[internal("private")]
    fn assert_config(config: Config) {
        assert_eq(
            config.immutables_hash(),
            get_contract_instance(self.address).immutables_hash,
            "config does not match the immutables hash",
        );
    }

    /// `signer` must hold `permission` in `config.auth` and must authorize `inner_hash`.
    #[internal("private")]
    fn authorize(config: Config, permission: Field, signer: AztecAddress, inner_hash: Field) {
        self.view(BorgAuthV2::at(config.auth).require_permission_private(permission, signer));
        assert_inner_hash_valid_authwit(self.context, signer, inner_hash);
    }

    /// The old version must be recorded and must be current. The superseded nullifier of the old version makes a
    /// second change of it fail.
    #[internal("private")]
    fn change(
        action: Field,
        config: Config,
        signer: AztecAddress,
        old: Cert,
        old_salt: Field,
        next: Cert,
        next_salt: Field,
    ) -> Field {
        self.internal.assert_config(config);
        next.assert_valid();
        assert_change(action, old, next);
        let old_id = old.version_id(old_salt);
        let next_id = next.version_id(next_salt);
        self.internal.authorize(
            config,
            BorgAuthV2::ADMINISTER_CERTIFICATES,
            signer,
            change_hash(action, old_id, next_id),
        );
        self.context.assert_nullifier_exists(compute_nullifier_existence_request(
            recorded_nullifier(old_id),
            self.address,
        ));
        self.context.push_nullifier_unsafe(superseded_nullifier(old_id));
        self.context.push_nullifier_unsafe(recorded_nullifier(next_id));
        next_id
    }

    #[external("utility")]
    unconstrained fn immutables_hash_of(config: Config) -> Field {
        config.immutables_hash()
    }

    #[external("utility")]
    unconstrained fn version_id_of(cert: Cert, salt: Field) -> Field {
        cert.version_id(salt)
    }

    /// The message hash that the officer authorizes for `mint`.
    #[external("utility")]
    unconstrained fn mint_hash_of(cert: Cert, salt: Field) -> Field {
        mint_hash(cert.version_id(salt))
    }

    /// The message hash that the officer authorizes for `update_details`.
    #[external("utility")]
    unconstrained fn update_details_hash_of(old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        change_hash(UPDATE_DETAILS_ACTION, old.version_id(old_salt), next.version_id(next_salt))
    }

    /// The message hash that the officer authorizes for `void`.
    #[external("utility")]
    unconstrained fn void_hash_of(old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        change_hash(VOID_ACTION, old.version_id(old_salt), next.version_id(next_salt))
    }

    /// The message hash that the officer authorizes for `unvoid`.
    #[external("utility")]
    unconstrained fn unvoid_hash_of(old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        change_hash(UNVOID_ACTION, old.version_id(old_salt), next.version_id(next_salt))
    }

    /// The message hash that the officer authorizes for `assign`.
    #[external("utility")]
    unconstrained fn assign_hash_of(old: Cert, old_salt: Field, next: Cert, next_salt: Field) -> Field {
        change_hash(ASSIGN_ACTION, old.version_id(old_salt), next.version_id(next_salt))
    }

    /// The message hash that the legal owner of `old` authorizes to endorse the certificate to `new_holder`.
    #[external("utility")]
    unconstrained fn endorse_hash_of(old: Cert, old_salt: Field, new_holder: AztecAddress) -> Field {
        endorse_hash(old.version_id(old_salt), new_holder)
    }

    /// Asks the node if a tx recorded the version. The node sees the queried nullifier.
    #[external("utility")]
    unconstrained fn is_recorded(cert: Cert, salt: Field) -> bool {
        check_nullifier_exists(recorded_nullifier(cert.version_id(salt)))
    }

    /// Asks the node if the version is recorded and no change replaced it. The node sees the queried nullifiers.
    #[external("utility")]
    unconstrained fn is_current(cert: Cert, salt: Field) -> bool {
        let version_id = cert.version_id(salt);
        check_nullifier_exists(recorded_nullifier(version_id))
            & !check_nullifier_exists(superseded_nullifier(version_id))
    }

    /// Asks the node if the class used `token_id`. The node sees the queried nullifier.
    #[external("utility")]
    unconstrained fn is_minted(token_id: Field) -> bool {
        check_nullifier_exists(minted_nullifier(token_id))
    }

    /// Reads the possession notes of `owner` in the PXE. The PXE must have the notes of `owner`.
    #[external("utility")]
    unconstrained fn possesses(owner: AztecAddress, token_id: Field) -> bool {
        let notes = self.storage.possessions.at(owner).view_notes(NoteViewerOptions::new().select(
            CertNote::properties().token_id,
            Comparator.EQ,
            token_id,
        ));
        notes.len() == 1
    }
}
