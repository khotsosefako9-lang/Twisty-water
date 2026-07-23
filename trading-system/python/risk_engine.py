"""
Python mirror of RiskEngine.mqh — same formula, same hard caps, so the
Python bridge and the MT5 EA never disagree on lot size or trade rejection.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from config import RiskConfig
from mt5_connector import SymbolSpec


@dataclass
class LotDecision:
    lot: float
    reject_reason: Optional[str] = None

    @property
    def accepted(self) -> bool:
        return self.lot > 0 and self.reject_reason is None


class RiskEngine:
    def __init__(self, config: RiskConfig):
        self.config = config
        self.risk_percent = min(config.risk_percent, config.max_risk_percent)

    def normalize_lot(self, raw_lot: float, spec: SymbolSpec) -> float:
        if spec.lot_step <= 0:
            return 0.0
        steps = math.floor(raw_lot / spec.lot_step)
        lot = steps * spec.lot_step
        if lot < spec.min_lot:
            return 0.0
        if lot > spec.max_lot:
            lot = spec.max_lot
        return round(lot, 2)

    def calculate_lot_size(self, balance: float, stop_distance_price: float, spec: SymbolSpec) -> LotDecision:
        if stop_distance_price <= 0:
            return LotDecision(0.0, "invalid stop distance")

        risk_amount = balance * (self.risk_percent / 100.0)
        if spec.tick_size <= 0 or spec.tick_value <= 0:
            return LotDecision(0.0, "symbol tick value/size unavailable")

        money_per_unit_price_per_lot = spec.tick_value / spec.tick_size
        raw_lot = risk_amount / (stop_distance_price * money_per_unit_price_per_lot)
        lot = self.normalize_lot(raw_lot, spec)

        if lot <= 0:
            return LotDecision(0.0, "computed lot below broker minimum — risk% too small for this stop distance")

        actual_risk = lot * stop_distance_price * money_per_unit_price_per_lot
        max_allowed_risk = balance * (self.config.max_risk_percent / 100.0)
        if actual_risk > max_allowed_risk * 1.01:
            return LotDecision(0.0, "rounded lot would exceed max risk ceiling")

        return LotDecision(lot)

    def validate_spread(self, spread_points: float) -> tuple[bool, str]:
        if spread_points > self.config.max_spread_points:
            return False, f"spread {spread_points:.1f} pts exceeds max {self.config.max_spread_points:.1f}"
        return True, ""

    def validate_volatility(self, atr_value: float, price: float) -> tuple[bool, str]:
        if price <= 0:
            return False, "invalid price"
        atr_pct = (atr_value / price) * 100.0
        if atr_pct < self.config.min_atr_pct:
            return False, f"ATR% {atr_pct:.4f} below min {self.config.min_atr_pct:.4f} (dead market)"
        if atr_pct > self.config.max_atr_pct:
            return False, f"ATR% {atr_pct:.4f} above max {self.config.max_atr_pct:.4f} (abnormal spike)"
        return True, ""
