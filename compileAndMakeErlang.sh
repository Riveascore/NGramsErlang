#!/bin/bash

erl -compile node_handler file_handler triplet_handler ngrams
erl -make
