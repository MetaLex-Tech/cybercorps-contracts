// A template from the MetaLeX catalog. The document holds its full text, so the vault blob is the whole agreement
// and the terms hash commits to the exact text.
export const NDA_TEMPLATE = {
  title: 'Mutual Non-Disclosure Agreement',
  globalFields: ['effectiveDate'],
  partyFields: ['name'],
  text: [
    'Purpose. The parties want to discuss a possible business relationship (the "Purpose"). For the Purpose, each party can disclose Confidential Information to the other party.',
    'Confidential Information. "Confidential Information" is all non-public business, technical and financial information that a party (the "Discloser") discloses to the other party (the "Recipient"), in any form, that is marked confidential or that a reasonable person would think is confidential.',
    'Exclusions. Confidential Information does not include information that: (a) is public, or becomes public through no fault of the Recipient; (b) the Recipient knew before the disclosure; (c) the Recipient gets from a third party that has no duty of confidentiality; or (d) the Recipient develops independently.',
    'Obligations. The Recipient must: (a) use the Confidential Information only for the Purpose; (b) keep it confidential with at least reasonable care; and (c) disclose it only to its employees and advisers who must know it for the Purpose and who have duties of confidentiality at least as strict as this agreement.',
    'Required disclosure. If law or a court requires the Recipient to disclose Confidential Information, the Recipient must tell the Discloser promptly, if the law permits, and disclose only the part that is required.',
    'Return or destruction. When the Discloser asks, the Recipient must return or destroy all Confidential Information and confirm this in writing.',
    'No license. This agreement gives no license or other right to the Confidential Information, other than for the Purpose.',
    'Term. This agreement starts on the Effective Date. The obligations in it continue for 2 years after the last disclosure.',
    'Remedies. A breach can cause harm that money cannot fully repair. So the Discloser can ask a court for an injunction, in addition to other remedies.',
    'General. Delaware law governs this agreement. This agreement is the entire agreement of the parties on its subject. A change to it must be in writing and signed by both parties.',
  ],
};
