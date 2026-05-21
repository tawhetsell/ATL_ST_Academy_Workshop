#!/usr/bin/env python3

"""Subset WoS Core XML deliveries to AI-only research records.

This script scans yearly WoS CORE folders that contain many `*.xml.gz` chunks,
filters records to those tagged with the exact traditional WoS subject category
`Computer Science, Artificial Intelligence` and with document type
`Article` or `Proceedings Paper`, then writes one consolidated `xml.gz` file
per year.

The output files keep the original WoS XML record structure so they can be
parsed later for affiliations, countries, keywords, abstracts, and other
fields without revisiting the full annual deliveries.

cd /Users/traviswhetsell/Desktop/ST_Academy_Workshop
python3 scripts/subset_wos_ai_records.py 2003_CORE 2008_CORE 2013_CORE 2018_CORE 2023_CORE --output-dir subset_ai_xml --summary-csv subset_ai_xml/subset_summary.csv
"""

from __future__ import annotations

import argparse
import csv
import gzip
from pathlib import Path
import xml.etree.ElementTree as ET


NS_URI = "http://clarivate.com/schema/wok5.30/public/FullRecord"
NS = {"wos": NS_URI}
AI_SUBJECT = "Computer Science, Artificial Intelligence"
ALLOWED_DOCTYPES = {"Article", "Proceedings Paper"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Subset WoS annual CORE folders to records tagged with the exact "
            "traditional subject 'Computer Science, Artificial Intelligence' "
            "and document type 'Article' or 'Proceedings Paper'."
        )
    )
    parser.add_argument(
        "year_dirs",
        nargs="+",
        help="One or more yearly CORE folders, e.g. 2003_CORE 2008_CORE",
    )
    parser.add_argument(
        "--output-dir",
        default="subset_ai_xml",
        help="Directory where yearly AI-only xml.gz files will be written.",
    )
    parser.add_argument(
        "--summary-csv",
        default="subset_ai_xml/subset_summary.csv",
        help="CSV path for the year-level summary report.",
    )
    return parser.parse_args()


def local_name(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


def find_xml_chunks(year_dir: Path) -> list[Path]:
    return sorted(path for path in year_dir.iterdir() if path.name.endswith(".xml.gz"))


def year_label_from_dir(year_dir: Path) -> str:
    return year_dir.name.split("_", 1)[0]


def record_has_ai_subject(rec: ET.Element) -> bool:
    subjects = rec.findall(
        ".//wos:category_info/wos:subjects/wos:subject",
        NS,
    )
    for subject in subjects:
        if subject.get("ascatype") == "traditional" and (subject.text or "").strip() == AI_SUBJECT:
            return True
    return False


def record_has_allowed_doctype(rec: ET.Element) -> bool:
    doctypes = rec.findall(
        "./wos:static_data/wos:summary/wos:doctypes/wos:doctype",
        NS,
    )
    return any((doctype.text or "").strip() in ALLOWED_DOCTYPES for doctype in doctypes)


def subset_year(year_dir: Path, output_dir: Path) -> dict[str, object]:
    year = year_label_from_dir(year_dir)
    xml_chunks = find_xml_chunks(year_dir)
    if not xml_chunks:
        raise FileNotFoundError(f"No .xml.gz files found in {year_dir}")

    output_path = output_dir / f"{year}_CORE_ai.xml.gz"

    ET.register_namespace("", NS_URI)

    scanned_records = 0
    ai_subject_records = 0
    matched_records = 0

    with gzip.open(output_path, "wb") as out_f:
        out_f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        out_f.write(f'<records xmlns="{NS_URI}">\n'.encode("utf-8"))

        for chunk_path in xml_chunks:
            with gzip.open(chunk_path, "rt", encoding="utf-8", errors="ignore") as in_f:
                for event, elem in ET.iterparse(in_f, events=("end",)):
                    if local_name(elem.tag) != "REC":
                        continue

                    scanned_records += 1
                    has_ai_subject = record_has_ai_subject(elem)

                    if has_ai_subject:
                        ai_subject_records += 1

                    if has_ai_subject and record_has_allowed_doctype(elem):
                        out_f.write(ET.tostring(elem, encoding="utf-8"))
                        out_f.write(b"\n")
                        matched_records += 1

                    elem.clear()

        out_f.write(b"</records>\n")

    return {
        "year": year,
        "source_dir": str(year_dir),
        "chunk_count": len(xml_chunks),
        "scanned_records": scanned_records,
        "ai_subject_records": ai_subject_records,
        "matched_records": matched_records,
        "output_file": str(output_path),
        "output_size_bytes": output_path.stat().st_size,
    }


def write_summary(summary_rows: list[dict[str, object]], summary_csv: Path) -> None:
    summary_csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "year",
        "source_dir",
        "chunk_count",
        "scanned_records",
        "ai_subject_records",
        "matched_records",
        "output_file",
        "output_size_bytes",
    ]
    with summary_csv.open("w", newline="", encoding="utf-8") as csv_f:
        writer = csv.DictWriter(csv_f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    summary_rows = []
    for year_dir_str in args.year_dirs:
        year_dir = Path(year_dir_str)
        if not year_dir.is_dir():
            raise NotADirectoryError(f"Not a directory: {year_dir}")
        summary_rows.append(subset_year(year_dir, output_dir))

    write_summary(summary_rows, Path(args.summary_csv))

    for row in summary_rows:
        print(
            f"{row['year']}: matched {row['matched_records']} records with AI subject "
            f"+ allowed doctypes out of {row['ai_subject_records']} AI-subject records "
            f"and {row['scanned_records']} total records across {row['chunk_count']} chunks -> "
            f"{row['output_file']}"
        )


if __name__ == "__main__":
    main()
