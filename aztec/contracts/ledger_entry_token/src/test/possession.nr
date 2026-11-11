use crate::LedgerEntryToken;
use crate::test::utils::{authorize_and_mint, cert, is_current, possesses, SALT, setup};
use aztec::{
    protocol::address::AztecAddress,
    test::helpers::{authwit::add_private_authwit_from_call, test_environment::CallPrivateOptions},
};

#[test]
unconstrained fn holder_transfers_possession() {
    let f = setup();
    let first = cert(1, f.alice);
    let _ = authorize_and_mint(f, first, SALT);

    f.env.call_private(f.alice, LedgerEntryToken::at(f.token).transfer(f.alice, f.bob, 1, 0));

    assert(!possesses(f, f.alice, 1));
    assert(possesses(f, f.bob, 1));
    assert(is_current(f, first, SALT));
}

// An operator, such as an exchange contract, moves the note with the holder's authwit. Its PXE has the holder's notes.
#[test]
unconstrained fn operator_transfers_with_holder_authwit() {
    let mut f = setup();
    let operator = f.env.create_light_account();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);
    let call = LedgerEntryToken::at(f.token).transfer(f.alice, f.bob, 1, 7);
    add_private_authwit_from_call(f.env, f.alice, operator, call);

    f.env.call_private_opts(operator, CallPrivateOptions::new().with_additional_scopes([f.alice]), call);

    assert(possesses(f, f.bob, 1));
}

#[test(should_fail_with = "Unknown auth witness for message hash")]
unconstrained fn revert_if_operator_has_no_authwit() {
    let mut f = setup();
    let operator = f.env.create_light_account();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);

    f.env.call_private_opts(
        operator,
        CallPrivateOptions::new().with_additional_scopes([f.alice]),
        LedgerEntryToken::at(f.token).transfer(f.alice, f.bob, 1, 7),
    );
}

#[test(should_fail_with = "duplicate")]
unconstrained fn revert_if_operator_authwit_is_replayed() {
    let mut f = setup();
    let operator = f.env.create_light_account();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);
    let token = LedgerEntryToken::at(f.token);
    let call = token.transfer(f.alice, f.bob, 1, 7);
    add_private_authwit_from_call(f.env, f.alice, operator, call);
    let opts = CallPrivateOptions::new().with_additional_scopes([f.alice]);
    f.env.call_private_opts(operator, opts, call);
    f.env.call_private(f.bob, token.transfer(f.bob, f.alice, 1, 0));

    f.env.call_private_opts(operator, opts, call);
}

#[test(should_fail_with = "cert not held")]
unconstrained fn revert_if_sender_does_not_hold_the_cert() {
    let f = setup();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);

    f.env.call_private(f.bob, LedgerEntryToken::at(f.token).transfer(f.bob, f.alice, 1, 0));
}

#[test(should_fail_with = "recipient is zero")]
unconstrained fn revert_if_recipient_is_zero() {
    let f = setup();
    let _ = authorize_and_mint(f, cert(1, f.alice), SALT);

    f.env.call_private(f.alice, LedgerEntryToken::at(f.token).transfer(f.alice, AztecAddress::zero(), 1, 0));
}
