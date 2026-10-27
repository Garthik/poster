#!/usr/bin/env python3
"""Local stdlib-only quality gate when PostgreSQL/MongoDB are not yet running."""
from pathlib import Path
import re

root=Path(__file__).resolve().parents[2]
catalog=(root/'queries/business_queries.sql').read_text(encoding='utf8')
sections=re.split(r"(?m)^\\echo 'Q[1-8]\.",catalog)[1:]
assert len(sections)==8, f'Expected 8 SQL queries; got {len(sections)}'
counts={
    'aggregates':sum(bool(re.search(r'\b(COUNT|SUM|AVG)\s*\(',part,re.I)) for part in sections),
    'window':sum(bool(re.search(r'\bOVER\s*\(',part,re.I)) for part in sections),
    'cte':sum(bool(re.search(r'\bWITH\b',part,re.I)) for part in sections),
    'joins':sum(bool(re.search(r'\bJOIN\b',part,re.I)) for part in sections),
}
assert counts['aggregates']>=3 and counts['window']>=3 and counts['cte']>=2 and counts['joins']>=5
assert all(v in catalog for v in ('DENSE_RANK()','LAG(attempts)','ROWS BETWEEN UNBOUNDED PRECEDING'))
validator=(root/'mongo/schema.js').read_text(encoding='utf8')
assert all(x in validator for x in ["'event_pages'", "'editorial_collections'", "'visitor_feedback'", 'uniqueItems:true', 'oneOf:', 'minimum:1', 'maximum:5'])
assert 'lab5_content_compare' in (root/'migrations/003_lab5_comparison.sql').read_text()
for name in ['crud.js','validation_test.js','sync_from_pg.js','export_comparison.js','migrate_v2.js']:
    assert (root/'mongo'/name).is_file(),name
print('PASS static: 8 query catalog / criteria',counts)
print('PASS static: 3 validated Mongo collections, CRUD, sync, comparison, versioning')
