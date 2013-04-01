-module(axiom_SUITE).
-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").


all() -> [
		redirect,
		redirect_non_get,
		render_dtl,
		render_dtl_with_params,
		process_response_binary,
		process_response_tuple_2,
		process_response_tuple_3,
		{group, with_defaults},
		{group, with_custom_500},
		{group, static_files},
		{group, session_ets}
		].

groups() -> [
		{with_defaults, [], [
				defaults,
				http_post_with_query_params,
				http_post_with_multipart_body,
				http_not_found,
				http_500,
				http_render_template,
				http_redirect,
				http_redirect_relative,
				http_respond_with_iolist
				]},
		{with_custom_500, [], [http_custom_500]},
		{static_files, [], [http_hello_static]},
		{session_ets, [], [http_set_and_get]}
		].

%% groupless

render_dtl(_Config) ->
	file:make_dir("templates"),
	Template = "templates/my_template.dtl",
	ok = file:write_file(Template, "<h1>It works!</h1>"),
	ok = erlydtl:compile(Template, my_template_dtl),
	[<<"<h1>It works!</h1>">>] = axiom:dtl(my_template).

render_dtl_with_params(_Config) ->
	file:make_dir("templates"),
	Template = "templates/my_template.dtl",
	ok = file:write_file(Template, "Hello {{who}} from {{from}}!"),
	ok = erlydtl:compile(Template, my_template_dtl),
	[<<"Hello ">>,<<"you">>,<<" from ">>,<<"me">>,<<"!">>] =
		axiom:dtl(my_template,
			[{<<"who">>, <<"you">>}, {<<"from">>, <<"me">>}]).

redirect(_Config) ->
	Req = axiom_test_helper:build_request([{host, <<"example.com">>}]),
	Req1 = axiom:redirect("/foo/bar", Req),
	{302, _} = cowboy_req:meta(resp_status, Req1),
	Headers = cowboy_req:get(resp_headers, Req1),
	<<"http://example.com/foo/bar">> =
		iolist_to_binary(proplists:get_value(<<"Location">>, Headers)).

redirect_non_get(_Config) ->
	Req = axiom_test_helper:build_request(
			[{method, <<"POST">>}, {host, <<"example.com">>}]),
	Req1 = axiom:redirect("/foo/bar", Req),
	{303, _} = cowboy_req:meta(resp_status, Req1),
	Headers = cowboy_req:get(resp_headers, Req1),
	<<"http://example.com/foo/bar">> =
		iolist_to_binary(proplists:get_value(<<"Location">>, Headers)).

process_response_binary(_Config) ->
	Req = axiom_test_helper:build_request(),
	Body = <<"<h1>It works!</h1>">>,
	Req1 = axiom:process_response(Body, Req),
	Body = cowboy_req:get(resp_body, Req1).

process_response_tuple_2(_Config) ->
	Req = axiom_test_helper:build_request(),
	Resp = {500, <<"<h1>It doesn't work!</h1>">>},
	Req1 = axiom:process_response(Resp, Req),
	<<"<h1>It doesn't work!</h1>">> = cowboy_req:get(resp_body, Req1),
	{500, _} = cowboy_req:meta(resp_status, Req1).

process_response_tuple_3(_Config) ->
	Req = axiom_test_helper:build_request(),
	Resp = {500, [{<<"Foo">>, <<"bar">>}], <<"<h1>It doesn't work!</h1>">>},
	Req1 = axiom:process_response(Resp, Req),
	<<"<h1>It doesn't work!</h1>">> = cowboy_req:get(resp_body, Req1),
	{500, _} = cowboy_req:meta(resp_status, Req1),
	[{<<"Foo">>, <<"bar">>}] = cowboy_req:get(resp_headers, Req1).

defaults(Config) ->
	{ok, {Status, Headers, Body}} = httpc:request(
			base_url(Config) ++ "defaults"),
	{"HTTP/1.1",200,"OK"} = Status,
	"<h1>It works!</h1>" = Body,
	"text/html" = proplists:get_value("content-type", Headers).

http_post_with_query_params(Config) ->
	{ok, {Status, _Headers, Body}} = httpc:request(post,
		{base_url(Config) ++ "query-params?foo=bar", [], [], []}, [], []),
	{"HTTP/1.1",200,"OK"} = Status,
	"ok" = Body.

http_post_with_multipart_body(Config) ->
	{ok, {Status, _Headers, Body}} = httpc:request(post,
		{base_url(Config) ++ "query-params", [], "multipart/form-data",
					"foo=bar"}, [], []),
	{"HTTP/1.1",200,"OK"} = Status,
	"ok" = Body.

