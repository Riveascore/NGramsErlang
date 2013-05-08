-module(triplet_handler).
-export([send_chunk_off/2]).

send_chunk_off(ChunkList, ListOfTripletGenerators) ->
    io:fwrite("ChunkList ~p~n", [ChunkList]).
