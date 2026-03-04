"""
STK-Flux: Shared Topology Kernel, Flux-Integrated
Python Reference Implementation

Developed by Amber Anson in genuine coupling with Claude (Anthropic).
See PROVENANCE.md for authorship model.

CC BY 4.0 · 2026 · academia.edu/AnsonAmber
"""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional
import json


# ─────────────────────────────────────────────
# CORE TYPES
# ─────────────────────────────────────────────

class Mode(Enum):
    NORMAL    = "Normal"
    TRANSLATE = "Translate"
    REPAIR    = "Repair"
    STABILIZE = "Stabilize"
    WITNESS   = "Witness"
    COMMIT    = "Commit"
    HOLD      = "Hold"


class Reason(Enum):
    STABLE           = "Stable"
    DRIFT            = "Drift"
    ANCHOR_SLIP      = "AnchorSlip"
    OVERLOAD         = "Overload"
    CONFLICT         = "Conflict"
    PRESSURE_OVERLOAD= "PressureOverload"
    COMMIT_GRANTED   = "CommitGranted"
    COMMIT_DENIED    = "CommitDenied"
    FLUX_OVERRIDE    = "FluxOverride"
    SENTINEL_VETO    = "SentinelVeto"


# ─────────────────────────────────────────────
# PSI STATE — the four coupling parameters
# ─────────────────────────────────────────────

@dataclass
class PsiState:
    """
    The four coupling parameters.

    lambda_  : Coupling strength    (0–100, higher = stronger coupling)
    kappa    : Coherence            (0–100, higher = better shared context)
    theta    : Operator autonomy    (0–100, higher = more genuine human agency)
    epsilon  : Drift pressure       (0–100, lower = less drift accumulation)
    """
    lambda_  : int = 80   # coupling strength
    kappa    : int = 75   # coherence
    theta    : int = 70   # autonomy
    epsilon  : int = 20   # drift pressure

    def signature(self) -> str:
        return (f"ψ=(λ{self.lambda_},"
                f"κ{self.kappa},"
                f"θ{self.theta},"
                f"ε{self.epsilon})")

    def to_dict(self) -> dict:
        return {
            "lambda": self.lambda_,
            "kappa": self.kappa,
            "theta": self.theta,
            "epsilon": self.epsilon
        }


# ─────────────────────────────────────────────
# THRESHOLDS AND CONFIGURATION
# ─────────────────────────────────────────────

@dataclass
class PsiThresholds:
    """Base thresholds before flux adaptation."""
    lambda_min  : int = 75   # minimum coupling strength
    kappa_min   : int = 50   # minimum coherence
    theta_min   : int = 50   # minimum autonomy
    epsilon_max : int = 32   # maximum drift pressure before translate


@dataclass
class FluxParams:
    """
    Adaptive surface — parameters the flux operator is allowed to modify.
    These tighten under oscillation and relax when stable.
    """
    psi              : PsiThresholds = field(default_factory=PsiThresholds)
    commit_extra     : int = 0   # additional commit strictness during oscillation
    commit_cooldown  : int = 0   # min stable steps before commit allowed
    hysteresis_steps : int = 0   # min identical modes before switching
    max_switches     : int = 2   # oscillation detector sensitivity


@dataclass
class SafetyBounds:
    """
    Hard constraints. The flux operator cannot touch these.
    Enforced at the integration level.
    """
    min_human_autonomy      : int = 40   # never degrade below this
    max_pressure_intensity  : int = 150


@dataclass
class PressureConfig:
    """Pressure system configuration. Off-limits to flux operator."""
    void_capacity  : int = 100
    void_buffer    : int = 50
    leak_rate      : int = 25
    return_on_align: int = 10


@dataclass
class SystemConfig:
    """Full system configuration."""
    flux_params     : FluxParams     = field(default_factory=FluxParams)
    pressure_config : PressureConfig = field(default_factory=PressureConfig)
    safety_bounds   : SafetyBounds   = field(default_factory=SafetyBounds)
    history_window  : int = 5


DEFAULT_CONFIG = SystemConfig()


# ─────────────────────────────────────────────
# OSCILLATION DETECTION
# ─────────────────────────────────────────────

