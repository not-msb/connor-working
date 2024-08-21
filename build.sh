#!/bin/sh

set -xe

zig build run -- $1 2>&1 >/dev/null | cat - lib.ssa | qbe > temp.S && cc temp.S

rm temp.S
