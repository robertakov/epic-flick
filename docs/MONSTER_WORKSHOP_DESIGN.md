# Monster Workshop — future technical design

Status: proposal, not an approved product specification. v14 implements only the star wallet and Free Run challenges. Nothing in this document adds a Monster, Workshop, component shop, art, round 41, leagues, networking, achievements or monetization to the game.

## Product boundary

Жестянка, Попрыгун, Тяжеловес, Ракета and Самурай remain five permanent fixed archetypes. Their existing identity, definitions, prices, skins and physics are not converted into modular builds. A future sixth robot is an experimental endgame Monster with its own build, catalog and progression namespace. Campaign mastery and repeatable Free Run skill challenges supply spendable stars. Spending must not alter Campaign objective ownership or completion icons.

The Monster gives long-term progression a physical purpose: an eventual special opponent revealed after the existing forty rounds. Several kilometers, illustratively around 4–5 km on strong runs, describe the intended scale rather than a guaranteed score or fixed victory threshold. The future opponent must use real rigid bodies, shared damage/contact/rocket rules and input-driven control. No teleportation, distance injection or predetermined result is acceptable. Its hardware and control may eventually be stronger; evidence must establish its distribution and attainable player counter-builds. Normal robots need not compete effectively against it. No new boss or unlocking rule is implemented in v14.

## Components and physical tradeoffs

Categories are provisional. Separate authored component definitions from player ownership and equipped instances. A slot schema should specify allowed categories, capacity, dependencies, attachment transforms and incompatibilities. Avoid allowing arbitrary file paths, scripts or unrestricted numeric overrides in saved builds.

| Candidate category | Possible physical benefit | Necessary cost/tradeoff to investigate |
|---|---|---|
| Chassis/body | Durability, attachment capacity, stability | Mass, inertia, size and control response |
| Head | Rocket system, guidance, durability | Mass distribution, detachment behavior, propulsion cost |
| Arms | Protection, balance, sacrificial contacts | Inertia, drag/contact exposure, added mass |
| Legs | Reach and landing geometry | Fragility, stiffness requirements, awkward clearance |
| Springs | Energy return, travel, supported load | Mass, instability, difficult timing, bottom-out risk |
| Armor | HP and zone protection | Mass and slower rotation/flight |
| Rocket propulsion | Thrust/impulse or burn duration | Fuel capacity/mass, steering compromise, price |
| Special modules | A clearly defined mechanical interaction | Explicit limitations, competing slot or energy demand |

These are hypotheses, not final bonuses or numbers. Stronger springs must interact with actual chassis mass and contact geometry, rather than simply multiplying reported distance. An armored body should change inertia and flight as well as durability. A powerful head may improve the real final jet phase while making earlier landings harder. Component definitions should declare bounded inputs to a build compiler; authored formulas resolve these into physics resources. Keep cosmetic skins separate from mechanical properties.

## Proposed architecture

1. **Component catalog:** immutable, config-driven definitions identified by stable IDs such as `monster.chassis.light_01`. Each definition has its own version, slot/category tags, attachment data, physical contribution, legal bounds, dependencies and separately tunable purchase price/equipped value. Never reuse an ID for an unrelated component. Retain historical versions or an explicit upgrade map.
2. **Build schema:** versioned data containing slot -> component ID/version selections, approved adjustable parameters, cosmetic IDs and a build revision. It contains no trusted final HP, distance, velocity, thrust or star wallet. Identical permitted input should resolve through a documented formula order, not dictionary iteration order.
3. **Build validator:** checks schema and catalog versions, required slots, allowed counts, ownership/entitlement when applicable, dependency/exclusion rules, parameter bounds, budgets and total physical feasibility. It returns specific reasons rather than silently equipping an illegal build.
4. **Build compiler:** pure/config-driven conversion of a validated build and ruleset into the Monster's resolved masses, shapes, inertia, center of mass, springs, rotational control, durability and propulsion resources. Tests compare a resolved-stat digest and reject nonfinite/out-of-range values. Runtime gameplay does not mutate the catalog.
5. **Monster assembler/controller:** a future separate consumer of those compiled resources, sharing suitable existing contact/damage/charge/rocket behavior. Assess whether the current single-body visual/limb model can express the approved tradeoffs before choosing a multi-body rig. Do not distort the five normal archetypes merely to fit this new assembler.
6. **Workshop session:** draft editing, preview, validation, explicit commit and reversible reconfiguration. Unsaved previews do not spend currency. A normal gameplay session holds a validated immutable build snapshot; editing a draft cannot change a robot already racing.

