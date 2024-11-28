#!/bin/bash

if [ "$1" == "fast" ]; then
    zig build -Doptimize=ReleaseFast && ./zig-out/bin/ws_server
elif  [ "$1" == "debug" ]; then
    zig build -Doptimize=Debug && gdb ./zig-out/bin/ws_server
else
    zig build -Doptimize=Debug && ./zig-out/bin/ws_server

fi
