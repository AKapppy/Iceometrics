from __future__ import annotations

import datetime as dt
import errno
import re
import time
from pathlib import Path
from typing import Any, Callable, TypeVar, cast
from urllib.parse import urljoin

import pandas as pd
import requests

DATE_IN_NAME = re.compile(r"(?<!\d)(\d{4})[-_]?(\d{2})[-_]?(\d{2})(?!\d)")
CSV_HREF = re.compile(r'href="([^"]+\.csv)"', re.IGNORECASE)
T = TypeVar("T")


def _is_deadlock_error(exc: Exception) -> bool:
    if isinstance(exc, OSError) and exc.errno == errno.EDEADLK:
        return True
    return "Resource deadlock avoided" in str(exc)


def _retry_deadlock(fn: Callable[..., T], /, *args: object, retries: int = 4, delay_s: float = 0.12, **kwargs: object) -> T:
    last: Exception | None = None
    for i in range(retries + 1):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            if not _is_deadlock_error(e) or i >= retries:
                raise
            last = e
            time.sleep(delay_s * (i + 1))
    if last is not None:
        raise last
    raise RuntimeError("unreachable")


def _safe_float(v: object, default: float = float("nan")) -> float:
    try:
        return float(cast(Any, v))
    except Exception:
        return default


def date_from_filename(filename: str) -> dt.date | None:
    m = DATE_IN_NAME.search(filename)
    return None if not m else dt.date(*map(int, m.groups()))


def list_dated_csv_links(index_url: str, *, headers: dict[str, str]) -> list[tuple[str, str, dt.date]]:
    request_headers = dict(headers)
    request_headers.update(
        {
            "Cache-Control": "no-cache, no-store, max-age=0",
            "Pragma": "no-cache",
        }
    )

    r = requests.get(
        index_url,
        headers=request_headers,
        params={"iceometrics_v": str(time.time_ns())},
        timeout=30,
    )
    r.raise_for_status()

    out: dict[str, tuple[str, str, dt.date]] = {}
    for href in CSV_HREF.findall(r.text):
        filename = href.split("/")[-1]
        d = date_from_filename(filename)
        if not d:
            continue
        if filename not in out:
            out[filename] = (filename, urljoin(index_url, href), d)

    return list(out.values())


