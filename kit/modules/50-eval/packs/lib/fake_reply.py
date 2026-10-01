#!/usr/bin/env python3
"""Fake model for shell providers: reads the prompt on stdin and prints the reply of the first
[substring, reply] pair in ANSWERS.json whose substring occurs in the prompt.
Usage: fake_reply.py ANSWERS.json [--bad]   (--bad: always answer "I do not know.")"""
import json
import sys

pairs = json.load(open(sys.argv[1], encoding="utf-8"))
prompt = sys.stdin.read()
if "--bad" not in sys.argv:
    for needle, reply in pairs:
        if needle in prompt:
            print(reply)
            sys.exit(0)
print("I do not know.")
