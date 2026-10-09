
from __future__ import annotations

import math
from typing import Any

import pandas as pd

from hockey_app.domain.seasons import games_per_team
from hockey_app.domain.teams import TEAM_NAMES, TEAM_TO_DIV
from hockey_app.ui.tabs.models_data import (
    games_played_snapshot,
    points_snapshot,
    standings_tiebreak_snapshot,
)
from hockey_app.ui.tabs.models_magic_tragic import (
    _conf_teams,
    _div_teams,
    _kth_highest,
    _magic_cell,
    _target_points,
    _tragic_cell,
)
from hockey_app.ui.tabs.models_point_probabilities import (
    _estimate_point_split_from_history,
)


def export_current_model_snapshots(
    *,
    points_df: pd.DataFrame | None,
    day,
    season: str,
    league: str = "NHL",
) -> dict[str, Any]:
    if not isinstance(points_df, pd.DataFrame) or points_df.empty or len(points_df.columns) == 0:
        return {
            "magicTragic": None,
            "pointProbabilities": None,
        }

    league_u = str(league or "NHL").upper()
    pts = points_snapshot(points_df, day)
    if not pts:
        return {
            "magicTragic": None,
            "pointProbabilities": None,
        }

    try:
        gp_map = games_played_snapshot(day, league=league_u)
    except Exception:
        gp_map = {}

    season_games = games_per_team(league_u, season)
    if season_games is None:
        season_games = 82
    season_games = int(season_games)

    standings = (
        standings_tiebreak_snapshot(day)
        if league_u == "NHL"
        else {}
    )

    return {
        "magicTragic": _magic_tragic_snapshot(
            pts=pts,
            gp_map=gp_map,
            standings=standings,
            day=day,
            season_games=season_games,
            league=league_u,
        ),
        "pointProbabilities": _point_probability_snapshot(
            points_df=points_df,
            pts=pts,
            gp_map=gp_map,
            day=day,
            season_games=season_games,
            league=league_u,
        ),
    }


def _magic_tragic_snapshot(
    *,
    pts: dict[str, float],
    gp_map: dict[str, int],
    standings: dict[str, dict[str, Any]],
    day,
    season_games: int,
    league: str,
) -> dict[str, Any] | None:
    if league != "NHL":
        return None

    conferences: list[dict[str, Any]] = []

    for conf in ("East", "West"):
        if conf == "East":
            div1, div2 = "Metro", "Atlantic"
        else:
            div1, div2 = "Central", "Pacific"

        conf_codes = _conf_teams(pts, conf, standings)
        if not conf_codes:
            continue

        div1_codes = _div_teams(pts, div1, standings)
        div2_codes = _div_teams(pts, div2, standings)
        slot_points = _target_points(pts, conf, standings)

        max_pts_map: dict[str, float] = {}
        games_remaining_map: dict[str, int] = {}
        for team in conf_codes:
            cur = float(pts.get(team, 0.0))
            gp = max(0, min(season_games, int(gp_map.get(team, 0))))
            gr = max(0, season_games - gp)
            games_remaining_map[team] = gr
            max_pts_map[team] = cur + 2.0 * gr

        slots = (
            "D1_1",
            "D1_2",
            "D1_3",
            "D2_1",
            "D2_2",
            "D2_3",
            "WC1",
            "WC2",
            "NP9",
        )

        labels = [
            f"{div1[0].upper()}1",
            f"{div1[0].upper()}2",
            f"{div1[0].upper()}3",
            f"{div2[0].upper()}1",
            f"{div2[0].upper()}2",
            f"{div2[0].upper()}3",
            "7",
            "8",
            "9+",
        ]

        rows: list[dict[str, Any]] = []

        for code in conf_codes:
            cur = float(pts.get(code, 0.0))
            mx = float(max_pts_map.get(code, cur))
            gr = int(games_remaining_map.get(code, 0))

            d1_others = [team for team in div1_codes if team != code]
            d2_others = [team for team in div2_codes if team != code]
            conf_others = [team for team in conf_codes if team != code]

            d1_vals = [max_pts_map.get(team, 0.0) for team in d1_others]
            d2_vals = [max_pts_map.get(team, 0.0) for team in d2_others]
            conf_vals = [max_pts_map.get(team, 0.0) for team in conf_others]

            playoff_cutoff_rival = _kth_highest(conf_vals, 8)
            same_d1 = TEAM_TO_DIV.get(code) == div1
            same_d2 = TEAM_TO_DIV.get(code) == div2

            magic: dict[str, str] = {}
            tragic: dict[str, str] = {}

            for slot in ("D1_1", "D1_2", "D1_3"):
                k = 1 if slot.endswith("_1") else 2 if slot.endswith("_2") else 3
                rival_max = _kth_highest(d1_vals, k)
                rival_next = _kth_highest(d1_vals, k + 1)
                if same_d1:
                    magic[slot] = _magic_cell(
                        cur,
                        mx,
                        slot_points[slot],
                        rival_max,
                        rival_next,
                        gr,
                        playoff_cutoff_rival,
                    )
                    tragic[slot] = _tragic_cell(
                        cur,
                        mx,
                        slot_points[slot],
                        rival_max,
                        rival_next,
                        gr,
                        playoff_cutoff_rival,
                    )
                else:
                    magic[slot] = "-"
                    tragic[slot] = "-"

            for slot in ("D2_1", "D2_2", "D2_3"):
                k = 1 if slot.endswith("_1") else 2 if slot.endswith("_2") else 3
                rival_max = _kth_highest(d2_vals, k)
                rival_next = _kth_highest(d2_vals, k + 1)
                if same_d2:
                    magic[slot] = _magic_cell(
                        cur,
                        mx,
                        slot_points[slot],
                        rival_max,
                        rival_next,
                        gr,
                        playoff_cutoff_rival,
                    )
                    tragic[slot] = _tragic_cell(
                        cur,
                        mx,
                        slot_points[slot],
                        rival_max,
                        rival_next,
                        gr,
                        playoff_cutoff_rival,
                    )
                else:
                    magic[slot] = "-"
                    tragic[slot] = "-"

            wc1_rival = _kth_highest(conf_vals, 8)
            wc2_rival = _kth_highest(conf_vals, 9)
            wc1_next = _kth_highest(conf_vals, 9)
            wc2_next = _kth_highest(conf_vals, 10)

            magic["WC1"] = _magic_cell(
                cur,
                mx,
                slot_points["WC1"],
                wc1_rival,
                wc1_next,
                gr,
                playoff_cutoff_rival,
            )
            magic["WC2"] = _magic_cell(
                cur,
                mx,
                slot_points["WC2"],
                wc2_rival,
                wc2_next,
                gr,
                playoff_cutoff_rival,
            )
            magic["NP9"] = "0"

            tragic["WC1"] = _tragic_cell(
                cur,
                mx,
                slot_points["WC1"],
                wc1_rival,
                wc1_next,
                gr,
                playoff_cutoff_rival,
            )
            tragic["WC2"] = _tragic_cell(
                cur,
                mx,
                slot_points["WC2"],
                wc2_rival,
                wc2_next,
                gr,
                playoff_cutoff_rival,
            )
            tragic["NP9"] = "MW"

            rows.append(
                {
                    "team": code,
                    "points": cur,
                    "gamesPlayed": season_games - gr,
                    "gamesRemaining": gr,
                    "magic": [magic.get(slot, "") for slot in slots],
                    "tragic": [tragic.get(slot, "") for slot in slots],
                }
            )

        conferences.append(
            {
                "name": conf,
                "columns": labels,
                "rows": rows,
            }
        )

    return {
        "day": day.isoformat(),
        "gamesPerTeam": season_games,
        "conferences": conferences,
    }


