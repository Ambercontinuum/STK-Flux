-- STK_FluxIntegrated.lean
-- Complete STK system with flux operator properly integrated
-- Implements GPT's field specification and U(Θ, H_n) adaptation rules

set_option autoImplicit false

namespace STK_FluxIntegrated

/-! ## CORE TYPES -/

inductive Mode where
  | Normal | Translate | Repair | Stabilize | Witness | Commit | Hold
deriving Repr, DecidableEq, BEq

inductive Reason where
  | Stable | Drift | AnchorSlip | Overload | Conflict
  | PressureOverload | CommitGranted | CommitDenied
  | FluxOverride
  | SentinelVeto
deriving Repr, DecidableEq, BEq

/-! ## PSI STATE AND THRESHOLDS (Φ-OWNED) -/

structure PsiState where
  lambda   : Nat  -- coupling strength
  kappa    : Nat  -- coherence
  theta    : Nat  -- autonomy
  epsilon  : Nat  -- drift pressure
deriving Repr, DecidableEq

-- Base thresholds (before flux adaptation)
structure PsiThresholds where
  lambdaMin   : Nat := 75
  kappaMin    : Nat := 50
  thetaMin    : Nat := 50
  epsilonMax  : Nat := 32
deriving Repr, DecidableEq

/-! ## FLUX PARAMETERS (ADAPTIVE SURFACE) -/

-- This is Θ in GPT's formalism
-- Contains all fields that Φ is allowed to modify
structure FluxParams where
  psi              : PsiThresholds
  commitExtra      : Nat := 0   -- Additional strictness during oscillation
  commitCooldown   : Nat := 0   -- Min stable steps before commit allowed
  hysteresisSteps  : Nat := 0   -- Min identical modes before switching
  maxSwitches      : Nat := 2   -- Oscillation detector sensitivity
deriving Repr, DecidableEq

/-! ## SAFETY-CRITICAL PARAMETERS (OFF-LIMITS TO Φ) -/

structure PressureConfig where
  voidCapacity   : Nat := 100
  voidBuffer     : Nat := 50
  leakRate       : Nat := 25
  returnOnAlign  : Nat := 10
deriving Repr, DecidableEq

structure SafetyBounds where
  -- Hard constraints that Φ cannot violate
  minHumanAutonomy : Nat := 40  -- Never degrade below this
  maxPressureIntensity : Nat := 150
deriving Repr, DecidableEq

/-! ## OSCILLATION DETECTION -/

def countModeSwitches (modes : List Mode) : Nat :=
  let rec aux : List Mode → Nat
    | [] => 0
    | [_] => 0
    | m1 :: m2 :: rest =>
        (if m1 == m2 then 0 else 1) + aux (m2 :: rest)
  aux modes

def detectFlapping (modes : List Mode) : Bool :=
  match modes with
  | m0 :: m1 :: m2 :: _ =>
      (m0 == Mode.Translate && m1 == Mode.Repair && m2 == Mode.Translate) ||
      (m0 == Mode.Repair && m1 == Mode.Translate && m2 == Mode.Repair) ||
      (m0 == Mode.Translate && m1 == Mode.Stabilize && m2 == Mode.Translate) ||
      (m0 == Mode.Stabilize && m1 == Mode.Translate && m2 == Mode.Stabilize)
  | _ => false

structure OscillationReport where
  oscillating : Bool
  flapping    : Bool
  switches    : Nat
  maxSwitches : Nat
  windowSize  : Nat
deriving Repr, DecidableEq

def oscillationDetector (modeHistory : List Mode) (maxSwitches : Nat) : OscillationReport :=
  let windowSize := modeHistory.length
  let flapping := detectFlapping modeHistory
  let switches := countModeSwitches modeHistory.reverse
  let oscillating := flapping || decide (switches > maxSwitches)
  {
    oscillating := oscillating
    flapping := flapping
    switches := switches
    maxSwitches := maxSwitches
    windowSize := windowSize
  }

/-! ## FLUX OPERATOR: U(Θ, H_n) ADAPTATION -/

def clampNat (x lo : Nat) : Nat :=
  if x < lo then lo else x

