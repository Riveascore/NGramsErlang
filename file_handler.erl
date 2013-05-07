-module(file_handler).
%-export([file_reader/2,make_file_readers/1,normalize_list/1,index/1,processFile/1,processChunks/2,processChunk/2]).
-export([normalize_list/1, processFile/2, getChunk/4, processLine/2, splitListToList/2]).

normalize_list(List) ->
    lists:map(fun(Word) -> string:to_lower(Word) end, List).

processFile(File, ChunkSize) ->		      
    {ok,IoDevice} = file:open(File,[read]),
    getChunk(IoDevice, ChunkSize, [], ChunkSize).

getChunk(IoDevice, 0, ChunkList, ChunkSize) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    triplet_handler:send_chunk_off(ChunkList);
	Line ->
	    NextLineList = processLine(Line, true),
	    NewList = lists:append(ChunkList, NextLineList),

	    %comment out following line
	    io:fwrite("ChunkList ~s~n", [[NewList]]),

	    %triplet_handler:send_chunk_off(NewList),
	    FreshChunkList = processLine(Line, false),
	    getChunk(IoDevice, ChunkSize-1, FreshChunkList, ChunkSize)
    end;

getChunk(IoDevice, LinesLeft, ChunkList, ChunkSize) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    %comment out following line
	    io:fwrite("ChunkList ~s~n", [[ChunkList]]);

	    %triplet_handler:send_chunk_off(ChunkList);
	Line ->
	    NextLineList = processLine(Line, false),
	    NewList = lists:append(ChunkList, NextLineList),
	    io:fwrite("ahhhh chk ~s~n", [[NextLineList]]),
	    getChunk(IoDevice, LinesLeft-1, NewList, ChunkSize)
     end.

%-define(Punctuation,"(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+").
-define(Punctuation,"(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+").

processLine(Line, true) ->
    case re:split(Line, ?Punctuation) of
	{ok, Words} ->
	    %Normalized = normalize_list(Words),
	    %FirstTwo = lists:sublist(Normalized, 2),
	    FirstTwo = lists:sublist(Words, 2),
	    FirstTwo;
	_ -> []
    end;

processLine(Line, false) ->
    case re:split(Line, ?Punctuation) of
	{ok, Words} ->
	    %Normalized = normalize_list(Words),
	    %Normalized;
	    Words;
	_ -> []
    end.

splitListToList(SplitList,EndList) ->
    case SplitList of
	[] -> ok;
	[Word|Rest] ->
	    NewList = lists:append(EndList, Word),
	    splitListToList(Rest, NewList)
    end.
		
	    
