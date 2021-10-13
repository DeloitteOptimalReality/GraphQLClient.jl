# [Struct Types Usage](@id using_struct_types)

JSON is the most common serialization format for GraphQL servers, and GraphQLClient assumes a
JSON response. As explained in [Custom Types](@ref custom_type_ref), GraphQLClient deserialises
this response by doing `JSON3.read(response, GQLResponse{T})` where `T` defaults to `Any` but
can be configured by using the `output_type` positional argument. The main benefit of configuring
this is to provide type stability to functions that use the response.

Typically, fields in a response will have different types and therefore a `struct` rather
than a `Dict` is better for type stability as `struct`s can have fields of different types,
where as values of a dictionary are either of the same type or of an abstract type.

To deserialise the response into structs, define a type that matches the expected output
and set its [`StructType`](https://github.com/JuliaData/StructTypes.jl). This enables JSON3
to deserialise directly into that type.

Because the GraphQL specification requires that fields of the response are in the same order
as fields in the operation, we know the order of fields in the response and can therefore use
the `StructType` of `OrderedStruct`, which is very efficient (although note this doesn't check
the field names, it simply deserialises each field in order). See the
[JSON3 documentation](https://quinnj.github.io/JSON3.jl/stable/#Struct-API) for more information
about the `StructType`s that can be used, along with other serialisation and deserialisation tricks.

For example

```@meta
DocTestSetup = quote
    using JSON3, StructTypes
    using GraphQLClient: GQLResponse
    using GraphQLClient
end
```

```jldoctest struct_types
julia> response_str = "{\"data\":{\"MyQuery\":{\"field1\":1,\"field2\":2}}}";

julia> print(GraphQLClient.prettify_query(response_str))
{
    "data":{
        "MyQuery":{
            "field1":1
            "field2":2
        }
    }
}

julia> struct MyQuery
           field1::Int
           field2::Int
       end

julia> StructTypes.StructType(::Type{MyQuery}) = StructTypes.OrderedStruct()

julia> JSON3.read(response_str, GQLResponse{MyQuery})
GQLResponse{MyQuery}
  data: Dict{String, Union{Nothing, MyQuery}}
          MyQuery: MyQuery
```

## Handling NULL fields

The fields of GraphQL responses are often nullable, i.e. they can be `nothing`. If this occurred
in the above example, then deserialisation would fail as it attempts to read `null` as an integer.

```julia-repl
julia> response_str = "{\"data\":{\"MyQuery\":{\"field1\":1,\"field2\":null}}}";

julia> print(GraphQLClient.prettify_query(response_str))
{
    "data":{
        "MyQuery":{
            "field1":1
            "field2":null
        }
    }
}

julia> JSON3.read(response_str, GQLResponse{MyQuery})
ERROR: ArgumentError: invalid JSON at byte position 63 while parsing type Int64: InvalidChar
  ry":{"field1":1,"field2":null}}}
```

In cases where this is due to an error from the server, then GraphQLClient will attempt to deserialise with `Any`
to read the errors (see [Response - Errors](@ref errors_in_response) for further details), but
when this is not due to an error we ideally want to be able to handle it without throwing an exception.

To do this we can make field types a `Union` without a significant affect on performance - it is
slightly slower, but compared to the cost of performing an HTTP request this difference is usually neglible.

```jldoctest struct_types
julia> struct MyQueryNullable
           field1::Union{Nothing, Int}
           field2::Union{Nothing, Int}
       end

julia> StructTypes.StructType(::Type{MyQueryNullable}) = StructTypes.OrderedStruct()

julia> JSON3.read(response_str, GQLResponse{MyQueryNullable})
GQLResponse{MyQueryNullable}
  data: Dict{String, Union{Nothing, MyQueryNullable}}
          MyQuery: MyQueryNullable
```

```@meta
DocTestSetup = nothing
end
```