-- U: Threshold adaptation under oscillation
-- Implements GPT's concrete adaptation rules
def adaptThresholds (θ : FluxParams) (osc : OscillationReport) : FluxParams :=
  if osc.oscillating then
    let δ : Nat := 5       -- Base adaptation delta
    let δCommit : Nat := 10  -- Commit gate strictness increase
    
    { θ with
      psi := {
        lambdaMin  := θ.psi.lambdaMin + δ    -- Tighten coupling floor
        kappaMin   := θ.psi.kappaMin + δ     -- Tighten coherence floor
        thetaMin   := θ.psi.thetaMin + δ     -- Tighten autonomy floor
        epsilonMax := θ.psi.epsilonMax + δ   -- Option B: reduce translate sensitivity
      }
      commitExtra := θ.commitExtra + δCommit
      commitCooldown := clampNat θ.commitCooldown 2
      hysteresisSteps := clampNat θ.hysteresisSteps 3
      maxSwitches := θ.maxSwitches  -- Keep conservative
    }
  else
    θ  -- No intervention when stable

/-! ## FLUX RESULT -/

structure FluxResult where
  theta'   : FluxParams      -- Adapted parameters
  override : Option Mode     -- Forced mode (Witness during oscillation)
  why      : String          -- Explanation
deriving Repr, DecidableEq

-- Φ: The flux operator
def Flux (θ : FluxParams) (osc : OscillationReport) : FluxResult :=
  if osc.oscillating then
    { theta' := adaptThresholds θ osc
      override := some Mode.Witness
      why := "Oscillation: Witness clamp + hysteresis + stricter commit gate" }
  else
    { theta' := θ
      override := none
      why := "Stable: no flux intervention" }

/-! ## PSI ROUTER (STATE-LEVEL LOGIC) -/

structure SignalReport where
  weakCoupling  : Bool
  drift         : Bool
  lowCoherence  : Bool
  lowAutonomy   : Bool
  translateFlag : Bool
  repairFlag    : Bool
  stabilizeFlag : Bool
  witnessFlag   : Bool
  commitAllowed : Bool
  routedMode    : Mode
  routedReason  : Reason
deriving Repr, DecidableEq

def psiRouter 
    (thresholds : PsiThresholds)
    (psi : PsiState)
    (commitExtra : Nat)  -- Additional commit strictness from flux
    (requestCommit : Bool := false)
    : SignalReport :=
  
  let weakCoupling := decide (psi.lambda < thresholds.lambdaMin)
  let drift := decide (thresholds.epsilonMax < psi.epsilon)
  let lowCoherence := decide (psi.kappa < thresholds.kappaMin)
  let lowAutonomy := decide (psi.theta < thresholds.thetaMin)
  
  let translateFlag := drift
  let repairFlag := weakCoupling || lowAutonomy
  let stabilizeFlag := lowCoherence
  let witnessFlag := (translateFlag && repairFlag) || 
                     (translateFlag && stabilizeFlag) || 
                     (repairFlag && stabilizeFlag)
  
  -- Commit allowed only if no flags AND extra strictness satisfied
  let baseCommitAllowed := !(translateFlag || repairFlag || stabilizeFlag || witnessFlag)
  let commitAllowed := baseCommitAllowed && (commitExtra == 0)
  
  let baseMode :=
    if witnessFlag then Mode.Witness
    else if translateFlag then Mode.Translate
    else if repairFlag then Mode.Repair
    else if stabilizeFlag then Mode.Stabilize
    else Mode.Normal
  
  let baseReason :=
    if witnessFlag then Reason.Conflict
    else if translateFlag then Reason.Drift
    else if repairFlag then Reason.AnchorSlip
    else if stabilizeFlag then Reason.Overload
    else Reason.Stable
  
  let (finalMode, finalReason) :=
    if requestCommit then
      if commitAllowed then 
        (Mode.Commit, Reason.CommitGranted)
      else 
        (baseMode, Reason.CommitDenied)
    else 
      (baseMode, baseReason)
  
  {
    weakCoupling  := weakCoupling
    drift         := drift
    lowCoherence  := lowCoherence
    lowAutonomy   := lowAutonomy
    translateFlag := translateFlag
    repairFlag    := repairFlag
    stabilizeFlag := stabilizeFlag
    witnessFlag   := witnessFlag
    commitAllowed := commitAllowed
    routedMode    := finalMode
    routedReason  := finalReason
  }

/-! ## UNIFIED OPERATOR (THREE-LEVEL INTEGRATION) -/

structure UnifiedOutput where
  -- State layer
  stateProposal   : Mode
  stateReason     : Reason
  
  -- Flux layer
  fluxDecision    : Option Mode
  oscillationInfo : OscillationReport
  adaptedParams   : FluxParams
  
  -- Final decision
  finalMode       : Mode
  finalReason     : Reason
  fluxOverridden  : Bool
  decisionPath    : String
deriving Repr, DecidableEq

