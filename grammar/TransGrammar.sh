#!/bin/bash

rm -rf Lang
bnfc -haskell -d -p Lang -bytestrings LAMA.cf
./ToLazyBS.sh
./MakeSkelQualified.sh
./RenameParser.sh
./RewriteComment.sh
