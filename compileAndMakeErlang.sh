#!/bin/bash

erl -compile file_handler ngrams node_handler triplet_handler
erl -make
