"Abstract type for GraphQL objects"
abstract type GraphQLType end

"Object type"
struct Object <: GraphQLType
    name::String
end
"InputObject type"
struct InputObject <: GraphQLType
    name::String
end

const GQL_DEFAULT_SCALAR_TO_JULIA_TYPE = Dict(
    "String" => String,
    "Float" => Float64,
    "Boolean" => Bool,
    "Int" => Int64,
    "ID" => String,
)

"""
    getjuliatype(field; level=:top, scalar_types::Dict{String, DataType}=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE)

Returns type of a GraphQL field by determining the kind of the field and
acting accordingly.

# Arguments
- `field`: introspected field dictionary.
- `scalar_types::Dict{String, DataType}=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE`: optional dictionary
    of scalar type name to Julia type which defaults to internal dictionary containing default
    scalars only.
"""
function getjuliatype(field; scalar_types::Dict{String, DataType}=GQL_DEFAULT_SCALAR_TO_JULIA_TYPE)
    if isobject(field)
        return Object
    elseif isinputobject(field)
        return InputObject
    elseif isscalar(field)
        name = getsubfield(field)["name"]
        if !haskey(scalar_types, name)
            if scalar_types == GQL_DEFAULT_SCALAR_TO_JULIA_TYPE
                throw(ArgumentError("Scalar type $(name) is not a default GraphQL SCALAR type. Use the scalar_types kwarg."))
            else
                throw(ArgumentError("Scalar type $(name) is not defined in scalar_types."))
            end
        end
        return scalar_types[name]
    elseif isenum(field)
        return String
    elseif islist(field)
        return Vector{getjuliatype(getsubfield(field); scalar_types=scalar_types)}
    elseif isnonnull(field)
        return getjuliatype(getsubfield(field); scalar_types=scalar_types)
    else
        throw(GraphQLClientException("getjuliatype function does not handle types of \"$(gettype(field))\""))
    end
end

"""
    get_field_type_string(field)

Returns string of the type of a GQL field by determining the kind of the field and
acting accordingly.
"""
function get_field_type_string(field)
    if isscalar(field) || isinputobject(field) || isenum(field) || isobject(field)
        return getsubfield(field)["name"]
    elseif islist(field)
        # Add square brackets and get type from next level down
        return "[" * get_field_type_string(getsubfield(field)) * "]" 
    elseif isnonnull(field)
        # Add ! to show that it is required and get type from next level down
        return get_field_type_string(getsubfield(field)) * "!"
    else
        throw(GraphQLClientException("get_field_type_string function does not handle types of \"$(gettype(field))\""))
    end
end

"""
    getsubfield(field)

Return `field["type"]` or `field["ofType"]`, throwing an error if neither exist.
"""
function getsubfield(field)
    haskey(field, "type") && return field["type"]
    haskey(field, "ofType") && return field["ofType"]
    throw(GraphQLClientException("$field is not a field, cannot return subfield."))
end

gettype(field) = getsubfield(field)["kind"]

"""
    istype(field, comparison)

Checks whether kind of `field` (which has either `type` or `ofType` as a key)
is `comparison`. Error if both `type` and `ofType` are not keys.
"""
istype(field, comparison) = gettype(field) == comparison

# Generate the simple cases
for type in ("OBJECT", "LIST", "SCALAR", "ENUM")
    f = Symbol("is", lowercase(type))
    @eval begin
        $f(field) = istype(field, $type)
    end
end

# Handle these separately due to underscores and more complicated logic
isnonnull(field) = istype(field, "NON_NULL")
isinputobject(field) = istype(field, "INPUT_OBJECT")
is_nonnull_input_object(field) = isnonnull(field) && istype(getsubfield(field), "INPUT_OBJECT")

"""
    getroottypefield(field)

Get the root type field of a NON_NULL or LIST field.
"""
function getroottypefield(field)
    if islist(field) || isnonnull(field)
        getroottypefield(getsubfield(field))
    else
        getsubfield(field)
    end
end

"""
    getroottype(field)

Get the name of the root type of a field.
"""
getroottype(field) = getroottypefield(field)["name"]

"""
    isroottypeenum(field)

Return `true` if field is an arbitrarily nested enum (nested in both NON_NULL and/or LISTs).
"""
isroottypeenum(field) = isenum(field) || ((islist(field) || isnonnull(field)) && isroottypeenum(getsubfield(field)))

"""
    isroottypeobject(field)

Return `true` if field is an arbitrarily nested enum (nested in both NON_NULL and/or LISTs).
"""
isroottypeobject(field) = isobject(field) || ((islist(field) || isnonnull(field)) && isroottypeobject(getsubfield(field)))

"""
    isroottypescalar(field)

Return `true` if field is an arbitrarily nested scalr (nested in both NON_NULL and/or LISTs).
"""
isroottypescalar(field) = isscalar(field) || ((islist(field) || isnonnull(field)) && isroottypescalar(getsubfield(field)))