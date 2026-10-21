"""Minimal quaternion / vector math. Quaternions are (w, x, y, z) tuples."""

from __future__ import annotations

import math

Vec3 = tuple[float, float, float]
Quat = tuple[float, float, float, float]

IDENTITY: Quat = (1.0, 0.0, 0.0, 0.0)


def v_add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_len(a: Vec3) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def v_norm(a: Vec3) -> Vec3:
    n = v_len(a)
    if n < 1e-12:
        return (0.0, 0.0, 0.0)
    return (a[0] / n, a[1] / n, a[2] / n)


def q_mul(a: Quat, b: Quat) -> Quat:
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (
        aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
    )


def q_conj(q: Quat) -> Quat:
    return (q[0], -q[1], -q[2], -q[3])


def q_normalize(q: Quat) -> Quat:
    n = math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
    if n < 1e-12:
        return IDENTITY
    return (q[0] / n, q[1] / n, q[2] / n, q[3] / n)


def q_rotate(q: Quat, v: Vec3) -> Vec3:
    """Rotate vector v by unit quaternion q (body -> world when q is an orientation)."""
    w, x, y, z = q
    # t = 2 * cross(q.xyz, v)
    tx = 2.0 * (y * v[2] - z * v[1])
    ty = 2.0 * (z * v[0] - x * v[2])
    tz = 2.0 * (x * v[1] - y * v[0])
    # v' = v + w * t + cross(q.xyz, t)
    return (
        v[0] + w * tx + (y * tz - z * ty),
        v[1] + w * ty + (z * tx - x * tz),
        v[2] + w * tz + (x * ty - y * tx),
    )


def q_from_axis_angle(axis: Vec3, angle: float) -> Quat:
    a = v_norm(axis)
    s = math.sin(angle * 0.5)
    return (math.cos(angle * 0.5), a[0] * s, a[1] * s, a[2] * s)


def q_from_rotvec(r: Vec3) -> Quat:
    """Quaternion for a rotation vector (axis * angle), exact exponential map."""
    angle = v_len(r)
    if angle < 1e-9:
        return q_normalize((1.0, r[0] * 0.5, r[1] * 0.5, r[2] * 0.5))
    s = math.sin(angle * 0.5) / angle
    return (math.cos(angle * 0.5), r[0] * s, r[1] * s, r[2] * s)


def q_from_two_vectors(u: Vec3, v: Vec3) -> Quat:
    """Shortest rotation taking direction u onto direction v."""
    u = v_norm(u)
    v = v_norm(v)
    d = v_dot(u, v)
    if d < -0.999999:
        # Opposite: rotate 180 deg around any axis perpendicular to u.
        axis = v_cross((1.0, 0.0, 0.0), u)
        if v_len(axis) < 1e-6:
            axis = v_cross((0.0, 1.0, 0.0), u)
        return q_from_axis_angle(axis, math.pi)
    c = v_cross(u, v)
    return q_normalize((1.0 + d, c[0], c[1], c[2]))


def q_twist_y(q: Quat) -> Quat:
    """Twist component of q around the world +Y axis (swing-twist decomposition)."""
    w, _, y, _ = q
    n = math.sqrt(w * w + y * y)
    if n < 1e-9:
        return IDENTITY
    return (w / n, 0.0, y / n, 0.0)


def q_yaw(q: Quat) -> float:
    """Heading angle (rad) around +Y; 0 means the controller's -Z points at world -Z."""
    t = q_twist_y(q)
    return 2.0 * math.atan2(t[2], t[0])


def q_angle_between(a: Quat, b: Quat) -> float:
    d = abs(a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3])
    return 2.0 * math.acos(min(1.0, d))
