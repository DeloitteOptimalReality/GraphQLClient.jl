"""
    get_generic_query_payload(client::Client, query_type, query_name, query_args, output_str="")

Get the payload for a gql query.

# Arguments
- `query_type`: typically "query", "mutation" or "subscription".
- `query_name`: name of query.
- `query_args`: dictionary of argument key value pairs - can be nested with
    dictionaries and lists.
- `output_str`: output string to be appended to query.
- `verbose=0`: set to 1, 2 for extra logging.
"""
function get_generic_query_payload(client::Client, query_type, query_name, query_args, output_str=""; verbose=0)
    query_args_str = ""
    vars_str = ""
    variables = Dict()
    if !isempty(query_args) 
        query_args_str, arg_names = get_query_args_str(query_args)
        vars_str = "(" * get_variables_str(client, query_args, arg_names, get_name(query_name)) * ")"
        variables = get_query_variables(query_args, arg_names)
    end
    
    # If any outputs provided, wrap in {}
    if !isempty(output_str) 
        output_str = "{" * output_str * "}"
    end

    query = "$query_type$vars_str{$query_name$query_args_str$output_str}"

    output_debug(verbose) && println("GraphQL input string is: \n $(prettify_query(query))")
    output_debug(verbose) && println("GraphQL input variables are: \n $variables")

    return Dict("query" => query, "variables" => variables)
end

"""
    get_generic_query_payload_direct_write(query_type, query_name, query_args, output_str="")

Get the payload for a gql query, with the main body of the query being `JSON3.write(query_args)`.

# Arguments
- `query_type`: typically "query", "mutation" or "subscription".
- `query_name`: name of query.
- `query_args`: dictionary of argument key value pairs - can be nested with
    dictionaries and lists.
- `output_str`: output string to be appended to query.
- `verbose=0`: set to 1, 2 for extra logging.
"""
function get_generic_query_payload_direct_write(query_type, query_name, query_args, output_str=""; verbose=0)
    # If any outputs provided, wrap in {}
    if !isempty(output_str) 
        output_str = "{" * output_str * "}"
    end

    query_args_str = directly_write_query_args(query_args)

    query = "$query_type{$query_name($query_args_str)$output_str}"

    output_debug(verbose) && println("GraphQL input string is: \n $(prettify_query(query))")

    return Dict("query" => query)
end

"""
    generic_gql_query(client::Client,
                      query_type::String,
                      query_name::Union{Alias, String},
                      query_args::Dict,
                      output_str::String="";
                      direct_write=false,
                      retries=1,
                      retry_non_idempotent=true)

Build and execute a query to `client`.

# Arguments
- `client::Client`: GraphQL client.
- `query_type::String,`: typically "query", "mutation" or "subscription".
- `query_name::Union{Alias, AbstractString}`: name of query.
- `query_args::Dict`: dictionary of argument key value pairs - can be nested with dictionaries and lists.
- `output_str::String`: output string to be appended to query.
- `direct_write=false`: if `true`, the query is formed by generating a string
    from `query_args` directly, and the introspected schema is not used. Any ENUMs
    must be wrapped in a `GQLEnum`. See [`directly_write_query_args`](@ref) for
    more information.
- `output_type::Type=Any`: output data type for query response object.
- `retries=1`: number of times the mutation will be attempted before erroring.
- `readtimeout=0`: HTTP request timeout length. Set to 0 for no timeout.
- `throw_on_execution_error=false`: set to `true` to throw an exception if the GraphQL server
    response contains errors that occurred during execution.
- `verbose=0`: set to 1, 2 for extra logging.
"""
function generic_gql_query(client::Client,
                           query_type::String,
                           query_name::Union{Alias, AbstractString},
                           query_args::Dict,
                           output_str::String="",
                           output_type::Type{T}=Any;
                           direct_write=false,
                           verbose=0,
                           kwargs...)::GQLResponse{T} where T
    if direct_write
        payload = get_generic_query_payload_direct_write(query_type, query_name, query_args, output_str; verbose)
    else
        payload = get_generic_query_payload(client, query_type, query_name, query_args, output_str; verbose)
    end
    body = execute(client, payload, output_type; kwargs...)
    return body
end

"""
    query(client::Client, query_name::Union{Alias, AbstractString}, output_type::Type=Any; kwargs...)

Perform a query on the server. If no `output_fields` are supplied, all possible
fields (determined by introspection of `client`) are returned.

The query uses the `endpoint` field of the `client`.

By default `query` returns a `GQLReponse{Any}`, where the data for an individual query
can be found by `gql_response.data[query_name]`.

# Arguments
- `client::Client`: GraphQL client.
- `query_name::Union{Alias, AbstractString}`: name of query in server.
- `output_type::Type=Any`: output data type for query response object. An object of type
    `GQLResponse{output_type}` will be returned. For further information, see documentation
    for `GQLResponse`.

# Keyword Arguments
- `query_args=Dict()`: dictionary of query argument key value pairs - can be
    nested with dictionaries and vectors.
- `output_fields=String[]`: output fields to be returned. Can be a string, or
    composed of dictionaries and vectors. If empty, `query` will attempt to return
    all fields.
- `direct_write=false`: if `true`, the query is formed by generating a string
    from `query_args` directly, and the introspected schema is not used. Any ENUMs
    must be wrapped in a `GQLEnum`. See [`directly_write_query_args`](@ref) for
    more information.
- `retries=1`: number of times the mutation will be attempted before erroring.
- `readtimeout=0`: HTTP request timeout length. Set to 0 for no timeout.
- `throw_on_execution_error=false`: set to `true` to throw an exception if the GraphQL server
    response contains errors that occurred during execution.
- `verbose=0`: set to 1, 2 for extra logging.

See also: [`GQLResponse`](@ref)
"""
function query(client::Client, query_name::Union{Alias, AbstractString}, output_type::Type=Any; query_args=Dict(),output_fields=String[], kwargs...)
    !in(get_name(query_name), get_queries(client)) && throw(GraphQLClientException("$(get_name(query_name)) is not an existing query"))

    # If output_fields is empty, return all fields
    output_str = isempty(output_fields) ?
        get_all_output_fields_str(client, get_name(query_name)) :  # TODO add caching of this output
        get_output_str(output_fields)

    return generic_gql_query(client, "query", query_name, query_args, output_str, output_type; kwargs...)
end

