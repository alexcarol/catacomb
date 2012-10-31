-module(ct_yaws_catacomb_ws_endpoint).

-export([handle_message/2]).

-include("deps/yaws/include/yaws_api.hrl").

%% define callback state to accumulate a fragmented WS message
%% which we echo back when all fragments are in, returning to
%% initial state.
-include("ct_client_state.hrl").
-record(state, {frag_type = none,               % fragment type
                acc = <<>>,                     % accumulate fragment data
                client_command_state=#ct_client_state{}}).    % client command state (opaque)              

%% start of a fragmented message
-spec handle_message(#ws_frame_info{},_) -> {'close',{'error',{'unhandled_message',{_,_,_,_,_,_,_,_,_,_}}}} | {'noreply',_} | {'reply',{'binary',_} | {'pong',_} | {'text',binary()},_} | {'stop',_,_}.
handle_message(#ws_frame_info{fin=0,
                              opcode=FragType,
                              data=Data},
               #state{frag_type=none, acc = <<>>}) ->
    {noreply, #state{frag_type=FragType, acc=Data}};

%% non-final continuation of a fragmented message
handle_message(#ws_frame_info{fin=0,
                              data=Data,
                              opcode=continuation},
               #state{frag_type = FragType, acc = Acc}) ->
    {noreply, #state{frag_type=FragType, acc = <<Acc/binary,Data/binary>>}};

%% end of text fragmented message
handle_message(#ws_frame_info{fin=1,
                              opcode=continuation,
                              data=Data},
               #state{frag_type=text, acc=Acc}) ->
    Unfragged = <<Acc/binary, Data/binary>>,
    {reply, {text, Unfragged}, #state{frag_type=none, acc = <<>>}};

%% one full non-fragmented message
handle_message(#ws_frame_info{opcode=text, data=Data}, State) ->
  try
    is_record (State,state),
    ClientState=State#state.client_command_state,
    io:format("Current state ~p ~p~n",[ClientState#ct_client_state.session_pid,ClientState#ct_client_state.user_id]),
    
    %% Decode received data into a Erlang structures
    {_BoolResult,Result,NewClientState}=ct_client_command:execute(Data,ClientState),
    
    NewState=State#state{client_command_state=NewClientState},

    {reply, {text, list_to_binary(Result)}, NewState}
  catch Exc:Why ->
      Trace=erlang:get_stacktrace(),
      error_logger:error_msg("Error in ~s: ~p ~p ~p.\n", [?MODULE,Exc,Why,Trace]),
        {stop, Why, State}
  end;


%% end of binary fragmented message
handle_message(#ws_frame_info{fin=1,
                              opcode=continuation,
                              data=Data},
               #state{frag_type=binary, acc=Acc}) ->
    Unfragged = <<Acc/binary, Data/binary>>,
    io:format("echoing back binary message~n",[]),
    {reply, {binary, Unfragged}, #state{frag_type=none, acc = <<>>}};

%% one full non-fragmented binary message
handle_message(#ws_frame_info{opcode=binary,
                              data=Data},
               State) ->
    io:format("echoing back binary message~n",[]),
    {reply, {binary, Data}, State};

handle_message(#ws_frame_info{opcode=ping,
                              data=Data},
               State) ->
    io:format("replying pong to ping~n",[]),
    {reply, {pong, Data}, State};

handle_message(#ws_frame_info{opcode=pong}, State) ->
    %% A response to an unsolicited pong frame is not expected.
    %% http://tools.ietf.org/html/\
    %%            draft-ietf-hybi-thewebsocketprotocol-08#section-4
    io:format("ignoring unsolicited pong~n",[]),
    {noreply, State};
%% Client is closing connection
handle_message(#ws_frame_info{opcode=close}, State) ->
    io:format("WS Endpoint client closing.~n"),
    {noreply, State};

%% Catch all
handle_message(#ws_frame_info{}=FrameInfo, State) ->
    io:format("WS Endpoint Unhandled message: ~p~n~p~n", [FrameInfo, State]),
    {close, {error, {unhandled_message, FrameInfo}}}.