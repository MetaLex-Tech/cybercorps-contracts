## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Propose Deal Workflows

```mermaid
graph TD
    start([start])
    
    start -->|"proposer.<br>deployCyberCorpAndCreateOffer()"| pending[agreement.isFinalized = FALSE<br>agreement.isVoided = FALSE<br>escrow = PENDING]
    start -->|"proposer.<br>deployCyberCorpAndCreateClosedOffer()"| pending
    
    pending -->|"counterParty.<br>signAndFinalizeDeal()"| signAndFinalizeDealCheckFinalizer{has finalizer?}
    pending -->|"counterParty.<br>signDealAndPay()"| signDealAndPayCheckFinalizer{has finalizer?}
    pending -->|"anyone.<br>voidExpiredDeal()"| expiryCheck{expired?}
    
    expiryCheck -->|yes| voided[agreement.isFinalized = FALSE<br>agreement.isVoided = TRUE<br>escrow = VOIDED]
    %% TODO Is that right?
    expiryCheck -->|no| onlyEscrowVoided[agreement.isFinalized = FALSE<br>agreement.isVoided = FALSE<br>escrow = VOIDED]
    
    signDealAndPayCheckFinalizer -->|yes| paidWithFinalizer[agreement.isFinalized = FALSE<br>agreement.isVoided = FALSE<br>escrow = PAID]
    signDealAndPayCheckFinalizer -->|no| paidWithoutFinalizer[agreement.isFinalized = TRUE<br>agreement.isVoided = FALSE<br>escrow = PAID]
    
    signAndFinalizeDealCheckFinalizer -->|yes| finalized[agreement.isFinalized = TRUE<br>agreement.isVoided = FALSE<br>escrow = FINALIZED]
    %% TODO Is that right?
    signAndFinalizeDealCheckFinalizer -->|no| revertNotFinalizer

    %% TODO Is that right?    
    paidWithoutFinalizer -->|"anyone.<br>finalizeDeal()"| revertNotFinalizer
    
    paidWithFinalizer -->|"anyone.<br>finalizeDeal()"| finalized
    paidWithFinalizer -->|"anyone.<br>signToVoid()"| voided
    
    %% TODO When does revokeDeal happen?
```
