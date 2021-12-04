# GraphQLClient.jl

*A Julia GraphQL client for seamless integration with a server*

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://deloittedigitalapac.github.io/GraphQLClient.jl/stable)
[![Stable](https://img.shields.io/badge/docs-dev-blue.svg)](https://deloittedigitalapac.github.io/GraphQLClient.jl/dev)
[![Build Status](https://github.com/DeloitteDigitalAPAC/GraphQLClient.jl/workflows/CI/badge.svg?branch=main)](https://github.com/DeloitteDigitalAPAC/GraphQLClient.jl/actions?query=workflow%3ACI+branch%3Amain)
[![Codecov](https://codecov.io/gh/DeloitteDigitalAPAC/GraphQLClient.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DeloitteDigitalAPAC/GraphQLClient.jl)
[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor's%20Guide-blueviolet)](https://github.com/SciML/ColPrac)

This package is intended to make connecting to and communicating with GraphQL servers easy whilst integrating easily with the wider Julia ecosystem.

## Key Features

- **Querying**, **mutating** and **subscribing** without manual writing of query strings
- Deserializing responses directly using **StructTypes**
- Type stable querying
- **Construction of Julia types** from GraphQL objects
- Using **introspection** to help with querying

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

```julia
using GraphQLClient

client = Client("https://countries.trevorblades.com")
```

This will, by default, use a query to introspect the server schema.

We can also set a global client to be user by queries, mutations, subscriptions and introspection functions.

```julia
global_graphql_client(Client("https://countries.trevorblades.com"))
```

### Querying

We can query a `client` without having to type a full GraphQL query by hand, with the response containing fields obtained by introspection

```julia
response = query(client, "countries")
```

Or we can query the global client

```julia
response = query("countries")
```

We can add arguments and specify fields in the response

```julia
query_args = Dict("filter" => Dict("code" => Dict("eq" => "AU")))
response = query("countries"; query_args=query_args, output_fields="name");
response.data["countries"]
# 1-element Vector{Any}:
#  Dict{String, Any}("name" => "Australia")
```

Or we can query with the query string directly using either a normal `String` or the `gql` [non-standard string literal](https://docs.julialang.org/en/v1/manual/strings/#non-standard-string-literals):

```julia
query_string = gql"""
    query(
      $eq: String
    ){
    countries(
        filter:{
            code:{
                eq:$eq
            }
        }
    ){
        name
    }
}
"""

variables = Dict("eq" => "AU")

response = GraphQLClient.execute(query_string, variables=variables)
```


We can define a `StructType` to deserialise the result into

```julia
using StructTypes

struct CountryName
    name::String
end
StructTypes.StructType(::Type{CountryName}) = StructTypes.OrderedStruct()

response = query("countries", Vector{CountryName}, query_args=query_args, output_fields="name")

response.data["countries"][1]
# CountryName("Australia")
```

Or we can use introspection to build the type automatically

```julia
Country = GraphQLClient.introspect_object("Country")

response = query("countries", Vector{Country}, query_args=query_args, output_fields="name")

response.data["countries"][1]
# Country
#   name : Australia
```

### Mutations

Mutations can be constructed in a similar way, except the arguments are not a keyword argument as typically
a mutation is doing something with an input. For example

```julia
response = mutate(client, "mutation_name", Dict("new_id" => 1))
response = mutate("mutation_name", Dict("new_id" => 1)) # Use global client
```


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