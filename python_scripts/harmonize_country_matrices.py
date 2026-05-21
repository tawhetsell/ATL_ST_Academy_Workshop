#!/usr/bin/env python3

"""Harmonize cleaned country matrices onto a common country roster.

This is the final preprocessing step before R. It reads the cleaned yearly
ISO3 matrices from `apply_country_crosswalk.py`, builds or applies a shared
country roster, and writes matrices with identical row/column order.

Example:
cd /Users/traviswhetsell/Desktop/ST_Academy_Workshop
python3 scripts/harmonize_country_matrices.py ai_country_clean --output-dir ai_country_model
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
import re


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pad and reorder cleaned AI country matrices to a common ISO3 roster."
    )
    parser.add_argument(
        "clean_matrix_dir",
        help="Directory containing *_ai_country_matrix_clean.csv files.",
    )
    parser.add_argument(
        "--output-dir",
        default="ai_country_model",
        help="Directory where harmonized matrices and roster will be written.",
    )
    parser.add_argument(
        "--roster-csv",
        default=None,
        help=(
            "Optional CSV with an ISO3 roster. If omitted, the union of countries "
            "observed in the cleaned matrices is used."
        ),
    )
    parser.add_argument(
        "--roster-column",
        default="iso3",
        help="Column name to read from --roster-csv.",
    )
    return parser.parse_args()


def infer_year_label(path: Path) -> str:
    match = re.search(r"(19|20)\d{2}", path.name)
    if not match:
        raise ValueError(f"Could not infer year from filename: {path}")
    return match.group(0)


def discover_matrix_files(clean_matrix_dir: Path) -> list[Path]:
    matrix_files = sorted(clean_matrix_dir.glob("*_ai_country_matrix_clean.csv"))
    if not matrix_files:
        raise FileNotFoundError(f"No *_ai_country_matrix_clean.csv files found in {clean_matrix_dir}")
    return matrix_files


def read_matrix(path: Path) -> tuple[list[str], dict[tuple[str, str], int]]:
    with path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.reader(csv_f)
        header = next(reader)
        countries = header[1:]
        values: dict[tuple[str, str], int] = {}
        for row in reader:
            row_country = row[0]
            for col_country, value in zip(countries, row[1:]):
                values[(row_country, col_country)] = int(value)
    return countries, values


def read_roster(path: Path, column: str) -> list[str]:
    with path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.DictReader(csv_f)
        if column not in (reader.fieldnames or []):
            raise ValueError(f"Roster file must contain column '{column}': {path}")
        roster = sorted({row[column].strip().upper() for row in reader if row[column].strip()})
    if not roster:
        raise ValueError(f"Roster file contains no countries in column '{column}': {path}")
    return roster


def build_union_roster(matrix_files: list[Path]) -> list[str]:
    countries: set[str] = set()
    for matrix_file in matrix_files:
        matrix_countries, _ = read_matrix(matrix_file)
        countries.update(matrix_countries)
    return sorted(countries)


def write_roster(roster: list[str], output_path: Path) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["iso3"])
        for iso3 in roster:
            writer.writerow([iso3])


def write_harmonized_matrix(
    year: str,
    roster: list[str],
    values: dict[tuple[str, str], int],
    output_dir: Path,
) -> Path:
    output_path = output_dir / f"{year}_ai_country_matrix_harmonized.csv"
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["country", *roster])
        for row_country in roster:
            writer.writerow(
                [
                    row_country,
                    *[values.get((row_country, col_country), 0) for col_country in roster],
                ]
            )
    return output_path


def write_summary(rows: list[dict[str, object]], output_path: Path) -> None:
    fieldnames = [
        "year",
        "input_matrix",
        "output_matrix",
        "input_node_count",
        "harmonized_node_count",
    ]
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.DictWriter(csv_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    clean_matrix_dir = Path(args.clean_matrix_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    matrix_files = discover_matrix_files(clean_matrix_dir)
    if args.roster_csv:
        roster = read_roster(Path(args.roster_csv), args.roster_column)
    else:
        roster = build_union_roster(matrix_files)

    write_roster(roster, output_dir / "country_roster.csv")

    summary_rows = []
    for matrix_file in matrix_files:
        year = infer_year_label(matrix_file)
        input_countries, values = read_matrix(matrix_file)
        output_path = write_harmonized_matrix(year, roster, values, output_dir)
        summary_rows.append(
            {
                "year": year,
                "input_matrix": str(matrix_file),
                "output_matrix": str(output_path),
                "input_node_count": len(input_countries),
                "harmonized_node_count": len(roster),
            }
        )
        print(f"{year}: wrote harmonized matrix with {len(roster)} countries -> {output_path}")

    write_summary(summary_rows, output_dir / "harmonize_summary.csv")
    print(f"Wrote roster to {output_dir / 'country_roster.csv'}")


if __name__ == "__main__":
    main()
