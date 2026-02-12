We are building a new cyber agreement registry.

## Background

cyberAgreements are legal contracts stored on the blockchain.

They reference legal text (in the form of a reusable template contract), and signing parties supply values that the legal wording references.

V1 achieves this by storing a `legalContractUri` pointing to a PDF and a set of `globalFields` and `partyFields`, as well as `globalValues` and `partyValues`.

Global fields are fields that are the same for both parties. They are set once when the agreement is first created, and both parties signatures include them in the hashed data that is signed. Examples would be a "purchase price" if one party is selling something to another.

Party fields are specific to the party - they are set by the signing party when they sign, and are normally the name and contact information for the party.

One of the issues with the current approach is that the values are all strings, to assist in forming a human readable document when combined with the legal text. This makes integration with other smart contract systems difficult, because the values are not typed, and are error prone.

Another issue is the management of templates. Because they reference a PDF, they are hard to maintain in version control.

Finally, the output of V1 is a pdf with associated fields that need to be cross referenced. This is a departure from what people traditionally expect from a legal agreement, with many asking where *their* version is.

## V2 Goals

There are two primary goals for V2:

1. Produce a system whose output on agreement completion is a single, downloadable pdf that can stand alone more like a traditional legal contract, with any onchain values read and embedded in the PDF

2. Produce a system that makes it possible for legal agreements to form integral parts of a wider smart contract system - variables from the contract can be read and used in other smart contracts.

## Design

### Legal wording 

V2 will create PDFs using *typst* - a LaTeX-like language for typesetting documents. Because typst is ultimately plaintext, it is easy to version and manage. It also allows for onchain values to be evaluated and embedded in the wording.

### Templates

Templates will now be smart contracts, deployed on the blockchain that they will be used on. This allows them to include their own logic for storing data, and importantly for converting it to human readable text.

We will use a similar approach to that used for `CyberCertPrinters`. Templates will extend an interface similar to `ICertificateExtension` contracts, having `EncodeTemplateData` and `DecodeTemplateData` functions to convert between a template specific struct and a byte array.

Additionally, they will also include:
- `templateContentUri` - this is a uri that will point to the .typ file that contains the template wording, used in combination with a styling file and the wording values (below) to generate a pdf output.
- `getLegalWordingValues` - this takes the template specific data struct and returns a map of string keys to string values that will be used to populate the template. It should be noted that the number of values that are output here is not necessarily equal to the data stored in the contract. For example, the legal contract could include a reference to an ERC20 token address, but the wording output might be the human readable name of the token, and an amount might use the decimals value to convert to a human readable amount.
- Validation logic should be included in the `encodeTemplateData` function, but to emphasize its important could be included in the interface.
- Templates should also be extendable with `ICondition` implementations to allow for closing conditions to be set and subsequently checked.

### Registry

The registry itself can be simpler. A contract can now simply include an array of parties, the the template address, and the template data struct, as well as the signatures of each party.