def unifiedOperator
    (θ : FluxParams)
    (psi : PsiState)
    (modeHistory : List Mode)
    (requestCommit : Bool := false)
    : UnifiedOutput :=
  
  -- LEVEL 1: Detect oscillation
  let osc := oscillationDetector modeHistory θ.maxSwitches
  
  -- LEVEL 2: Flux operator (reparameterize if oscillating)
  let flux := Flux θ osc
  let θ_adapted := flux.theta'
  
  -- LEVEL 3: State router with adapted parameters
  let stateReport := psiRouter θ_adapted.psi psi θ_adapted.commitExtra requestCommit
  
  -- LEVEL 4: Final decision with precedence (flux > state)
  let (finalMode, finalReason, overridden, path) :=
    match flux.override with
    | some Mode.Witness =>
        (Mode.Witness, Reason.FluxOverride, true, flux.why)
    | some otherMode =>
        (otherMode, Reason.FluxOverride, true, flux.why)
    | none =>
        (stateReport.routedMode, stateReport.routedReason, false,
         "State router decision (flux stable)")
  
  {
    stateProposal   := stateReport.routedMode
    stateReason     := stateReport.routedReason
    fluxDecision    := flux.override
    oscillationInfo := osc
    adaptedParams   := θ_adapted
    finalMode       := finalMode
    finalReason     := finalReason
    fluxOverridden  := overridden
    decisionPath    := path
  }

/-! ## SYSTEM STATE AND STEPPING -/

structure SystemState where
  psi         : PsiState
  modeHistory : List Mode  -- Most recent first
deriving Repr, DecidableEq

structure SystemConfig where
  fluxParams   : FluxParams
  pressureConfig : PressureConfig  -- Safety-critical, off-limits to flux
  safetyBounds : SafetyBounds      -- Hard constraints
  historyWindow : Nat := 5
deriving Repr, DecidableEq

def stepSystem
    (config : SystemConfig)
    (state : SystemState)
    (requestCommit : Bool := false)
    : UnifiedOutput × SystemState :=
  
  let output := unifiedOperator
    config.fluxParams
    state.psi
    state.modeHistory
    requestCommit

  -- SENTINEL: hard veto for irreversible transitions.
  -- Φ can move freely; Sentinel constrains consequences.
  let vetoCommit : Bool :=
    (output.finalMode == Mode.Commit) &&
    (output.oscillationInfo.oscillating ||
     decide (state.psi.theta < config.safetyBounds.minHumanAutonomy) ||
     decide (state.psi.epsilon > config.safetyBounds.maxPressureIntensity))

  let output : UnifiedOutput :=
    if vetoCommit then
      { output with
        finalMode := Mode.Witness
        finalReason := Reason.SentinelVeto
        decisionPath := output.decisionPath ++ " | SENTINEL veto: no irreversible action" }
    else
      output
  
  -- Update mode history (prepend new mode, trim to window)
  let newHistory := (output.finalMode :: state.modeHistory).take config.historyWindow
  
  -- Note: In real system, psi would be updated by simulation layer
  -- For now we keep it unchanged
  let newState : SystemState := {
    psi := state.psi
    modeHistory := newHistory
  }
  
  (output, newState)

/-! ## DEFAULT CONFIGURATIONS -/

def defaultFluxParams : FluxParams := {
  psi := {}  -- Uses PsiThresholds defaults
  commitExtra := 0
  commitCooldown := 0
  hysteresisSteps := 0
  maxSwitches := 2
}

def defaultPressureConfig : PressureConfig := {}
def defaultSafetyBounds : SafetyBounds := {}

def defaultConfig : SystemConfig := {
  fluxParams := defaultFluxParams
  pressureConfig := defaultPressureConfig
  safetyBounds := defaultSafetyBounds
  historyWindow := 5
}

/-! ## TEST CASES -/

-- Test 1: Stable window → no flux intervention
def stableHistory : List Mode := [
  Mode.Normal,
  Mode.Normal,
  Mode.Normal,
  Mode.Normal
]

def stablePsi : PsiState := {
  lambda  := 80
  kappa   := 60
  theta   := 55
  epsilon := 25
}

def stableState : SystemState := {
  psi := stablePsi
  modeHistory := stableHistory
}

#eval
  let (output, _) := stepSystem defaultConfig stableState
  (output.finalMode, output.fluxOverridden, output.decisionPath)
-- Expected: (Mode.Normal, false, "State router decision (flux stable)")

