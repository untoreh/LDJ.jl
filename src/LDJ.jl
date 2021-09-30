module LDJ

# include("Content.jl")
# using .Content

using JSON
using Dates: Date, now, year, DateTime
using URIs: URI

const DATE_FORMAT = "mm/dd/yyyy"
const EMPTY_DATE = Date("0001-01-01")

export wrap_ldj, website, search, place, author, publisher, languages, webpage, translation, breadcrumbs, Book, book,
    bookfeed, event_status, online_event, license, orgschema, coverage, place_schema, dataset, faqschema, image,
    howtoitem, howto, logo, ratingprop, movie, itemslist, review, searchaction, speakable, pubevents, video

macro unimp(fname)
    quote
        function $(esc(fname))()
            throw("unimplemented")
        end
    end
end

@doc "Set properties (a (k, v) vector) to data (an dict)."
macro setprops!()
    quote
        pr = $(esc(:props))
        data = $(esc(:data))
        if !isempty(pr)
            for (p, v) in pr
	            data[p] = v
            end
        end
        data
    end
end

function setargs!(data, args...)
    for (k, v) in args
        if !isnothing(v) && !isempty(v)
            data[k] = v
        end
    end
    data
end

## LD+JSON functions
@inline function schema()
    "@context" => "https://schema.org"
end

@inline function wrap_ldj(data::IdDict, wrap=true)
    wrap && return "<script type=\"application/ld+json\">$(JSON.json(data))</script>"
    data
end

@doc "https://schema.org/WebSite"
function website(url, author, year)
    IdDict(
        "@context" => "https://schema.org/",
        "@type" => "WebSite",
        "@id" => url,
        "url" => url,
        "copyrightHolder" => author,
        "copyrightYear" => year,
    )
end

@doc "https://schema.org/SearchAction
`parts` are url parts (scheme, host, port, path, query, fragment) to merge with the url string. It has
to contain a parameter which value is `{input}`."
function search(url::AbstractString; parts=NamedTuple(), maxlength=100)
    @assert "{input}" in values(parts.query)
    uri = URI(url)
    IdDict(
        "potentialAction" => IdDict(
            "@type" => "SearchAction",
            "target" => URI(uri; parts...),
            "query" => "required",
            "query-input" => "required maxlength=$(maxlength) name=input",
            "actionStatus" => "https://schema.org/PotentialActionStatus",
        ),
    )
end

@doc "https://schema.org/Place"
function place(place="homeLocation"; country="", region="", props=[])
    data = IdDict(
        place => IdDict(
            "@type" => "https://schema.org/Place",
            "addressCountry" => locvar(:country),
            "addressRegion" => locvar(:region),
        ),
    )
    if !isempty(country)
        data["addressCountry"] = country
    end
    if !isempty(region)
        data["addressRegion"] = region
    end
    @setprops!
    data
end

@doc "Convenience function for authors.
Requires at least `name` and `email`."
function author(entity="Person"; name, email="", description="", image="", sameAs="")
    data = IdDict{String, Any}(
        "@type" => "https://schema.org/$(entity)",
        "name" => name,
        "email" => email
    )
    setargs!(data, "image" => image, "description" => description, "sameAs" => sameAs)
end

@doc "Currently same as `author`"
function publisher(args...; kwargs...)
	author(args; kwargs...)
end

@doc "Create a list of Language types"
function languages(langs)
    [IdDict("@type" => "Language", "name" => l) for l in langs]
end

@doc "convert VAL to TO if equal to WHAT, otherwise return VAL."
@inline function coerce(val; what=nothing, to="")
    val === what && return to
    val
end
@doc "convert VAL to TO if FN returns true, otherwise return VAL."
@inline function coercf(val; fn=isempty, to="")
    fn(val) && return to
    val
end

