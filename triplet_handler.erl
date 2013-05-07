-module(triplet_handler).
-export([send_chunk_off/1]).

send_chunk_off(ChunkList) ->
    io:fwrite("ChunkList ~p~n", [ChunkList]).
