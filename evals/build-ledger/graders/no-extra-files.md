---
type: regex
target: files
match: not_contains
flags: m
pattern: '^(?!(ledger/(models|parse|report)\.py|oracle\.txt)$)(?!.*(__pycache__|\.pyc|^\.git/)).+$'
---
