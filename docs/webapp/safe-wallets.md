---
description: Connect a Safe through Ambire or Rabby, collect the required message signatures, and understand profile access versus delegation.
---

# Safe wallets: login and profile access

Use a Safe account through the **Ambire or Rabby browser extension**. Select the Safe inside the extension, then choose that extension in MetaLeX's wallet picker. You do not need to find a WalletConnect option or scan a QR code for this flow.

A Safe account is a smart contract wallet. Its owner wallets approve for it according to its signature threshold. For example, a **3-of-5 Safe requires three owner approvals** to produce a valid Safe signature. Connecting one owner wallet alone does not authenticate the Safe.

> **Verification status:** These instructions describe the supported application flow and the wallets’ documented Safe features. A complete MetaLeX Safe login using the currently installed Ambire and Rabby extensions has not yet been verified end to end. Wallet-picker availability and extension screens can vary. If an option is missing or signing stalls, contact support with the extension name, version and error.

## Choose the result you need

| Your situation | Flow |
| --- | --- |
| You want to sign into MetaLeX using the Safe's address | Connect the Safe account and complete login and authorization below. |
| You already have a MetaLeX profile under another wallet and can arrange Safe signatures | Stay signed into that profile and use **Link another wallet** to connect and authorize the Safe. |
| Your login wallet is not a Safe owner, but you control a different owner wallet | Keep your login profile. Use the separate owner wallet to approve for the Safe. The two wallet addresses do not need to match. |
| You have no Safe signer available and want its owners to give your profile access to records | See [Access without a Safe signer](#access-without-a-safe-signer). Adding the address as a watch-only account cannot authorize access. |
| You want an EOA to sign supported agreements on behalf of the Safe | Use [agreement-signing delegation](profile.md#delegate-signing-for-a-safe). This grants separate onchain authority. |

## Add the existing Safe to your wallet extension

### Ambire

1. Open Ambire's account menu. Choose **Import an account**, then **Safe account**.
2. Add your existing Safe's address. Make an owner wallet you control available as a signer, using the extension's supported hardware-wallet or existing-account connection.
3. Select the imported **Safe account** as the account you want to connect to MetaLeX.

Importing the Safe adds a way to interact with the existing account; it does not create a new Safe or change its owners. Ambire requires at least one owner key to connect the imported Safe to an app. Other owners can add their required approvals separately. See Ambire's [import instructions](https://help.ambire.com/en/articles/16146180-import-your-safe-account-into-ambire-wallet) and [direct app connection requirements](https://help.ambire.com/en/articles/16146268-use-safe-accounts-with-any-app).

### Rabby

Use Rabby's **Safe** account option to add the existing Safe on the intended network, then select that Safe account when connecting to MetaLeX. Account-import labels vary by extension version. Make the owner wallet you will sign with available through Rabby's supported signer connection.

The account exposed to MetaLeX must be the **Safe address**, not just the EOA that owns it. A watch-only account is insufficient. Rabby maintains separate pending Safe message and transaction queues; the approval interface can differ from Ambire's. Consult [Rabby's official support](https://support.rabby.io/) for extension-specific setup. MetaLeX applies the same permissions and threshold checks to signatures it receives from either extension; this does not establish that every extension version completes the login flow.

MetaLeX never asks for your seed phrase or private key. Keep hardware-wallet keys on the device; use its supported connection.

## Sign in as the Safe

1. Open MetaLeX and choose **Connect wallet** or **Sign in**.
2. In the wallet picker, choose **Ambire** or **Rabby**. If the picker shows a searchable list of wallets, search for the extension name.
3. Approve the connection in the extension with the **Safe account selected**. Check that MetaLeX displays the Safe's address and the intended network.
4. Review the sign-in message. Its domain should match the MetaLeX page you opened, its account should be the Safe, and its chain should match the Safe's network.
5. Sign using an actual Safe owner wallet. Collect the remaining owner approvals required by the Safe's threshold. Keep the originating MetaLeX tab and signing request open while approvals are collected.
6. Complete any separate MetaLeX wallet-authorization prompt. Login/linking through Privy and MetaLeX's application authorization are distinct steps, so more than one message may be requested. Finish the current request before retrying.

For the normal offchain message flow, these are signatures rather than asset transfers and do not require transaction gas. Safe can also be configured for onchain message approvals, which are a different flow and may cost gas. A login request should not ask you to approve a token allowance, transfer assets, change Safe owners or grant agreement-signing delegation.

After authorization, open [Wallet Settings](https://profile.metalex.tech/wallets). Under **Contract wallet access**, check the Safe's address and chain. This is the application access confirmation; a connected-wallet icon alone does not establish it.

## Link the Safe to your existing profile

If you already use a hot wallet to log into MetaLeX, **stay signed into that profile**:

1. Open [Wallet Settings](https://profile.metalex.tech/wallets) and select **Link another wallet**.
2. Choose Ambire or Rabby and connect the Safe account from the extension.
3. Complete the Safe's required signatures. If it is already linked but needs authorization, connect it on the intended network and select **Authorize** beside it.
4. Confirm the address and chain under **Contract wallet access**.

Your profile login wallet need not be a Safe owner. However, the extension flow still needs an actual Safe signer and sufficient Safe approvals. If your owner wallet is separate from your hot wallet, use that owner wallet for approval while keeping the existing MetaLeX profile signed in.

The Safe remains the holder address. Linking does not transfer its shares to your EOA, change its owners, or merge two MetaLeX profiles. If the Safe already belongs to another profile, resolve the conflict in Wallet Settings or contact support instead of creating repeated linking requests.

## Where are the other owners' approvals?

**Sign-in requests are messages. Look in Safe's Messages tab, not its transaction Queue.**

In [Safe](https://app.safe.global), select the same Safe and network, then open **Transactions**. Near the top of the page, the tabs are:

**Queue · History · Messages**

Click **Messages**, immediately to the right of **History**. Locate the request for the expected MetaLeX domain and compare its contents. Other owners approve that same message. One owner's green check in a 3-of-5 Safe still leaves two approvals to collect.

Ambire submits messages through the Safe API so approvals can be continued in Safe or another connected owner's wallet. Keep the originating request open until the wallet returns the completed signature. See [Ambire's synchronization guide](https://help.ambire.com/en/articles/16146206-how-safe-accounts-imported-in-ambire-extension-works) and [Safe's signed-message guide](https://help.safe.global/articles/7507962149-what-are-signed-messages).

If Messages is empty too, verify the Safe address and network, refresh, and inspect the extension for an error. An empty transaction queue alone is expected for an offchain login message. If the message never appears, report the extension/version and error to support; creating more login attempts can leave several different nonces awaiting signatures. Do not combine approvals from different requests.

## Expiry, renewal and revocation

Normal Safe application authorization lasts **up to one hour from preparation of the authorization request**, on the listed chain. MetaLeX checks that the contract still accepts its signature when access is used. A Safe configuration change may invalidate it; failed verification refuses access.

After expiry, connect the Safe on the same network and select **Authorize** in Wallet Settings to obtain a new authorization. Access on another chain requires authorization on that chain.

**Revoke access** removes that Safe's application access for your profile across chains while leaving the wallet linked. It does not change Safe owners or revoke onchain agreement delegation. Previously downloaded documents cannot be recalled.

## Access without a Safe signer

If your hot wallet is not an owner and you have no owner signer available, importing the Safe as watch-only will not let you authorize it. The Safe's owners must approve access.

A separate flow for requesting limited offchain read access from an existing profile is **in development as of November 10, 2026**. Its intended purpose is to let the owners approve on a separate device without linking the Safe to the recipient's profile or making the recipient a Safe owner. Do not assume this is available until its release is announced.

## Login is separate from agreement signing

Authorizing a Safe for MetaLeX does not enable every signing workflow. Some document, formation and secondary-sale paths still require an EOA. Supported delegated agreement flows use the separate [Delegation Settings](profile.md#delegate-signing-for-a-safe) process.

A delegation proposal must receive the required Safe approvals and be executed before the authority is active. It is not needed merely to log in or view records, and it should not be used as a substitute for limited read access.
