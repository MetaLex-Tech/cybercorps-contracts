use aztec::{macros::notes::note, protocol::traits::{Deserialize, Packable, Serialize}};

/// Possession of the certificate `token_id`, like an AIP-721 `NFTNote`. The note owner is the possessor.
#[derive(Deserialize, Eq, Packable, Serialize)]
#[note]
pub struct CertNote {
    pub token_id: Field,
}
