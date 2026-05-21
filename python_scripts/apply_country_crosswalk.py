#!/usr/bin/env python3

"""Apply a country crosswalk to raw AI country-tie outputs.

This script is the third stage of the workshop pipeline. It reads the raw
country outputs from `parse_ai_country_matrices.py`, applies a reviewed
crosswalk from normalized country labels to ISO3 codes, drops unresolved
or intentionally excluded labels, and writes cleaned edge lists and matrices.

If the crosswalk file does not exist, the script builds a starter template
from the observed raw country labels and exits so the template can be reviewed.

Example:
cd /Users/traviswhetsell/Desktop/ST_Academy_Workshop
python3 scripts/apply_country_crosswalk.py ai_country_raw --crosswalk ai_country_clean/country_crosswalk.csv --output-dir ai_country_clean
"""

from __future__ import annotations

import argparse
import ast
import csv
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
import re


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Apply a reviewed country crosswalk to raw AI-country edge lists "
            "and produce ISO3-cleaned outputs."
        )
    )
    parser.add_argument(
        "raw_output_dir",
        help="Directory produced by parse_ai_country_matrices.py.",
    )
    parser.add_argument(
        "--crosswalk",
        default="ai_country_clean/country_crosswalk.csv",
        help="CSV file that maps normalized country labels to ISO3 codes.",
    )
    parser.add_argument(
        "--output-dir",
        default="ai_country_clean",
        help="Directory where cleaned outputs will be written.",
    )
    parser.add_argument(
        "--allow-unresolved",
        action="store_true",
        help=(
            "Write unresolved labels to diagnostics and continue, dropping "
            "unresolved labels from cleaned matrices."
        ),
    )
    return parser.parse_args()


