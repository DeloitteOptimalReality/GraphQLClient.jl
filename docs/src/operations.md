# Operations

```@contents
Pages = ["operations.md"]
Depth = 5
```

## Overview

As per [the specification](https://spec.graphql.org/June2018/#sec-Language.Operations),
a GraphQL operation can be one of three types:
- query, a read-only fetch
- mutation, a write followed by a fetch
- subscription, a long-lived request that fetches data in response to source events

There three operations can be performed using the [`query`](@ref), [`mutate`](@ref) and
[`open_subscription`](@ref) functions. These three functions share a lot of common
functionality which serves to build the query string by

- Setting the operation type depending on the function used (i.e., for the `query` function the operation type is `query`)
- Taking the query, mutation or subscription name and setting it as the top level field
- Building an arguments string for this top level field and, if required, an associated dictionary of variable definitions
- Using the `output_field` keyword argument to form the rest of the query string. (Note,
    "output field" is not a term that you will find in the GraphQL specification.
    We use it here to refer to any fields that are not the top level field).

As an example, consider an imaginary GraphQL server

```julia
query("get_countries", query_args=Dict("name" => "Australia"), output_fields="states")
```
becomes a query string of
```
{
    get_countries($name: String){
        states
    }
}
```
and a variables dictionary of
```
{
    "name": "Australia"
}
```
which together form the payload to the GraphQL server.

These three functions read the response from the server, process it and return a `GQLReponse{T}`
object, where `T` defaults to `Any` but is configurable - see [Response](@ref).

## Executing an Operation

A query, mutation or subscription can be selected by inputting its name as the first positional
argument of [`query`](@ref), [`mutate`](@ref) and [`open_subscription`](@ref) respectively.
These names can be strings or [Aliases](@ref).

## Arguments

[`query`](@ref), [`mutate`](@ref) and [`open_subscription`](@ref) accept arguments for the top
level field (i.e., the query, mutation or subscription) via a positional argument in the case
of `mutate`, and via the `query_args` and `sub_args` keyword arguments for `query` and
`open_subscription` respectively. Because a mutation is a write followed by a read, it will
typically always have arguments associated with it, and therefore for `mutate` it is not a
keyword argument. Arguments for output fields are currently not implemented.

Arguments for the operation are supplied as a dictionary, the keys of which are `String`s or
 `Symbol`s and the fields of which can be any combination of scalar values, dictionaries for
 input objects or vectors of dictionaries for lists of input objects.

The example below shows some of the possible inputs to give an idea of what is possible.
The structure of the arguments will depend on the GraphQL schema.

```julia
args = Dict(
    "arg1" => "word",
    "arg2" => [1,2,3],
    "arg3" => Dict(
        "arg1" => true,
        "arg4" => [
            Dict("arg10" => 1.0),
            Dict("arg10" => 2.0),
        ]
    )
)
```

There are two options for how the arguments are constructed into the operation, the
choice of which is controlled by the `direct_write` keyword argument.

1. `direct_write=false` (default), argument values are supplied in a variables along with the query string.
2. `direct_write=true`, argument values are directly written into the query string.

### [Using Variables](@id variables_section)

When the `direct_write` keyword argument is false, the arguments will be written
into a query string and a variables dictionary that is sent with the string. Assuming that arguments
in the example above are for for a query called `MyQuery`, the query
string would be as follows (with exact types depending on the schema):

```
MyQuery(
    $arg1: String
    $arg2: [Int]
    $arg1__1: Boolean
    $arg10__2: Float
    $arg10__3: Float
){
    arg1: $arg1
    arg2: $arg2
    arg3: {
        arg1: $arg1__1
        arg2: [
            {arg10: $arg10__2}
            {arg10: $arg10__3}
        ]
    }
}
```

And the variables dictionary (once serialised as a JSON) would be

```json
{
    "arg1": "word",
    "arg2": [1,2,3],
    "arg1__1": true,
    "arg10__2": 1.0,
    "arg10__3": 2.0
}
```
Repeated argument names (for example, in lists of input objects or objects with the
same field names) are handled by appending the name with a double score and
an incrementing count.

### Direct Write

When `direct_write` is `true`, argument values are written directly into the query. The above example becomes

```
MyQuery{
    arg1:"word"
    arg2:[
        123
    ]
    arg3:{
        arg1:true
        arg4:[
            { arg10:1.0}
            { arg10:2.0 }
        ]
    }
}
```

### ENUMs

ENUM values are not quoted in GraphQL queries. If using `direct_write=false`, this is handled
by the GraphQL server. However if using `direct_write=true`, arguments that are an ENUM value
cannot be `String`s in the argument dictionary. Instead, the string value should be wrapped
in a `GQLEnum` type which will be written correctly.

For example if the arguments are

```julia
args = Dict(
    "enum_arg" => GQLEnum("value")
)
```

The directly written query string will be

```
MyQuery{
    enum_arg: value
}
```

## Output Fields

The output fields are typically used to control what fields are in the response. The
`output_fields` keyword argument can be any combination of strings, vectors and dictionaries
and the query string is constructed accordingly. See below for some examples of `output_fields`
values and the query string formed for a query called MyQuery with no arguments.

```
# output_fields = "Field1"
MyQuery{
    Field1
}
```
```
# output_fields = ["Field1", "Field2"]
MyQuery{
    Field1,
    Field2
}
```
```
# output_fields = ["Field1", "Field2", Dict("Field3" => "Field4")]
MyQuery{
    Field1,
    Field2,
    Field3{
        Field4
    }
}
```

If `output_fields` is not supplied for a `query`, introspection is used to query all possible
fields (subject to some handling of recurive objects). If `output_fields` is not supplied for
`mutation` or `query`, the query string has no output fields.

Output field names can be [Aliases](@ref) to control what the keys of the response object are.

## Aliases

An alias can be created using a `Alias` struct

```
my_alias = Alias("my_name", "field_name")
```

Aliases will be correctly interpreted into the query string, for example the following aliases and query
```julia
alias1 = Alias("MyData", "MyQuery")
output_alias = Alias("value", "Field1")
response = query(alias1, output_fields=output_alias)
```

will produce the following query string

```
MyData: MyQuery{
    value: Field1
}
```

And the response will have the key `"MyData"` rather than `"MyQuery"` (see [Response](@ref) for more information).

## Response

### [Errors](@id errors_in_response)

A GraphQL response can contain one or both of `data` and `error` fields, depending on what
has happened during the execution of the operation. GraphQLClient, however, will always
return a `GQLResponse` object that has both `error` and `data` fields. This is to ensure
that operations are type stable. The table below shows what the value of the fields of
a `GQLResponse` show about the response

|Outcome| `data` key in response | `errors` key in response | `GQLResponse.data` | `GQLResponse.errors` |
|---|---|---|---|---
|No errors occurred| Populated with requested data| Not present | Populated with requested data| `nothing` 
|Error occurred before execution begins | Not present | Populated with error information | `nothing` | Populated with error information |
| Error occurred during execution | `null` or relevant data entry is `null` | Populated with error information | `nothing` or relevant data entry is `nothing` | Populated with error information |

The key difference to be aware of is that if `GQLReponse.data` is `nothing`, this does
not necessarily mean an error did or didn't occur *during execution*, just that an error
occurred.

Whether or not GraphQLClient throws an exception when an error occurs during execution
is controlled by the `throw_on_execution_error` keyword argument which defaults to `false`.

### [Custom Types](@id custom_type_ref)

By default, the response will be a `GQLResponse{Any}`. The parametric type refers to the
value of the `data` field, which is a `Dict{String, Union{Nothing, Any}}`. `query`, `mutate`
and `open_subscription` allow this parametric type to be set
using the `output_type` positional argument, which typically enables more concrete typing.
GraphQLClient uses [JSON3](https://github.com/quinnj/JSON3.jl) to deserialize the response.

For example, if the response is

```julia
str = """
{
    "data":{
        "MyQuery": {
            "field1": 1,
            "field2": 2
        }
    }
}
"""
```
Then the type `Dict{String, Int}` could be inputted to the `output_type` positional argument

```@meta
DocTestSetup = quote
    str = """
    {
    "data": {
        "MyQuery": {
            "field1": 1,
            "field2": 2
            }
        }
    }"""
    using JSON3, StructTypes
    using GraphQLClient: GQLResponse
end
```

```jldoctest
julia> JSON3.read(str, GQLResponse{Dict{String, Int}})
GQLResponse{Dict{String, Int64}}
  data: Dict{String, Union{Nothing, Dict{String, Int64}}}
          MyQuery: Dict{String, Int64}
```

Alternatively, a custom type can be defined and used with [StructTypes](https://github.com/JuliaData/StructTypes.jl) allowing for more complex reponses.

```jldoctest
julia> struct MyQuery
           field1::Int
           field2::Int
       end

julia> StructTypes.StructType(::Type{MyQuery}) = StructTypes.OrderedStruct()

julia> JSON3.read(str, GQLResponse{MyQuery})
GQLResponse{MyQuery}
  data: Dict{String, Union{Nothing, MyQuery}}
          MyQuery: MyQuery
```

```@meta
DocTestSetup = nothing
end
```

There are some things to watch out for when using a custom type, namely that a custom type will
typically be less flexible than the default `GQLResponse{Any}` in terms of handling a response
that is different to what is expected, and therefore deserialisation errors are more likley.
If a custom type is used and deserialisation fails, GraphQLClient will attempt to deserialize
with a `GQLResponse{Any}` to see if there are any error messages that were the source of the
deserialisation failure. If this happens, the following warning will be outputted

```julia
┌ Warning: Deserialisation of GraphQL response failed, trying to access execution errors
└ @ GraphQLClient ../GraphQLClient/src/http_execution.jl:144
```

Followed by either a `GraphQLError` being thrown (if the response contained errors) or the following error message which will in turn be followed by the original deserialisation error message

```julia
┌ Error: No errors in GraphQL response, error most likely in deserialisation.
│ Check type supplied to output_type.
└ @ GraphQLClient ../GraphQLClient/src/http_execution.jl:150
ERROR: ArgumentError: invalid JSON at byte position ...
```

For more information, please see [Struct Types Usage](@ref using_struct_types).

## HTTP Interaction

[`query`](@ref) and [`mutate`](@ref) make HTTP post requests to the GraphQL server. Retries and timeouts can be controlled using the following keyword arguments

- `retries` - the number of times a query or mutation will be attempted before an error is thrown
- `readtimeout` - the request timeout in seconds which should be set to 0 for no timeout

## Subscription Control

As well as the `subscription_name`, `output_type`, `sub_args`, `output_fields` and `throw_on_execution_error` arguments that have been discussed above, [`open_subscription`](@ref) has additional arguments which control initialisation and stopping of subscriptions.

### Initialisation

A function can be passed to the `initfn` to be run once the subscription is open. This means that if subscribing to the result of a mutation, for example, it can be guaranteed that no responses will be missed between the mutation being executed and the subscription being opened.

If the `retry` keyword argument is `true`, GraphQLClient will retry the opening of the subscription if it fails. This keyword argument is passed directly to `HTTP.WebSockets.open`.

### Stopping

A subscription stops in three situations

1. The function that acts on the response returning `true`
2. If the `subtimeout` keyword argument is greater than zero, the `stopfn` keyword argument is `nothing` and the subscription has been open for longer than `subtimeout`
3. If the `subtimeout` keyword argument is greater than zero, a function has been supplied to the `stopfn` keyword argument and this function returns `true` when executed (which occurs every `subtimeout` seconds)