def download_file(url: str, out_path: Path, *, headers: dict[str, str]) -> None:
    tmp = out_path.with_suffix(out_path.suffix + ".part")

    request_headers = dict(headers)
    request_headers.update(
        {
            "Cache-Control": "no-cache, no-store, max-age=0",
            "Pragma": "no-cache",
        }
    )

    with requests.get(
        url,
        headers=request_headers,
        params={"iceometrics_v": str(time.time_ns())},
        stream=True,
        timeout=60,
    ) as r:
        r.raise_for_status()

        with _retry_deadlock(open, tmp, "wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 256):
                if chunk:
                    f.write(chunk)

    _retry_deadlock(tmp.replace, out_path)


def download_missing_simulations(
    start_date: dt.date,
    end_date: dt.date,
    sims_dir: Path,
    *,
    headers: dict[str, str],
    ensure_dir_writable: Callable[[Path], None],
    index_url: str,
) -> list[str]:
    try:
        ensure_dir_writable(sims_dir)
    except Exception as e:
        return [f"Directory error: {e}"]

    try:
        links = list_dated_csv_links(index_url, headers=headers)
    except Exception as e:
        return [f"Failed to read index page: {e}"]

    index_dates = [d for _, _, d in links]
    latest_index_date = max(index_dates) if index_dates else None

    print(
        "MoneyPuck index: "
        f"{len(links)} dated CSVs; "
        f"latest={latest_index_date.isoformat() if latest_index_date else 'none'}"
    )

    in_range = [
        (f, u)
        for (f, u, d) in links
        if start_date <= d <= end_date
    ]

    def _exists(path: Path) -> bool:
        return bool(_retry_deadlock(path.exists))

    to_download = [
        (f, u)
        for (f, u) in in_range
        if not _exists(sims_dir / f)
    ]

    print(
        "Downloads needed."
        if to_download
        else "No downloads needed from index."
    )

    errors: list[str] = []

    for filename, file_url in to_download:
        try:
            download_file(
                file_url,
                sims_dir / filename,
                headers=headers,
            )
            print(f"Downloaded {filename}")
        except Exception as e:
            errors.append(f"{filename}: {e}")

    # MoneyPuck can publish the newest simulation to simulations_recent.csv
    # several hours before the matching dated archive appears in the directory.
    # update_date.txt is the source of truth for which hockey date "recent"
    # represents.
    try:
        request_headers = dict(headers)
        request_headers.update(
            {
                "Cache-Control": "no-cache, no-store, max-age=0",
                "Pragma": "no-cache",
            }
        )

        update_response = requests.get(
            urljoin(index_url, "update_date.txt"),
            headers=request_headers,
            params={"iceometrics_v": str(time.time_ns())},
            timeout=30,
        )
        update_response.raise_for_status()

        recent_updated_at = dt.datetime.fromisoformat(
            update_response.text.strip()
        )
        recent_date = recent_updated_at.date()

        print(
            "MoneyPuck recent: "
            f"updated_at={recent_updated_at.isoformat()}, "
            f"date={recent_date.isoformat()}"
        )

        if start_date <= recent_date <= end_date:
            filename = f"simulations_{recent_date:%Y_%m_%d}.csv"
            recent_path = sims_dir / filename

            # Treat the dated local file as the cache for that hockey date.
            # If today's MoneyPuck file is already present, leave it alone.
            # Otherwise, use simulations_recent.csv so a newly published day
            # is available even before it appears in the dated archive index.
            if _exists(recent_path):
                print(
                    "MoneyPuck recent already present locally: "
                    f"{filename}"
                )
            else:
                download_file(
                    urljoin(index_url, "simulations_recent.csv"),
                    recent_path,
                    headers=headers,
                )

                print(
                    "MoneyPuck recent downloaded as "
                    f"{filename}"
                )
        else:
            print(
                "MoneyPuck recent does not cover requested range: "
                f"{start_date.isoformat()}..{end_date.isoformat()}"
            )

    except Exception as exc:
        errors.append(
            f"MoneyPuck recent fallback: {exc}"
        )

    return errors


def date_range(start: dt.date, end: dt.date) -> list[dt.date]:
    return [start + dt.timedelta(days=i) for i in range((end - start).days + 1)]


def md_label(d: dt.date) -> str:
    return f"{d.month}/{d.day}"


def compile_probability_tables(
    sims_dir: Path,
    start_date: dt.date,
    end_date: dt.date,
    *,
    metrics: dict[str, str],
    canon_team_code: Callable[[str], str],
    forward_fill: bool = True,
) -> dict[str, pd.DataFrame]:
    all_dates = date_range(start_date, end_date)
    date_to_col = {d: md_label(d) for d in all_dates}
    columns = [date_to_col[d] for d in all_dates]

    values: dict[str, dict[tuple[str, dt.date], float]] = {k: {} for k in metrics}
    teams: set[str] = set()

    csv_files = _retry_deadlock(lambda: sorted(sims_dir.glob("*.csv")))
    for csv_path in csv_files:
        file_date = date_from_filename(csv_path.name)
        if not file_date or not (start_date <= file_date <= end_date):
            continue

        df = cast(pd.DataFrame, _retry_deadlock(pd.read_csv, csv_path))
        scenario_col = "scenario" if "scenario" in df.columns else "scenerio" if "scenerio" in df.columns else None
        if scenario_col is None or "teamCode" not in df.columns:
            continue

        df_all = df.loc[df[scenario_col].astype(str).str.upper() == "ALL"].copy()
        if df_all.empty:
            continue

        df_all["teamCode"] = df_all["teamCode"].astype(str).map(canon_team_code)
        df_all["teamCode"] = df_all["teamCode"].astype(str)
        teams.update(df_all["teamCode"].tolist())

        for out_key, src_col in metrics.items():
            if src_col not in df_all.columns:
                continue
            for team, val in zip(df_all["teamCode"], df_all[src_col]):
                try:
                    values[out_key][(str(team), file_date)] = _safe_float(val)
                except Exception:
                    pass

    idx = sorted(teams)
    tables: dict[str, pd.DataFrame] = {}
    for out_key in metrics:
        table = pd.DataFrame(index=idx, columns=columns, dtype="float64")
        for (team, d), v in values[out_key].items():
            table.loc[team, date_to_col[d]] = v
        if forward_fill:
            table = table.ffill(axis=1)

        tables[out_key] = table

    return tables


def append_terminal_outcome(tables, terminal_date, outcomes):
    """Append the factual next-day result to provider tables with provenance."""
    if not terminal_date or not outcomes:
        return tables
    col = md_label(terminal_date)
    mapping = {"madeplayoffs": "make_playoffs", "round2": "round2", "round3": "round3", "round4": "finals", "woncup": "cup"}
    for table_key, metric in mapping.items():
        table = tables.get(table_key)
        if table is None: continue
        for code in outcomes:
            if code not in table.index: table.loc[code] = float("nan")
            table.loc[code, col] = float(outcomes[code][metric])
        table.attrs.setdefault("column_sources", {})[col] = "final_result"
    return tables
