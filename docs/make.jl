using Documenter
using GraphQLClient
using StructTypes
using JSON3

DocMeta.setdocmeta!(GraphQLClient, :DocTestSetup, :(using GraphQLClient); recursive=true)

makedocs(
    modules=[GraphQLClient],
    authors="Malcolm Miller",
    sitename="GraphQLClient.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://deloittedigitalapac.github.io/GraphQLClient.jl/stable",
    ),
    strict=:doctest,
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "client.md",
            "operations.md",
            "struct_types_usage.md",
            "type_introspection.md",
            "low_level_execution.md",
            "limitations.md",
        ],
        "Library" => [
            "public.md",
            "private.md",
        ],
        "Contributing" => "contributing.md",
    ],
)

deploydocs(;
    repo="github.com/DeloitteDigitalAPAC/GraphQLClient.jl",
    push_preview=true,
    devbranch="main",
)