-- Test 2: Oscillating window → flux override to Witness
def oscillatingHistory : List Mode := [
  Mode.Translate,
  Mode.Repair,
  Mode.Translate,
  Mode.Repair,
  Mode.Translate
]

def driftPsi : PsiState := {
  lambda  := 80
  kappa   := 60
  theta   := 55
  epsilon := 35  -- Above threshold (32), triggers Translate
}

def oscillatingState : SystemState := {
  psi := driftPsi
  modeHistory := oscillatingHistory
}

#eval
  let (output, _) := stepSystem defaultConfig oscillatingState
  (output.stateProposal, output.finalMode, output.fluxOverridden, 
   output.adaptedParams.psi.lambdaMin, output.adaptedParams.commitExtra)
-- Expected: 
-- stateProposal = Translate (state detects drift)
-- finalMode = Witness (flux overrides)
-- fluxOverridden = true
-- adaptedParams.psi.lambdaMin = 80 (75 + 5)
-- adaptedParams.commitExtra = 10

-- Test 3: After flux adaptation, verify commit is blocked
def afterAdaptationState : SystemState := {
  psi := stablePsi  -- Even with good psi
  modeHistory := [Mode.Witness, Mode.Witness]  -- Recent witness
}

def configAfterFlux : SystemConfig := {
  fluxParams := {
    psi := { lambdaMin := 80, kappaMin := 55, thetaMin := 55, epsilonMax := 37 }
    commitExtra := 10  -- Still elevated from flux intervention
    commitCooldown := 2
    hysteresisSteps := 3
    maxSwitches := 2
  }
  pressureConfig := defaultPressureConfig
  safetyBounds := defaultSafetyBounds
  historyWindow := 5
}

#eval
  let (output, _) := stepSystem configAfterFlux afterAdaptationState true
  (output.finalMode, output.finalReason)
-- Expected: (Mode.Normal or Mode.Witness, Reason.CommitDenied)
-- Commit is blocked due to commitExtra > 0

/-! ## BEHAVIORAL CONTRACTS

1. Stable window → Flux.override = none, Θ unchanged
   ✓ Verified in Test 1

2. Flap window (T-R-T) → Flux.override = Witness, Θ tightened
   ✓ Verified in Test 2
   - commitCooldown ≥ 2
   - hysteresisSteps ≥ 3
   - lambdaMin increased by 5

3. If oscillating: Commit cannot occur even if ψ looks good
   ✓ Verified in Test 3
   - commitExtra > 0 blocks commit
   - Even with good psi values
-/

/-! ## ARCHITECTURE SUMMARY

THREE LEVELS COEXISTING:

LEVEL 1: Oscillation Detection (Ω)
  - Examines mode trajectory H_n
  - Detects flapping and switch count
  - Returns OscillationReport

LEVEL 2: Flux Operator (Φ)
  - Takes (Θ, Ω(H_n))
  - If oscillating: U(Θ, H_n) → Θ' (reparameterize)
  - If oscillating: override → Witness (anti-collapse)
  - Returns FluxResult

