## Architectures

```mermaid
classDiagram
    direction LR

    namespace DeployedAtGenesis {
        class CyberCorp
        class CyberCorpBeacon {
            <<UpgradeableBeacon>>
            +upgradeTo()
        }
        class CyberCorpSingleFactory {
            +upgradeImplementation()
        }
        
        class CyberCorpFactory {
            <<UUPSUpgradeable>>
            +upgradeToAndCall()
        }
        class CyberCorpFactoryProxy {
            <<ERC1967Proxy>>
        }
        
        class DealManager
        class DealManagerBeacon {
            <<UpgradeableBeacon>>
            +upgradeTo()
        }    
        class DealManagerFactory {
            +upgradeImplementation()
        }
        
        class IssuanceManager
        class IssuanceManagerBeacon {
            <<UpgradeableBeacon>>
            +upgradeTo()
        }
        class IssuanceManagerFactory {
            +upgradeImplementation() // Update IssuanceManager implementation
            +upgradePrinterBeaconAt() // Update CyberCertPrinter implementation
        }
        
        class CertificateUriBuilder {
            <<UUPSUpgradeable>>
            +upgradeToAndCall()
        }
        class CertificateUriBuilderProxy {
            <<ERC1967Proxy>>
        }
        
        class CyberAgreementRegistry {
            <<UUPSUpgradeable>>
            +upgradeToAndCall()
        }
        class CyberAgreementRegistryProxy {
            <<ERC1967Proxy>>
        }    
    
        class CyberCertPrinter 
    }
    
    namespace DeployedAtCyberCorpCreation {
        class CyberCorpProxy {
            <<BeaconProxy(CyberCorpBeacon)>>
        }
        
        class DealManagerProxy {
            <<BeaconProxy(DealManagerBeacon)>>
        }
        
        class IssuanceManagerProxy {
            <<BeaconProxy(IssuanceManagerBeacon)>>
        }
        
        class CyberCertPrinterBeacon {
            <<UpgradeableBeacon>>
            +upgradeTo()
        }            
        class CyberCertPrinterProxy {
            <<BeaconProxy(CyberCertPrinterBeacon)>>
        }
    }
    
    CyberCorpFactory <-- CyberCorpFactoryProxy : fallback to
    
    CyberCorp <-- CyberCorpBeacon : implementation
    CyberCorpBeacon <-- CyberCorpSingleFactory : beacon
    CyberCorpSingleFactory <-- CyberCorpFactoryProxy : depend on
    
    DealManager <-- DealManagerBeacon : implemnetation
    DealManagerBeacon <-- DealManagerFactory : beacon
    DealManagerFactory <-- CyberCorpFactoryProxy : depend on
    
    IssuanceManager <-- IssuanceManagerBeacon : implementation
    IssuanceManagerBeacon <-- IssuanceManagerFactory : beacon
    IssuanceManagerFactory <-- CyberCorpFactoryProxy : depend on

    CertificateUriBuilderProxy <-- CyberCorpFactoryProxy : depend on
    CertificateUriBuilder <-- CertificateUriBuilderProxy : fallback to
    
    CyberAgreementRegistry <-- CyberAgreementRegistryProxy : fallback to
    
    CyberAgreementRegistryProxy <-- CyberCorpFactoryProxy : depend on
    
    CyberCorpFactoryProxy <-- CyberCorpProxy : created by
    CyberCorpFactoryProxy <-- IssuanceManagerProxy : created by        
    CyberCorpFactoryProxy <-- DealManagerProxy : created by
    
    CyberCertPrinter <-- CyberCertPrinterBeacon : implementation    
    CyberCertPrinterBeacon <-- IssuanceManagerProxy : CyberCertPrinterBeacon()
    IssuanceManagerProxy <-- CyberCertPrinterProxy : created by    
```
