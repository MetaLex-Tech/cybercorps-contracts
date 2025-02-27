pragma solidity 0.8.28;

enum SecurityClass {
    SAFE,
    SAFT,
    SAFTE,
    TokenPurchaseAgreement,
    TokenWarrant,
    ConvertibleNote,
    CommonStock,
    StockOption,
    PreferredStock,
    RestrictedStockPurchaseAgreement,
    RestrictedStockUnit,
    RestrictedTokenPurchaseAgreement,
    RestrictedTokenUnit
}

enum SecuritySeries {
    SeriesPreSeed,
    SeriesSeed,
    SeriesA,
    SeriesB,
    SeriesC,
    SeriesD,
    SeriesE,
    SeriesF,
    NA
}

enum SecurityStatus {
    Issued,
    Redeemed,
    Expired,
    Cancelled
}

