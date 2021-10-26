"""
    AbstractIntrospectedStruct

Default supertype for introspected structs.
"""
abstract type AbstractIntrospectedStruct end
StructTypes.StructType(::Type{<:AbstractIntrospectedStruct}) = StructTypes.Struct()

function Base.show(io::IO, ::MIME"text/plain", obj::T) where {T <: AbstractIntrospectedStruct}
    nonnull_fields = Symbol[]
    for field in fieldnames(T)
        !isnothing(getproperty(obj, field)) && push!(nonnull_fields, field)
    end
    display_text = split(string(typeof(obj)),'#')[3]
    if length(nonnull_fields) == 0
        display_text *= "\n  All fields are nothing"
    else
        longest = maximum(length.(string.(nonnull_fields)))
        for field in nonnull_fields
            display_text *= "\n  "
            display_text *= lpad(field, longest)
            display_text *= " : $(getproperty(obj, field))"
        end
    end
    print(io, display_text)
end

"""
    create_struct_AST(struct_name::Symbol, parent_type, fields, mutable=true)

Returns an `Expr` which can be evaluated to create a struct. The struct
has fields and types specifed by the key value pairs of `fields`, with all types
being a union of `Nothing` and the type supplied. If the `parent_type` method is used
the struct is given the supplied parent type. Mutability can be controlled with 
the `mutable` kwarg.
"""
function create_struct_AST(struct_name::Symbol, parent_type, fields; mutable=true)
    e = Expr(:struct, mutable)
    push!(e.args,Expr(:<:))
    push!(e.args[2].args, struct_name)
    push!(e.args[2].args, parent_type)
    push!(e.args, Expr(:block))
    for (name, type) in fields
        push!(e.args[3].args, :($name::Union{Nothing, $type}))
    end
    return e
end

"""
    build_name_to_type(client,
                       object_name;
                       objects_being_introspected=String[],
                       allowed_level=2,
                       custom_scalar_types=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE,
                       kwargs...)

Builds a dictionary of field name to Julia type for the given object.
"""
function build_name_to_type(client,
                            object_name;
                            objects_being_introspected=String[],
                            allowed_level=2,
                            scalar_types=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE,
                            kwargs...)

    fields_dict = client.type_to_fields_map[object_name]

    name_to_type = Dict{Symbol, Type}()
    for (key, val) in fields_dict
        type = getjuliatype(val; scalar_types)
        if !(type <: GraphQLType) && !(type <: Vector{<:GraphQLType})
            # Simple types, just add to dictionary
            push!(name_to_type, Symbol(key) => type)
        elseif getroottype(val) in objects_being_introspected
            @warn "Cannot introspect field $key on type $object_name due to recursion of object $(getroottype(val))"
            continue
        elseif allowed_level <= 1
            @warn "Cannot introspect field $key on type $object_name due to allowed_level kwarg"
            continue
        else
            introspected_type = _instrospect_object(
                client,
                getroottype(val);
                objects_being_introspected,
                allowed_level=allowed_level-1,
                scalar_types=scalar_types,
                kwargs...
            )
            if type <: GraphQLType
                push!(name_to_type, Symbol(key) => introspected_type)
            elseif type <: Vector{<:GraphQLType}
                push!(name_to_type, Symbol(key) => Vector{introspected_type})
            end
        end
    end
    return name_to_type
end

"""
    _instrospect_object(client,
                        object_name;
                        objects_being_introspected=String[],
                        parent_map=Dict{String, Type}(),
                        mutable=true,
                        allowed_level=2,
                        scalar_types=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE)

Create a new type from instrospection of the object specified by `object_name`. The name of the
tupe is calculated by `gen_sym(string(object_name))`

This is an internal method that is called recursively.

See also: [`introspect_object`](@ref).
"""
function _instrospect_object(client,
                             object_name;
                             objects_being_introspected=String[],
                             parent_map=Dict{String, Type}(),
                             mutable=true,
                             allowed_level=2,
                             scalar_types=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE)
    
    # If this object has already been introspected, return type
    haskey(client.introspected_types, object_name) && return client.introspected_types[object_name]

    # Build a dictionary of field names to types whilst keeping track of what objects are currently being intropsected
    push!(objects_being_introspected, object_name)
    name_to_type = build_name_to_type(
        client,
        object_name;
        objects_being_introspected,
        allowed_level,
        parent_map,
        mutable,
        scalar_types,
    )
    deleteat!(objects_being_introspected, findfirst(obj -> obj==object_name, objects_being_introspected))

    # Create struct from dictionary
    name = gensym(string(object_name)) # gensym creates a unique name, string needed in case of substring
    super_type = get(parent_map, object_name, AbstractIntrospectedStruct)
    eval(create_struct_AST(name, super_type, name_to_type; mutable))

    # Add to objects introspected in this pass
    push!(client.introspected_types, object_name => eval(name)) # eval so type goes in dict
    return eval(name)
end