The interfaces above are design proposals. v14 introduces no classes, resources or catalog entries for them.

## Serialization and reconstruction

Illustrative future payload, not a save field currently present:

```json
{
  "schema_version": 1,
  "catalog_revision": "monster-catalog-001",
  "ruleset_revision": "physics-001",
  "slots": {
    "chassis": {"component_id": "monster.chassis.light_01", "version": 1},
    "springs": {"component_id": "monster.spring.long_01", "version": 1}
  },
  "parameters": {},
  "cosmetics": {},
  "build_revision": 7
}
```

Stable slot and component IDs are mandatory. The receiving side resolves definitions from a trusted versioned catalog, validates the payload, compiles it and compares a canonical build/config digest. Canonical serialization orders keys and normalizes bounded numeric inputs. A future input replay also needs track seed, starting conditions, fixed simulation tick rate, control events, game/engine/build/ruleset versions and relevant allowed settings. Which current user settings may affect competition must become an explicit ruleset decision; fairness cannot rely on each player's local sliders.

Config-driven inputs and fixed ticks improve reproducibility, but Godot rigid-body floating-point physics is not assumed bit-identical across Android devices, architectures or engine releases. Do not promise deterministic peer lockstep. Measure replay drift. A server-authoritative simulation, authoritative snapshots or a controlled simulation environment with explicit tolerances are safer candidates; feasibility and cost require a later prototype.

## Save migration and currency transactions

Current v14 ProfileStore VERSION5 separates `star_wallet.{earned,available,spent,sources}` from permanent `campaign.stars/star_claimed`, plus one persistent Free Run set and its completion receipts. It provides centralized earning/spending APIs with save failure rollback. Existing Campaign coin bonuses and Free Run distance coins remain separate.

A future Workshop migration should add its own schema, owned component IDs/versions and named build slots while preserving all v14 wallet and challenge receipts. Choose a default unbuilt Monster rather than inventing purchases for existing players. Unknown/retired component versions need documented substitutions, retained historical definitions or a review/refund path. Migration must be idempotent and atomic. Save backups and failure injection tests should cover interruption before/after rename.

A purchase must atomically commit **both** the currency debit and the component ownership receipt. Calling `spend_stars()` and then saving ownership separately would risk charging without delivering the component. Extend ProfileStore's internal transaction boundary for that operation; gameplay/UI must not directly alter wallet integers. The same principle applies to refunds or construction receipts. Duplicate purchase/request IDs must return the prior outcome without charging twice. Bounded current ownership/receipts can prevent local repetition; a future online economy needs a trusted server ledger, request idempotency and reconciliation.

## Two star-spending models

| Consideration | A: permanent component purchases, free re-equipping | B: spend stars as construction/build resource |
|---|---|---|
| Experimentation | Ownership enables many free combinations; strong fit for physics discovery | Each rebuild may cost; preview/refund/recovery rules become essential |
| Regret | A weak purchase remains usable in another build; catalog previews still matter | Poor build choices may consume progression; unclear salvage harms trust |
| Progression | Collection grows while equipped slots remain limited | Repeated construction creates a resource sink; loss/rebuild behavior must be defined |
| Free Run farming | Expands options, eventually saturates collection; new content and calibrated rewards needed | Repeated farming funds rebuilding and can overshadow skill experimentation |
| Competitive balance | Equipped-value leagues can equalize loadouts despite broad ownership | Spending ability can become match power unless separate equipped limits/rules exist |
| Save complexity | Owned IDs plus builds and atomic purchase receipts | Material inventory, construction history, refunds/salvage, interrupted builds and duplication handling |

