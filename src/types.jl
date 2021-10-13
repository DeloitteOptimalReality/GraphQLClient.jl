"""
    Alias

Contains an alias for a GraphQL field or query. `Alias`es can be used in
the `output_fields` keyword argument as well as directly instead of query,
mutation and subscription names.

# Examples

Using an `Alias` instead of the query name:

```jldoctest alias_label; setup=:(using GraphQLClient)
julia> client = Client("https://countries.trevorblades.com");

julia> alias = Alias("country_alias", "country");

julia> query(client, alias, query_args=Dict("code"=>"BR"), output_fields=["name"]).data
Dict{String, Any} with 1 entry:
  "country_alias" => Dict{String, Any}("name"=>"Brazil")

```

Using an `Alias` in `output_fields`:

```jldoctest alias_label; setup=:(using GraphQLClient)
julia> field_alias = Alias("country_name_alias", "name");

julia> query(client, "country", query_args=Dict("code"=>"BR"), output_fields=[field_alias]).data
Dict{String, Any} with 1 entry:
  "country" => Dict{String, Any}("country_name_alias"=>"Brazil")
```
"""
struct Alias
    alias::String
    name::String
end
Base.show(io::IO, ::MIME"text/plain", a::Alias) = print(io, "Alias: ", a.alias, ":", a.name)
Base.show(io::IOBuffer, a::Alias) = print(io, a.alias * ":" * a.name) # for string interpolation

"""
    get_name(name::AbstractString)
    get_name(alias::Alias)

To be used when the GraphQL field name is required, which will
either be inputted as a string or in the `name` field of an
`Alias`.
"""
get_name(name::AbstractString) = name
get_name(alias::Alias) = alias.name

"""
    GQLEnum

When using `direct_write=true` in queries and mutations, ENUMs must be wrapped
in this type to ensure that they are not wrapped in quotes in the query string.

See [`directly_write_query_args`](@ref) for more information and examples.
"""
struct GQLEnum
    value::String
end