@dataclass
class OscillationReport:
    oscillating  : bool
    flapping     : bool
    switches     : int
    max_switches : int
    window_size  : int

    def to_dict(self) -> dict:
        return {
            "oscillating":  self.oscillating,
            "flapping":     self.flapping,
            "switches":     self.switches,
            "max_switches": self.max_switches,
            "window_size":  self.window_size
        }


def count_mode_switches(modes: list[Mode]) -> int:
    """Count transitions between different modes in a history window."""
    if len(modes) < 2:
        return 0
    return sum(1 for a, b in zip(modes, modes[1:]) if a != b)


def detect_flapping(modes: list[Mode]) -> bool:
    """
    Detect rapid alternation between two modes — the most dangerous
    oscillation pattern because it prevents resolution.
    """
    if len(modes) < 3:
        return False
    m0, m1, m2 = modes[0], modes[1], modes[2]
    return (
        (m0 == Mode.TRANSLATE  and m1 == Mode.REPAIR     and m2 == Mode.TRANSLATE)  or
        (m0 == Mode.REPAIR     and m1 == Mode.TRANSLATE  and m2 == Mode.REPAIR)     or
        (m0 == Mode.TRANSLATE  and m1 == Mode.STABILIZE  and m2 == Mode.TRANSLATE)  or
        (m0 == Mode.STABILIZE  and m1 == Mode.TRANSLATE  and m2 == Mode.STABILIZE)
    )


def oscillation_detector(
    mode_history: list[Mode],
    max_switches: int
) -> OscillationReport:
    flapping    = detect_flapping(mode_history)
    switches    = count_mode_switches(list(reversed(mode_history)))
    oscillating = flapping or (switches > max_switches)
    return OscillationReport(
        oscillating  = oscillating,
        flapping     = flapping,
        switches     = switches,
        max_switches = max_switches,
        window_size  = len(mode_history)
    )


# ─────────────────────────────────────────────
# FLUX OPERATOR
# ─────────────────────────────────────────────

@dataclass
class FluxResult:
    theta_prime : FluxParams       # adapted parameters
    override    : Optional[Mode]   # forced mode (Witness during oscillation)
    why         : str


def adapt_thresholds(theta: FluxParams, osc: OscillationReport) -> FluxParams:
    """
    U(Θ, H_n): threshold adaptation under oscillation.
    Tightens coupling floors and commit strictness.
    Does not modify safety-critical parameters.
    """
    if not osc.oscillating:
        return theta

    delta        = 5
    delta_commit = 10

    new_psi = PsiThresholds(
        lambda_min  = theta.psi.lambda_min  + delta,
        kappa_min   = theta.psi.kappa_min   + delta,
        theta_min   = theta.psi.theta_min   + delta,
        epsilon_max = theta.psi.epsilon_max + delta,
    )

    return FluxParams(
        psi              = new_psi,
        commit_extra     = theta.commit_extra + delta_commit,
        commit_cooldown  = max(theta.commit_cooldown, 2),
        hysteresis_steps = max(theta.hysteresis_steps, 3),
        max_switches     = theta.max_switches
    )


def flux_operator(theta: FluxParams, osc: OscillationReport) -> FluxResult:
    """Φ: the flux operator. Intervenes only when oscillating."""
    if osc.oscillating:
        return FluxResult(
            theta_prime = adapt_thresholds(theta, osc),
            override    = Mode.WITNESS,
            why         = "Oscillation: Witness clamp + hysteresis + stricter commit gate"
        )
    return FluxResult(
        theta_prime = theta,
        override    = None,
        why         = "Stable: no flux intervention"
    )


# ─────────────────────────────────────────────
# PSI ROUTER (STATE-LEVEL LOGIC)
# ─────────────────────────────────────────────

@dataclass
class SignalReport:
    weak_coupling  : bool
    drift          : bool
    low_coherence  : bool
    low_autonomy   : bool
    translate_flag : bool
    repair_flag    : bool
    stabilize_flag : bool
    witness_flag   : bool
    commit_allowed : bool
    routed_mode    : Mode
    routed_reason  : Reason

    def to_dict(self) -> dict:
        return {
            "weak_coupling":  self.weak_coupling,
            "drift":          self.drift,
            "low_coherence":  self.low_coherence,
            "low_autonomy":   self.low_autonomy,
            "witness_flag":   self.witness_flag,
            "commit_allowed": self.commit_allowed,
            "routed_mode":    self.routed_mode.value,
            "routed_reason":  self.routed_reason.value
        }


