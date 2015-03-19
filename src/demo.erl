
-module(demo).

-export([main/1, parse/1]).

main([]) ->
  io:format("need at least one filename to convert~n"),
  halt(1);
main(Files) ->
  lists:foreach(fun parse/1, Files),
  halt(0).

parse(Filename) ->
  {ok, Bytes} = file:read_file(Filename),
  read_demo(Bytes).

read_demo(<<"HL2DEMO", 0,
            Demo:32/little, Net:32/little,
            Server:260/bytes, Client:260/bytes,
            Map:260/bytes, Game:260/bytes,
            Time:32/float-little, Ticks:32/little,
            Frames:32/little, Signon:32/little,
            Stream/binary>>) ->
  Header = [
    {demo, Demo}
   ,{net, Net}
   ,{server, zs(Server)}
   ,{client, zs(Client)}
   ,{map, zs(Map)}
   ,{game, zs(Game)}
   ,{time, Time}
   ,{ticks, Ticks}
   ,{tick_rate, Ticks / Time}
   ,{frames, Frames}
   ,{signon, Signon}
   ],
  format({header, Header}),
  read_frames(Stream),
  ok;
read_demo(_) ->
  {error, "unrecognised demo file"}.

read_frames(<<Cmd:8, Tick:32/little, Slot:8, Rest/binary>>) ->
  Command = command(Cmd),
  {Data, Next} =
    case Command of
      signon -> read_packet(Rest);
      packet -> read_packet(Rest);
      consolecmd -> read_consolecmd(Rest);
      usercmd -> read_usercmd(Rest);
      datatables -> read_datatab(Rest);
      stringtables -> read_stringtab(Rest);
      synctick -> {skip, Rest};
      customdata -> {skip, Rest};
      stop ->
        <<>> = Rest,
        {stop, Rest}
     end,
  format({frame, [{cmd, Command}, {tick, Tick}, {slot, Slot}, {data, Data}]}),
  read_frames(Next);
read_frames(<<>>) ->
  ok.

command(1) -> signon;
command(2) -> packet;
command(3) -> synctick;
command(4) -> consolecmd;
command(5) -> usercmd;
command(6) -> datatables;
command(7) -> stop;
command(8) -> customdata;
command(9) -> stringtables.

read_packet(B0) ->
  {Cmd, B1} = cmd_info(B0),
  {Seq, B2} = seq_info(B1),
  {Data, B3} = raw_data(B2),
  {{packet, [Seq, Cmd, {size, size(Data)}]}, B3}.

cmd_info(B0) ->
  {Split1, B1} = split(B0),
  {Split2, B2} = split(B1),
  {{cmd, [{split_1, Split1}, {split_2, Split2}]}, B2}.

split(<<Flags:32/little, B0/binary>>) ->
  {Vec1, B1} = vector(B0),
  {QA11, B2} = qangle(B1),
  {QA12, B3} = qangle(B2),
  {Vec2, B4} = vector(B3),
  {QA21, B5} = qangle(B4),
  {QA22, B6} = qangle(B5),
  {[{flags, Flags}
    ,{view_origin_1, Vec1}
    ,{view_angles_1, QA11}
    ,{local_view_angles_1, QA12}
    ,{view_origin_2, Vec2}
    ,{view_angles_2, QA21}
    ,{local_view_angle_2, QA22}], B6}.

vector(<<X:32/float-little, Y:32/float-little, Z:32/float-little, B/binary>>) ->
  {[{x, X}, {y, Y}, {z, Z}], B}.

qangle(Bin) -> vector(Bin).


seq_info(<<In:32/little, Out:32/little, B/binary>>) ->
  {{seq, [{in, In}, {out, Out}]}, B}.

% Read arbitrary length-prefixed bytes.
raw_data(<<Size:32/little, Data:Size/bytes, Rest/binary>>) ->
  {Data, Rest}.


read_consolecmd(B0) ->
  {Data, B1} = raw_data(B0),
  {{consolecmd, size(Data)}, B1}.

read_usercmd(<<Out:32/little, B0/binary>>) ->
  {Data, B1} = raw_data(B0),
  {{usercmd, [{out, Out}, {size, size(Data)}]}, B1}.

read_datatab(B0) ->
  % The data is a set of protobuf encoded messages.
  {Data, B1} = raw_data(B0),
  {{datatab, size(Data)}, B1}.

read_stringtab(B0) ->
  {Data, B1} = raw_data(B0),
  {{stringtab, size(Data)}, B1}.


% Extract a zero terminated string from a binary.
-spec zs(binary()) -> binary().

zs(Bin) -> zs(Bin, 0).

zs(Bin, N) ->
  case Bin of
    <<S:N/binary, 0, _/binary>> -> S;
    <<S:N/binary>> -> S;
    _ -> zs(Bin, N+1)
  end.


format(Fields) ->
  io:format("~s~n", [encode(Fields)]).

encode(D) ->
  L = lift(D),
  jiffy:encode(L).


% Lift our data structure to something jiffy can encode.
lift({K, V1}) when is_list(V1) ->
  V2 = lists:map(fun loft/1, V1),
  V3 = case lists:all(fun erlang:is_tuple/1, V1) of
    true -> { V2 };
    false -> V2
  end,
  { [ {K, V3} ] };
lift({K, V}) -> {[ {K, loft(V)} ]};
lift(V) -> loft(V).

loft(T = {_, V}) when is_atom(V); is_number(V); is_binary(V) -> T;
loft({K, V1}) when is_list(V1) ->
  V2 = lists:map(fun loft/1, V1),
  V3 = case lists:all(fun erlang:is_tuple/1, V1) of
    true -> { V2 };
    false -> V2
  end,
  {K, V3};
loft({K, V}) when is_tuple(V); size(V) == 2 -> {K, lift(V)};
loft(V) when is_atom(V); is_number(V); is_binary(V) -> V.

