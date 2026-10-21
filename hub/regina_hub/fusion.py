"""Sensor fusion shared by every controller source.

Input:  device-timestamped raw gyro (rad/s) + accel (m/s^2, incl. gravity) in the canonical body frame.
Output: recentered orientation, bias-corrected gyro, body accel and world linear accel.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass

from .quat import (
    IDENTITY,
    Quat,
    Vec3,
    q_conj,
    q_from_rotvec,
    q_from_two_vectors,
    q_mul,
    q_normalize,
    q_rotate,
    q_twist_y,
    v_add,
    v_cross,
    v_len,
    v_scale,
    v_sub,
)

GRAVITY = 9.80665
WORLD_UP: Vec3 = (0.0, 1.0, 0.0)


class TimeMapper:
    """Maps a device clock (microseconds, optionally wrapping) onto the hub's monotonic clock.

    The offset tracks the minimum observed (hub - device) difference, i.e. the lowest-latency
    packet, and creeps upward slowly so clock drift between the two clocks is followed.
    """

    def __init__(self, wrap_bits: int | None = 32, drift_per_s: float = 2e-4):
        self._wrap = (1 << wrap_bits) if wrap_bits else None
        self._last_raw: float | None = None
        self._epochs = 0
        self._offset: float | None = None
        self._last_hub: float | None = None
        self._drift = drift_per_s

    def device_seconds(self, raw_us: float) -> float:
        if self._wrap is not None and self._last_raw is not None:
            if raw_us < self._last_raw and (self._last_raw - raw_us) > self._wrap / 2:
                self._epochs += 1
        self._last_raw = raw_us
        wrapped = self._epochs * self._wrap if self._wrap is not None else 0
        return (raw_us + wrapped) / 1e6

    def observe(self, device_s: float, hub_now: float) -> None:
        cand = hub_now - device_s
        if self._offset is None or cand < self._offset:
            self._offset = cand
        elif self._last_hub is not None:
            self._offset += self._drift * max(0.0, hub_now - self._last_hub)
            self._offset = min(self._offset, cand)
        self._last_hub = hub_now

    def to_hub(self, device_s: float) -> float:
        return device_s + (self._offset or 0.0)


class _RunningStats:
    """O(1) sliding-window mean / variance for a scalar."""

    def __init__(self, size: int):
        self.size = size
        self.buf: deque[float] = deque()
        self.s = 0.0
        self.s2 = 0.0

    def push(self, x: float) -> None:
        self.buf.append(x)
        self.s += x
        self.s2 += x * x
        if len(self.buf) > self.size:
            old = self.buf.popleft()
            self.s -= old
            self.s2 -= old * old

    @property
    def full(self) -> bool:
        return len(self.buf) >= self.size

    @property
    def mean(self) -> float:
        return self.s / max(1, len(self.buf))

    @property
    def std(self) -> float:
        n = max(1, len(self.buf))
        m = self.s / n
        return math.sqrt(max(0.0, self.s2 / n - m * m))

    def clear(self) -> None:
        self.buf.clear()
        self.s = 0.0
        self.s2 = 0.0


@dataclass
class BiasConfig:
    window_s: float = 0.4
    gyro_std_max: float = 0.03       # rad/s, noise level while held still on a table / in hand rest
    accel_std_max: float = 0.25      # m/s^2
    accel_norm_tol: float = 0.6      # m/s^2 from 1 g
    max_rate_uncal: float = 0.35     # rad/s, mean rate accepted as bias before first calibration
    max_rate_cal: float = 0.08       # rad/s residual accepted as bias drift afterwards
    initial_hold_s: float = 1.0
    track_hold_s: float = 0.5
    track_alpha: float = 0.01        # per-sample EMA while tracking
    forced_timeout_s: float = 5.0


class BiasEstimator:
    """Stationary detection + gyro zero-rate offset estimation."""

    def __init__(self, rate_hint_hz: float = 200.0, cfg: BiasConfig | None = None):
        self.cfg = cfg or BiasConfig()
        n = max(8, int(self.cfg.window_s * rate_hint_hz))
        self._g = [_RunningStats(n) for _ in range(3)]
        self._a = _RunningStats(n)
        self.bias: Vec3 = (0.0, 0.0, 0.0)
        self.calibrated = False
        self.stationary = False
        self._still_time = 0.0
        self._forced = False
        self._forced_elapsed = 0.0
        self.events: list[str] = []

    def request_calibration(self) -> None:
        self._forced = True
        self._forced_elapsed = 0.0

    @property
    def calibrating(self) -> bool:
        return self._forced or not self.calibrated

    def update(self, gyro_raw: Vec3, accel: Vec3, dt: float) -> None:
        for i in range(3):
            self._g[i].push(gyro_raw[i])
        self._a.push(v_len(accel))
        if not self._a.full:
            return

        mean = (self._g[0].mean, self._g[1].mean, self._g[2].mean)
        gstd = max(s.std for s in self._g)
        quiet = (
            gstd < self.cfg.gyro_std_max
            and self._a.std < self.cfg.accel_std_max
            and abs(self._a.mean - GRAVITY) < self.cfg.accel_norm_tol
        )
        residual = v_len(v_sub(mean, self.bias))
        limit = self.cfg.max_rate_uncal if (not self.calibrated or self._forced) else self.cfg.max_rate_cal
        self.stationary = quiet and (residual < limit or (not self.calibrated and v_len(mean) < limit))

        self._still_time = self._still_time + dt if self.stationary else 0.0

        if self._forced:
            self._forced_elapsed += dt
            if self._still_time >= self.cfg.initial_hold_s:
                self.bias = mean
                self.calibrated = True
                self._forced = False
                self.events.append("calibrated")
            elif self._forced_elapsed > self.cfg.forced_timeout_s:
                self._forced = False
                self.events.append("calibrate_failed")
            return

        if not self.calibrated:
            if self._still_time >= self.cfg.initial_hold_s:
                self.bias = mean
                self.calibrated = True
                self.events.append("calibrated")
        elif self._still_time >= self.cfg.track_hold_s:
            a = self.cfg.track_alpha
            self.bias = v_add(v_scale(self.bias, 1.0 - a), v_scale(gyro_raw, a))


@dataclass
class MahonyConfig:
    kp_moving: float = 0.6
    kp_still: float = 2.5
    kp_startup: float = 12.0
    startup_s: float = 1.5
    accel_gate: float = 0.15        # fraction of g; accel ignored outside 1 g +- gate


class Mahony:
    """Mahony complementary filter, Y-up world. q maps body -> world."""

    def __init__(self, cfg: MahonyConfig | None = None):
        self.cfg = cfg or MahonyConfig()
        self.q: Quat = IDENTITY
        self.initialized = False
        self._elapsed = 0.0

    def reset_from_accel(self, accel: Vec3) -> None:
        self.q = q_from_two_vectors(accel, WORLD_UP)
        self.initialized = True
        self._elapsed = 0.0

    def update(self, gyro: Vec3, accel: Vec3, dt: float, still: bool) -> Quat:
        if not self.initialized:
            if v_len(accel) > 1e-3:
                self.reset_from_accel(accel)
            return self.q

        self._elapsed += dt
        if self._elapsed < self.cfg.startup_s:
            kp = self.cfg.kp_startup
        else:
            kp = self.cfg.kp_still if still else self.cfg.kp_moving

        omega = gyro
        an = v_len(accel)
        if an > 1e-6 and abs(an - GRAVITY) < self.cfg.accel_gate * GRAVITY:
            a_n = v_scale(accel, 1.0 / an)
            up_body = q_rotate(q_conj(self.q), WORLD_UP)
            err = v_cross(a_n, up_body)
            omega = v_add(gyro, v_scale(err, kp))

        self.q = q_normalize(q_mul(self.q, q_from_rotvec(v_scale(omega, dt))))
        return self.q


@dataclass
class FusedSample:
    t: float
    q: Quat            # (w, x, y, z), recentered, body -> world
    gyro: Vec3         # body, rad/s, bias removed
    accel: Vec3        # body, m/s^2, incl. gravity
    lin_world: Vec3    # world, m/s^2, gravity removed


class ImuPipeline:
    """Bias estimation + Mahony + yaw recentering for one controller."""

    MAX_DT = 0.1

    def __init__(self, rate_hint_hz: float = 200.0):
        self.bias = BiasEstimator(rate_hint_hz)
        self.ahrs = Mahony()
        self._yaw_ref: Quat = IDENTITY
        self._last_t: float | None = None
        self._auto_recentered = False
        self._pending_recenter = False
        self.events: list[str] = []
        self.rate_hz = 0.0

    def recenter(self) -> None:
        self._yaw_ref = q_twist_y(self.ahrs.q)
        self.events.append("recentered")

    def request_calibration(self) -> None:
        self.bias.request_calibration()

    @property
    def orientation(self) -> Quat:
        return q_normalize(q_mul(q_conj(self._yaw_ref), self.ahrs.q))

    def push(self, t: float, gyro_raw: Vec3, accel: Vec3) -> FusedSample | None:
        if self._last_t is None:
            self._last_t = t
            self.ahrs.update((0.0, 0.0, 0.0), accel, 0.0, True)
            return None
        dt = t - self._last_t
        if dt <= 0.0:
            return None
        self._last_t = t
        if dt > self.MAX_DT:
            # Gap (packet loss / pause): don't integrate across it.
            dt = 1.0 / max(self.rate_hz, 50.0) if self.rate_hz else 0.005
        self.rate_hz = 1.0 / dt if self.rate_hz == 0.0 else self.rate_hz * 0.98 + (1.0 / dt) * 0.02

        self.bias.update(gyro_raw, accel, dt)
        if self.bias.events:
            for ev in self.bias.events:
                self.events.append(ev)
                if ev == "calibrated" and not self._auto_recentered:
                    self._auto_recentered = True
                    self._pending_recenter = True
            self.bias.events.clear()

        gyro = v_sub(gyro_raw, self.bias.bias)
        self.ahrs.update(gyro, accel, dt, self.bias.stationary)
        if self._pending_recenter:
            self._pending_recenter = False
            self.recenter()

        q = self.orientation
        lin = v_sub(q_rotate(q, accel), (0.0, GRAVITY, 0.0))
        return FusedSample(t=t, q=q, gyro=gyro, accel=accel, lin_world=lin)