function webpage(;id, title, url, mtime, selector, description, keywords, name="", headline="",
                 image="", entity="Article", status="Published",lang="english", mentions=[],
                 access_mode=["textual", "visual"], access_sufficient=[], access_summary="",
                 created="", published="", props=[])
    d_mtime = coerce(mtime)
	data = IdDict(
        "@context" => "https://schema.org",
        "@type" => "https://schema.org/WebPage",
        "@id" => id,
        "url" => url,
        "lastReviewed" => coerce(mtime),
        "mainEntityOfPage" => IdDict(
            "@type" => entity,
            "@id" => url
        ),
        "mainContentOfPage" =>
            IdDict("@type" => "WebPageElement", "cssSelector" => selector),
        "accessMode" => access_mode,
        "accessModeSufficient" => IdDict(
            "@type" => "itemList",
            "itemListElement" => coercf(access_sufficient; to=access_mode),
        ),
        "creativeWorkStatus" => status,
        "dateModified" => d_mtime,
        "dateCreated" => coerce(created; to=d_mtime),
        "datePublished" => coerce(published; to=d_mtime),
        "name" => coerce(name; to=title),
        "description" => coerce(description),
        "keywords" => coerce(keywords; to=[])
    )
    setargs!(data, "inLanguage" => lang, "accessibilitySummary" => access_summary,
             "headline" => headline, "image" => image,
             "mentions" => mentions)
    @setprops!
end

@doc "file path must be relative to the project directory, assumes the published website is under '__site/'"
function translation(;src_url, trg_url, lang, title, mtime, selector, description, keywords,
                     image="", headline="", props=[],
                     translator_name="Google", translator_url="https://translate.google.com/")

    data = webpage(;id=trg_url, title, url=trg_url, mtime, selector, description,
                   keywords, image, headline, lang, props)
    data["translator" ] = IdDict("@type" => "https://schema.org/Organization",
                               "name" => translator_name,
                               "url" => translator_url)
    data["translationOfWork"] = IdDict("@id" => src_url)
    data
end

@doc """Take a list of (name, link) tuples and returns a breadcrumb
definition with hierarchy from top to bottom"""
function breadcrumbs(items)
    IdDict(
        "@type" => "BreadcrumbList",
        "itemListElement" => [
            IdDict(
                "@type" => "ListItem",
                "position" => n,
                "name" => name,
                "item" => item
            ) for (n, (name, item)) in enumerate(items)
                ]
    )
end

Book = @NamedTuple begin
	name::String
    author::String
    url::String
    sameas::String
    tags::Vector{String}
    comments::String
end

function book(name, author, url, tags, sameas)
    book = IdDict(                schema(),
                                  "@type" => "Book",
                                  "@id" => url,
                                  "url" => url,
                                  "urlTemplate" => url,
                                  "name" => name,
                                  "author" => IdDict(
                                      "@type" => "Person",
                                      "name" => author
                                  ),
                                  "sameAs" => sameas )
    !isempty(url) && begin
	    book["url"] = url
        book["@id"] = url
        book["urlTemplate"] = url
    end
    book
end

function bookfeed(books; props=[])
    data = IdDict(
        schema(),
        "@type" => "DataFeed",
        "dataFeedElement" => [book(b...) for b in books],)
    @setprops!
end

function event_status(status)
    let schema = "https://schema.org/Event"
        if status === "cancelled"
            schema * "Cancelled"
        elseif status === "moved"
            schema * "MovedOnline"
        elseif status === "postponed"
            schema * "Postponed"
        elseif status === "rescheduled"
            schema * "Rescheduled"
        else
            schema * "Scheduled"
        end
    end
end

function online_event(;name, start_date, end_date, url, image=[], desc="",
                      status="EventScheduled", prev_date="",
                      perf=IdDict(), org=IdDict(), offers=IdDict())
	IdDict(
        schema(),
        "@type" => "Event",
        "name" => name,
        "startDate" => start_date,
        "endDate" => end_date,
        "previousStartDate" => prev_date,
        "eventStatus" => event_status(status),
        "eventAttendanceMode" => "https://schema.org/OnlineEventAttendanceMode",
        "location" => IdDict(
            "@type" => "VirtualLocation",
            "url" => url
        ),
        "image" => image,
        "description" => desc,
        "offers" => offers,
        "performer" => perf,
        "organizer" => org)
