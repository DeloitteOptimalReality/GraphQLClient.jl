"""
    get_all_output_fields_str(client::Client, query_name, objects_to_ignore=String[])

Returns a string containing all fields of the given query. To be used
when returning all fields from a GQL query.

This could be used with mutations (untested), but the default mutation
behaviour is to return nothing.
"""
function get_all_output_fields_str(client::Client, query_name, objects_to_ignore=String[])
    type = client.query_to_type_map[query_name]
    objects_that_recurse = String[]
    if haskey(client.type_to_fields_map, type)
        push!(objects_to_ignore, type)
        fields_str = get_field_names_string(client, type, objects_to_ignore, objects_that_recurse)
        deleteat!(objects_to_ignore, findfirst(objects_to_ignore .== type)) # Only stopping recursion
    else
        fields_str = ""
    end
    !isempty(objects_that_recurse) && @warn "Can't query all output fields due to recursion of these object(s):\n$(join(unique(objects_that_recurse), ", "))"
    return fields_str
end

"""
    get_field_names_string(client::Client, query_name, objects_to_ignore, objects_that_recurse)

Returns a string containing all fields of the given GQL schema type.

Gets all fields from `type_to_fields_map` and then recursively gets all fields.
"""
function get_field_names_string(client::Client, type, objects_to_ignore, objects_that_recurse)
    fields = client.type_to_fields_map[type]
    fields_str = ""
    for field in keys(fields)
        fields_str *= _get_field_str(client, fields[field], objects_to_ignore, objects_that_recurse)
    end
    return fields_str
end

"""
    _get_fields_str(client::Client, field, objects_that_recurse)

Returns a string containing all fields of the given field.

If field is not NON_NULL or an OBJECT, the name of the field is returned. Otherwise,
the subfield(s) of the field are returned wrapped in {}.
"""
function _get_field_str(client::Client, field, objects_to_ignore, objects_that_recurse)
    if isroottypescalar(field) || isroottypeenum(field)
        return field["name"] * ","
    end

    if !isroottypeobject(field)
        throw(GraphQLClientException("_get_field_str does not handle types of \"$(gettype(field))\""))
    end

    subtype = getroottypefield(field)["name"]

    if !in(subtype, objects_to_ignore)
        push!(objects_to_ignore, subtype)
        fields_str = get_field_names_string(client, subtype, objects_to_ignore, objects_that_recurse)
        deleteat!(objects_to_ignore, findfirst(objects_to_ignore .== subtype)) # Only want to stop recursion
    else
        push!(objects_that_recurse, subtype)
        return ""
    end

    if isempty(fields_str)
        # Don't want "{}" in the string
        return ""
    end

    # If we get here field is an OBJECT with fields, wrap fields_str in {} and return.
    return field["name"] * "{"* fields_str * "}"
end

"""
    get_output_str(outputs::Vector)
    get_output_str(output::String)
    get_output_str(output::Alias)
    get_output_str(output::Dict)

Return a `String` containing the output fields. Options:

- If input arg is a `Vector`, `get_output_str` is called on each element.
- If input arg is a `String`, the input is returned with a comma added.
- If input is an `Alias`, "\\\$(Alias.alias):\\\$(Alias.name)," is returned.
- If input arg is a `Dict`, the output creates a structured output string
    based on the keys and values.

# Examples
```jldoctest; setup=:(using GraphQLClient: get_output_str, prettify_query)
julia> str = get_output_str(["Field1", "Field2"])
"Field1,Field2,"
julia> println(prettify_query(str))
Field1
Field2

julia> str = get_output_str("Field1")
"Field1,"

julia> str = get_output_str(["OuterField", Dict("Outer" => Dict("Inner" => ["Field1", "Field2"]))])
"OuterField,Outer{Inner{Field1,Field2,},},"

julia> println(prettify_query(str))
OuterField
Outer{
    Inner{
        Field1
        Field2
    }
}
```
"""
function get_output_str(outputs::Vector)
    str = ""
    for output in outputs
        str *= get_output_str(output) 
    end
    return str
end
get_output_str(output::String) = output * ","
get_output_str(output::Alias) = "$output,"
function get_output_str(output::Dict)
    str = ""
    for (key, val) in output
        str *= "$key{"
        str *= get_output_str(val)
        str *= "},"
    end
    return str
end