"""
    introspect_object([client::Client],
                      object_name;
                      force=false,
                      reset_all=false,
                      parent_type=nothing,
                      parent_map=Dict{String, Type}(),
                      mutable=true,
                      allowed_level=2,
                      custom_scalar_types=Dict{String, DataType}())

Introspects an object and creates a Julia type.

Due to the recursion that is possible with GraphQL schemas, this introspection
can be difficult. Please read this docstring carefully.

# Parent Type

All introspected type, by default, will be given the parent type `AbstractIntrospectedStruct`.
The parent type of the top level object being introspected can be set by `parent_type`, and
the parent types of any object being introspected can be set using the `parent_map` dictionary.
If `object_type` is a key in `parent_map` and `parent_type` is not `nothing`, the value of
`parent_type` will take precedence.

# StructTypes

`AbstractIntrospectedStruct` has a defined `StructType` of `Struct` for JSON serialisation.
You can define `StructType`s for the concrete type that is introspected by doing

```
StructTypes.StructType(::Type{GraphQLClient.get_introspected_object(object_name)}) = StructTypes.Struct()
```

# Recursion

Recursion is handled by two methods:

1. Providing the `allowed_level` kwarg to control how deep introspection goes.
2. Maintaining a list of objects that are currently being introspected. No object can be instrospected
    twice and a type cannot be used in a type definition until it has been defined itself. Therefore
    if this situation occurs, the fields that need to use the not-yet-defined type are ignored.
    This means the order in which objects are intropsected can have an impact on the final structs.

For example consider the following objects

```
Country:
 - name: String
 - leader: Person

Person:
 - name: String
 - countryOfBirth: Country
```

If we introspected `Country` first, the `Person` object would not contain the `countryOfBirth` field,
as it is impossible to set the type of that field to `Country` before it is defined itself. If we
introspected `Person` first, the `Country` boject would not contain the `leader` field for the same
reason.

# Keyword Arguments
- `force=false`: if `false`, the introspection will use already introspected types for objects
    if they exist. If `true`, any previously introspected types will be overwritten if they
    are introspected whilst introspecting `object_name`. Use with caution, as other types
    may rely on types that are then overwritten.
- `reset_all`: delete all introspected types to start from a clean sheet.
- `parent_type=nothing`: the parent type to give to the new introspected struct. See
    comment above.
- `parent_map=Dict{String, Type}()`: dictionary to maps
    object names to desired parent types. If `parent_type` is supplied, this value
    will take precedence over the entry in `parent_map` for `object_name`.
- `mutable=true`: boolean to set the mutability of top level and all lower level types.
- `allowed_level=2`: how many levels of introspection are allowed. For example, if this
    is `1` then only top level fields that are objects will be in the introspected type.
- `custom_scalar_types`: dictionary of custom GraphQL scalar type to Julia type. This kwarg enables
    custom scalar types to be introspected to the correct type.
"""
introspect_object(object_name; kwargs...) = introspect_object(global_graphql_client(), object_name; kwargs...)
function introspect_object(client::Client,
                           object_name;
                           force=false,
                           reset_all=false,
                           parent_type=nothing,
                           parent_map=Dict{String, Type}(),
                           mutable=true,
                           allowed_level=2,
                           custom_scalar_types=Dict{String, DataType}())
    
    if reset_all
        empty!(client.introspected_types)
    elseif force
        perviously_introspected_types = deepcopy(client.introspected_types)
        empty!(client.introspected_types)
    end

    if !haskey(parent_map, object_name)
        parent_map[object_name] = isnothing(parent_type) ? AbstractIntrospectedStruct : parent_type
    elseif haskey(parent_map, object_name) && !isnothing(parent_type)
        @warn "Parent type for $object_name supplied in both parent_map and parent_type kwargs. \n parent_type value ($(parent_type)) will be used."
        parent_map[object_name] = parent_type
    end

    scalar_types = merge(GQL_DEFAULT_SCALAR_TO_JULIA_TYPE, custom_scalar_types)

    _instrospect_object(client, object_name; parent_map, mutable, allowed_level, scalar_types)

    # Update client
    if force
        # Ensure any newly introspected types get precedence
        client.introspected_types = merge(perviously_introspected_types, client.introspected_types)
    end

    return client.introspected_types[object_name]
end

"""
    get_introspected_type([client::Client], object_name::String)

Return the introspected `Type` for an object.
"""
get_introspected_type(object_name::String) = get_introspected_type(global_graphql_client(), object_name)
get_introspected_type(client::Client, object_name::String) = client.introspected_types[object_name]

"""
    list_all_introspected_objects([client::Client])

Return a `Vector` of the objects which have been introspected.
"""
list_all_introspected_objects() = list_all_introspected_objects(global_graphql_client())
list_all_introspected_objects(client::Client) = collect(keys(client.introspected_types))

"""
    initialise_introspected_struct([client::Client], name::String)
    initialise_introspected_struct([client::Client], name::SubString)
    initialise_introspected_struct(T::Type)

Initialise an introspected struct with all fields set to nothing. If name of
type supplied as string, this get the `Type` from `client.introspected_types`.
"""
initialise_introspected_struct(name::AbstractString) = initialise_introspected_struct(global_graphql_client(), name)
initialise_introspected_struct(client::Client, name::String) = initialise_introspected_struct(client.introspected_types[name])
initialise_introspected_struct(client::Client, name::SubString) = initialise_introspected_struct(client, string(name))
function initialise_introspected_struct(T::Type)
    n_fields = length(fieldnames(T))
    return T((nothing for i in 1:n_fields)...)
end

"""
    create_introspected_struct([client::Client], object_name::AbstractString, fields::AbstractDict)

Creates a struct for the object specified and populates its fields with
the keys and values of `fields`.

# Examples
```julia
julia> GraphQLClient.create_introspected_struct("ResultObject",Dict(:resultId=>"MyResult", :Score => 1.0))
ResultObject
  Score : 1.0
      resultId : MyResult
```
"""
create_introspected_struct(object_name::AbstractString, fields::AbstractDict) = create_introspected_struct(global_graphql_client(), object_name, fields)
function create_introspected_struct(client::Client, object_name::AbstractString, fields::AbstractDict)
    struct_instance = initialise_introspected_struct(client, object_name)
    !ismutable(struct_instance) && throw(GraphQLClientException("create_introspected_struct only works for mutable types"))
    for (key, val) in fields
        setproperty!(struct_instance, Symbol(key), val)
    end
    return struct_instance
end