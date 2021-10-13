# [Type Introspection](@id type_introspection_page)

```@contents
Pages = ["type_introspection.md"]
Depth = 5
```

## Overview

Because types are well defined in a GraphQL server and we can read the definition via
introspection, we can build a Julia type for any GraphQL object.

```julia-repl
julia> client = Client("https://countries.trevorblades.com")
GraphQLClient Client
       endpoint: https://countries.trevorblades.com
    ws_endpoint: wss://countries.trevorblades.com

julia> T = introspect_object(client, "Country")
GraphQLClient.var"##Country#261"
```

[`introspect_object`](@ref) creates a new, uniquely-named mutable type, which has a
[StructType](@ref using_struct_types) of `Struct()` and where the type of every field
is a `Union` of `Nothing` and the field type, . This makes the type flexible as it can
be used for queries where not all field names are requested.

We can use this as the `output_type` of a query

```julia-repl
julia> response = query(client, "country", T, query_args=Dict("code"=>"AU"), output_fields="phone")
GraphQLClient.GQLResponse{GraphQLClient.var"##Country#261"}
  data: Dict{String, Union{Nothing, GraphQLClient.var"##Country#261"}}
          country: GraphQLClient.var"##Country#261"

julia> country = response.data["country"]
Country
  phone : 61

julia> country.phone
"61"

julia> isnothing(country.continent)
true

julia> propertynames(country)
(:emoji, :currency, :states, :phone, :emojiU, :continent, :native, :capital, :name, :languages, :code)
```

## Using and Initialising

The `Type` for an object can be accessed using [`get_introspected_type`](@ref)

```julia-repl
julia> get_introspected_type(client, "Country")
GraphQLClient.var"##Country#262"
```

We can initialise an instance of the type with every field set to `nothing`

```julia-repl
julia> country = initialise_introspected_struct(client, "Country")
Country
  All fields are nothing

julia> country.name = "Australia"
"Australia"
```

Or pass a dictionary of key value pairs to parameterise an instance of the type with

```julia-repl
julia> fields = Dict("name" => "Australia", "phone" => "61");

julia> create_introspected_struct(client, "Country", fields)
Country
   name : Australia
  phone : 61
```

Note, the latter method will not work if the `mutable` keyword argument of `introspect_object` is set to `false`.


## Handling Recursion and Nested Objects

GraphQL schemas can have objects as fields of other objects, and often these end up recursing.
When an object is being introspected, any objects used in its fields are also introspected.
For example, in the above introspection of `Country`, the object `State` is also introspected

```julia-repl
julia> get_introspected_type(client, "State")
GraphQLClient.var"##State#259"
```

We can view all the introspected objects of a `Client` and see that four objects were actually introspected

```julia-repl
julia> list_all_introspected_objects(client)
4-element Vector{String}:
 "Continent"
 "State"
 "Country"
 "Language"
```

GraphQLClient keeps track of all introspected objects so that if two fields use the same object,
they use the same Julia type. This information is stored in `client` so that if other objects
are introspected that use already-introspected objects they will use the already-introspected
types. Furthermore, if the name of an already-introspected object is inputted to
`introspect_object`, the -already introspected type will be returned.

GraphQLClient also keeps track of the object(s) that is/are currently being introspected to 
ensure that it doesn't attempt to introspect any of them again, which would lead to infinite recursion.

For example in the above introspection of `Country`, we actually get the following warning
messages which were ommited above

```julia-repl
julia> T = introspect_object(client, "Country")
┌ Warning: Cannot introspect field country on type State due to recursion of object Country
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:75
┌ Warning: Cannot introspect field countries on type Continent due to recursion of object Country
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:75
GraphQLClient.var"##Country#261"
```

They indicate that during the introspection of `Country`, both `State` and `Continent` are
being introspected. Both of these objects have fields which use `Country`, and therefore
GraphQLClient cannot introspect these fields, otherwise we would be using the type that we
are currently in the process of definining which therefore doesn't exist (i.e., the
definition of the type for `State` would fail as the type for `Country` doesn't exist yet).

The `allowed_level` keyword argument can be used to control how deep an object is introspected
(note in this example we using the `force` keyword argument to
[force the re-introspection](@ref forcing_re-introspection) of the object)

```julia-repl
julia> T = introspect_object(client, "Country", allowed_level=1, force=true)
┌ Warning: Cannot introspect field languages on type Country due to allowed_level kwarg
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:78
┌ Warning: Cannot introspect field states on type Country due to allowed_level kwarg
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:78
┌ Warning: Cannot introspect field continent on type Country due to allowed_level kwarg
└ @ GraphQLClient ../GraphQLClient/src/type_construction.jl:78
GraphQLClient.var"##Country#262"
```

When setting this to `1` in this example, `introspect_object` will not include any fields
of `Country` that are objects

```julia-repl
julia> fieldnames(T)
(:emoji, :currency, :native, :code, :name, :phone, :capital, :emojiU)
```

Because of the nesting and recursion of objects, it is important to be careful with the
order that objects are introspected and what level is allowed as this can affect the
fields of introspected types. Considering `State` and `Country` in the above example,
here are three possible outcomes:

If `allowed_level=3` and `Country` is introspected first (`State` is introspected during the introspection of `Country`)

```julia
julia> Country = introspect_object(client, "Country", allowed_level=3, force=true);

julia> sort(collect(fieldnames(Country)))
11-element Vector{Symbol}:
 :capital
 :code
 :continent
 :currency
 :emoji
 :emojiU
 :languages
 :name
 :native
 :phone
 :states

julia> sort(collect(fieldnames(get_introspected_type(client, "State"))))
2-element Vector{Symbol}:
 :code
 :name
```

If `allowed_level=3` and State is introspected first (`Client` is introspected during the introspection
of `Country`) we can see that `State` now has the field `name` and `Country` does not have the field `states`.

```julia
julia> State = introspect_object(client, "State", allowed_level=3, force=true);

julia> sort(collect(fieldnames(State)))
3-element Vector{Symbol}:
 :code
 :country
 :name

julia> sort(collect(fieldnames(get_introspected_type(client, "Country"))))
10-element Vector{Symbol}:
 :capital
 :code
 :continent
 :currency
 :emoji
 :emojiU
 :languages
 :name
 :native
 :phone
```

If `allowed_level=1`, both objects must be introspected separately and have fewer fields

```julia
julia> State = introspect_object(client, "State", allowed_level=1, force=true);

julia> sort(collect(fieldnames(State)))
2-element Vector{Symbol}:
 :code
 :name

julia> Country = introspect_object(client, "Country", allowed_level=1, force=true);

julia> sort(collect(fieldnames(Country)))
10-element Vector{Symbol}:
 :capital
 :code
 :currency
 :emoji
 :emojiU
 :name
 :native
 :phone
```

We can see that in each of the three scenarios, the types have different fields according to how
they have been introspected.

A more sophiscated solution could potentially use parametric typing to get around this and
allow full recursion within defined types, but this is not implemented currently.
## [Forcing Re-Introspection](@id forcing_re-introspection)

Fortunately, GraphQL schemas are typically fairly static so we shouldn't need to re-introspect
an object too frequently. Howeve re-intropsection of an object and any objects used by its
fields (and so on for those objects) can be forced using the `force` keyword argument. This
should be done with care, however, as the following example illustrates.

First we introspect `Country`, as we have done previously

```julia-repl
julia> Country = introspect_object(client, "Country")
GraphQLClient.var"##Country#403"
```

Then we force re-introspect `Language`, which has already been introspected during the intropsection of `Country`

```julia-repl
julia> Language = introspect_object(client, "Language", force=true)
GraphQLClient.var"##Language#404"
```

Now if we try to use them together, the type of `Language` will not match that of the `languages` field of `Country`

```julia-repl
julia> language = create_introspected_struct(client, "Language", Dict("name" => "English"))
Language
  name : English

julia> country = create_introspected_struct(client, "Country", Dict("languages" => [language]))
ERROR: MethodError: Cannot `convert` an object of type GraphQLClient.var"##Language#404" to an object of type GraphQLClient.var"##Language#400"
```

It is safer to use the `reset_all` keyword argument once to delete all introspected types and start again.

```julia-repl
julia> Language = introspect_object(client, "Language", reset_all=true);

julia> Country = introspect_object(client, "Country");

julia> language = create_introspected_struct(client, "Language", Dict("name" => "English"))
Language
  name : English

julia> country = create_introspected_struct(client, "Country", Dict("languages" => [language]))
Country
  languages : GraphQLClient.var"##Language#405"[GraphQLClient.var"##Language#405"(nothing, nothing, nothing, "English")]
```
## Parent Types

By default, all introspected types have the parent type [`GraphQLClient.AbstractIntrospectedStruct`](@ref),
which has a defined [StructType](@ref using_struct_types) of `Struct`. However it may be
desirable to change this for multiple dispatch or display purposes. This can be done in two ways in two ways.

The `parent_type` keyword argument sets the parent type of the top level object being
introspected, but no nested objects.

```julia-repl
julia> abstract type MyType end

julia> Country = introspect_object(client, "Country", parent_type=MyType, force=true);

julia>  Country <: MyType
true

julia> get_introspected_type(client, "State") <: MyType
false
```

Alternatively, a dictionary mapping object name to parent type can be supplied to the `parent_map`
keyword argument. Any object that is not in the map will have the default parent type.

```julia-repl
julia> parent_map = Dict("Country" => MyType, "State" => MyType)
julia> Country = introspect_object(client, "Country", parent_map=parent_map, force=true);

julia> Country <: MyType
true

julia> get_introspected_type(client, "State") <: MyType
true

julia> get_introspected_type(client, "Continent") <: MyType # not in parent_map
false
```

If both `parent_type` and `parent_map` are supplied, `parent_type` take precedence.

## Custom Scalar Types

If the GraphQL server has custom scalar types defined and these are used by the object(s)
being intropsected, then they must be mapped to Julia types in the `custom_scalar_types` keyword argument of `introspect_object`.

```julia-repl
julia> custom_scalar_types = Dict("ScalarTypeName" => Int8)
```