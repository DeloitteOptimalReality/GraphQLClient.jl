# GraphQLClient.jl

*A Julia GraphQL client for seamless integration with a server*

This package is intended to make connecting to and communicating with GraphQL servers easy whilst integrating easily with the wider Julia ecosystem.

What is GraphQL? It is a *"query language for APIs and a runtime for fulfilling those queries with your existing data"*. For further information, see [https://graphql.org](https://graphql.org).

## Key Features of GraphQLClient

- **Querying**, **mutating** and **subscribing** without manual writing of query strings
- Deserializing responses directly using **StructTypes**
- Type stable querying
- **Construction of Julia types** from GraphQL objects
- Using **introspection** to help with querying

!!! info "There is plenty more to come"
    GraphQL is a featureful language, and we are working to bring in new features to meet all of the specification.
    Please see [the issues](https://github.com/DeloitteDigitalAPAC/GraphQLClient.jl/issues), let us know what you'd
    like us to be working on and contribute!

## Basic Usage

### Connecting to a server

A client can be instantiated by using the `Client` type

```jldoctest client_intro
julia> using GraphQLClient

julia> client = Client("https://countries.trevorblades.com")
GraphQLClient Client
       endpoint: https://countries.trevorblades.com
    ws_endpoint: wss://countries.trevorblades.com
```

This will, by default, use a query to introspect the server schema, populating
several fields of the `Client` object which can then be used to help with
querying.

We can set a global client to be used by [`query`](@ref), [`mutate`](@ref), [`open_subscription`](@ref) and [`GraphQLClient.execute`](@ref).

```jldoctest client_intro
julia> global_graphql_client(Client("https://countries.trevorblades.com"))
GraphQLClient Client
       endpoint: https://countries.trevorblades.com
    ws_endpoint: wss://countries.trevorblades.com
```

And access the global client with the same function

```jldoctest client_intro
julia> global_graphql_client()
GraphQLClient Client
       endpoint: https://countries.trevorblades.com
    ws_endpoint: wss://countries.trevorblades.com
```
### Querying

```@meta
DocTestSetup = quote
    using GraphQLClient
    client = Client("https://countries.trevorblades.com")
    query_args = Dict("filter" => Dict("code" => Dict("eq" => "AU")))
    query_alias = Alias("country_names", "countries")
end
```

Now we have a `Client` object, we can query it without having to type a full
GraphQL query by hand (note, you should be able to test these queries for yourself,
thanks to [https://github.com/trevorblades/countries](https://github.com/trevorblades/countries)).

```julia-repl
julia> response = query(client, "countries")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
    countries: Vector{Any}

julia> response.data["countries"]
250-element Vector{Any}:
 Dict{String, Any}...
```

In this case, GraphQLClient used the introspected schema to determine what output fields
were available (with some limitations to avoid recursing infinitely). Alternatively, we can
specify what fields we would like to be returned

```julia-repl
julia> response = query(client, "countries", output_fields="name")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country_names: Vector{Any}

julia> response.data["countries"]
250-element Vector{Any}:
 Dict{String, Any}("name" => "Andorra")
 Dict{String, Any}("name" => "United Arab Emirates")
 Dict{String, Any}("name" => "Afghanistan")
 Dict{String, Any}("name" => "Antigua and Barbuda")
⋮
```

We can add arguments to the query

```jldoctest
julia> query_args = Dict("filter" => Dict("code" => Dict("eq" => "AU"))); # Filter for countries with code equal to AU

julia> response = query(client, "countries"; query_args=query_args, output_fields="name");

julia> response.data["countries"]
1-element Vector{Any}:
 Dict{String, Any}("name" => "Australia")
```

We can use an alias to change the name of either a query or a field in our results

```jldoctest
julia> query_alias = Alias("country_names", "countries");

julia> response = query(client, query_alias, query_args=query_args, output_fields="name")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country_names: Vector{Any}

julia> response.data["country_names"]
1-element Vector{Any}:
 Dict{String, Any}("name" => "Australia")
```
We can define a `StructType` to deserialise the result into

```jldoctest
julia> using StructTypes

julia> struct CountryName
           name::String
       end

julia> StructTypes.StructType(::Type{CountryName}) = StructTypes.OrderedStruct()

julia> response = query(client, query_alias, Vector{CountryName}, query_args=query_args, output_fields="name")
GraphQLClient.GQLResponse{Vector{CountryName}}
  data: Dict{String, Union{Nothing, Vector{CountryName}}}
          country_names: Vector{CountryName}

julia> response.data["country_names"][1]
CountryName("Australia")
```

Or we can use introspection to build the type automatically

```julia-repl
julia> Country = GraphQLClient.introspect_object(client, "Country")
┌ Warning: Cannot introspect field country on type State due to recursion of object Country
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:75
┌ Warning: Cannot introspect field countries on type Continent due to recursion of object Country
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:75
GraphQLClient.var"##Country#604"

julia> response = query(client, query_alias, Vector{Country}, query_args=query_args, output_fields="name")
GQLResponse{Vector{GraphQLClient.var"##Country#604"}}
  data: Dict{String, Union{Nothing, Vector{GraphQLClient.var"##Country#604"}}}
          country_names: Vector{GraphQLClient.var"##Country#604"}

julia> response.data["country_names"][1]
Country
  name : Australia
```


```@meta
DocTestSetup = nothing
```

### Mutations

Mutations can be constructed in a similar way, except the arguments are not a keyword argument as typically
a mutation is doing something with an input. For example

```julia-repl
julia> response = mutate(client, "mutation_name", Dict("new_id" => 1))
```

Unlike with `query`, the output fields are not introspected as mutations often do not have a response.

### Subscriptions

The subscriptions syntax is similar, except that we use Julia's `do` notation

```julia
open_subscription(
    client,
    "subscription_name",
    sub_args=("id" => 1),
    output_fields="val"
) do response
    val = response.data["subscription_name"]["val"]
    stop_sub = val == 2
    return stop_sub # If this is true, the subscription ends
end
```

## Use with Microservices Architectures

GraphQL is often used with microservice architectures. Often, you will find that you have multiple microservices that perform the same GraphQL queries. A nice solution to this is to write a new package which wraps GraphQLClient and provides a higher-level interface, and which also handles connection to the server. For example, the `country` query above could be wrapped as follows

```julia
const CLIENT = Ref(Client)

function connect()
    CLIENT[] = Client("url","ws")
end

function get_country(code)
    response = query(
        CLIENT[],
        "country",
        query_args=Dict("code"=>code),
        output_fields="name"
    )
    return response.data["country]
end

```

For more information, see this JuliaCon talk

```@raw html
<center>
<iframe width="560" style="height:315px" src="https://www.youtube.com/embed/KixO3udfcKA?start=1104" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
</center>
```