def _point_probability_snapshot(
    *,
    points_df: pd.DataFrame,
    pts: dict[str, float],
    gp_map: dict[str, int],
    day,
    season_games: int,
    league: str,
) -> dict[str, Any] | None:
    if league != "NHL" or not pts:
        return None

    teams = sorted(
        pts,
        key=lambda code: (TEAM_NAMES.get(code, code), code),
    )

    min_target = int(min(pts.values()))
    max_target = 0
    row_probs: dict[str, dict[int, float]] = {}

    for team in teams:
        cur_pts = float(pts[team])
        gp = int(gp_map.get(team, 0))

        if gp <= 0:
            gp = int(round(cur_pts / 1.15))
            gp = max(0, min(season_games, gp))

        gp_floor = int(math.ceil(cur_pts / 1.45))
        gp = max(gp, gp_floor)
        gp = max(0, min(season_games, gp))
        gr = max(0, season_games - gp)

        point_pct = max(
            0.01,
            min(
                0.99,
                cur_pts / float(max(2, 2.0 * gp)),
            ),
        )

        t_min = int(max(0, math.floor(cur_pts)))
        t_max = int(
            min(
                season_games * 2,
                math.floor(cur_pts + (2.0 * gr)),
            )
        )
        max_target = max(max_target, t_max)

        history: list[float] = []
        try:
            row = points_df.loc[team]
            history = [
                float(value)
                for value in row.tolist()
                if pd.notna(value)
            ]
        except Exception:
            history = []

        p0, p1, p2 = _estimate_point_split_from_history(
            history,
            gp,
            point_pct,
        )

        dist: dict[int, float] = {
            int(round(cur_pts)): 1.0
        }

        for _ in range(gr):
            nxt: dict[int, float] = {}
            for total, probability in dist.items():
                nxt[total] = nxt.get(total, 0.0) + probability * p0
                nxt[total + 1] = nxt.get(total + 1, 0.0) + probability * p1
                nxt[total + 2] = nxt.get(total + 2, 0.0) + probability * p2
            dist = nxt

        total_probability = sum(dist.values())
        if total_probability > 0.0:
            dist = {
                target: probability / total_probability
                for target, probability in dist.items()
            }

        row_probs[team] = {
            target: probability
            for target, probability in dist.items()
            if t_min <= target <= t_max
        }

    values = [
        target
        for target in range(min_target, max_target + 1)
        if any(
            row_probs.get(team, {}).get(target, 0.0) > 0.0
            for team in teams
        )
    ]

    rows: list[dict[str, Any]] = []
    for team in teams:
        probs = row_probs.get(team, {})
        if probs:
            prediction = int(
                max(
                    probs.items(),
                    key=lambda item: (
                        float(item[1]),
                        int(item[0]),
                    ),
                )[0]
            )
        else:
            prediction = int(round(float(pts.get(team, 0.0))))

        rows.append(
            {
                "team": team,
                "prediction": prediction,
                "probabilities": [
                    round(float(probs.get(target, 0.0)), 8)
                    for target in values
                ],
            }
        )

    rows.sort(
        key=lambda row: (
            -int(row["prediction"]),
            TEAM_NAMES.get(str(row["team"]), str(row["team"])),
            str(row["team"]),
        )
    )

    return {
        "day": day.isoformat(),
        "values": values,
        "rows": rows,
    }