http_not_found(Config) ->
	{ok, {Status, _Headers, Body}} =
		httpc:request(base_url(Config) ++ "do/not/find"),
    true = string:str(Body, "Not Found") > 0,
	{"HTTP/1.1",404,"Not Found"} = Status.

http_500(Config) ->
	{ok, {Status, _Headers, Body}} =
		httpc:request(base_url(Config) ++ "fail"),
	{"HTTP/1.1",500,"Internal Server Error"} = Status,
    true = string:str(Body, "Something went wrong.") > 0.

http_custom_500(Config) ->
	{ok, {Status, _Headers, Body}} =
		httpc:request(base_url(Config) ++ "fails"),
	{"HTTP/1.1",500,"Internal Server Error"} = Status,
	"custom 500 message" = Body.

http_render_template(Config) ->
	file:make_dir("templates"),
	Template = "templates/my_template.dtl",
	ok = file:write_file(Template, "Hello {{who}} from {{from}}!"),
	ok = erlydtl:compile(Template, my_template_dtl),
	{ok, {_Status, _Headers, Body}} =
		httpc:request(base_url(Config) ++ "template/?who=you&from=me"),
	"Hello you from me!" = Body.

http_redirect(Config) ->
	{ok, {Status, Headers, _Body}} =
	httpc:request(get, {base_url(Config) ++ "where/are/you", []},
			[{autoredirect, false}],[]),
	{"HTTP/1.1",302,"Found"} = Status,
	"http://example.com/over/here" = proplists:get_value("location", Headers).

http_redirect_relative(Config) ->
	{ok, {Status, Headers, _Body}} =
	httpc:request(get, {base_url(Config) ++ "where/am/i", []},
			[{autoredirect, false}],[]),
	{"HTTP/1.1",302,"Found"} = Status,
	Expect = base_url(Config) ++ "some/strange/place/?p=yes",
	Expect = proplists:get_value("location", Headers).

http_respond_with_iolist(Config) ->
	{ok, {Status, _Headers, Body}} =
	httpc:request(get, {base_url(Config) ++ "iolist", []}, [],[]),
	{"HTTP/1.1",200,"OK"} = Status,
	"I am an iolist!" = Body.

http_hello_static(Config) ->
	{ok, {Status, _Headers, Body}} =
	httpc:request(get, {base_url(Config) ++ "html/index.html", []}, [],[]),
	{"HTTP/1.1",200,"OK"} = Status,
	"<h1>It works!</h1>" = Body.

http_set_and_get(Config) ->
	httpc:set_options([{cookies, enable}]),
	{ok, {Status, _Headers, Body}} =
		httpc:request(base_url(Config) ++ "set"),
	{"HTTP/1.1",200,"OK"} = Status,
	"OK" = Body,
	{ok, {Status1, _Headers1, Body1}} =
		httpc:request(base_url(Config) ++ "get"),
	{"HTTP/1.1",200,"OK"} = Status1,
	"bar" = Body1.

%http_with_filters(Config) ->
%	{ok, {Status, _Headers, Body}} = httpc:request(base_url(Config)),
%	{"HTTP/1.1",200,"OK"} = Status,
%	"It works!" = Body.
%
%http_stream_data(Config) ->
%	{ok, _Ref} = httpc:request(get,
%			{base_url(Config) ++ "stream", []}, [],
%			[{sync, false}, {stream, self}]),
%	Body = receive_stream([]),
%	<<"Hello world!">> = Body.
%
%
%% suite
%
%all() -> [{group, with_defaults}, {group, with_options}, {group, session_ets},
%		  {group, with_custom_500}, {group, with_filters}, {group, static_files}].
%
%groups() -> [
%		{with_defaults, [],
%			[redirect, http_hello_world, http_not_found, http_post_with_params,
%				http_render_template, http_redirect, http_respond_with_iolist,
%				http_500, http_stream_data, set_header_on_response,
%				set_header_on_http_req, http_redirect_relative]},
%		{with_options, [], [http_hello_world]},
%		{static_files, [], [http_hello_static]},
%		{session_ets, [], [http_set_and_get]},
%		{with_custom_500, [], [http_custom_500]},
%		{with_filters, [], [http_with_filters]}
%	].
%
init_per_suite(Config) ->
	inets:start(),
	ok = application:start(crypto),
	Config.

end_per_suite(_Config) ->
	ok = application:stop(crypto),
	inets:stop(),
	ok.

init_per_group(with_defaults, Config) ->
	ok = application:start(ranch),
	ok = application:start(cowboy),
	axiom:start(?MODULE),
	Config;