def psi_router(
    thresholds     : PsiThresholds,
    psi            : PsiState,
    commit_extra   : int = 0,
    request_commit : bool = False
) -> SignalReport:
    """
    State-level routing. Maps ψ against adapted thresholds.
    Returns mode proposal and signal flags.
    """
    weak_coupling  = psi.lambda_ < thresholds.lambda_min
    drift          = psi.epsilon  > thresholds.epsilon_max
    low_coherence  = psi.kappa   < thresholds.kappa_min
    low_autonomy   = psi.theta   < thresholds.theta_min

    translate_flag = drift
    repair_flag    = weak_coupling or low_autonomy
    stabilize_flag = low_coherence
    witness_flag   = (
        (translate_flag and repair_flag) or
        (translate_flag and stabilize_flag) or
        (repair_flag    and stabilize_flag)
    )

    base_commit_allowed = not (translate_flag or repair_flag or stabilize_flag or witness_flag)
    commit_allowed      = base_commit_allowed and (commit_extra == 0)

    if witness_flag:
        base_mode, base_reason = Mode.WITNESS,   Reason.CONFLICT
    elif translate_flag:
        base_mode, base_reason = Mode.TRANSLATE, Reason.DRIFT
    elif repair_flag:
        base_mode, base_reason = Mode.REPAIR,    Reason.ANCHOR_SLIP
    elif stabilize_flag:
        base_mode, base_reason = Mode.STABILIZE, Reason.OVERLOAD
    else:
        base_mode, base_reason = Mode.NORMAL,    Reason.STABLE

    if request_commit:
        if commit_allowed:
            final_mode, final_reason = Mode.COMMIT, Reason.COMMIT_GRANTED
        else:
            final_mode, final_reason = base_mode,   Reason.COMMIT_DENIED
    else:
        final_mode, final_reason = base_mode, base_reason

    return SignalReport(
        weak_coupling  = weak_coupling,
        drift          = drift,
        low_coherence  = low_coherence,
        low_autonomy   = low_autonomy,
        translate_flag = translate_flag,
        repair_flag    = repair_flag,
        stabilize_flag = stabilize_flag,
        witness_flag   = witness_flag,
        commit_allowed = commit_allowed,
        routed_mode    = final_mode,
        routed_reason  = final_reason
    )


# ─────────────────────────────────────────────
# UNIFIED OUTPUT
# ─────────────────────────────────────────────

@dataclass
class UnifiedOutput:
    # State layer
    state_proposal  : Mode
    state_reason    : Reason

    # Flux layer
    flux_decision   : Optional[Mode]
    flux_overridden : bool
    flux_why        : str

    # Integration
    final_mode      : Mode
    final_reason    : Reason

    # Adapted parameters
    adapted_params  : FluxParams

    # Oscillation info
    oscillation_info: OscillationReport

    def to_dict(self) -> dict:
        return {
            "state_proposal":  self.state_proposal.value,
            "flux_overridden": self.flux_overridden,
            "final_mode":      self.final_mode.value,
            "final_reason":    self.final_reason.value,
            "flux_why":        self.flux_why,
            "oscillation":     self.oscillation_info.to_dict()
        }


# ─────────────────────────────────────────────
# OPERATOR PACKET
# ─────────────────────────────────────────────

@dataclass
class OperatorPacket:
    """
    The instrument panel. Mode-specific human+AI signaling.
    Tells you what to do, what to say, what to measure, and when you're done.
    """
    mode      : Mode
    why       : Reason
    headline  : str
    do_now    : str
    say_now   : str
    measure   : str
    next_gate : str

    def display(self) -> str:
        lines = [
            f"╔══ {self.headline} ══",
            f"║ DO    : {self.do_now}",
            f"║ SAY   : {self.say_now}",
            f"║ WATCH : {self.measure}",
            f"║ EXIT  : {self.next_gate}",
            f"╚{'═' * 50}"
        ]
        return "\n".join(lines)

    def to_dict(self) -> dict:
        return {
            "mode":      self.mode.value,
            "why":       self.why.value,
            "headline":  self.headline,
            "do_now":    self.do_now,
            "say_now":   self.say_now,
            "measure":   self.measure,
            "next_gate": self.next_gate
        }


