%% ``The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved via the world wide web at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% The Initial Developer of the Original Code is Ericsson Utvecklings AB.
%% Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
%% AB. All Rights Reserved.''
%% 
-module(erl_html_tools).

%% This file contains tools for updating HTML files in an installed system
%% depending on the installed applications. Currently the only use is
%% to update the top index file.


%% ------ VERY IMPORTANT ------
%%
%% Original location for this file: 
%% /clearcase/otp/internal_tools/integration/scripts/make_index/
%% When updating this file, copy the source to 
%% /home/otp/patch/share/program/
%% and place .beam files (compiled with correct release) in all 
%% /home/otp/patch/share/program/<release>
%% for releases >= R9C
%%
%% ----------------------------


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% This program generate the top index files for the OTP documentation.
% Part of the HTML code is in templates, like "index.html.src" and
% part is written out from this module. So the program and the templates
% has to match.
%
% The templates are searched from the current directory, a directory
% "templates" relative to the current directory or at RootDir.
%
% RootDir is given as an argument or assumed to be code:root_dir(),
% i.e. the root of the system running this program.
%
% The output is put into DestDir or RootDir if not given.
%
% The functions to call are
%
%     top_index()
%     top_index([RootDir])
%     top_index([RootDir,DestDir,OtpRel])
%     top_index(RootDir)
%     top_index(RootDir, DestDir, OtpRel)
%
% where RootDir can be a string or an atom.
%
%
% USING THIS SCRIPT FROM THE UNIX COMMAND LINE
% --------------------------------------------
% If the Erlang started is the same as the Erlang to create index.html
% for the  use
%
%   % erl -noshell -s erl_html_tools top_index
%
% If you want to create an index for another Erlang installation or
% documentation located separate from the object code, then use
%
%   % erl -noshell -s erl_html_tools top_index /path/to/erlang/root
%
%
% COLLECTING INFORMATION
% ----------------------
% This script assumes that all applications have an "info" file
% in their top directory. This file should have some keywords with
% values defined. The keys are 'group' and 'short' (for "short
% description). See the OTP applications for examples.
%
% Some HTML code is generated by this program, others are taken from
% the file "index.html.src" that may be located in the patch directory
% or in the "$ERLANG_ROOT/doc/" directory.
%
% The code for creating the top index page assumes all applications
% have a file "info" with some fields filled in
%
%     short: Text		Short text describing the application
%     group: tag [Heading]	Group tag optionally followed by a description.
%				Only one app need to describe the group but
%				more than one can.
%
% FIXME: Check that there is documentation for the application, not just
%        an info file.
% FIXME: Use records, it is now unreadable :-(
% FIXME: Use a separate URL and URLIndexFile
% FIXME: Pass the OTP release name as an argument instead of in
%        process dictionary (for elegance).

-export([top_index/0,top_index/1,top_index/3,top_index_silent/3]).

% This is the order groups are inserted into the file. Groups
% not in this list is inserted in undefined order.

group_order() ->
    [
     basic,
     dat,
     oam,
     orb,
     comm,
     tools
    ].

top_index() ->
    top_index(code:root_dir()).

top_index([RootDir]) when atom(RootDir) ->
    top_index(atom_to_list(RootDir));
top_index([RootDir,DestDir,OtpRel])
  when is_atom(RootDir), is_atom(DestDir), is_atom(OtpRel) ->
    top_index(atom_to_list(RootDir), atom_to_list(DestDir), atom_to_list(OtpRel));
top_index(RootDir) ->
    {_,RelName} = init:script_id(),
    top_index(RootDir, filename:join(RootDir, "doc"), RelName).

top_index(RootDir, DestDir, OtpRel) ->
    report("****\nRootDir: ~p", [RootDir]),
    report("****\nDestDir: ~p", [DestDir]),
    report("****\nOtpRel: ~p", [OtpRel]),

    put(otp_release, OtpRel),

    Templates = find_templates(["","templates",DestDir]),
    report("****\nTemplates: ~p", [Templates]),
    Bases = [{"../lib/", filename:join(RootDir,"lib")},
	     {"../",     RootDir}],
    Groups = find_information(Bases),
    report("****\nGroups: ~p", [Groups]),
    process_templates(Templates, DestDir, Groups).

top_index_silent(RootDir, DestDir, OtpRel) ->
    put(silent,true),
    Result = top_index(RootDir, DestDir, OtpRel),
    erase(silent),
    Result.
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Main loop - process templates
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

process_templates([], _DestDir, _Groups) ->
    report("\n", []);
process_templates([Template | Templates], DestDir, Groups) ->
    report("****\nIN-FILE: ~s", [Template]),
    BaseName = filename:basename(Template, ".src"),
    case lists:reverse(filename:rootname(BaseName)) of
	"_"++_ ->
	    %% One template expands to several output files.
	    process_multi_template(BaseName, Template, DestDir, Groups);
	_ ->
	    %% Standard one-to-one template.
	    OutFile = filename:join(DestDir, BaseName),
	    subst_file("", OutFile, Template, Groups)
    end,
    process_templates(Templates, DestDir, Groups).


process_multi_template(BaseName0, Template, DestDir, Info) ->
    Ext = filename:extension(BaseName0),
    BaseName1 = filename:basename(BaseName0, Ext),
    [_|BaseName2] = lists:reverse(BaseName1),
    BaseName = lists:reverse(BaseName2),
    Groups0 = [{[$_|atom_to_list(G)],G} || G <- group_order()],
    Groups = [{"",basic}|Groups0],
    process_multi_template_1(Groups, BaseName, Ext, Template, DestDir, Info).

process_multi_template_1([{Suffix,Group}|Gs], BaseName, Ext, Template, DestDir, Info) ->
    OutFile = filename:join(DestDir, BaseName++Suffix++Ext),
    subst_file(Group, OutFile, Template, Info),
    process_multi_template_1(Gs, BaseName, Ext, Template, DestDir, Info);
process_multi_template_1([], _, _, _, _, _) -> ok.

subst_file(Group, OutFile, Template, Info) ->
    report("\nOUTFILE: ~s", [OutFile]),
    case subst_template(Group, Template, Info) of
	{ok,Text,_NewInfo} ->
	    case file:open(OutFile, [write]) of
		{ok, Stream} ->
		    file:write(Stream, Text),
		    file:close(Stream);
		Error ->
		    error("Can't write to file ~s: ~w", [OutFile,Error])
	    end;
	Error ->
	    error("Can't write to file ~s: ~w", [OutFile,Error])
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Find the templates
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

find_templates(SearchPaths) ->
    find_templates(SearchPaths, SearchPaths).

find_templates([SearchPath | SearchPaths], AllSearchPaths) ->
    case filelib:wildcard(filename:join(SearchPath, "*.html.src")) of
	[] ->
	    find_templates(SearchPaths, AllSearchPaths);
	Result ->
	    Result
    end;
find_templates([], AllSearchPaths) ->
    error("No templates found in ~p",[AllSearchPaths]).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This function read all application names and if present all "info" files.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

find_information(Bases) ->
    Paths = find_application_paths(Bases),
%    report("****\nPaths: ~p", [Paths]),
    Apps = find_application_infos(Paths),
%    report("****\nApps: ~p", [Apps]),
    form_groups(Apps).

% The input is a list of tuples of the form
%
%   IN: [{BaseURL,SearchDir}, ...]
%
% and the output is a list
%
%  OUT: [{Appname,AppVersion,AppPath,IndexUTL}, ...]
%
% We know URL ends in a slash.

find_application_paths([]) ->
    [];
find_application_paths([{URL,Dir} | Paths]) ->
    Sub1 = "doc/html/index.html",
%%     Sub2 = "doc/index.html",
    case file:list_dir(Dir) of
	{ok, Dirs} ->
	    AppDirs =
		lists:filter(
		  fun(E) ->
			  is_match(E, "^[A-Za-z0-9_]+-[0-9\\.]+")
		  end, Dirs),
	    AppPaths =
		lists:map(
		  fun(AppDir) -> 
			  {ok,[App,Ver]} = regexp:split(AppDir, "-"),
			  DirPath = filename:join(Dir,AppDir),
			  AppURL = URL ++ AppDir,
			  {App,Ver,DirPath,AppURL ++ "/" ++ Sub1}
%% 			  case file:read_file_info(
%% 				 filename:join(DirPath, Sub1)) of
%% 			      {ok, _} ->
%% 				  {App,Ver,DirPath,AppURL ++ "/" ++ Sub1};
%% 			      _ ->
%% 				  {App,Ver,DirPath,AppURL ++ "/" ++ Sub2}
%% 			  end
		  end, AppDirs),
	    AppPaths ++ find_application_paths(Paths)
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Find info for one application.
% Read the "info" file for each application. Look at "group" and "short".
% key words.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%   IN: [{Appname,AppVersion,AppPath,IndexUTL}, ...]
%  OUT: [{Group,Heading,[{AppName,[{AppVersion,Path,URL,Text} | ...]}
%                        | ...]}, ...]

find_application_infos([]) ->
    [];
find_application_infos([{App,Ver,AppPath,IndexURL} | Paths]) ->
    case read_info(filename:join(AppPath,"info")) of
	{error,_Reason} ->
	    warning("No info for app ~p", [AppPath]),
	    find_application_infos(Paths);
	Db ->
	    {Group,Heading} =
		case lists:keysearch("group", 1, Db) of
		    {value, {_, G0}} ->
			% This value may be in two parts, 
		        % tag and desciption
			case string:str(G0," ") of
			    0 ->
				{list_to_atom(G0),""};
			    N ->
				{list_to_atom(string:substr(G0,1,N-1)),
				 string:substr(G0,N+1)}
			end;
		    false ->
			error("No group given",[])
		end,
	    Text =
		case lists:keysearch("short", 1, Db) of
		    {value, {_, G1}} ->
			G1;
		    false ->
			""
		end,
	    [{Group,Heading,{App,{Ver,AppPath,IndexURL,Text}}}
	     | find_application_infos(Paths)]
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Group into one list element for each group name.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% IN : {Group,Heading,{AppName,{AppVersion,Path,URL,Text}}}
% OUT: {Group,Heading,[{AppName,[{AppVersion,Path,URL,Text} | ...]} | ...]}

form_groups(Apps) ->
    group_apps(lists:sort(Apps)).

group_apps([{Group,Heading,AppInfo} | Info]) ->
    group_apps(Info, Group, Heading, [AppInfo]);
group_apps([]) ->
    [].

% First description
group_apps([{Group,"",AppInfo} | Info], Group, Heading, AppInfos) ->
    group_apps(Info, Group, Heading, [AppInfo | AppInfos]);
group_apps([{Group,Heading,AppInfo} | Info], Group, "", AppInfos) ->
    group_apps(Info, Group, Heading, [AppInfo | AppInfos]);
% Exact match
group_apps([{Group,Heading,AppInfo} | Info], Group, Heading, AppInfos) ->
    group_apps(Info, Group, Heading, [AppInfo | AppInfos]);
% Different descriptions
group_apps([{Group,_OtherHeading,AppInfo} | Info], Group, Heading, AppInfos) ->
    warning("Group ~w descriptions differ",[Group]),
    group_apps(Info, Group, Heading, [AppInfo | AppInfos]);
group_apps(Info, Group, Heading, AppInfos) ->
    [{Group,Heading,combine_apps(AppInfos)} | group_apps(Info)].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Group into one list element for each application name.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% IN : {AppName,{AppVersion,Path,URL,Text}}
% OUT: {AppName,[{AppVersion,Path,URL,Text} | ...]}

combine_apps(Apps) ->
    combine_apps(Apps,[],[]).

combine_apps([{AppName,{Vsn1,Path1,URL1,Text1}}, 
	      {AppName,{Vsn2,Path2,URL2,Text2}} | Apps], AppAcc, Acc) ->
    combine_apps([{AppName,{Vsn2,Path2,URL2,Text2}} | Apps],
		 [{Vsn1,Path1,URL1,Text1} | AppAcc],
		 Acc);
combine_apps([{AppName,{Vsn1,Path1,URL1,Text1}}, 
	      {NewAppName,{Vsn2,Path2,URL2,Text2}} | Apps], AppAcc, Acc) ->
    App = lists:sort(fun vsncmp/2,[{Vsn1,Path1,URL1,Text1}|AppAcc]),
    combine_apps([{NewAppName,{Vsn2,Path2,URL2,Text2}} | Apps],
		 [],
		 [{AppName,App}|Acc]);
combine_apps([{AppName,{Vsn,Path,URL,Text}}], AppAcc, Acc) ->
    App = lists:sort(fun vsncmp/2,[{Vsn,Path,URL,Text}|AppAcc]),
    [{AppName,App}|Acc].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Open a template and fill in the missing parts
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% IN : {Group,Heading,[{AppName,[{AppVersion,Path,URL,Text} | ...]} | ...]}
% OUT: String that is the HTML code

subst_template(Group, File, Info) ->
    case file:open(File, read) of
	{ok,Stream} ->
	    Res = subst_template_1(Group, Stream, Info),
	    file:close(Stream),
	    Res;
	{error,Reason} ->
	    {error, Reason}
    end.

subst_template_1(Group, Stream, Info) ->
    case file:read(Stream, 100000) of
	{ok, Template} ->
	    Fun = fun(Match, _) -> {subst(Match, Info, Group),Info} end,
	    gsub(Template, "#[A-Za-z0-9]+#", Fun, Info);
	{error, Reason} ->
	    {error, Reason}
    end.

get_version(Info) ->
    case lists:keysearch('runtime', 1, Info) of
	{value, {_,_,Apps}} ->
	    case lists:keysearch("erts", 1, Apps) of
		{value, {_,[{Vers,_,_,_} | _]}} ->
		    Vers;
		_ ->
		    ""
	    end;
	_ ->
	    ""
    end.
		    
subst("#release#", _Info, _Group) ->
    get(otp_release);
subst("#version#", Info, _Group) ->
    get_version(Info);
subst("#copyright#", _Info, _Group) ->
    "copyright  Copyright &copy; 1991-2004";
subst("#groups#", Info, _Group) ->
    [
     "<table border=0 width=\"90%\" cellspacing=3 cellpadding=5>\n",
     subst_groups(Info),
     "</table>\n"
    ];
subst("#applinks#", Info, Group) ->
    subst_applinks(Info, Group);
subst(KeyWord, Info, _Group) ->
    case search_appname(KeyWord -- "##", Info) of
	{ok,URL} ->
	    URL;
	_ ->
	    warning("Can't substitute keyword ~s~n",[KeyWord]),
	    ""
    end.

search_appname(App, [{_Group,_,Apps} | Groups]) ->
    case lists:keysearch(App, 1, Apps) of
	{value, {_,[{_Vers,_Path,URL,_Text} | _]}} ->
	    {ok,lists:sublist(URL, length(URL) - length("/index.html"))}; 
	_ ->
	    search_appname(App, Groups)
    end;
search_appname(_App, []) ->
    {error,noapp}.

subst_applinks(Info, Group) ->
    subst_applinks_1(group_order(), Info, Group).

subst_applinks_1([G|Gs], Info0, Group) ->
    case lists:keysearch(G, 1, Info0) of
	{value,{G,Heading,Apps}} ->
	    Info = lists:keydelete(G, 1, Info0),
	    ["\n<li>",Heading,"\n<ul>\n",
	     html_applinks(Apps),"\n</ul></li>\n"|
	     subst_applinks_1(Gs, Info, Group)];
	false ->
	    warning("No applications in group ~w\n", [G]),
	    subst_applinks_1(Gs, Info0, Group)
    end;
subst_applinks_1([], [], _) -> [];
subst_applinks_1([], Info, _) ->
    error("Info left:\n", [Info]),
    [].

html_applinks([{Name,[{_,_,URL,_}|_]}|AppNames]) ->
    ["<li><a href=\"",URL,"\">",Name,
     "</a></li>\n"|html_applinks(AppNames)];
html_applinks([]) -> [].


% Info: [{Group,Heading,[{AppName,[{AppVersion,Path,URL,Text} | ..]} | ..]} ..]

subst_groups(Info0) ->
    {Html1,Info1} = subst_known_groups(group_order(), Info0, ""),
    {Html2,Info}  = subst_unknown_groups(Info1, Html1, []),
    Fun = fun({_Group,_GText,Applist}, Acc) -> Applist ++ Acc end,
    case lists:foldl(Fun, [], Info) of
	[] ->
	    Html2;
	Apps ->
	    [Html2,group_table("Misc Applications",Apps)]
    end.
    

subst_known_groups([], Info, Text) ->
    {Text,Info};
subst_known_groups([Group | Groups], Info0, Text0) ->    
    case lists:keysearch(Group, 1, Info0) of
	{value,{_,Heading,Apps}} ->
	    Text = group_table(Heading,Apps),
	    Info = lists:keydelete(Group, 1, Info0),
	    subst_known_groups(Groups, Info, Text0 ++ Text);
	false ->
	    warning("No applications in group ~w~n",[Group]),
	    subst_known_groups(Groups, Info0, Text0)
    end.


subst_unknown_groups([], Text0, Left) ->
    {Text0,Left};
subst_unknown_groups([{Group,"",Apps} | Groups], Text0, Left) ->
    warning("No text describes ~w",[Group]),
    subst_unknown_groups(Groups, Text0, [{Group,"",Apps} | Left]);
subst_unknown_groups([{_Group,Heading,Apps} | Groups], Text0, Left) ->    
    Text = group_table(Heading,Apps),
    subst_unknown_groups(Groups, Text0 ++ Text, Left).


group_table(Heading,Apps) ->
    [
     "  <tr>\n",
     "    <td colspan=2 class=header>\n",
     "      <font size=\"+1\"><b>",Heading,"</b></font>\n",
     "    </td>\n",
     "  </tr>\n",
     subst_apps(Apps),
     "  <tr>\n",
     "    <td colspan=2><font size=1>&nbsp;</font></td>\n",
     "  </tr>\n"
    ].

% Count and split the applications in half to get the right sort
% order in the table.

subst_apps([{App,VersionInfo} | Apps]) ->
    [subst_app(App, VersionInfo) | subst_apps(Apps)];
subst_apps([]) ->
    [].


subst_app(App, [{VSN,_Path,Link,Text}]) ->
    [
     "  <tr class=app>\n",
     "    <td align=left valign=top>\n",
     "      <table border=0 width=\"100%\" cellspacing=0 cellpadding=0>\n",
     "        <tr class=app>\n",
     "          <td align=left valign=top>\n",
     "            <a href=\"",Link,"\" target=\"_top\">",uc(App),"</a>\n",
     "            <a href=\"",Link,"\" target=\"_top\">",VSN,"</a>\n",
     "          </td>\n",
     "        </tr>\n",
     "      </table>\n"
     "    </td>\n",
     "    <td align=left valign=top>\n",
     Text,"\n",
     "    </td>\n",
     "  </tr>\n"
    ];
subst_app(App, [{VSN,_Path,Link,Text} | VerInfos]) ->
    [
     "  <tr class=app>\n",
     "    <td align=left valign=top>\n",
     "      <table border=0 width=\"100%\" cellspacing=0 cellpadding=0>\n",
     "        <tr class=app>\n",
     "          <td align=left valign=top>\n",
     "            <a href=\"",Link,"\" target=\"_top\">",uc(App),
     "</a>&nbsp;&nbsp;<br>\n",
     "            <a href=\"",Link,"\" target=\"_top\">",VSN,"</a>\n",
     "          </td>\n",
     "          <td align=right valign=top width=50>\n",
     "            <table border=0 width=40 cellspacing=0 cellpadding=0>\n",
     "              <tr class=app>\n",
     "                <td align=left valign=top class=appnums>\n",
     subst_vsn(VerInfos),
     "                </td>\n",
     "              </tr>\n",
     "            </table>\n"
     "          </td>\n",
     "        </tr>\n",
     "      </table>\n"
     "    </td>\n",
     "    <td align=left valign=top>\n",
     Text,"\n",
     "    </td>\n",
     "  </tr>\n"
    ].


subst_vsn([{VSN,_Path,Link,_Text} | VSNs]) ->
    [
     "      <font size=\"2\"><a class=anum href=\"",Link,"\" target=\"_top\">",
     VSN,
     "</a></font><br>\n",
     subst_vsn(VSNs)
    ];
subst_vsn([]) ->
    "".
    

% Yes, this is very inefficient an is done for every comarision
% in the sort but it doesn't matter in this case.

vsncmp({Vsn1,_,_,_}, {Vsn2,_,_,_}) ->
    L1 = [list_to_integer(N1) || N1 <- string:tokens(Vsn1, ".")],
    L2 = [list_to_integer(N2) || N2 <- string:tokens(Vsn2, ".")],
    L1 > L2.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%  GENERIC FUNCTIONS, NOT SPECIFIC FOR GENERATING INDEX.HTML
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Read the "info" file into a list of Key/Value pairs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

read_info(File) ->
    case file:open(File, read) of
	{ok,Stream} ->
	    Res =
		case file:read(Stream,10000) of
		    {ok, Text} ->
			Lines = string:tokens(Text, "\n\r"),
			KeyValues0 = lines_to_key_value(Lines),
			combine_key_value(KeyValues0);
		    {error, Reason} ->
			{error, Reason}
		end,
	    file:close(Stream),
	    Res;
	{error,Reason} ->
	    {error,Reason}
    end.

combine_key_value([{Key,Value1},{Key,Value2} | KeyValues]) ->
    combine_key_value([{Key,Value1 ++ "\n" ++ Value2} | KeyValues]);
combine_key_value([KeyValue | KeyValues]) ->
    [KeyValue | combine_key_value(KeyValues)];
combine_key_value([]) ->
    [].

lines_to_key_value([]) ->
    [];
lines_to_key_value([Line | Lines]) ->
    case regexp:first_match(Line, "^[a-zA-Z_\\-]+:") of
	nomatch ->
	    case regexp:first_match(Line, "[\041-\377]") of
		nomatch ->
		    lines_to_key_value(Lines);
		_ ->
		    warning("skipping line \"~s\"",[Line]),
		    lines_to_key_value(Lines)
	    end;
	{match, _, Length} ->
	    Value0 = lists:sublist(Line, Length+1, length(Line) - Length),
	    {ok, Value1, _} = regexp:sub(Value0, "^[ \t]*", ""),
	    {ok, Value,  _} = regexp:sub(Value1, "[ \t]*$", ""),
            Key = lists:sublist(Line, Length-1),
	    [{Key,Value} | lines_to_key_value(Lines)]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Extensions to the 'regexp' module.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

is_match(Ex, Re) ->
    case regexp:first_match(Ex, Re) of
	{match, _, _} ->
	    true;
	nomatch ->
	    false
    end.

%% -type gsub(String, RegExp, Fun, Acc) -> subres().
%%  Substitute every match of the regular expression RegExp with the
%%  string returned from the function Fun(Match, Acc). Accept pre-parsed
%%  regular expressions. Acc is an argument to the Fun. The Fun should return
%%  a tuple {Replacement, NewAcc}.
 
gsub(String, RegExp, Fun, Acc) when list(RegExp) ->
    case regexp:parse(RegExp) of
        {ok,RE} -> gsub(String, RE, Fun, Acc);
	{error,E} -> {error,E}
    end;
gsub(String, RE, Fun, Acc) ->
    {match,Ss} = regexp:matches(String, RE),
    {NewString, NewAcc} = sub_repl(Ss, Fun, Acc, String, 1),
    {ok,NewString,NewAcc}.


% New code that uses fun for finding the replacement. Also uses accumulator
% to pass argument between the calls to the fun.
sub_repl([{St,L}|Ss], Fun, Acc0, S, Pos) ->
        Match = string:substr(S, St, L),
        {Rep, Acc} = Fun(Match, Acc0),
        {Rs, NewAcc} = sub_repl(Ss, Fun, Acc, S, St+L),
        {string:substr(S, Pos, St-Pos) ++ Rep ++ Rs, NewAcc};
sub_repl([], _Fun, Acc, S, Pos) -> {string:substr(S, Pos), Acc}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Error and warnings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

error(Format, Args) ->
    io:format("ERROR: " ++ Format ++ "\n", Args),
    exit(1).

warning(Format, Args) ->
    case get(silent) of
	true -> ok;
	_ -> io:format("WARNING: " ++ Format ++ "\n", Args)
    end.

report(Format, Args) ->
    case get(silent) of
	true -> ok;
	_ -> io:format(Format ++ "\n", Args)
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Extensions to the 'string' module.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

uc(String) ->
    lists:reverse(uc(String, [])).

uc([], Acc) ->
    Acc;
uc([H | T], Acc) when is_integer(H), [97] =< H, H =< $z ->
    uc(T, [H - 32 | Acc]);
uc([H | T], Acc) ->
    uc(T, [H | Acc]).