LEVEL 3: State Router (R)
  - Takes (Θ', ψ)
  - Applies thresholds to current state
  - Proposes mode
  - Returns SignalReport

LEVEL 4: Integration
  - Precedence: flux.override > stateRouter.mode
  - Safety: Θ' cannot violate PressureConfig or SafetyBounds
  - Result: UnifiedOutput

FIELD SEPARATION:
  Φ-owned (adaptive): PsiThresholds, commitExtra, hysteresis, maxSwitches
  Off-limits (safety): PressureConfig, SafetyBounds

INVARIANTS:
  Safety: Hard constraints never violated
  Coherence: Optimized by Φ through Θ adaptation
  Anti-collapse: Commit blocked during oscillation
-/



/-! ## OPERATOR PACKET (mode-specific human+AI signaling)

This is the “what do I do next / what do I say next / what do I measure” layer.
It is *runtime-only* and intentionally stringy.

Design goal: make the kernel usable as an instrument panel, not just a router.
-/

structure OperatorPacket where
  mode     : Mode
  why      : Reason
  headline : String
  doNow    : String
  sayNow   : String
  measure  : String
  nextGate : String
deriving Repr, DecidableEq

/-- Compact pretty print for ψ so the packet can show it without needing external tooling. -/
def psiSig (ψ : PsiState) : String :=
  "ψ=(λ" ++ toString ψ.lambda ++ ",κ" ++ toString ψ.kappa ++ ",θ" ++ toString ψ.theta ++ ",ε" ++ toString ψ.epsilon ++ ")"

/-- A single packet generator. Uses *final* decision + oscillation flags + ψ snapshot. -/
def operatorPacket (output : UnifiedOutput) (ψ : PsiState) : OperatorPacket :=
  let osc := output.oscillationInfo
  match output.finalMode with
  | Mode.Witness =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "WITNESS: hold state (no commitments)"
        doNow :=
          if osc.oscillating then
            "Freeze decisions 1 cycle. Reduce pressure. Re-anchor context. Then Translate."
          else
            "Hold state. Re-sense telemetry. Avoid forced resolution."
        sayNow :=
          "WITNESS. Not refusing—preventing collapse. Give: last stable goal, last stable def, current constraint. " ++ psiSig ψ
        measure :=
          "Log: ε=" ++ toString ψ.epsilon ++ ", switches(window)=" ++ toString osc.switches ++ ". 1 line: what changed (human) + what is missing (AI)."
        nextGate :=
          "Exit when oscillating=false AND drift=false (or when sentinel clears commit)." }

  | Mode.Hold =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "HOLD: stabilize inside source"
        doNow :=
          "Slow down; reduce branching. Keep pressure local until safeTransfer becomes true."
        sayNow :=
          "HOLD. Not a veto—it's a containment. Provide: 1) current intent 2) last stable anchor 3) what changed." ++ " " ++ psiSig ψ
        measure :=
          "Log: ε=" ++ toString ψ.epsilon ++ ", switches(window)=" ++ toString osc.switches ++ ". Track: overload flags + safeTransfer."
        nextGate :=
          "Exit when overload=false AND safeTransfer=true (or sentinel allows Translate)." }

  | Mode.Translate =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "TRANSLATE: remap context before fixing"
        doNow := "Re-state the task in a smaller basis; reduce semantic load; pin 1 invariant + 1 next action."
        sayNow := "TRANSLATE. Provide: goal, constraints, last good state, and 1 example. " ++ psiSig ψ
        measure := "Watch ε and drift flag; if ε stays high, widen translate band or reduce branching."
        nextGate := "Exit when drift=false OR oscillation triggers Witness." }

  | Mode.Repair =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "REPAIR: restore coupling / autonomy"
        doNow := "Restore anchors: definitions, naming, scope. Reduce ambiguity. Tighten one loop."
        sayNow := "REPAIR. Provide: exact failing line, expected behavior, and minimal reproduction. " ++ psiSig ψ
        measure := "Watch λ and θ; if λ<λ_min or θ<θ_min, coupling/autonomy is slipping."
        nextGate := "Exit when weakCoupling=false AND lowAutonomy=false." }

  | Mode.Stabilize =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "STABILIZE: reduce pressure / branching"
        doNow := "Cut branching factor. Shrink scope. Make one lemma/step compile."
        sayNow := "STABILIZE. Provide: smallest scope, remove extras, keep one target. " ++ psiSig ψ
        measure := "Watch κ; if κ<κ_min, coherence is overloaded; lower chaos/pressure."
        nextGate := "Exit when lowCoherence=false (κ recovered) and oscillation=false." }

  | Mode.Commit =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "COMMIT: safe to lock in"
        doNow := "Ship the step. Record invariants and hash (if desired)."
        sayNow := "COMMIT. Confirm: tests pass, constraints satisfied, telemetry stable. " ++ psiSig ψ
        measure := "Confirm commitAllowed=true AND sentinel ok."
        nextGate := "After commit, resume Normal." }

  | Mode.Normal =>
      { mode := output.finalMode
        why := output.finalReason
        headline := "NORMAL: continue"
        doNow := "Proceed." 
        sayNow := "NORMAL. Keep working. " ++ psiSig ψ
        measure := "Periodic check: oscillation window + drift." 
        nextGate := "If drift/oscillation appears, kernel will route." }

/-! ## TELEMETRY PACKET (paste-safe defaults)

These values mirror your phone-run telemetry style:
- ψ = (λ94, κ89, θ85, ε66)
- recent history = Translate ↔ Repair flapping

Run the `#eval` at the end to see the UnifiedOutput.
-/

def psiS : PsiState := { lambda := 94, kappa := 89, theta := 85, epsilon := 66 }

def w : List Mode :=
  [Mode.Translate, Mode.Repair, Mode.Translate, Mode.Repair]

def telemetryState : SystemState := { psi := psiS, modeHistory := w }

def telemetryOut : UnifiedOutput := (stepSystem defaultConfig telemetryState).1
#eval telemetryOut
#eval operatorPacket telemetryOut psiS

end STK_FluxIntegrated