def normalize_country_label(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def squash_country_label(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def build_builtin_iso3_map() -> dict[str, str]:
    aliases = {
        "AFG": ["afghanistan"],
        "ALB": ["albania"],
        "DZA": ["algeria"],
        "AND": ["andorra"],
        "AGO": ["angola"],
        "ATG": ["antigua and barbuda", "antigua and barbu"],
        "ARG": ["argentina"],
        "ARM": ["armenia"],
        "AUS": ["australia", "commonwealth of australia"],
        "AUT": ["austria"],
        "AZE": ["azerbaijan"],
        "BHS": ["bahamas"],
        "BHR": ["bahrain"],
        "BGD": ["bangladesh"],
        "BRB": ["barbados"],
        "BLR": ["belarus"],
        "BEL": ["belgium"],
        "BLZ": ["belize"],
        "BEN": ["benin"],
        "BTN": ["bhutan"],
        "BOL": ["bolivia", "bolivia plurinational state of"],
        "BIH": [
            "bosnia and herzegovina",
            "bosnia and herceg",
            "bosnia herceg",
            "bosnia and herzeg",
        ],
        "BWA": ["botswana"],
        "BRA": ["brazil"],
        "BRN": ["brunei", "brunei darussalam"],
        "BGR": ["bulgaria"],
        "BFA": ["burkina faso"],
        "BDI": ["burundi"],
        "KHM": ["cambodia"],
        "CMR": ["cameroon"],
        "CAN": ["canada"],
        "CPV": ["cape verde", "cabo verde"],
        "CAF": ["central african republic"],
        "TCD": ["chad"],
        "CHL": ["chile"],
        "CHN": [
            "china",
            "china mainland",
            "peoples r china",
            "people s r china",
            "peoples republic of china",
            "people s republic of china",
            "peoples rep china",
            "people s rep china",
            "p r china",
            "pr china",
            "mainland china",
            "peoples china",
        ],
        "COL": ["colombia"],
        "COM": ["comoros"],
        "COG": ["congo", "republic of the congo", "congo brazzaville"],
        "COD": [
            "democratic republic of congo",
            "democratic republic of the congo",
            "dr congo",
            "d r congo",
            "congo democratic republic",
            "zaire",
        ],
        "CRI": ["costa rica"],
        "CIV": ["cote d ivoire", "cote divoire", "ivory coast"],
        "HRV": ["croatia"],
        "CUB": ["cuba"],
        "CYP": ["cyprus"],
        "CZE": ["czech republic", "czechia"],
        "DNK": ["denmark"],
        "DJI": ["djibouti"],
        "DMA": ["dominica"],
        "DOM": ["dominican republic"],
        "ECU": ["ecuador"],
        "EGY": ["egypt"],
        "SLV": ["el salvador"],
        "GNQ": ["equatorial guinea"],
        "ERI": ["eritrea"],
        "EST": ["estonia"],
        "SWZ": ["eswatini", "swaziland"],
        "ETH": ["ethiopia"],
        "FJI": ["fiji"],
        "FIN": ["finland"],
        "FRA": ["france"],
        "GAB": ["gabon"],
        "GMB": ["gambia"],
        "GEO": ["georgia"],
        "DEU": ["germany", "deutschland"],
        "GHA": ["ghana"],
        "GRC": ["greece"],
        "GRD": ["grenada"],
        "GTM": ["guatemala"],
        "GIN": ["guinea"],
        "GNB": ["guinea bissau"],
        "GUY": ["guyana"],
        "HTI": ["haiti"],
        "HND": ["honduras"],
        "HUN": ["hungary"],
        "ISL": ["iceland"],
        "IND": ["india"],
        "IDN": ["indonesia"],
        "IRN": ["iran", "iran islamic republic of", "islamic republic of iran"],
        "IRQ": ["iraq"],
        "IRL": ["ireland", "republic of ireland"],
        "ISR": ["israel"],
        "ITA": ["italy"],
        "JAM": ["jamaica"],
        "JPN": ["japan"],
        "JOR": ["jordan"],
        "KAZ": ["kazakhstan"],
        "KEN": ["kenya"],
        "KWT": ["kuwait"],
        "KGZ": ["kyrgyzstan"],
        "LAO": ["laos", "lao pdr", "lao people s democratic republic"],
        "LVA": ["latvia"],
        "LBN": ["lebanon"],
        "LSO": ["lesotho"],
        "LBR": ["liberia"],
        "LBY": ["libya"],
        "LIE": ["liechtenstein"],
        "LTU": ["lithuania"],
        "LUX": ["luxembourg"],
        "MDG": ["madagascar"],
        "MWI": ["malawi"],
        "MYS": ["malaysia"],
        "MDV": ["maldives"],
        "MLI": ["mali"],
        "MLT": ["malta"],
        "MRT": ["mauritania"],
        "MUS": ["mauritius"],
        "MEX": ["mexico"],
        "MDA": ["moldova", "republic of moldova"],
        "MCO": ["monaco"],
        "MNG": ["mongolia"],
        "MNE": ["montenegro"],
        "MAR": ["morocco"],
        "MOZ": ["mozambique"],
        "MMR": ["myanmar", "burma"],
        "NAM": ["namibia"],
        "NPL": ["nepal"],
        "NLD": ["netherlands", "the netherlands", "holland"],
        "NZL": ["new zealand"],
        "NIC": ["nicaragua"],
        "NER": ["niger"],
        "NGA": ["nigeria"],
        "PRK": ["north korea", "dprk", "democratic people s republic of korea"],
        "MKD": ["north macedonia", "macedonia", "fyr macedonia"],
        "NOR": ["norway"],
        "OMN": ["oman", "sultanate of oman"],
        "PAK": ["pakistan"],
        "PAN": ["panama"],
        "PNG": ["papua new guinea"],
        "PRY": ["paraguay"],
        "PER": ["peru"],
        "PHL": ["philippines"],
        "POL": ["poland"],
        "PRT": ["portugal"],
        "QAT": ["qatar"],
        "ROU": ["romania"],
        "RUS": ["russia", "russian federation"],
        "RWA": ["rwanda"],
        "KNA": ["saint kitts and nevis", "st kitts and nevi"],
        "LCA": ["saint lucia"],
        "VCT": ["saint vincent and the grenadines"],
        "WSM": ["samoa"],
        "SMR": ["san marino"],
        "STP": ["sao tome and principe"],
        "SAU": ["saudi arabia"],
        "SEN": ["senegal"],
        "SRB": ["serbia", "serbia and montenegro"],
        "SYC": ["seychelles"],
        "SLE": ["sierra leone"],
        "SGP": ["singapore"],
        "SVK": ["slovakia"],
        "SVN": ["slovenia"],
        "SLB": ["solomon islands"],
        "SOM": ["somalia"],
        "ZAF": ["south africa"],
        "KOR": ["south korea", "korea", "republic of korea", "korea republic of"],
        "SSD": ["south sudan"],
        "ESP": ["spain"],
        "LKA": ["sri lanka"],
        "SDN": ["sudan"],
        "SUR": ["suriname"],
        "SWE": ["sweden"],
        "CHE": ["switzerland"],
        "SYR": ["syria", "syrian arab republic"],
        "TWN": ["taiwan"],
        "TJK": ["tajikistan"],
        "TZA": ["tanzania", "united republic of tanzania"],
        "THA": ["thailand"],
        "TLS": ["timor leste", "east timor"],
        "TGO": ["togo"],
        "TTO": ["trinidad and tobago"],
        "TUN": ["tunisia"],
        "TUR": ["turkey", "turkiye"],
        "TKM": ["turkmenistan"],
        "UGA": ["uganda"],
        "UKR": ["ukraine"],
        "ARE": ["united arab emirates", "uae"],
        "GBR": [
            "united kingdom",
            "uk",
            "u k",
            "u kingdom",
            "great britain",
            "britain",
            "england",
            "scotland",
            "wales",
            "northern ireland",
            "north ireland",
            "united kingdom england",
            "united kingdom scotland",
            "united kingdom wales",
        ],
        "USA": [
            "united states",
            "united states of america",
            "usa",
            "u s a",
            "u s",
            "us",
            "america",
        ],
        "URY": ["uruguay"],
        "UZB": ["uzbekistan"],
        "VEN": ["venezuela", "venezuela bolivarian republic of"],
        "VNM": ["vietnam", "viet nam"],
        "YEM": ["yemen"],
        "ZMB": ["zambia"],
        "ZWE": ["zimbabwe"],
        "HKG": ["hong kong", "hong kong sar china", "hong kong s a r china"],
        "MAC": ["macao", "macau", "macao sar china", "macau sar china"],
        "PSE": ["palestine", "palestinian territory", "occupied palestinian territory"],
        "SUN": ["ussr", "soviet union"],
        "YUG": ["yugoslavia"],
    }

    mapping: dict[str, str] = {}
    for iso3, names in aliases.items():
        for name in names:
            mapping[normalize_country_label(name)] = iso3
    return mapping


def load_legacy_disambiguation_map() -> dict[str, str | None]:
    script_dir = Path(__file__).resolve().parent
    legacy_path = (
        script_dir.parent
        / "Academic-Freedom-and-International-Research-Collaboration"
        / "QSS_WOS_Country_Disambigation.py"
    )
    if not legacy_path.is_file():
        return {}

    source = legacy_path.read_text(encoding="utf-8")
    module = ast.parse(source, filename=str(legacy_path))
    for node in module.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "disambiguation_dict":
                    return ast.literal_eval(node.value)
    return {}


def discover_raw_files(raw_output_dir: Path) -> list[tuple[str, Path, Path, Path]]:
    edge_files = sorted(raw_output_dir.glob("*_ai_country_edges_raw.csv"))
    discovered: list[tuple[str, Path, Path, Path]] = []
    for edge_file in edge_files:
        year_match = re.search(r"(19|20)\d{2}", edge_file.name)
        if not year_match:
            continue
        year = year_match.group(0)
        variant_file = raw_output_dir / f"{year}_ai_country_variants_raw.csv"
        paper_file = raw_output_dir / f"{year}_ai_country_papers_raw.csv"
        if not variant_file.is_file():
            raise FileNotFoundError(f"Missing matching variant file for {edge_file}: {variant_file}")
        if not paper_file.is_file():
            raise FileNotFoundError(f"Missing matching paper file for {edge_file}: {paper_file}")
        discovered.append((year, edge_file, variant_file, paper_file))
    if not discovered:
        raise FileNotFoundError(f"No raw edge files found in {raw_output_dir}")
    return discovered


def read_variant_file(variant_path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with variant_path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.DictReader(csv_f)
        for row in reader:
            rows.append(
                {
                    "normalized_country": row["normalized_country"].strip(),
                    "raw_country": row["raw_country"].strip(),
                    "address_occurrences": int(row["address_occurrences"]),
                    "paper_occurrences": int(row["paper_occurrences"]),
                }
            )
    return rows


def aggregate_observed_labels(discovered_files: list[tuple[str, Path, Path, Path]]) -> dict[str, dict[str, object]]:
    observed: dict[str, dict[str, object]] = {}
    for _, _, variant_path, _ in discovered_files:
        for row in read_variant_file(variant_path):
            normalized_country = row["normalized_country"]
            bucket = observed.setdefault(
                normalized_country,
                {
                    "address_occurrences": 0,
                    "paper_occurrences": 0,
                    "raw_examples": Counter(),
                },
            )
            bucket["address_occurrences"] += row["address_occurrences"]
            bucket["paper_occurrences"] += row["paper_occurrences"]
            bucket["raw_examples"][row["raw_country"]] += row["address_occurrences"]
    return observed


def infer_iso3(
    normalized_country: str,
    builtin_map: dict[str, str],
    legacy_map: dict[str, str | None],
) -> tuple[str, str]:
    if normalized_country in builtin_map:
        return builtin_map[normalized_country], "builtin"

    squashed = squash_country_label(normalized_country)
    legacy_value = legacy_map.get(squashed)
    if isinstance(legacy_value, str) and legacy_value.strip():
        return legacy_value.strip(), "legacy"
    if legacy_value is None and squashed in legacy_map:
        return "", "legacy-drop"

    return "", ""


def write_crosswalk_template(
    observed_labels: dict[str, dict[str, object]],
    crosswalk_path: Path,
    builtin_map: dict[str, str],
    legacy_map: dict[str, str | None],
) -> None:
    crosswalk_path.parent.mkdir(parents=True, exist_ok=True)
    with crosswalk_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(
            [
                "normalized_country",
                "iso3",
                "action",
                "suggestion_source",
                "raw_examples",
                "address_occurrences",
                "paper_occurrences",
                "note",
            ]
        )

        for normalized_country in sorted(
            observed_labels,
            key=lambda key: (-observed_labels[key]["paper_occurrences"], key),
        ):
            info = observed_labels[normalized_country]
            iso3, suggestion_source = infer_iso3(normalized_country, builtin_map, legacy_map)
            action = "map" if iso3 else ""
            if suggestion_source == "legacy-drop":
                action = "drop"
            raw_examples = "; ".join(
                raw_country
                for raw_country, _ in info["raw_examples"].most_common(5)
            )
            writer.writerow(
                [
                    normalized_country,
                    iso3,
                    action,
                    suggestion_source,
                    raw_examples,
                    info["address_occurrences"],
                    info["paper_occurrences"],
                    "",
                ]
            )


def load_crosswalk(crosswalk_path: Path) -> dict[str, dict[str, str]]:
    mapping: dict[str, dict[str, str]] = {}
    with crosswalk_path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.DictReader(csv_f)
        required_columns = {"normalized_country", "iso3", "action"}
        if not required_columns.issubset(reader.fieldnames or set()):
            raise ValueError(
                f"Crosswalk must include columns {sorted(required_columns)}: {crosswalk_path}"
            )

        for row in reader:
            normalized_country = row["normalized_country"].strip()
            if not normalized_country:
                continue
            if normalized_country in mapping:
                raise ValueError(f"Duplicate normalized_country in crosswalk: {normalized_country}")
            mapping[normalized_country] = {
                "iso3": row["iso3"].strip().upper(),
                "action": row["action"].strip().lower(),
            }
    return mapping


def write_unresolved_report(
    unresolved_labels: dict[str, dict[str, object]],
    output_path: Path,
) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(
            [
                "normalized_country",
                "raw_examples",
                "address_occurrences",
                "paper_occurrences",
            ]
        )
        for normalized_country in sorted(
            unresolved_labels,
            key=lambda key: (-unresolved_labels[key]["paper_occurrences"], key),
        ):
            info = unresolved_labels[normalized_country]
            raw_examples = "; ".join(
                raw_country for raw_country, _ in info["raw_examples"].most_common(5)
            )
            writer.writerow(
                [
                    normalized_country,
                    raw_examples,
                    info["address_occurrences"],
                    info["paper_occurrences"],
                ]
            )


def resolve_label_mapping(
    observed_labels: dict[str, dict[str, object]],
    crosswalk_map: dict[str, dict[str, str]],
    allow_unresolved: bool = False,
) -> tuple[dict[str, str | None], dict[str, dict[str, object]]]:
    resolved: dict[str, str | None] = {}
    unresolved: dict[str, dict[str, object]] = {}

    for normalized_country, info in observed_labels.items():
        row = crosswalk_map.get(normalized_country)
        if row is None:
            if allow_unresolved:
                resolved[normalized_country] = None
            else:
                unresolved[normalized_country] = info
            continue

        action = row["action"]
        iso3 = row["iso3"]

        if action == "drop":
            resolved[normalized_country] = None
        elif action == "map" and iso3:
            resolved[normalized_country] = iso3
        else:
            if allow_unresolved:
                resolved[normalized_country] = None
            else:
                unresolved[normalized_country] = info

    return resolved, unresolved


def aggregate_year_nodes(
    variant_rows: list[dict[str, object]],
    paper_rows: list[dict[str, object]],
    resolved_mapping: dict[str, str | None],
) -> dict[str, dict[str, object]]:
    nodes: dict[str, dict[str, object]] = {}

    for row in variant_rows:
        normalized_country = row["normalized_country"]
        iso3 = resolved_mapping.get(normalized_country)
        if not iso3:
            continue
        bucket = nodes.setdefault(
            iso3,
            {
                "address_occurrences": 0,
                "paper_occurrences": 0,
                "source_labels": Counter(),
            },
        )
        bucket["address_occurrences"] += int(row["address_occurrences"])
        bucket["source_labels"][normalized_country] += int(row["paper_occurrences"])

    for row in paper_rows:
        mapped_countries = set()
        for normalized_country in row["normalized_countries"]:
            iso3 = resolved_mapping.get(normalized_country)
            if iso3:
                mapped_countries.add(iso3)
        for iso3 in mapped_countries:
            bucket = nodes.setdefault(
                iso3,
                {
                    "address_occurrences": 0,
                    "paper_occurrences": 0,
                    "source_labels": Counter(),
                },
            )
            bucket["paper_occurrences"] += 1

    return nodes


def read_edge_counts(edge_path: Path) -> dict[tuple[str, str], int]:
    edge_counts: dict[tuple[str, str], int] = {}
    with edge_path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.DictReader(csv_f)
        for row in reader:
            edge_counts[
                (
                    row["source_normalized"].strip(),
                    row["target_normalized"].strip(),
                )
            ] = int(row["weight"])
    return edge_counts

def read_paper_rows(paper_path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with paper_path.open("r", newline="", encoding="utf-8") as csv_f:
        reader = csv.DictReader(csv_f)
        for row in reader:
            normalized_countries = [
                item.strip()
                for item in row["normalized_countries"].split("|")
                if item.strip()
            ]
            rows.append(
                {
                    "uid": row["uid"].strip(),
                    "pubyear": row["pubyear"].strip(),
                    "normalized_countries": normalized_countries,
                }
            )
    return rows


def apply_mapping_to_edges(
    paper_rows: list[dict[str, object]],
    resolved_mapping: dict[str, str | None],
) -> tuple[dict[tuple[str, str], int], int]:
    clean_edge_counts: dict[tuple[str, str], int] = defaultdict(int)
    dropped_self_loop_weight = 0

    for row in paper_rows:
        mapped_countries = {
            resolved_mapping.get(normalized_country)
            for normalized_country in row["normalized_countries"]
            if resolved_mapping.get(normalized_country)
        }
        mapped_countries.discard(None)
        ordered_countries = sorted(mapped_countries)
        if len(ordered_countries) < 2:
            continue
        for source_iso3, target_iso3 in combinations(ordered_countries, 2):
            if source_iso3 == target_iso3:
                dropped_self_loop_weight += 1
                continue
            clean_edge_counts[(source_iso3, target_iso3)] += 1

    return clean_edge_counts, dropped_self_loop_weight


def write_clean_edge_csv(edge_counts: dict[tuple[str, str], int], output_path: Path) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["source_iso3", "target_iso3", "weight"])
        for (source_iso3, target_iso3), weight in sorted(edge_counts.items()):
            writer.writerow([source_iso3, target_iso3, weight])


def write_clean_matrix_csv(
    node_summaries: dict[str, dict[str, object]],
    edge_counts: dict[tuple[str, str], int],
    output_path: Path,
) -> None:
    ordered_nodes = sorted(node_summaries)
    index_lookup = {country: idx for idx, country in enumerate(ordered_nodes)}
    matrix = [[0 for _ in ordered_nodes] for _ in ordered_nodes]

    for (source_iso3, target_iso3), weight in edge_counts.items():
        source_idx = index_lookup[source_iso3]
        target_idx = index_lookup[target_iso3]
        matrix[source_idx][target_idx] += weight
        matrix[target_idx][source_idx] += weight

    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(["country", *ordered_nodes])
        for country, row in zip(ordered_nodes, matrix):
            writer.writerow([country, *row])


def write_node_csv(node_summaries: dict[str, dict[str, object]], output_path: Path) -> None:
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.writer(csv_f)
        writer.writerow(
            [
                "iso3",
                "address_occurrences",
                "paper_occurrences",
                "source_labels",
            ]
        )
        for iso3 in sorted(node_summaries):
            info = node_summaries[iso3]
            source_labels = "; ".join(
                label for label, _ in info["source_labels"].most_common()
            )
            writer.writerow(
                [
                    iso3,
                    info["address_occurrences"],
                    info["paper_occurrences"],
                    source_labels,
                ]
            )


def write_apply_summary(rows: list[dict[str, object]], output_path: Path) -> None:
    fieldnames = [
        "year",
        "raw_edge_file",
        "clean_edge_file",
        "clean_matrix_file",
        "clean_node_file",
        "mapped_iso3_nodes",
        "clean_country_pairs",
        "dropped_self_loop_weight",
    ]
    with output_path.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.DictWriter(csv_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def process_year(
    year: str,
    edge_path: Path,
    variant_path: Path,
    paper_path: Path,
    resolved_mapping: dict[str, str | None],
    output_dir: Path,
) -> dict[str, object]:
    variant_rows = read_variant_file(variant_path)
    paper_rows = read_paper_rows(paper_path)
    node_summaries = aggregate_year_nodes(variant_rows, paper_rows, resolved_mapping)
    clean_edge_counts, dropped_self_loop_weight = apply_mapping_to_edges(
        paper_rows,
        resolved_mapping,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    edge_output = output_dir / f"{year}_ai_country_edges_clean.csv"
    matrix_output = output_dir / f"{year}_ai_country_matrix_clean.csv"
    node_output = output_dir / f"{year}_ai_country_nodes_clean.csv"

    write_clean_edge_csv(clean_edge_counts, edge_output)
    write_clean_matrix_csv(node_summaries, clean_edge_counts, matrix_output)
    write_node_csv(node_summaries, node_output)

    print(
        f"{year}: wrote {len(clean_edge_counts)} cleaned country pairs across "
        f"{len(node_summaries)} ISO3 nodes."
    )

    return {
        "year": year,
        "raw_edge_file": str(edge_path),
        "clean_edge_file": str(edge_output),
        "clean_matrix_file": str(matrix_output),
        "clean_node_file": str(node_output),
        "mapped_iso3_nodes": len(node_summaries),
        "clean_country_pairs": len(clean_edge_counts),
        "dropped_self_loop_weight": dropped_self_loop_weight,
    }


def main() -> None:
    args = parse_args()
    raw_output_dir = Path(args.raw_output_dir)
    output_dir = Path(args.output_dir)
    crosswalk_path = Path(args.crosswalk)

    discovered_files = discover_raw_files(raw_output_dir)
    observed_labels = aggregate_observed_labels(discovered_files)

    builtin_map = build_builtin_iso3_map()
    legacy_map = load_legacy_disambiguation_map()
    legacy_map = {squash_country_label(key): value for key, value in legacy_map.items()}

    if not crosswalk_path.is_file():
        write_crosswalk_template(observed_labels, crosswalk_path, builtin_map, legacy_map)
        if not args.allow_unresolved:
            print(
                f"Wrote starter crosswalk template to {crosswalk_path}. "
                "Review it, then rerun this script."
            )
            return
        print(
            f"Wrote starter crosswalk template to {crosswalk_path}. "
            "Continuing because --allow-unresolved was set."
        )

    crosswalk_map = load_crosswalk(crosswalk_path)
    resolved_mapping, unresolved_labels = resolve_label_mapping(
        observed_labels,
        crosswalk_map,
        allow_unresolved=args.allow_unresolved,
    )

    if unresolved_labels:
        output_dir.mkdir(parents=True, exist_ok=True)
        unresolved_path = output_dir / "country_crosswalk_unresolved.csv"
        write_unresolved_report(unresolved_labels, unresolved_path)
        print(
            f"Found {len(unresolved_labels)} unresolved normalized country labels. "
            f"Wrote {unresolved_path}. Update {crosswalk_path} and rerun."
        )
        return

    if args.allow_unresolved:
        dropped_labels = {
            label: info
            for label, info in observed_labels.items()
            if resolved_mapping.get(label) is None
        }
        if dropped_labels:
            output_dir.mkdir(parents=True, exist_ok=True)
            unresolved_path = output_dir / "country_crosswalk_unresolved.csv"
            write_unresolved_report(dropped_labels, unresolved_path)
            print(
                f"Dropping {len(dropped_labels)} unresolved or excluded labels. "
                f"Wrote {unresolved_path}."
            )
        else:
            unresolved_path = output_dir / "country_crosswalk_unresolved.csv"
            if unresolved_path.exists():
                unresolved_path.unlink()

    summary_rows = []
    for year, edge_path, variant_path, paper_path in discovered_files:
        summary_rows.append(
            process_year(
                year,
                edge_path,
                variant_path,
                paper_path,
                resolved_mapping,
                output_dir,
            )
        )

    write_apply_summary(summary_rows, output_dir / "apply_summary.csv")
    print(f"Wrote apply summary to {output_dir / 'apply_summary.csv'}")


if __name__ == "__main__":
    main()
