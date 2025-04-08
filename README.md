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
    subgraph proposer
        subgraph nonClosed["Non-closed (counter-party values are not set)"]
            deployCyberCorpAndCreateOffer(["deployCyberCorpAndCreateOffer"])
            proposeDeal[proposeDeal<br><br>status = PENDING]
        end
        
        subgraph closed["Closed (counter-party values are set)"]
            deployCyberCorpAndCreateClosedOffer(["deployCyberCorpAndCreateClosedOffer(counterPartyValues)"])
            proposeClosedDeal["proposeClosedDeal(counterPartyValues)<br><br>status = PENDING"]
        end
        
        deployCyberCorp
        
        signContractFor["signContractFor(proposer)"]
    end
    
    subgraph counterParty
        signAndFinalizeDeal["signAndFinalizeDeal(counterPartyValues)<br><br>status = FINALIZED"]
        signDealAndPay["signDealAndPay<br><br>status = PAID"]
    end
    
    subgraph anyone
        finalizeDeal["finalizeDeal<br><br>status = FINALIZED"]
        voidExpiredDeal["voidExpiredDeal<br><br>status = VOIDED"]
        signToVoid["signToVoid<br><br>status = VOIDED"]
    end
    
    deployCyberCorpAndCreateOffer([deployCyberCorpAndCreateOffer])
        --> deployCyberCorp 
        --> proposeDeal 
        --> signContractFor
    
    deployCyberCorpAndCreateClosedOffer
        --> deployCyberCorp
        --> proposeClosedDeal 
        --> signContractFor
        
    signContractFor --> signAndFinalizeDeal
    signContractFor --> signDealAndPay
    signContractFor --> voidExpiredDeal
    
    signDealAndPay --> finalizeDeal
    signDealAndPay --> signToVoid
    
    signAndFinalizeDeal --> voidExpiredDealRevert[\"voidExpiredDeal<br><br>revert!"\]
```
