-module(file_handler).
-export([normalize_list/1, processFile/4, getChunk/5, processLine/2, processFiles/5]).

normalize_list(List) ->
    lists:map(fun(Word) -> string:to_lower(Word) end, List).

processFiles([], CounterLoop, ChunkSize, ListOfTripletGenerators, OverallCounterPID) ->
    ok;
processFiles(ListOfFiles, CounterLoop, ChunkSize, ListOfTripletGenerators, OverallCounterPID) ->
    %io:fwrite("OverallCounterPID: ~p~n", [OverallCounterPID]),
    [File|Rest] = ListOfFiles,
    Node = node_handler:round_robin(CounterLoop),
    spawn(Node, file_handler, processFile, [File, ChunkSize, ListOfTripletGenerators, OverallCounterPID]),
    processFiles(Rest, CounterLoop, ChunkSize, ListOfTripletGenerators, OverallCounterPID).

processFile(File, ChunkSize, ListOfTripletGenerators, OverallCounterPID) ->		      
    {ok,IoDevice} = file:open(File,[read]),
    getChunk(IoDevice, ChunkSize, [], ChunkSize, ListOfTripletGenerators),
    %io:fwrite("Done processing a file: ~p on node: ~p~n", [File, node()]).
    OverallCounterPID ! {file_finished}.
    

getChunk(IoDevice, 0, ChunkList, ChunkSize, ListOfTripletGenerators) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, ChunkList),
	    triplet_handler:send_chunk_off(FixedList, ListOfTripletGenerators, true);
	Line ->
	    NextLineList = processLine(Line, true),
	    NewList = lists:append(ChunkList, NextLineList),
	    
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, NewList),
	    triplet_handler:send_chunk_off(FixedList, ListOfTripletGenerators, false),
	    FreshChunkList = processLine(Line, false),
	    getChunk(IoDevice, ChunkSize-1, FreshChunkList, ChunkSize, ListOfTripletGenerators)
    end;

getChunk(IoDevice, LinesLeft, ChunkList, ChunkSize, ListOfTripletGenerators) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, ChunkList),
	    triplet_handler:send_chunk_off(FixedList, ListOfTripletGenerators, true);
	Line ->
	    NextLineList = processLine(Line, false),
	    NewList = lists:append(ChunkList, NextLineList),
	    getChunk(IoDevice, LinesLeft-1, NewList, ChunkSize, ListOfTripletGenerators)
     end.

processLine(Line, true) ->
    InitialList = re:split(Line, "(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+", [{return,list}]),
    FixedList = lists:filter(fun(Entry) -> Entry /= " " end, InitialList),
    Normalized = normalize_list(FixedList),
    FirstTwo = lists:sublist(Normalized, 2),
    FirstTwo;

processLine(Line, false) ->
    InitialList = re:split(Line, "(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+", [{return,list}]),
    FixedList = lists:filter(fun(Entry) -> Entry /= " " end, InitialList),
    Normalized = normalize_list(FixedList),
    Normalized.


