-module(sudoku).
-import(lists, [member/2, filter/2, map/2, flatmap/2, sort/1, all/2]).
-compile(export_all).

print_results(Filename, Seperator) ->
    Solutions = solve_file(Filename, Seperator),
    Msg = "Solved ~p of ~p puzzles from ~s in ~f secs
\t(avg ~f sec (~f Hz) max ~f secs, min ~f secs)~n",
    io:format(Msg, time_stats(Solutions, Filename)).

time_stats(Solutions, Filename) ->
    Solved = filter(fun({_, Dict}) -> is_solved(Dict) end, Solutions),
    NumberPuzzles = length(Solutions),
    Times = [Time|| {Time, _} <- Solutions],
    Max = lists:max(Times)/1000000,
    Min = lists:min(Times)/1000000,
    TotalTime = lists:sum(Times)/1000000,
    Avg = TotalTime/NumberPuzzles,
    Hz = NumberPuzzles/TotalTime,
    [length(Solved), NumberPuzzles, Filename,
     TotalTime, Avg, Hz, Max, Min].

solve_file(Filename, Seperator) ->
    Solutions = solve_all(from_file(Filename, Seperator)),
    OutFilename = [filename:basename(Filename, ".txt")|".out"],
    ok = to_file(OutFilename, Solutions),
    Solutions.

solve_all(GridList) ->
    map(fun time_solve/1, GridList).

from_file(Filename, Seperator) ->
    {ok, BinData} = file:read_file(Filename),
    string:tokens(binary_to_list(BinData), Seperator).

to_file(Filename, Solutions) ->
    GridStrings = map(fun({_, S}) -> [to_string(S)|"\n"] end, Solutions),
    ok = file:write_file(Filename, list_to_binary(GridStrings)).

is_solved(ValuesDict) ->
    all(fun(Unit) -> is_unit_solved(ValuesDict, Unit) end, unitlist()).

is_unit_solved(ValuesDict, Unit) ->
    UnitValues = flatmap(fun(S) -> dict:fetch(S, ValuesDict) end, Unit),
    (length(UnitValues) == 9) and (sets:from_list(UnitValues) == sets:from_list(digits())).

time_solve(GridString) ->
    timer:tc(sudoku, solve, [GridString]).

solve(GridString) ->
    search(parse_grid(GridString)).

search(false) ->
    false;
search(ValuesDict) ->
    search(ValuesDict, is_solved(ValuesDict)).
search(ValuesDict, true) ->
    %% Searching an already solved puzzle should just return it unharmed.
    ValuesDict;
search(ValuesDict, false) ->
    Square = least_valued_unassigned_square(ValuesDict),
    Values = dict:fetch(Square, ValuesDict),
    Results = [search(assign(ValuesDict, Square, Digit))||Digit <- Values],
    first_value(Results).

assign(ValuesDict, Square, Digit) ->
    %% Assign by eliminating all values except the assigned value.
    OtherValues = exclude_from(dict:fetch(Square, ValuesDict), [Digit]),
    eliminate(ValuesDict, [Square], OtherValues).

eliminate(false, _, _) ->
    false;
eliminate(ValuesDict, [], _) ->
    ValuesDict;
eliminate(ValuesDict, [Square|T], Digits) ->
    %% Eliminate the specified Digits from all specified Squares.
    OldValues = dict:fetch(Square, ValuesDict),
    NewValues = exclude_from(OldValues, Digits),
    NewDict = eliminate(ValuesDict, Square, Digits, NewValues, OldValues),
    eliminate(NewDict, T, Digits).

eliminate(_, _, _, [], _) ->
    %% Contradiction: removed last value
    false;
eliminate(ValuesDict, _, _, Vs, Vs) ->
    %% NewValues and OldValues are the same, already eliminated.
    ValuesDict;
eliminate(ValuesDict, Square, Digits, NewValues, _) ->
    NewDict1 = dict:store(Square, NewValues, ValuesDict),
    NewDict2 = peer_eliminate(NewDict1, Square, NewValues),

    %% Digits have been eliminated from this Square.
    %% Now see if the elimination has created a unique place for a digit
    %% to live in the surrounding units of this Square.
    assign_unique_place(NewDict2, units(Square), Digits).

peer_eliminate(ValuesDict, Square, [AssignedValue]) ->
    %% If there is only one value left, we can also
    %% eliminate that value from the peers of Square
    eliminate(ValuesDict, peers(Square), [AssignedValue]);
peer_eliminate(ValuesDict, _, _) ->
    %% Multiple values, cannot eliminate from peers.
    ValuesDict.

assign_unique_place(false, _, _) ->
    false;
assign_unique_place(ValuesDict, [], _) ->
    ValuesDict;
assign_unique_place(ValuesDict, [Unit|T], Digits) ->
    %% If a certain digit can only be in one place in a unit,
    %% assign it.
    NewDict = assign_unique_place_for_unit(ValuesDict, Unit, Digits),
    assign_unique_place(NewDict, T, Digits).

