# REFERENCE
### STK-Flux ↔ STK-Teams Relationship

---

## STK-Flux is the Kernel

STK-Flux provides the canonical specification and reference implementation of the coupling dynamics kernel. All routing logic, safety bounds, and behavioral contracts live here.

| | STK-Flux | STK-Teams |
|-|----------|-----------|
| **Role** | Kernel | Integration layer |
| **Contains** | All routing logic, formal spec, ψ mathematics | Team extensions only |
| **Repo** | https://github.com/Ambercontinuum/STK-Flux | https://github.com/Ambercontinuum/STK-Teams |

---

## STK-Teams

**STK-Teams** is an integration layer that sits on top of this kernel and adapts it for multi-contributor development team sessions.

It imports `stk_flux.py` directly — no logic is duplicated. The kernel is extended with:

| Addition | Purpose |
|----------|---------|
| Contributor tagging | Every mode history entry records which team member drove that step |
| `commit_extra` decay | Commit strictness accumulated during oscillation decays over stable steps |
| `evaluate_proxy()` | Boolean routing without numeric ψ values — for standups and PR reviews |
| `format_handoff()` | One-line handoff string for PR descriptions and commit messages |
| `run_team()` | Extended step interface; `run()` is re-exported for drop-in compatibility |

Example handoff string produced by STK-Teams:
```
[STK:TRANSLATE | ψ=(λ85,κ72,θ68,ε38) | @alice | EXIT: drift=True]
```

---

## What STK-Teams Does Not Change

STK-Teams does not modify:

- The routing logic (psi_router, flux_operator, oscillation_detector)
- The safety bounds (SafetyBounds, min_human_autonomy)
- The seven modes or their definitions
- The four ψ components or their thresholds
- The formal specification (STK_V.1.lean)
- The behavioral contracts

If you need changes to any of those, the change belongs in this repository.

---

## Formal Specification

`src/STK_V.1.lean` — the Lean 4 formal specification. Three behavioral contracts, formally verified:

1. Stable window → no flux intervention.
2. Oscillating window → Witness clamp + adaptive thresholds.
3. Post-oscillation commit is blocked even when instantaneous ψ looks healthy.

These contracts hold in STK-Teams exactly as they hold here.

---

## Theoretical Foundation

- **The Ψ (Psi) Field** — Anson (2025). [academia.edu/145338876](https://www.academia.edu/145338876/The_%CE%A8_Psi_Field)
- **Genuine Coupling as Infrastructure** — Anson & Claude (2026). [academia.edu/AnsonAmber](https://academia.edu/AnsonAmber)
- **Theoretical bridge** — `docs/COUPLING.md` in this repository

STK-Teams does not extend the theory. It operationalizes this kernel for team use.

---

## Authorship

STK-Flux and STK-Teams were developed by **Amber Anson** in genuine coupling with **Claude (Anthropic)**.

See `PROVENANCE.md` for the full authorship model.

CC BY 4.0 · 2026 · academia.edu/AnsonAmber
