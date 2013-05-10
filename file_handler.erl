-module(file_handler).
-export([normalize_list/1, processFile/4, getChunk/6, processLine/2, processFiles/5]).

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
    getChunk(IoDevice, ChunkSize, [], ChunkSize, ListOfTripletGenerators, OverallCounterPID).

getChunk(IoDevice, 0, ChunkList, ChunkSize, ListOfTripletGenerators, OverallCounterPID) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, ChunkList),
	    OverallCounterPID ! {added_triplets, length(FixedList)-2},
	    OverallCounterPID ! {eof},	
	    handle_triplets:send_chunk_off(FixedList, ListOfTripletGenerators);
	Line ->
	    NextLineList = processLine(Line, true),
	    NewList = lists:append(ChunkList, NextLineList),
	    
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, NewList),
	    OverallCounterPID ! {added_triplets, length(FixedList)-2},
	    handle_triplets:send_chunk_off(FixedList, ListOfTripletGenerators),
	    FreshChunkList = processLine(Line, false),
	    getChunk(IoDevice, ChunkSize-1, FreshChunkList, ChunkSize, ListOfTripletGenerators, OverallCounterPID)
    end;
    

getChunk(IoDevice, LinesLeft, ChunkList, ChunkSize, ListOfTripletGenerators, OverallCounterPID) ->
    case io:get_line(IoDevice, "") of
	eof ->
	    FixedList = lists:filter(fun(Entry) -> (Entry /= "\n") and (Entry /= []) end, ChunkList),
	    io:fwrite("FixedList: ~p~n", [FixedList]),
	    OverallCounterPID ! {added_triplets, length(FixedList)-2},
	    OverallCounterPID ! {eof},
	    handle_triplets:send_chunk_off(FixedList, ListOfTripletGenerators);
	Line ->
	    NextLineList = processLine(Line, false),
	    NewList = lists:append(ChunkList, NextLineList),
	    getChunk(IoDevice, LinesLeft-1, NewList, ChunkSize, ListOfTripletGenerators, OverallCounterPID)
     end.
     

processLine(Line, Extended) ->
    InitialList = re:split(Line, "(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+", [{return,list}]),
    FixedList = lists:filter(fun(Entry) -> Entry /= " " end, InitialList),
    Normalized = normalize_list(FixedList),
    case Extended of
	true ->
	    FirstTwo = lists:sublist(Normalized, 2),
	    FirstTwo;
	false ->
	    Normalized
    end.