assign_unique_place_for_unit(false, _, _) ->
    false;
assign_unique_place_for_unit(ValuesDict, _, []) ->
    ValuesDict;
assign_unique_place_for_unit(ValuesDict, Unit, [Digit|T]) ->
    Places = places_for_value(ValuesDict, Unit, Digit),
    NewDict = assign_unique_place_for_digit(ValuesDict, Places, Digit),
    assign_unique_place_for_unit(NewDict, Unit, T).

assign_unique_place_for_digit(_, [], _) ->
    %% Contradiction: no place for Digit found
    false;
assign_unique_place_for_digit(ValuesDict, [Square], Digit) ->
    %% Unique place for Digit found, assign
    assign(ValuesDict, Square, Digit);
assign_unique_place_for_digit(ValuesDict, _, _) ->
    %% Mutlitple palces (or none) found for Digit
    ValuesDict.

places_for_value(ValuesDict, Unit, Digit) ->
    [Square||Square <- Unit, member(Digit, dict:fetch(Square, ValuesDict))].

least_valued_unassigned_square(ValuesDict) ->
    least_valued_unassigned_square(ValuesDict, is_solved(ValuesDict)).
least_valued_unassigned_square(_, true) ->
    %% It does not make sense to call this on a solved puzzle
    false;
least_valued_unassigned_square(ValuesDict, false) ->
    %% Return the unassigned square with the fewest possible values
    Lengths = map(fun({S, Values}) -> {length(Values), S} end,
                  dict:to_list(ValuesDict)),
    Unassigned = filter(fun({Length, _}) -> Length > 1 end, Lengths),
    {_, Square} = lists:min(Unassigned),
    Square.

to_string(ValuesDict) ->
    Fun = fun({_, [V]}) -> [V];
             ({_, _}) -> "."
          end,
    flatmap(Fun, sort(dict:to_list(ValuesDict))).

parse_grid(GridString) ->
    CleanGrid = clean_grid(GridString),
    81 = length(CleanGrid),
    parsed_dict(empty_dict(), squares(), CleanGrid).

clean_grid(GridString) ->
    %% Return a string with only digits, 0 and .
    ValidChars = digits() ++ "0.",
    filter(fun(E) -> member(E, ValidChars) end, GridString).

parsed_dict(ValuesDict, [], []) ->
    ValuesDict;
parsed_dict(ValuesDict, [Square|Squares], [Value|GridString]) ->
    IsDigit = member(Value, digits()),
    NewDict = assign_if_digit(ValuesDict, Square, Value, IsDigit),
    parsed_dict(NewDict, Squares, GridString).

assign_if_digit(ValuesDict, Square, Value, true) ->
    %% Value is a Digit, possible to assign
    assign(ValuesDict, Square, Value);
assign_if_digit(ValuesDict, _, _, false) ->
    %% Not possible to assign
    ValuesDict.

empty_dict() ->
    Digits = digits(),
    dict:from_list([{Square, Digits} || Square <- squares()]).

cross(SeqA, SeqB) ->
    %% Cross product of elements in SeqA and elements in SeqB.
    [[X,Y] || X <- SeqA, Y <- SeqB].

digits() ->
    "123456789".
rows() ->
    "ABCDEFGHI".
cols() ->
    digits().

squares() ->
    %% Returns a list of 81 square names, including "A1" etc.
    cross(rows(), cols()).

col_squares() ->
    %% All the square names for each column.
    [cross(rows(), [C]) || C <- cols()].
row_squares() ->
    %% All the square names for each row.
    [cross([R], cols()) || R <- rows()].
box_squares() ->
    %% All the square names for each box.
    [cross(Rows, Cols) || Rows <- ["ABC", "DEF", "GHI"],
                          Cols <- ["123", "456", "789"]].

unitlist() ->
    %% A list of all units (columns, rows, boxes) in a grid.
    col_squares() ++ row_squares() ++ box_squares().

units(Square) ->
    %% A list of units for a specific square
    [S || S <- unitlist(), member(Square, S)].

peers(Square) ->
    %% A unique list of squares (excluding this one)
    %% that are also part of the units for this square.
    NonUniquePeers = shallow_flatten([S || S <- units(Square)]),
    PeerSet = sets:from_list(NonUniquePeers),
    PeersWithSelf = sets:to_list(PeerSet),
    lists:delete(Square, PeersWithSelf).

shallow_flatten([]) -> [];
shallow_flatten([H|T]) ->
    H ++ shallow_flatten(T).

exclude_from(Values, Exluders) ->
    filter(fun(E) -> not member(E, Exluders) end, Values).

%% Returns the first non-false value, otherwise false
first_value([]) ->
    false;
first_value([H|T]) ->
    first_value(H, T).
first_value(false, T) ->
    first_value(T);
first_value(H, _) ->
    H.