end

function license(name="")
	if name === "mit"
        "https://en.wikipedia.org/wiki/MIT_License"
    elseif name === "apache"
        "https://en.wikipedia.org/wiki/Apache_License"
    elseif name === "gpl" || name === "gplv3"
        "https://www.gnu.org/licenses/gpl-3.0.html"
    elseif name === "gplv2"
        "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
    elseif name === "sol"
        "https://wiki.p2pfoundation.net/Copysol_License"
    elseif name === "crypto" || name === "cal"
        "https://raw.githubusercontent.com/holochain/cryptographic-autonomy-license/master/README.md"
    else
        "https://creativecommons.org/publicdomain/zero/1.0/"
    end
end

function orgschema(name, url, contact="", tel="", email="", sameas="")
    IdDict(
        "@type" => "Organization",
        "name" => name,
        "url" => url,
        "sameAs" => sameas,
        "contactPoint" => IdDict(
            "@type" => "ContactPoint",
            "contactType" => contact,
            "telephone" => tel,
            "email" => email,))
end

function coverage(start_date, end_date="")
	start_date * "/" * (isempty(end_date) ? ".." : end_date)
end

function place_schema(coords="")
    IdDict(
        "@type" => "Place",
        "geo" => IdDict(
            "@type" => "GeoShape",
            "box" => coords
        )
    )
end

@doc "dist is a tuple of (format, url) for content format and download link"
function dataset(;name, url, desc="", sameas="", id="",
                 keywords=[], parts=[], license="", access=true,
                 creator=IdDict(), funder=IdDict(), catalog="", dist=[],
                 start_date="", end_date="", coords="")
    IdDict(
        schema(),
        "@type" => "Dataset",
        "name" => name,
        "url" => url,
        "description" => desc,
        "sameAs" => sameas,
        "identifier" => isempty(id) ? url : id,
        "keywords" => keywords,
        "hasPart" => parts,
        "license" => license,
        "isAccessibleForFree" => access,
        "creator" => creator,
        "funder" => funder,
        "includedInDataCatalog" => IdDict(
            "@type" => "DataCatalog",
            "name" => catalog
        ),
        "distribution" => [
            IdDict(
                "@type" => "DataDownload",
                "encodingFormat" => f,
                "contentUrl" => d
            ) for (f, d) in dist
                ],
        "temporalCoverage" => isempty(start_date) ? start_date : coverage(start_date, end_date),
        "spatialCoverage" => place_schema(coords)
    )
end


function faqschema(faqs)
    IdDict(
        schema(),
        "@type" => "FAQPage",
        "mainEntity" => [
            IdDict(
                "@type" => "Question",
                "name" => question,
                "acceptedAnswer" => IdDict(
                    "@type" => "Answer",
                    "text" => answer
                )
            ) for (question, answer) in faqs])
end

@doc "estimatedCost, MonetaryAmount (monetary) or Text"
function cost(type; currency="USD", value="0")
    if type === "monetary"
	    IdDict(
            "@type" => "MonetaryAmount",
            "currency" => currency,
            "value" => value
        )
    else
        type
    end
end

function image(url; width="", height="", license=(license="", acquire=""))
	IdDict(
        schema(),
        "@type" => "ImageObject",
        "url" => url,
        "width" => width,
        "height" => height,
        "license" => license.license,
        "acquireLicensePage" => license.acquire)
end

@doc "create an HowToSupply, HowToTool or HowToStep"
function howtoitem(name, type="supply"; props=[])
    if type === "supply"
        tp = "HowToSupply"
    elseif type === "item"
        tp = "HowToItem"
    elseif type === "direction"
        tp = "HowToDirection"
    elseif type === "tip"
        tp = "HowToTip"
    else
        tp = "HowToStep"
    end
    data = IdDict(
        "@type" => tp,
        "name" => name
    )
    @setprops!
end

