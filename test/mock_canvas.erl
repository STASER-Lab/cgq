-module(mock_canvas).
-export([start/0]).

-define(BEARER, "Bearer mock-token").
-define(POINTS_GIVEN_TO_EACH_MEMBER, <<"3">>).

start() ->
    ok = use_cacerts_from_ssl_cert_file_env(),
    case ets:info(db) of
        undefined -> ets:new(db, [named_table, public, set]);
        _ -> ets:delete_all_objects(db)
    end,
    ets:insert(db, {next_quiz_id, 300}),
    ets:insert(db, {next_question_id, 1000}),
    {ok, Listen} =
        gen_tcp:listen(0, [
            binary, {packet, http_bin}, {active, false}, {reuseaddr, true}
        ]),
    {ok, Port} = inet:port(Listen),
    Acceptor = spawn(fun() -> accept_loop(Listen) end),
    ok = gen_tcp:controlling_process(Listen, Acceptor),
    Port.

%% httpc loads OS CA certs even for plain-http requests; sandboxes (nix
%% builds) have none, so honor SSL_CERT_FILE the way openssl tooling does.
use_cacerts_from_ssl_cert_file_env() ->
    case os:getenv("SSL_CERT_FILE") of
        false -> ok;
        Path -> application:set_env(public_key, cacerts_path, Path, [{persistent, true}])
    end.

accept_loop(Listen) ->
    {ok, Socket} = gen_tcp:accept(Listen),
    Pid = spawn(fun() -> receive go -> serve(Socket) end end),
    ok = gen_tcp:controlling_process(Socket, Pid),
    Pid ! go,
    accept_loop(Listen).

