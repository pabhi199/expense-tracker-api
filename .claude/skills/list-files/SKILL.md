---
name: list-files
description: Explore a directory (defaults to the project root) and display the names of the files it contains. Use when the user asks to list, explore, or show the files in a project or folder.
context: fork
model: haiku
---

# List Files

Explore the target directory and display its file names to the user.

1. Determine the target directory:
   - If an argument (a path) was passed to the skill, use it.
   - Otherwise, use the current project's root directory.
2. List files with something like:
   `find <dir> -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/__pycache__/*' -not -path '*/.venv/*' | sort`
   Adjust the excludes if the project has other obvious noise directories.
3. Display the results to the user as a clean, readable list, grouped by top-level folder.

Keep the output concise — if there are hundreds of files, summarize counts per directory instead of dumping every single path.
