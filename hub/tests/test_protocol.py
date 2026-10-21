import math
import struct

from regina_hub import protocol as P
from regina_hub.fusion import FusedSample


def test_imu_roundtrip_scales_and_timestamps():
    # +1 g on z, +100 dps on x at +-8 g / +-2000 dps
    lsb_g = 4096
    lsb_dps = 32768 / 2000
    samples = [(0, 0, 0, lsb_g, int(100 * lsb_dps), 0, 0), (5000, 0, 0, lsb_g, 0, 0, 0), (5000, -lsb_g, 0, 0, 0, 0, -int(50 * lsb_dps))]
    pkt = P.parse_imu(P.build_imu(7, 0xFFFFF000, samples))
    assert pkt.seq == 7
    assert [s.t_us for s in pkt.samples] == [0xFFFFF000, (0xFFFFF000 + 5000) & 0xFFFFFFFF, (0xFFFFF000 + 10000) & 0xFFFFFFFF]
    assert math.isclose(pkt.samples[0].accel_g[2], 1.0, rel_tol=1e-6)
    assert math.isclose(pkt.samples[0].gyro_dps[0], 100.0, rel_tol=1e-3)
    assert math.isclose(pkt.samples[2].accel_g[0], -1.0, rel_tol=1e-6)
    assert math.isclose(pkt.samples[2].gyro_dps[2], -50.0, rel_tol=1e-3)


def test_imu_packet_size_fits_ble_mtu():
    data = P.build_imu(0, 0, [(0, 0, 0, 0, 0, 0, 0)] * 4)
    assert len(data) == 8 + 4 * 14
    assert len(data) <= 247 - 3


def test_input_and_status_roundtrip():
    inp = P.parse_input(P.build_input(P.BTN_A | P.BTN_D, -3, 12, 123456))
    assert (inp.buttons, inp.dial_small, inp.dial_big, inp.t_us) == (9, -3, 12, 123456)
    st = P.parse_status(P.build_status(None, True, True, False, (0, 1), 2))
    assert st.battery is None and st.charging and st.imu_ok and not st.imu_irq and st.fw == (0, 1) and st.player == 2


def test_commands():
    assert P.cmd_set_player(3) == b"\x01\x03"
    assert P.cmd_beep(2000, 80) == struct.pack("<BHH", 4, 2000, 80)
    assert P.cmd_beep(99999, -5) == struct.pack("<BHH", 4, 20000, 0)


def test_ui_normalize_and_tlv_roundtrip():
    ui = P.normalize_ui(
        {
            "clear": True,
            "title": "ARCHERY",
            "main": "75%",
            "bar": {"pct": 175, "label": "POWER"},
            "legends": ["DRAW", None, "", "ZERO"],
            "toast": {"ms": 800, "text": "HIT!"},
            "bogus": 1,
        }
    )
    assert "bogus" not in ui and ui["bar"]["pct"] == 100
    decoded = P.decode_ui_tlv(P.encode_ui_tlv(ui))
    assert decoded["clear"] is True
    assert decoded["title"] == "ARCHERY" and decoded["main"] == "75%"
    assert decoded["bar"] == {"pct": 100, "label": "POWER"}
    assert decoded["legends"] == ["DRAW", None, "", "ZERO"]
    assert decoded["toast"] == {"ms": 800, "text": "HIT!"}


def test_ui_non_ascii_and_length_limits():
    ui = P.normalize_ui({"title": "射箭" + "x" * 100, "bar": None})
    tlv = P.encode_ui_tlv(ui)
    decoded = P.decode_ui_tlv(tlv)
    assert decoded["title"].startswith("??") and len(decoded["title"]) == P.UI_MAX_STR
    assert decoded["bar"] is None
    assert len(tlv) <= 244


def test_ui_state_merges_partial_updates():
    st = P.UiState()
    st.apply({"clear": True, "title": "A", "legends": ["X", None, None, None]})
    st.apply({"main": "B", "legends": [None, "Y", None, None], "toast": {"ms": 500, "text": "t"}})
    snap = st.snapshot()
    assert snap == {"clear": True, "title": "A", "main": "B", "legends": ["X", "Y", None, None]}


def test_game_samples_layout():
    s = FusedSample(t=12.5, q=(1.0, 0.0, 0.0, 0.0), gyro=(1.0, 2.0, 3.0), accel=(0.0, 9.8, 0.0), lin_world=(0.1, 0.2, 0.3))
    dgrams = P.build_game_samples(5, [s] * 20)
    assert len(dgrams) == 2
    assert len(dgrams[0]) == 4 + 16 * 60
    cid, rows = P.parse_game_samples(dgrams[1])
    assert cid == 5 and len(rows) == 4
    t, qx, qy, qz, qw, gx, gy, gz, ax, ay, az, lx, ly, lz = rows[0]
    assert t == 12.5 and (qx, qy, qz, qw) == (0.0, 0.0, 0.0, 1.0)
    assert math.isclose(ay, 9.8, rel_tol=1e-6) and math.isclose(lz, 0.3, rel_tol=1e-6)


def test_game_input_layout():
    data = P.build_game_input(2, 5, -40000, 7, 0.5, float("nan"))
    assert len(data) == P.INPUT_DATAGRAM_SIZE == 16
    typ, ver, cid, b, small, big, a0, a1 = struct.unpack("<BBBBhhff", data)
    assert (typ, ver, cid, b, small, big, a0, a1) == (0x49, 1, 2, 5, -32768, 7, 0.5, 0.0)


def test_normalize_vibe():
    assert P.normalize_vibe({}) == [60]
    assert P.normalize_vibe({"ms": 120}) == [120]
    assert P.normalize_vibe({"ms": "x"}) == []
    assert P.normalize_vibe({"pattern": [30, 60, 30]}) == [30, 60, 30]
    # Ends on a pulse; steps clamped to 1 s; the whole thing to 3 s.
    assert P.normalize_vibe({"pattern": [30, 60]}) == [30]
    assert P.normalize_vibe({"pattern": [5000, -3, 40]}) == [1000, 0, 40]
    assert P.normalize_vibe({"pattern": [1000] * 9}) == [1000, 1000, 1000]
    assert len(P.normalize_vibe({"pattern": [10] * 40})) == 15
