#!/bin/bash

ROOT="$(cd $(dirname "$(realpath "$0")");pwd)"

rm -rf $ROOT/build
rm -rf $ROOT/dist
rm -rf $ROOT/out