function howto(;name, desc="", image=IdDict(),
               cost=(currency="USD", value=0), supply=[],
               tool=[], step=[], totaltime="")
	IdDict(
        schema(),
        "@type" => "HowTo",
        "name" => name,
        "description" => desc,
        "image" => image,
        "estimatedCost" => cost("monetary"; cost...),
        "supply" => supply,
        "tool" => tool,
        "step" => step,
        # https://en.wikipedia.org/wiki/ISO_8601#Durations
        "totalTime" => "")
end

function logo(;type="Organization", url, logo, props=[])
    data = IdDict(
        schema(),
        "@type" => type,
        "url" => url,
        "logo" => logo
    )
    @setprops!
end

function ratingprop(value, best, count)
    "aggregateRating" => IdDict(
        "@type" => "AggregateRating",
        "ratingValue" => value,
        "bestRating" => best,
        "ratingCount" => count)
end

function movie(;url, name, image="", created="", director="", rating="", review_author="", review="", props=[])
    data = IdDict(
        "@type" => "Movie",
        "url" => url,
        "name" => name,
        "image" => image,
        "dateCreated" => created,
        "director" => IdDict(
            "@type" => "Person",
            "name" => director,),
        "review" => IdDict(
            "@type" => "Review",
            "reviewRating" => IdDict(
                "@type" => "Rating",
                "ratingValue" => rating,),
            "author" => IdDict(
                "type" => "Person",
                "name" => review_author
            ),
            "reviewBody" => review,))
    @setprops!
end

function itemslist(items)
    IdDict(
        schema(),
        "@type" => "ItemList",
        "itemListElement" => items
    )
end

function review(;name, rating="", author="", review="", org=[],
                item_props=[], props=[])
    data = IdDict(
        schema(),
        "@type" => "Review",
        "itemReviewed" => IdDict(p => v for (p, v) in item_props) ,
        "reviewRating" => IdDict(
            "@type" => "Rating",
            "ratingvalue" =>  rating,
        ),
        "name" => name,
        "author" => IdDict(
            "@type" => "Person",
            "name" => author
        ),
        "reviewBody" => review,
        "publisher" => orgschema(org...)
    )
    @setprops!
end

function searchaction(;url, template, query, props=[])
    data = IdDict(
        schema(),
        "@type" => "WebSite",
        "url" => url,
        "potentialAction" => IdDict(
            "@type" => "SearchAction",
            "target" => IdDict(
                "@type" => "EntryPoint",
                "urlTemplate" => template,),
            "query-input" => "required " * query))
    @setprops!
end

function speakable(;name, url, css::AbstractVector)
    IdDict(
        schema(),
        "@type" => "WebPage",
        "name" => name,
        "speakable" => IdDict(
            "@type" => "SpeakableSpecification",
            "cssSelector" => css
        ),
        "url" => url
    )
end

function pubevents(events)
    [IdDict(
        "@type" => "BroadcastEvent",
        "isLiveBroadcast" => true,
        "startDate" => start_date,
        "endDate" => end_date) for (start_date, end_date) in events]
end

function video(;name, url, desc="", duration="", embed="",
               expire="", regions="", views, thumbnail="", date="", pubevents=[])
    IdDict(
        schema(),
        "@type" => "VideoObject",
        "contentURL" => url,
        "description" => desc,
        "duration" => duration,
        "embedURL" => embed,
        "expires" => expire,
        "regionsAllowed" => regions,
        "interactionStatistic" => IdDict(
            "@type" => "InteractionCounter",
            "interactionType" => IdDict("@type" => "WatchAction"),
            "userInteractionCount" => views,
        ),
        "name" => name,
        "thumbnailUrl" => thumbnail,
        "uploadDate" => date,
        "publication" => pubevents
    )
end

@unimp jobtraining

@unimp jobposting

@unimp business

@unimp factcheck

@unimp mathsolver

@unimp practiceproblems

@unimp product

@unimp qapage

@unimp recipe

@unimp softwareapp

@unimp subscription

include("LDJFranklin.jl")

end