%
%init_per_group(with_options, Config) ->
%	Options = [{port, 7655}],
%	axiom:start(?MODULE, Options),
%	Options ++ Config;
%
init_per_group(static_files, Config) ->
	ok = file:make_dir("public"),
	ok = file:make_dir("public/html"),
	ok = file:write_file("public/html/index.html", "<h1>It works!</h1>"),
	ok = application:start(ranch),
	ok = application:start(cowboy),
	axiom:start(?MODULE),
	Config;

init_per_group(session_ets, Config) ->
	Options = [{sessions, []}],
	ok = httpc:set_options([{cookies, enabled}]),
	ok = application:start(ranch),
	ok = application:start(cowboy),
	axiom:start(?MODULE, Options),
	Options ++ Config;

init_per_group(with_custom_500, Config) ->
	ok = application:start(ranch),
	ok = application:start(cowboy),
	axiom_error_test_app:start(),
	Config.
%
%init_per_group(with_filters, Config) ->
%	axiom_app_with_filters:start(),
%	Config.
%
end_per_group(with_defaults, _Config) ->
	axiom:stop(),
	ok = application:stop(cowboy),
	ok = application:stop(ranch);
%
%end_per_group(with_options, _Config) ->
%	axiom:stop();
%
end_per_group(static_files, _Config) ->
	ok = file:delete("public/html/index.html"),
	ok = file:del_dir("public/html"),
	ok = file:del_dir("public"),
	axiom:stop(),
	ok = application:stop(cowboy),
	ok = application:stop(ranch);

end_per_group(session_ets, _Config) ->
	axiom:stop(),
	ok = application:stop(cowboy),
	ok = application:stop(ranch);

end_per_group(with_custom_500, _Config) ->
	axiom:stop(),
	ok = application:stop(cowboy),
	ok = application:stop(ranch).
%
%end_per_group(with_filters, _Config) ->
%	axiom:stop().
%
%% handlers
%
handle(<<"GET">>, [<<"return">>, <<"binary">>], _Req) ->
	<<"Hello world!">>;

handle(<<"GET">>, [<<"return">>, <<"req">>], Req) ->
	Req;

handle(<<"GET">>, [<<"defaults">>], _Req) ->
	<<"<h1>It works!</h1>">>;

handle(<<"POST">>, [<<"query-params">>], Req) ->
	{[{Param, Value}], _Req1} = axiom:params(Req),
	<<"foo">> = Param,
	<<"bar">> = Value,
	<<"ok">>;

handle(<<"GET">>, [<<"template">>], Req) ->
	{Params, _Req1} = axiom:params(Req),
	axiom:dtl(my_template, Params);

handle(<<"GET">>, [<<"where">>, <<"are">>, <<"you">>], Request) ->
	axiom:redirect("http://example.com/over/here", Request);

handle(<<"GET">>, [<<"where">>, <<"am">>, <<"i">>], Request) ->
	axiom:redirect("/some/strange/place/?p=yes", Request);

handle(<<"GET">>, [<<"iolist">>], _Request) ->
	["I ", [<<"am">>], <<" ">>, ["an"], <<" iolist!">>];

handle(<<"GET">>, [<<"set">>], Req) ->
	axiom_session:set(<<"foo">>, <<"bar">>, Req),
	<<"OK">>;

handle(<<"GET">>, [<<"get">>], Req) ->
	Foo = axiom_session:get(<<"foo">>, Req),
	Foo;

handle(<<"GET">>, [<<"fail">>], _Request) ->
	foo = bar.
%
%handle('GET', [<<"stream">>], Req) ->
%	{ok, Req2} = axiom:chunk(<<"Hello">>, Req),
%	{ok, _} = axiom:chunk(<<" world!">>, Req2),
%	Req2.
%


%% helpers

get_option(Opt, Config) ->
	Defaults = [{port, 7654}],
	case proplists:get_value(Opt, Config) of
		undefined -> proplists:get_value(Opt, Defaults);
		Else -> Else
	end.

base_url(Config) ->
	"http://localhost:" ++ integer_to_list(get_option(port, Config)) ++ "/".
%
%
%receive_stream(ReceivedSoFar) ->
%	receive
%		{http, {_ReqId, stream_start, _Headers}} -> receive_stream(ReceivedSoFar);
%		{http, {_ReqId, stream, BodyPart}} -> receive_stream([ReceivedSoFar, BodyPart]);
%		{http, {_ReqId, stream_end, _Headers}} -> list_to_binary(ReceivedSoFar)
%	after 1000 ->
%		{error, timeout}
%	end.
%

