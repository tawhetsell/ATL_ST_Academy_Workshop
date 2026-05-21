#!/usr/bin/env python3

"""Parse AI-only WoS XML subsets into raw country collaboration files.

This script is the second stage of the workshop pipeline:

1. `subset_wos_ai_records.py`
   Produces one AI-only `xml.gz` file per year.
2. `parse_ai_country_matrices.py`
   Extracts raw affiliation-country ties from those subset files.
3. `apply_country_crosswalk.py`
   Maps raw country labels to ISO3 codes and merges duplicates.

The parser intentionally keeps country cleanup light. It preserves the raw
country strings in a variant report so ambiguous values can be audited before
they are collapsed to ISO3 codes.

Example:
cd /Users/traviswhetsell/Desktop/ST_Academy_Workshop
python3 scripts/parse_ai_country_matrices.py subset_ai_xml/2003_CORE_ai.xml.gz --output-dir ai_country_raw
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
import gzip
from itertools import combinations
from pathlib import Path
import re
import unicodedata
import xml.etree.ElementTree as ET


NS = {"wos": "http://clarivate.com/schema/wok5.30/public/FullRecord"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Parse one or more AI-only WoS xml.gz files into raw country "
            "edge lists, matrices, and country-variant reports."
        )
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help=(
            "One or more AI subset xml.gz files or directories that contain "
            "them, e.g. subset_ai_xml/2003_CORE_ai.xml.gz or subset_ai_xml/"
        ),
    )
    parser.add_argument(
        "--output-dir",
        default="ai_country_raw",
        help="Directory where raw country outputs will be written.",
    )
    return parser.parse_args()


def local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


def collapse_whitespace(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_country_label(text: str) -> str:
    """Keep a human-readable normalized label for later crosswalking."""
    ascii_text = (
        unicodedata.normalize("NFKD", text)
        .encode("ascii", "ignore")
        .decode("ascii")
    )
    ascii_text = ascii_text.replace("&", " and ")
    ascii_text = re.sub(r"[^A-Za-z0-9]+", " ", ascii_text.lower())
    return collapse_whitespace(ascii_text)


def resolve_input_files(input_args: list[str]) -> list[Path]:
    files: list[Path] = []
    for input_arg in input_args:
        path = Path(input_arg)
        if path.is_dir():
            files.extend(sorted(child for child in path.iterdir() if child.name.endswith(".xml.gz")))
        elif path.is_file():
            files.append(path)
        else:
            raise FileNotFoundError(f"Missing input path: {path}")
    if not files:
        raise FileNotFoundError("No .xml.gz files found in the provided inputs.")
    return files


def infer_year_label(path: Path) -> str:
    match = re.search(r"(19|20)\d{2}", path.name)
    if match:
        return match.group(0)
    return path.stem


def raw_output_prefix(path: Path) -> str:
    year = infer_year_label(path)
    return f"{year}_ai_country"


def extract_country_tokens(rec: ET.Element) -> list[tuple[str, str]]:
    tokens: list[tuple[str, str]] = []
    for address_name in rec.findall(
        "./wos:static_data/wos:fullrecord_metadata/wos:addresses/wos:address_name",
        NS,
    ):
        country_elem = address_name.find("./wos:address_spec/wos:country", NS)
        if country_elem is None or not country_elem.text:
            continue
        raw_country = collapse_whitespace(country_elem.text)
        normalized_country = normalize_country_label(raw_country)
        if not raw_country or not normalized_country:
            continue
        tokens.append((raw_country, normalized_country))
    return tokens


def extract_uid(rec: ET.Element) -> str:
    uid_elem = rec.find("./wos:UID", NS)
    if uid_elem is None or not uid_elem.text:
        return ""
    return collapse_whitespace(uid_elem.text)


def extract_pubyear(rec: ET.Element) -> str:
    pub_info = rec.find("./wos:static_data/wos:summary/wos:pub_info", NS)
    if pub_info is None:
        return ""
    return (pub_info.get("pubyear") or "").strip()


def write_edge_csv(edge_counts: dict[tuple[str, str], int], output_path: Path) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["source_normalized", "target_normalized", "weight"])
        for (source, target), weight in sorted(edge_counts.items()):
            writer.writerow([source, target, weight])


def write_variant_csv(
    variant_address_counts: Counter[tuple[str, str]],
    variant_paper_counts: Counter[tuple[str, str]],
    output_path: Path,
) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(
            [
                "normalized_country",
                "raw_country",
                "address_occurrences",
                "paper_occurrences",
            ]
        )
        keys = sorted(
            variant_address_counts.keys() | variant_paper_counts.keys(),
            key=lambda item: (item[1], item[0]),
        )
        for raw_country, normalized_country in keys:
            writer.writerow(
                [
                    normalized_country,
                    raw_country,
                    variant_address_counts[(raw_country, normalized_country)],
                    variant_paper_counts[(raw_country, normalized_country)],
                ]
            )


def write_matrix_csv(
    countries: set[str],
    edge_counts: dict[tuple[str, str], int],
    output_path: Path,
) -> None:
    ordered_countries = sorted(countries)
    index_lookup = {country: idx for idx, country in enumerate(ordered_countries)}
    matrix = [[0 for _ in ordered_countries] for _ in ordered_countries]

    for (source, target), weight in edge_counts.items():
        source_idx = index_lookup[source]
        target_idx = index_lookup[target]
        matrix[source_idx][target_idx] += weight
        matrix[target_idx][source_idx] += weight

    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["country", *ordered_countries])
        for country, row in zip(ordered_countries, matrix):
            writer.writerow([country, *row])


def write_paper_country_csv(paper_rows: list[dict[str, object]], output_path: Path) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(
            [
                "uid",
                "pubyear",
                "raw_country_count",
                "unique_country_count",
                "normalized_countries",
            ]
        )
        for row in paper_rows:
            writer.writerow(
                [
                    row["uid"],
                    row["pubyear"],
                    row["raw_country_count"],
                    row["unique_country_count"],
                    row["normalized_countries"],
                ]
            )


def process_subset_file(input_path: Path, output_dir: Path) -> dict[str, object]:
    prefix = raw_output_prefix(input_path)
    year = infer_year_label(input_path)

    edge_counts: dict[tuple[str, str], int] = defaultdict(int)
    all_countries: set[str] = set()
    variant_address_counts: Counter[tuple[str, str]] = Counter()
    variant_paper_counts: Counter[tuple[str, str]] = Counter()
    paper_rows: list[dict[str, object]] = []

    scanned_records = 0
    records_with_country_data = 0
    records_with_international_ties = 0
    total_address_rows_with_country = 0

    print(f"Parsing country ties from {input_path} ...")

    with gzip.open(input_path, "rt", encoding="utf-8", errors="ignore") as in_f:
        for event, elem in ET.iterparse(in_f, events=("end",)):
            if local_name(elem.tag) != "REC":
                continue

            scanned_records += 1
            country_tokens = extract_country_tokens(elem)

            if country_tokens:
                records_with_country_data += 1
                total_address_rows_with_country += len(country_tokens)

                for token in country_tokens:
                    variant_address_counts[token] += 1

                for token in set(country_tokens):
                    variant_paper_counts[token] += 1

                unique_countries = {normalized for _, normalized in country_tokens}
                all_countries.update(unique_countries)
                paper_rows.append(
                    {
                        "uid": extract_uid(elem),
                        "pubyear": extract_pubyear(elem),
                        "raw_country_count": len(country_tokens),
                        "unique_country_count": len(unique_countries),
                        "normalized_countries": "|".join(sorted(unique_countries)),
                    }
                )

                if len(unique_countries) >= 2:
                    records_with_international_ties += 1
                    for source, target in combinations(sorted(unique_countries), 2):
                        edge_counts[(source, target)] += 1

            elem.clear()

    output_dir.mkdir(parents=True, exist_ok=True)

    edge_output = output_dir / f"{prefix}_edges_raw.csv"
    matrix_output = output_dir / f"{prefix}_matrix_raw.csv"
    variant_output = output_dir / f"{prefix}_variants_raw.csv"
    paper_output = output_dir / f"{prefix}_papers_raw.csv"

    write_edge_csv(edge_counts, edge_output)
    write_matrix_csv(all_countries, edge_counts, matrix_output)
    write_variant_csv(variant_address_counts, variant_paper_counts, variant_output)
    write_paper_country_csv(paper_rows, paper_output)

    print(
        f"{year}: {records_with_international_ties} records with 2+ countries, "
        f"{len(all_countries)} normalized country labels, {len(edge_counts)} unique country pairs."
    )

    return {
        "year": year,
        "input_file": str(input_path),
        "scanned_records": scanned_records,
        "records_with_country_data": records_with_country_data,
        "records_with_international_ties": records_with_international_ties,
        "address_rows_with_country": total_address_rows_with_country,
        "unique_normalized_countries": len(all_countries),
        "unique_country_pairs": len(edge_counts),
        "edge_output": str(edge_output),
        "matrix_output": str(matrix_output),
        "variant_output": str(variant_output),
        "paper_output": str(paper_output),
    }


def write_summary(rows: list[dict[str, object]], output_dir: Path) -> None:
    output_path = output_dir / "parse_summary.csv"
    fieldnames = [
        "year",
        "input_file",
        "scanned_records",
        "records_with_country_data",
        "records_with_international_ties",
        "address_rows_with_country",
        "unique_normalized_countries",
        "unique_country_pairs",
        "edge_output",
        "matrix_output",
        "variant_output",
        "paper_output",
    ]
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.DictWriter(csv_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    input_files = resolve_input_files(args.inputs)
    output_dir = Path(args.output_dir)

    summary_rows = [process_subset_file(input_path, output_dir) for input_path in input_files]
    write_summary(summary_rows, output_dir)

    print(f"Wrote parser summary to {output_dir / 'parse_summary.csv'}")


if __name__ == "__main__":
    main()