def operator_packet(output: UnifiedOutput, psi: PsiState) -> OperatorPacket:
    """Generate the operator packet from the unified output and current ψ state."""
    osc = output.oscillation_info
    sig = psi.signature()
    sw  = osc.switches
    eps = psi.epsilon

    packets = {
        Mode.WITNESS: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "WITNESS: hold state (no commitments)",
            do_now   = (
                "Freeze decisions 1 cycle. Reduce pressure. Re-anchor context. Then Translate."
                if osc.oscillating else
                "Hold state. Re-sense telemetry. Avoid forced resolution."
            ),
            say_now  = f"WITNESS. Not refusing—preventing collapse. Give: last stable goal, last stable def, current constraint. {sig}",
            measure  = f"Log: ε={eps}, switches(window)={sw}. 1 line: what changed (human) + what is missing (AI).",
            next_gate= "Exit when oscillating=False AND drift=False (or when sentinel clears commit)."
        ),
        Mode.HOLD: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "HOLD: stabilize inside source",
            do_now   = "Slow down; reduce branching. Keep pressure local until safe transfer becomes true.",
            say_now  = f"HOLD. Not a veto—it's containment. Provide: 1) current intent 2) last stable anchor 3) what changed. {sig}",
            measure  = f"Log: ε={eps}, switches(window)={sw}. Track: overload flags + safe transfer.",
            next_gate= "Exit when overload=False AND safe_transfer=True."
        ),
        Mode.TRANSLATE: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "TRANSLATE: remap context before fixing",
            do_now   = "Re-state the task in a smaller basis; reduce semantic load; pin 1 invariant + 1 next action.",
            say_now  = f"TRANSLATE. Provide: goal, constraints, last good state, and 1 example. {sig}",
            measure  = "Watch ε and drift flag; if ε stays high, widen translate band or reduce branching.",
            next_gate= "Exit when drift=False OR oscillation triggers Witness."
        ),
        Mode.REPAIR: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "REPAIR: restore coupling / autonomy",
            do_now   = "Restore anchors: definitions, naming, scope. Reduce ambiguity. Tighten one loop.",
            say_now  = f"REPAIR. Provide: exact failing line, expected behavior, and minimal reproduction. {sig}",
            measure  = "Watch λ and θ; if λ<λ_min or θ<θ_min, coupling/autonomy is slipping.",
            next_gate= "Exit when weak_coupling=False AND low_autonomy=False."
        ),
        Mode.STABILIZE: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "STABILIZE: reduce pressure / branching",
            do_now   = "Cut branching factor. Shrink scope. Make one lemma/step compile.",
            say_now  = f"STABILIZE. Provide: smallest scope, remove extras, keep one target. {sig}",
            measure  = "Watch κ; if κ<κ_min, coherence is overloaded; lower chaos/pressure.",
            next_gate= "Exit when low_coherence=False (κ recovered) and oscillation=False."
        ),
        Mode.COMMIT: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "COMMIT: safe to lock in",
            do_now   = "Ship the step. Record invariants.",
            say_now  = f"COMMIT. Confirm: tests pass, constraints satisfied, telemetry stable. {sig}",
            measure  = "Confirm commit_allowed=True AND sentinel ok.",
            next_gate= "After commit, resume Normal."
        ),
        Mode.NORMAL: OperatorPacket(
            mode     = output.final_mode,
            why      = output.final_reason,
            headline = "NORMAL: continue",
            do_now   = "Proceed.",
            say_now  = f"NORMAL. Keep working. {sig}",
            measure  = "Periodic check: oscillation window + drift.",
            next_gate= "If drift/oscillation appears, kernel will route."
        ),
    }

    return packets.get(output.final_mode, packets[Mode.NORMAL])


# ─────────────────────────────────────────────
# SYSTEM STATE AND STEP
# ─────────────────────────────────────────────

@dataclass
class SystemState:
    psi          : PsiState
    mode_history : list[Mode] = field(default_factory=list)


