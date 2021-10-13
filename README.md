# GraphQLClient.jl

*A Julia GraphQL client for seamless integration with a server*

This package is intended to make connecting to and communicating with GraphQL servers easy whilst integrating easily with the wider Julia ecosystem.

## Key Features

- Querying, mutating and subscribing without manual writing of query strings
- Deserializing responses directly using StructTypes
- Type stable querying
- Construction of Julia types from GraphQL objects
- Using introspected schema for various purposes, such as getting all possible output fields from a query

## Installation

The package can be installed with Julia's package manager,
either by using the Pkg REPL mode (press `]` to enter):
```
pkg> add GraphQLClient
```
or by using Pkg functions
```julia
julia> using Pkg; Pkg.add("GraphQLClient")
```

## Basic Usage

### Connecting to a server

A client can be instantiated by using the `Client` type

```julia-repl
julia> using GraphQLClient

julia> client = Client("https://countries.trevorblades.com")
GraphQLClient Client
       endpoint: https://countries.trevorblades.com
    ws_endpoint: wss://countries.trevorblades.com
```

This will, by default, use a query to introspect the server schema, populating
several fields of the `Client` object which can then be used to help with
querying.

### Querying

We can query it without having to type a full GraphQL query by hand

```julia-repl
julia> response = query(client, "countries")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
    countries: Vector{Any}
```

We can add arguments and request fields in the response

```julia-repl
julia> query_args = Dict("filter" => Dict("code" => Dict("eq" => "AU"))); # Filter for countries with code equal to AU

julia> response = query(client, "countries"; query_args=query_args, output_fields="name");

julia> response.data["countries"]
1-element Vector{Any}:
 Dict{String, Any}("name" => "Australia")
```

We can define a `StructType` to deserialise the result into

```julia-repl
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