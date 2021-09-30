module LDJFranklin

using Franklin: globvar, locvar, pagevar
using FranklinUtils
using LDJ
using Conda
using JSON
using IterTools: chain
using DataStructures: OrderedDict
using Base.Unicode: titlecase
using Memoization
using Dates: year, now
using URIs: URI

using HTTP: get
using URIs: URI
import Base.convert

const BOOKS = []

export hfun_ldj_author, hfun_ldj_publisher, hfun_ldj_place, hfun_ldj_search, hfun_ldj_website,
    hfun_ldj_book, hfun_ldj_crumbs, hfun_ldj_webpage, hfun_ldj_library, hfun_insert_library, ldj_trans


function hfun_ldj_website(k="")
    website(locvar(:website_url),
            locvar(:author), year(now())) |>
                wrap_ldj
end

function hfun_ldj_search(k="")
    search(locvar(:website_url);
           parts=(path="/search", query=(q="{input}",))) |> wrap_ldj
end

function hfun_ldj_place(k="")
    place(;country=locvar(:country), region=locvar(:region))|> wrap_ldj
end

function hfun_ldj_author(k=""; wrap=true)
    author(;name=locvar(:author),
           email=locvar(:email),
           image=locvar(:author_image),
           description=(isdefined( @__MODULE__, :author_bio) ? author_bio() : ""),
           sameAs=[locvar(:github), locvar(:twitter)]) |>
               x -> wrap_ldj(x, wrap)
end

function hfun_ldj_publisher(k=""; wrap=true)
    hfun_ldj_author(k; wrap)
end

@memoize function get_languages()
    languages((lang for (lang, _) in locvar(:languages)))
end

function hfun_ldj_webpage()
    webpage(id=locvar(:fd_full_url),
            title=locvar(:title),
            url=locvar(:fd_full_url),
            mtime=locvar(:fd_mtime_raw),
            selector= ".franklin-content",
            description=locvar(:rss_description),
            keywords=locvar(:tags),
            access_mode=locvar(:accessMode),
            access_sufficient=locvar(:accessModeSufficient),
            access_summary="Visual elements are tentatively described.",
            image=locvar(:images),
            lang=globvar(:lang),
            created=locvar(:fd_ctime),
            props=["availableLanguage" => get_languages(),
                   "author" => hfun_ldj_author(;wrap=false),
                   "publisher" => hfun_ldj_publisher(;wrap=false),
                   "audience" => "cool people",
                   "mentions" => locvar(:mentions)]
                    ) |> wrap_ldj
end

@inline function nostring(str::Union{Nothing, AbstractString})
	isnothing(str) ? "" : str
end

@doc "file path must be relative to the project directory, assumes the published website is under '__site/'"
function ldj_trans(file_path, src_url, trg_url, lang)
    translation(;src_url, trg_url, lang,
                title=nostring(pagevar(file_path, :title)),
                mtime=nostring(pagevar(file_path, :fd_mtime_raw)),
                selector=".franklin-content",
                description=pagevar(file_path, :rss_description),
                keywords=pagevar(file_path, :tags),
                image=pagevar(file_path, :images),
                headline=pagevar(file_path, :title),
                translator_name=globvar(:translator_name),
                translator_url=globvar(:translator_url),
                props=["mentions" => locvar(:mentions)]) |> wrap_ldj
end

@doc "create breadcrumbs schema for posts, requires a function to generate breadcrumbs"
function hfun_ldj_crumbs(args)
    func = getfield(Main, Symbol(args[1]))
    func() |> breadcrumbs |> wrap_ldj
end

@doc "create a book structure"
function hfun_ldj_book(args...; kwargs...)
	book(args...; kwargs...)
end

@inline function get_date()
	let d = fr.locvar(:date)
        if d === EMPTY_DATE
            DateTime(year(now), 1, 1)
        else
            DateTime(d, DATE_FORMAT)
        end
    end
end

# function lx_book(name, author, url, sameas="", _)
function lx_book(com, _)
    args = lxproc(com)
    name, author, url, tags, comments  = strip.(args) |>
        x -> split(x, r"; ?")
    # name, author, url = split(args, "\" \"")
    push!(BOOKS, (name=name, author=author, url=url, tags=tags, comments=comments, sameas=""))
    "[" * name * "](" * url * ")"
end


convert(::Type{Symbol}, s::String) = Symbol(s)
@doc "Fetch books list from a calibre content server"
function calibredb_books_server(server="http://localhost:8099";
                                query=Dict("library_id" => "",
                                           "num" => typemax(Int32)))
    get(server * "/interface-data/books-init";  query) |>
        res -> String(res.body) |>
        JSON.parse |>
        r -> r["metadata"]
end

@doc "generate LDJ data from a list of books"
function hfun_ldj_library()
    empty!(BOOKS)
    if locvar(:fd_rpath) === "reads/index.md"
        # add calibre books to library
        calibre_books = calibredb_books_server(locvar(:calibre_server);
                                               query=Dict("library_id" => locvar(:calibre_library),
                                                          "num" => 10000))
        for (_, book) in calibre_books
            push!(BOOKS, (name=book["title"], author=book["author_sort"],
                          url="", tags=book["tags"], sameas=""))
        end
        bookfeed(BOOKS) |> wrap_ldj
    else
        ""
    end
end

@doc "create html lists by grouping books based on their tags"
function hfun_insert_library(groups=[])
    c = IOBuffer()
    if isempty(groups)
        lists = Dict(["all" => Vector{String}()])
        setgroup! = book -> begin
            "read" ∈ book.tags && push!(lists["all"], book.name)
        end
    else
        lists = OrderedDict([g => [] for g in groups])
        setgroup! = book -> begin
            for g in groups
                if "read" ∈ book.tags && g ∈ book.tags
                    push!(lists[g], book)
                end
            end
        end
    end
    for book in BOOKS
        setgroup!(book)
    end
    write(c, "<div id=\"library\">")
    for (group_name, group_list) in lists
        if length(group_list) > 0
            write(c, "<h2>$(titlecase(group_name))</h2>")
            write(c, "<ul class=\"$(group_name)-books\">")
            for book in group_list
                write(c, "<li class=\"book-entry\">")
                println(c, book.name, "<div class=\"book-author\"> - ", book.author,"<div>")
                write(c, "</li>")
            end
            write(c, "</ul>")
        end
    end
    write(c, "</div>")
    ret = String(take!(c))
    close(c)
    ret
end

# function calibre_books_cli(library="http://localhost:8099", fields="authors,isbn,publisher,tags,title")
#     @assert !isnothing(Sys.which("calibredb"))
#     # since calibre is a python package, and is installed system-wide,
#     # make sure we are not using julia python env
#     let pythonpath = ENV["PYTHONPATH"]
#         delete!(ENV, "PYTHONPATH")
#         l = read(`calibredb --with-library $library list --for-machine -f $fields`, String)
#         ENV["PYTHONPATH"] = pythonpath
#         l |> JSON.parse
#     end
# end

end
