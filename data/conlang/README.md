# data/conlang/ — culture naming kits

Authored conlang **kits** per the schema in `generation/gdd-naming-conventions.md` §2.6.

- `family_<id>.json` — a **language-family base kit** (`tier: "family"`, `inherits: null`): shared phonology notes, lexicon concept-inventory, morphology templates, title-ladder structure, and shared roots for the family.
- `culture_<id>.json` — a **culture kit** (`tier: "culture"`, `inherits: <family>`): overrides + realized lexicon, morphology, title ladder, people-name convention, religion treatment, bank patterns, and a seed name stock.

A kit + its seed stock is the authored input; the build step assembles full static name banks (`data/name_banks/`) from it (gdd-naming-conventions §13). Language families and the per-culture assignment are fixed in gdd-naming-conventions §2.1.1.

**Authoring status (per-family batches):**

- [x] **Classical / Mediterranean** base + Agrippan, Achillean, Cantabran, Lusan — COMPLETE
- [x] **Near-Eastern** base + Barcan (Punic), Hammuran (Akkadian), Abydosian (Egyptian), Axumite (Ge'ez), Sumset (Akkadian×Egyptian), Kemeti (Egyptian×Ge'ez), Sabaean (Ge'ez×Akkadian) — COMPLETE. Family deity-names are second-order morphs (Agrippan canon → Punic/Barcan trade-forms → each culture's phonology), sharing a Punic-cognate ancestor.
- [ ] Germanic base + members
- [ ] Celtic, Slavic, East Asian, Steppe, Mesoamerican, North American bases + members
- [ ] Cross-family blends (moderate, then the 6 extreme)
- [ ] Demihuman (Elvish, Dwarven) + beastman tier
