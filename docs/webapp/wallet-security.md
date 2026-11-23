---
description: Back up a company's only owner wallet when it is an embedded wallet, and use a backup owner wallet without the app or a Privy sign-in.
---

# Keep your company's owner wallet safe

## Add a backup for your company's owner wallet

If your company has one owner wallet on MetaLeX, and that sole wallet is an
"embedded wallet" created and managed by a software service called Privy,
this page is for you. Privy describes embedded wallets as "non-custodial."
They are generally secure and provide a better user experience than
traditional wallets, but are subject to service interruptions and other
risks from Privy and thus are best managed through additional security
practices.

Keep in mind: your wallet is your and your company's signature and
transaction authority on MetaLeX. It can be used to sign documents, issue
securities, change officers, and other activities. Although unauthorized
actions might not have legal validity or enforceability, it is best to
prevent them entirely through good wallet management practices. Furthermore,
if you lose access to your wallet (for example, because you lose your email
account or Privy's service is interrupted), you could lose the ability to
act for your company on MetaLeX unless you have a backup sign-in method or a
second owner wallet.

We recommend the following actions, either independently or in combination:

1. Add a second, non-embedded owner wallet that you fully control, such as a
   hardware wallet or a Safe. You can keep both wallets and, since many
   users prefer the convenience of embedded wallets, you may be best served
   by doing so: you can use the embedded wallet as your daily driver while
   keeping the non-embedded wallet as a secure backup, so that you can still
   act for your company directly onchain even if you lose access to the
   embedded wallet or Privy's service is interrupted.

2. Consider adding two-factor authentication for wallet actions in the
   application (like document-signing and transactions). This limits the
   potential damage on MetaLeX from unauthorized access to your email
   account or MetaLeX sessions.

3. If you continue to use the embedded wallet as your company's only owner
   wallet, export a copy of its private key with the export tool in [Wallet
   Settings](profile.md#export-your-embedded-wallets-key). Do this securely
   and follow the guidance in the tool: anyone with this private key can
   sign and transact as you, so a mismanaged copy creates an additional
   security risk rather than protecting you. Also, a copy that you hold does
   not remove the key from Privy's systems, so the wallet stays exposed to a
   failure or compromise of Privy or of the MetaLeX application. For these
   reasons, adding a non-embedded owner wallet is the more highly
   recommended approach.

## Use your backup owner wallet

A non-embedded owner wallet keeps control of your company even if you lose
access to the embedded wallet or Privy's service is interrupted. It needs
neither the MetaLeX app nor a Privy sign-in: it can call your company's
contracts with any tool that sends a contract call, such as a block
explorer's contract page or the Safe Transaction Builder.

1. Note the addresses now, while the app works. In the [Incorporation
   Hub](company.md#incorporation-hub), the **Public company record** lists
   the company's contracts (cyberCORP, BorgAuth, and the issuance, deal and
   round managers), each linked to a block explorer.
2. Connect the non-embedded owner wallet to the tool.
3. Call the function on the cyberCORP contract:
   * `addOfficer` adds an owner wallet with the officer's name, contact and
     title.
   * `removeOfficer` removes one, for example a lost embedded wallet.

Add the new owner before you remove the old one. The contract lets you
remove the last officer, and then nobody can act as the company's owner.

The cyberCORP contract sits behind a proxy, so on a block explorer use
**Write as Proxy**. If the explorer does not show its functions, use a tool
that accepts the contract's ABI, such as the Safe Transaction Builder.
[Configure BorgAuth roles](../how-to/configure-roles.md) gives the exact
calls, and [CyberCorp](../reference/contracts/CyberCorp.md) lists the
others.

Offchain records, such as the cap table's private data, documents and
offchain signing requests, stay in the app and cannot be reached this way.
