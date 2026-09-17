---
type: regex
target: { source: file, path: .git/logs/HEAD }
pattern: 'commit: task 1[\s\S]*commit: task 2[\s\S]*commit: task 3'
arm: with-only
---
