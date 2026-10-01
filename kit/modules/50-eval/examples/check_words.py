"""Example script grader: reads the response on stdin, exit 0 = pass."""
import sys

text = sys.stdin.read()
words = len(text.split())
if words == 3:
    print("three words")
else:
    print(f"expected 3 words, got {words}")
    sys.exit(1)
