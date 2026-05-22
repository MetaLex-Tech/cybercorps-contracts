# MetaDAO — entity formation

The **MetaDAO** page is a narrow, single-purpose integration: it forms the
legal entity for a token launched through [MetaDAO](https://metadao.fi). It
is **not** a governance or prediction-market surface — it does one thing,
once.

## When you'd use it

You would not navigate to this page directly. You arrive at it from the
**MetaDAO launch flow**, via a link that carries the details of your token
and enterprise. Opening the page without those details just shows an error.

## What it does

The page presents a **formation agreement** for your entity — specifically a
*Segregated Portfolio of a Futarchy Governance SPC*, a Cayman Islands
structure. Almost every field is **pre-filled and locked**, carried over
from the MetaDAO form:

* the enterprise and company name,
* the company type (a segregated portfolio of a segregated portfolio
  company),
* the jurisdiction (Cayman Islands),
* the token name and ticker,
* the founder address,
* the network (Base).

The only fields you fill in are the **founder/operator name and contact**.

## The steps

1. Arrive from the MetaDAO launch flow (the page opens with your details
   already populated).
2. Enter the founder/operator name and contact.
3. **Sign the formation agreement** — a free signature.
4. **Submit.** MetaLeX forms the cyberCORP for your entity.
5. You are redirected back to MetaDAO to continue the launch.

That's the whole flow. Once the entity is formed, you manage it like any
other cyberCORP — see [The cyberCORPs app](mainframe.md).

## Under the hood

Submitting forms a cyberCORP structured as a Cayman Segregated Portfolio
Company. At the protocol level this is the **MetaDAO / SPC** path — see the
[MetaDAOFactory](../reference/factories.md) reference and, for how a single
legal entity can hold multiple independently-governed portfolios,
[Legal mappings across jurisdictions](../explanation/legal-mappings.md). The
futarchy *governance* of the entity happens on MetaDAO's own platform; this
page only handles the onchain legal-entity formation.

## Good to know

* This page is a **handoff**, not an app you spend time in.
* For everything you do *after* formation — issuing securities, raising —
  you use the [cyberCORPs app](mainframe.md) and [cyberRAISE](cyberraise.md)
  like any other company.
