# Actual query measurements

Seed SHA256: 0c6d57575e3d62b7ffc9c455a54b4d443df4b20faacd59de28f2f8ac7e51736e. 5 samples/phase, 3 warmups. Natural optimizer; no hint. Full documents fetched, limit 100.

|Query|Phase|Median ms|Docs|Keys|Returned|
|---|---|---:|---:|---:|---:|
|feedback|before|2|593|593|100|
|feedback|after|0|100|100|100|
|pages|before|15|9000|18000|100|
|pages|after|0|100|100|100|

- **feedback**: FETCH|IXSCAN|SORT (pageSlug_1_moderation_1) → FETCH|IXSCAN|LIMIT (lab6_feedback_page_moderation_created_id). Equality fields precede sort fields; _id breaks ties. Lab5 indexes retained. Median server time: 2 → 0 ms. Low millisecond resolution, cache and scheduling can obscure timing changes; examine documents/keys and SORT as well.
- **pages**: FETCH|IXSCAN|SORT (status_1_keywords_1) → FETCH|IXSCAN|LIMIT (lab6_pages_status_editor_headline_id). Equality fields precede sort fields; _id breaks ties. Lab5 indexes retained. Median server time: 15 → 0 ms. Low millisecond resolution, cache and scheduling can obscure timing changes; examine documents/keys and SORT as well.