serve(Socket) ->
    {ok, {http_request, Method, {abs_path, RawPath}, _}} = gen_tcp:recv(Socket, 0),
    Headers = read_headers(Socket, #{}),
    Body = read_body(Socket, Headers),
    {Path, Query} = split_path(binary_to_list(RawPath)),
    Segments = string:lexemes(Path, "/"),
    {Status, Json} =
        case maps:get("authorization", Headers, missing) of
            ?BEARER -> route(Method, Segments, Query, Body);
            _ -> {401, json_bin(#{errors => [#{message => <<"Invalid access token.">>}]})}
        end,
    send_response(Socket, Status, Json),
    gen_tcp:close(Socket).

route('GET', ["api", "v1", "courses"], _, _) ->
    {200, json_bin([#{id => 101, name => <<"Mock Software Engineering">>}])};
route('GET', ["api", "v1", "courses", "101", "groups"], Query, _) ->
    All = [group_json(G) || G <- groups()],
    {200, json_bin(paginate(All, Query, 1))};
route('GET', ["api", "v1", "groups", GidS, "users"], _, _) ->
    {_, _, MemberIds} = group(list_to_integer(GidS)),
    {200, json_bin([user_json(Uid) || Uid <- MemberIds])};
route('GET', ["api", "v1", "groups", GidS], _, _) ->
    {200, json_bin(group_json(group(list_to_integer(GidS))))};
route('GET', ["api", "v1", "courses", "101", "quizzes", QidS, "questions"], Query, _) ->
    Qid = list_to_integer(QidS),
    Matching = lists:sort(ets:match_object(db, {{question, Qid, '_'}, '_', '_', '_'})),
    All =
        [(question_json(Type, Text, Points))#{id => Quid}
         || {{question, _, Quid}, Type, Text, Points} <- Matching],
    {200, json_bin(paginate(All, Query, 50))};
route('GET', ["api", "v1", "courses", "101", "quizzes"], Query, _) ->
    Term = proplists:get_value("search_term", Query, ""),
    Matching =
        [Q || {{quiz, _}, _, Title} = Q <- ets:match_object(db, {{quiz, '_'}, '_', '_'}),
              string:find(Title, Term) =/= nomatch],
    Sorted = lists:sort(Matching),
    All = [quiz_json(Id, Aid, Title) || {{quiz, Id}, Aid, Title} <- Sorted],
    {200, json_bin(paginate(All, Query, 1))};
route('GET', ["api", "v1", "courses", "101", "assignments", AidS, "submissions"], _, _) ->
    {200, json_bin(synthesized_submissions(list_to_integer(AidS)))};
route('GET', ["api", "v1", "courses", "101", "users", UidS], _, _) ->
    {200, json_bin(user_json(list_to_integer(UidS)))};
route('GET', ["api", "v1", "courses", "101", "users"], Query, _) ->
    All = [user_json(Uid) || {Uid, _} <- users()],
    {200, json_bin(paginate(All, Query, 10))};
route('GET', ["api", "v1", "courses", "101", "assignment_groups"], _, _) ->
    {200, json_bin([#{id => 1, name => <<"Quizzes">>}])};
route('POST', ["api", "v1", "courses", "101", "quizzes"], _, Body) ->
    Form = uri_string:dissect_query(Body),
    Title = proplists:get_value(<<"quiz[title]">>, Form, <<"Untitled">>),
    Id = ets:update_counter(db, next_quiz_id, 1),
    Aid = Id + 1000,
    ets:insert(db, {{quiz, Id}, Aid, Title}),
    {200, json_bin(quiz_json(Id, Aid, Title))};
route('POST', ["api", "v1", "courses", "101", "quizzes", QidS, "questions"], _, Body) ->
    Form = uri_string:dissect_query(Body),
    Qid = list_to_integer(QidS),
    Quid = ets:update_counter(db, next_question_id, 1),
    Type = proplists:get_value(<<"question[question_type]">>, Form),
    Text = proplists:get_value(<<"question[question_text]">>, Form),
    Points =
        case proplists:get_value(<<"question[points_possible]">>, Form) of
            undefined -> none;
            P -> binary_to_integer(P)
        end,
    ets:insert(db, {{question, Qid, Quid}, Type, Text, Points}),
    {200, json_bin((question_json(Type, Text, Points))#{id => Quid})};
route('POST', ["api", "v1", "courses", "101", "assignments", AidS, "overrides"], _, Body) ->
    Form = uri_string:dissect_query(Body),
    Aid = list_to_integer(AidS),
    StudentIds =
        [binary_to_integer(V) || {<<"assignment_override[student_ids][]">>, V} <- Form],
    ets:insert(db, {{override, Aid}, StudentIds}),
    [{{quiz, QuizId}, Aid, _}] = ets:match_object(db, {{quiz, '_'}, Aid, '_'}),
    {200, json_bin(#{assignment_id => Aid, quiz_id => QuizId, student_ids => StudentIds})};
route('PUT', ["api", "v1", "courses", "101", "quizzes", _QidS], _, _) ->
    {200, <<"{}">>};
route(Method, Segments, _, _) ->
    io:format("mock canvas 404: ~p ~p~n", [Method, Segments]),
    {404, json_bin(#{errors => [#{message => <<"not found">>}]})}.

users() ->
    [
        {1, <<"Alice Anderson">>},
        {2, <<"Bob Brown">>},
        {3, <<"Carol Clarke">>},
        {4, <<"Dave Dunn">>},
        {5, <<"Erin Estrada">>}
    ].

groups() ->
    [
        {201, <<"Group Alpha">>, [1, 2, 3]},
        {202, <<"Group Beta">>, [4, 5]}
    ].

group(Gid) -> lists:keyfind(Gid, 1, groups()).

user_json(Uid) ->
    {Uid, Name} = lists:keyfind(Uid, 1, users()),
    #{id => Uid, name => Name}.

group_json({Gid, Name, MemberIds}) ->
    #{id => Gid, members_count => length(MemberIds), name => Name}.

quiz_json(Id, Aid, Title) ->
    #{id => Id, assignment_id => Aid, title => Title}.

question_json(Type, Text, none) ->
    #{question_type => Type, question_text => Text};
question_json(Type, Text, Points) ->
    #{question_type => Type, question_text => Text, points_possible => Points}.

synthesized_submissions(Aid) ->
    case ets:match_object(db, {{quiz, '_'}, Aid, '_'}) of
        [] ->
            [];
        [{{quiz, QuizId}, Aid, _}] ->
            StudentIds =
                case ets:lookup(db, {override, Aid}) of
                    [{_, Ids}] -> Ids;
                    [] -> []
                end,
            Questions =
                lists:sort(ets:match_object(db, {{question, QuizId, '_'}, '_', '_', '_'})),
            [synthesized_submission(Aid, Uid, Questions) || Uid <- StudentIds]
    end.

synthesized_submission(Aid, Uid, Questions) ->
    Answers =
        [
            #{question_id => Quid, text => synthesized_answer(Type, Text)}
         || {{question, _, Quid}, Type, Text, _} <- Questions
        ],
    #{
        id => Aid * 100 + Uid,
        user_id => Uid,
        user => user_json(Uid),
        submission_history => [#{submission_data => Answers}]
    }.

synthesized_answer(_, <<"The points distributed for ", _/binary>>) ->
    ?POINTS_GIVEN_TO_EACH_MEMBER;
synthesized_answer(<<"numerical_question">>, _) ->
    <<"2">>;
synthesized_answer(<<"essay_question">>, _) ->
    <<"<p>Mock feedback: steady progress this week.</p>">>;
synthesized_answer(_, _) ->
    <<>>.

read_headers(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, {http_header, _, Name, _, Value}} ->
            Key = string:lowercase(to_list(Name)),
            read_headers(Socket, Acc#{Key => to_list(Value)});
        {ok, http_eoh} ->
            Acc
    end.

read_body(Socket, Headers) ->
    Len = list_to_integer(maps:get("content-length", Headers, "0")),
    ok = inet:setopts(Socket, [{packet, raw}]),
    case Len of
        0 ->
            <<>>;
        _ ->
            {ok, Body} = gen_tcp:recv(Socket, Len),
            Body
    end.

split_path(RawPath) ->
    case string:split(RawPath, "?") of
        [Path] -> {Path, []};
        [Path, Qs] -> {Path, uri_string:dissect_query(Qs)}
    end.

paginate(All, Query, PageSize) ->
    Page = list_to_integer(proplists:get_value("page", Query, "1")),
    Start = (Page - 1) * PageSize + 1,
    case Start > length(All) of
        true -> [];
        false -> lists:sublist(All, Start, PageSize)
    end.

send_response(Socket, Status, Body) ->
    Phrase =
        case Status of
            200 -> "OK";
            401 -> "Unauthorized";
            _ -> "Not Found"
        end,
    Response = [
        "HTTP/1.1 ", integer_to_list(Status), " ", Phrase, "\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ", integer_to_list(iolist_size(Body)), "\r\n",
        "Connection: close\r\n",
        "\r\n",
        Body
    ],
    ok = gen_tcp:send(Socket, Response).

json_bin(Term) -> iolist_to_binary(json:encode(Term)).

to_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_list(Binary) when is_binary(Binary) -> binary_to_list(Binary);
to_list(List) when is_list(List) -> List.