**Editable recommendation: model A for an initial Workshop prototype.** It better supports trying physical combinations without recurring regret and keeps the transaction model simpler. Purchase once, freely equip/reconfigure; an equipped-value budget is a competitive constraint rather than another currency debit. This is a recommendation, not an irreversible decision. Model B remains possible if later design explicitly defines whether stars are consumed, locked while equipped, fully recoverable, partially salvaged or charged only for new components. Those versions have materially different player incentives and must not be conflated.

Do not set permanent prices from v14's provisional earning rate. First measure phone completion time, stars/hour by skill, abandonment patterns, attainable build variety and perceived rebuild regret. A spendable wallet does not itself determine which model wins. Keep price/value fields independently tunable and define how balance patches affect existing purchases.

## Competitive validation and anti-cheat considerations

Local saves are appropriate for the current offline game, but they are editable and provide no trustworthy competitive proof. Neither star cost nor a client-generated build hash certifies ownership or performance. A future server must validate authenticated ownership/purchase state, allowed catalog/ruleset, legal slots/parameters, equipped budget and request/replay uniqueness. It must reject client-provided derived stats and distance totals. Trusted simulation or a verified replay protocol must establish the actual outcome, with explicit limits on replay drift and impossible inputs. Signed catalogs help establish data integrity; they do not stop a modified client by themselves.

Do not transmit raw resources or executable scripts as a build. Rate-limit and bound payloads. Validate finite numeric ranges, maximum slot counts and payload size before assembly. Separate cosmetic claims from physics authority. Consider engine/game version admission, reconnect semantics and dispute logs in a future networking design. None of this is networking code in v14.

## Power Rating, matchmaking and leagues

An initial **Power Rating** can estimate a build's physical capability from mass/inertia, spring energy envelope, durability, maneuverability and rocket range, then improve using simulations over multiple tracks and control strategies. Interactions are nonlinear: stronger springs on an unsuitable heavy/unstable body may reduce useful distance. A sum of component prices is not a physical power model. Publish the limits of a rough rating and periodically recalibrate against measured performance.

Matchmaking should consider actual performance/MMR, uncertainty, player skill, track/ruleset and perhaps coarse build rating. Expensive ownership must not be treated as demonstrated competitive ability. Avoid promising a single scalar can capture every counter-build.

Future format proposals:

- **Open League:** no equipped-cost cap, but all builds still obey legal slots, approved components, safe bounds and the same ruleset. Unlimited cost is not permission for arbitrary physics values.
- **Budget League:** equipped component value totals ≤ a ruleset-defined X. Players may own many components and choose any legal combination within X. Owned-but-unequipped parts do not count. The ruleset/catalog revision fixes valuation, independently of historical purchase price, discounts or available wallet. Define ties, component variants and balance patches before admission.

Neither league nor MMR is implemented. Validate that a league's budget allows diverse competitive builds rather than one dominant recipe.

## Future prototype gates and open decisions

Before implementation approval: choose provisional slots and physics tradeoffs; decide purchase versus construction model; measure Free Run economy on phones; define post-Campaign reveal rules; specify budget valuation and competitive physics settings; evaluate the current rig's limitations and replay determinism. Then prototype assembly on an isolated test scene, demonstrate real physical differences, test save/transaction failure modes and validate legal-build serialization. Only after this should a future superboss or online mode be considered.

Acceptance for a future Monster prototype: normal archetypes unchanged, no fake distance, useful build diversity, atomic no-duplicate spending, reversible experimentation under the chosen model, bounded legal stats, explicit catalog migration and reproducible reconstruction within documented physics limits.
