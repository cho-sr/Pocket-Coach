from __future__ import annotations

import math


def compute_zone_index(center_x: float, frame_width: int, num_zones: int = 7) -> int:
    if frame_width <= 0:
        raise ValueError("frame_width must be positive")
    zone_width = frame_width / float(num_zones)
    zone_idx = math.floor(center_x / zone_width)
    return max(0, min(num_zones - 1, zone_idx))


def compute_signal_angle(zone_idx: int) -> int:
    zone_idx = max(0, min(6, zone_idx))
    return 90 + (zone_idx - 3) * 5


def zone_label(zone_idx: int) -> str:
    return f"ZONE_{zone_idx + 1}"
