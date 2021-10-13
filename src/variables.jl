""" 
    get_variables_str(client::Client,
                      args::AbstractDict,
                      arg_names::AbstractDict,
                      query::String;
                      typedict=client.query_to_args_map)

Returns the variable string, not bracketed, for the `args` of a given `query`.
For each variable, the string is:

`\$var_name: var_type`

where `var_name` is specified in `arg_names`. This allows multiple args of the same type
to be parameterised with different names. For queries and mutations, `arg_names` is
calculated by `get_query_args_str`.

# Arguments
- `client::Client`: client.
- `args::AbstractDict`: contains name of type and value of argument as key value pairs.
    For nested arguments, the value should be a `AbstractDict` or `Vector{<:AbstractDict})`.
    See examples below.
- `arg_names::AbstractDict`: contains name of type and name to be used in variable string
    as key value pairs. The structure and keys of `arg_names` should match that of `args`.
- `query::String`: query/mutation/subscription name
- `typedict=client.query_to_args_map`: dictionary to look up type in. For top level variables,
    `query_to_args_map` is used. For lower level variables, `type_to_fields_map` is used.

# Examples
```jldoctest; setup=:(using GraphQLClient: get_variables_str, prettify_query, Client)
julia> client = Client("https://countries.trevorblades.com");

julia> args = Dict("code" => "BR");

julia> arg_names = Dict("code" => "code1");

julia> str = get_variables_str(client, args, arg_names, "country")
\"\\\$code1: ID!,\"
```
"""
function get_variables_str(client::Client,
                           args::AbstractDict,
                           arg_names::AbstractDict,
                           query::String;
                           typedict=client.query_to_args_map)

    # Query might be appended with !, so remove
    query = replace(query, r"!" => "")
    
    # Query might be a list containing a string, so remove outer square brackets
    query = replace(query, r"^\[|\]$" => "")

    str = ""
    for (key, val) in args
        !haskey(typedict[query], key) && throw(GraphQLClientException("Cannot query field \"$key\" on type \"$query\""))
        if isa(val, AbstractDict)
            str *= get_variables_str(client, val, arg_names[key], typedict[query][key], typedict=client.input_object_fields_to_type_map)
        elseif isa(val, Vector{<:AbstractDict})
            str *= join(get_variables_str.(Ref(client), val, arg_names[key], Ref(typedict[query][key]), typedict=client.input_object_fields_to_type_map))
        else
            str *= "\$" * arg_names[key] * ": " * typedict[query][key]
            str *= ","
        end
    end
    return str
end

"""
    get_query_variables(args, arg_names)

Returns single level dictionary with variable name and value as key val pairs.

`args` and `arg_names` must be dictionaries with the same structure and keys. `args` contains
the original variable name and its value, `arg_names` contains the original variable name and
the name being used in the query, which may be different from the original variable name, for
example if multiple of the same original name are used.

# Examples
```jldoctest; setup=:(using GraphQLClient: get_query_args_str, get_query_variables, prettify_query)
julia> args = Dict("int" => 1, "vector" => [1, 2, 3], "dict" => Dict("float" => 1.0), "vec_dict" => [Dict("bool" => true, "int" => 2)]);

julia> _, arg_names = get_query_args_str(args);

julia> arg_names
Dict{String, Any} with 4 entries:
  "int"      => "int"
  "dict"     => Dict{String, Any}("float"=>"float")
  "vec_dict" => Dict{String, Any}[Dict("int"=>"int__2", "bool"=>"bool__2")]
  "vector"   => "vector__1"

julia> get_query_variables(args, arg_names)
Dict{String, Any} with 5 entries:
  "int"       => 1
  "int__2"    => 2
  "bool__2"   => true
  "float"     => 1.0
  "vector__1" => [1, 2, 3]
```
"""
function get_query_variables(args, arg_names; name_tracking=[])
    variables = Dict{String, Any}()
    for (key, val) in args
        if val isa AbstractDict
            merge!(variables, get_query_variables(val, arg_names[key], name_tracking=name_tracking))
        elseif val isa Vector{<:AbstractDict}
            for i in eachindex(val)
                merge!(variables, get_query_variables(val[i], arg_names[key][i], name_tracking=name_tracking))
            end
        else
            # Check name is unique and add to tracking if so
            arg_names[key] in name_tracking && throw(GraphQLClientException("Duplicate name \"$(arg_names[key])\" found when creating variable dictionary for HTTP query."))
            push!(name_tracking, arg_names[key])
            variables[arg_names[key]] = val
        end
    end
    return variables
end