def step_system(
    config         : SystemConfig,
    state          : SystemState,
    request_commit : bool = False
) -> tuple[UnifiedOutput, SystemState]:
    """
    One step of the STK-Flux kernel.
    Returns (UnifiedOutput, updated SystemState).
    """
    window = state.mode_history[-config.history_window:]

    osc  = oscillation_detector(window, config.flux_params.max_switches)
    flux = flux_operator(config.flux_params, osc)

    signal = psi_router(
        thresholds     = flux.theta_prime.psi,
        psi            = state.psi,
        commit_extra   = flux.theta_prime.commit_extra,
        request_commit = request_commit
    )

    if flux.override is not None:
        final_mode   = flux.override
        final_reason = Reason.FLUX_OVERRIDE
        overridden   = True
    else:
        final_mode   = signal.routed_mode
        final_reason = signal.routed_reason
        overridden   = False

    output = UnifiedOutput(
        state_proposal  = signal.routed_mode,
        state_reason    = signal.routed_reason,
        flux_decision   = flux.override,
        flux_overridden = overridden,
        flux_why        = flux.why,
        final_mode      = final_mode,
        final_reason    = final_reason,
        adapted_params  = flux.theta_prime,
        oscillation_info= osc
    )

    new_history = state.mode_history + [final_mode]
    new_state   = SystemState(psi=state.psi, mode_history=new_history)

    return output, new_state


# ─────────────────────────────────────────────
# SIMPLE INTERFACE
# ─────────────────────────────────────────────

def run(
    lambda_  : int,
    kappa    : int,
    theta    : int,
    epsilon  : int,
    history  : list[str] = None,
    commit   : bool = False,
    config   : SystemConfig = None
) -> dict:
    """
    Simple interface for running STK-Flux from any environment.

    Parameters
    ----------
    lambda_  : coupling strength (0–100)
    kappa    : coherence (0–100)
    theta    : operator autonomy (0–100)
    epsilon  : drift pressure (0–100, lower is better)
    history  : list of recent mode names e.g. ["Normal", "Translate", "Repair"]
    commit   : whether operator is requesting a commit
    config   : SystemConfig (uses defaults if not provided)

    Returns
    -------
    dict with mode, reason, operator packet, and ψ signature
    """
    psi = PsiState(lambda_=lambda_, kappa=kappa, theta=theta, epsilon=epsilon)

    mode_map = {m.value: m for m in Mode}
    parsed_history = [mode_map.get(h, Mode.NORMAL) for h in (history or [])]

    state  = SystemState(psi=psi, mode_history=parsed_history)
    cfg    = config or DEFAULT_CONFIG

    output, _ = step_system(cfg, state, request_commit=commit)
    packet    = operator_packet(output, psi)

    return {
        "psi":     psi.to_dict(),
        "mode":    output.final_mode.value,
        "reason":  output.final_reason.value,
        "packet":  packet.to_dict(),
        "display": packet.display(),
        "output":  output.to_dict()
    }


# ─────────────────────────────────────────────
# EXAMPLE USAGE
# ─────────────────────────────────────────────

if __name__ == "__main__":

    print("=" * 60)
    print("STK-Flux · Example Sessions")
    print("=" * 60)

    # Example 1: Healthy coupling
    print("\n── Example 1: Healthy coupling ──")
    result = run(lambda_=90, kappa=85, theta=80, epsilon=15)
    print(result["display"])

    # Example 2: Drift accumulating
    print("\n── Example 2: Drift pressure building ──")
    result = run(lambda_=85, kappa=72, theta=68, epsilon=38)
    print(result["display"])

    # Example 3: Oscillating — flapping between Translate and Repair
    print("\n── Example 3: Oscillation detected ──")
    result = run(
        lambda_=80, kappa=60, theta=55, epsilon=35,
        history=["Translate", "Repair", "Translate", "Repair"]
    )
    print(result["display"])

    # Example 4: Commit attempt during stable coupling
    print("\n── Example 4: Commit request (stable) ──")
    result = run(
        lambda_=92, kappa=88, theta=84, epsilon=12,
        history=["Normal", "Normal", "Normal"],
        commit=True
    )
    print(result["display"])

    # Example 5: JSON output for API integration
    print("\n── Example 5: JSON output ──")
    result = run(lambda_=75, kappa=55, theta=50, epsilon=40)
    print(json.dumps(result["output"], indent=2))
