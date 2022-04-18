"""
    execute([client::Client], query::AbstractString, output_type::Type{T}=Any; kwargs...) where T
    execute([client::Client], payload::AbstractDict, output_type::Type{T}=Any; kwargs...) where T
    execute(endpoint::AbstractString, query::AbstractString, headers::AbstractDict=Dict(), output_type::Type{T}=Any; variables=Dict(), kwargs...) where T
    execute(endpoint::AbstractString, payload::AbstractDict, headers::AbstractDict=Dict(), output_type::Type{T}=Any; kwargs...) where T

Executes a HTTP Post request and returns the result as a `GQLResponse{T}`.

This function allows for lower level querying of the GraphQL server. A `Client`, the global client or endpoint can be
queried with a query string (and optionally variables can be supplied to the keyword argument), or
with the payload directly. This payload is typically a dictionary containing the key "query"
at a minimum, with `variables` (and other keys) begin optional.

For all methods, the content type is set to `application/json` unless this is set differently
in `client.headers.`/`headers`.

# Keyword Arguments
- `variables=Dict()`: dictionary of variable name to value, used to construct the payload.
- `retries=1`: number of times to retry.
- `readtimeout=0`: close the connection if no data is received for this many seconds.
    Use `readtimeout = 0` to disable.
- `operation_name=""`: name of operation to execute. Must be supplied if more than one operation in
    query. Empty `String` is equal to no name supplied.
- `throw_on_execution_error=false`: set to `true` to throw an exception if the GraphQL
    server response contains errors that occurred during execution. Otherwise, errors
    can be found in the error field of the return value.

See also: [`Client`](@ref), [`GQLResponse`](@ref)

# Examples

```julia
julia> client = Client("https://countries.trevorblades.com");

julia> GraphQLClient.execute(client, "query{country(code:\\"BR\\"){name}}")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
      country: Dict{String, Any}

julia> global_graphql_client(Client("https://countries.trevorblades.com"));

julia> GraphQLClient.execute("query{country(code:\\"BR\\"){name}}")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
      country: Dict{String, Any}

julia> GraphQLClient.execute("https://countries.trevorblades.com", "query{country(code:\\"BR\\"){name}}")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
      country: Dict{String, Any}

julia> GraphQLClient.execute(
           "https://countries.trevorblades.com",
           Dict("query" => "query{country(code:\\"BR\\"){name}}")
       )
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
      country: Dict{String, Any}

julia> query_string = \"\"\"
           query getCountries{countries{name}}
           query getLanguages{languages{name}}
       \"\"\"

julia> GraphQLClient.execute(client, query_string, operation_name="getCountries")
```
"""
execute(query::AbstractString, output_type::Type{T}=Any; kwargs...) where T = execute(global_graphql_client(), query, output_type; kwargs...)
function execute(client::Client, query::AbstractString, output_type::Type{T}=Any; variables=Dict(), operation_name=nothing, kwargs...) where T
    return execute(client, Dict("query" => query, "variables" => variables, "operationName" => operation_name), output_type; kwargs...)
end
execute(payload::AbstractDict, output_type::Type{T}=Any; kwargs...) where T  = execute(global_graphql_client(), payload, output_type; kwargs...)
function execute(client::Client, payload::AbstractDict, output_type::Type{T}=Any; kwargs...) where T
    return execute(client.endpoint, payload, client.headers, output_type; kwargs...)
end
function execute(endpoint::AbstractString, query::AbstractString, headers::AbstractDict=Dict(), output_type::Type{T}=Any; variables=Dict(), operation_name=nothing, kwargs...) where T
    return execute(endpoint, Dict("query" => query, "variables" => variables, "operationName" => operation_name), headers, output_type; kwargs...)
end
function execute(endpoint::AbstractString, payload::AbstractDict, headers::AbstractDict=Dict(), output_type::Type{T}=Any; kwargs...) where T
    return _execute(endpoint, JSON3.write(payload), headers, output_type; kwargs...)
end

"""
    _execute(endpoint::AbstractString,
             execution_string::AbstractString,
             headers::AbstractDict,
             output_type::Type{T}=Any;
             retries=1,
             readtimeout=0,
             throw_on_execution_error=false)::GQLResponse{T} where T

Private function to execute a HTTP Post request.
"""
function _execute(endpoint::AbstractString,
                  execution_string::AbstractString,
                  headers::AbstractDict,
                  output_type::Type{T}=Any;
                  retries=1,
                  readtimeout=0,
                  operation_name=nothing,
                  throw_on_execution_error=false)::GQLResponse{T} where T

    headers = merge(Dict("Content-Type" => "application/json"), headers)

    local resp

    try
        resp = HTTP.post(
            endpoint,
            headers,
            execution_string,
            retries=retries,
            readtimeout=readtimeout,
            retry_non_idempotent=retries > 0)
        body = JSON3.read(resp.body, GQLResponse{output_type})
        throw_on_execution_error && checkbodyforerrors(body)
        return body
    catch err
        @isdefined(resp) && handle_deserialisation_error(err, resp, output_type)
        handle_error(err)
    end
end

"""
    checkbodyforerrors(body::GQLResponse)

If `body` has any errors, throw a `GraphQLError`.
"""
checkbodyforerrors(body::GQLResponse) = !isnothing(body.errors) && !isempty(body.errors) && throw(GraphQLError("Request to server failed", body))

"""
    handle_error(::Exception)
    handle_error(err::HTTP.StatusError)

Handle the error caught during HTTP execution and deserialisation.

It the error is an `HTTP.StatusError` with status 400, a `GraphQLError` is thrown, otherwise
the original error is thrown.
"""
handle_error(::Exception) = rethrow()
handle_error(err::HTTP.StatusError) = err.status == 400 ? throw(GraphQLError(err)) : rethrow()

"""
    handle_deserialisation_error(::Exception, _, _)
    handle_deserialisation_error(err::HTTP.StatusError, resp, output_type)

Handle the error caught during deserialisation.

If it is an `ArgumentError` containing "invalid JSON" in its message, then we attempt
to deserialise the body of the response using a `GQLResponse{Any}` object (if this
wasn't the original output type). This is because this type can handle null fields
in the response, whereas a user defined type may not.

Once deserialised, if there are errors in the body these are thrown. Otherwise, the
original error is rethrown.
"""
handle_deserialisation_error(err::Exception, _, _) = handle_error(err)
function handle_deserialisation_error(err::ArgumentError, resp, output_type)
    !occursin("invalid JSON", err.msg) && rethrow() # Doesn't look like a JSON parsing error
    output_type == Any && rethrow() # If type was already Any then can't use GQLResponse{Any} to try and recover error

    # Use GQLResponse{Any} to try and recover error,
    @warn "Deserialisation of GraphQL response failed, trying to access execution errors"
    body = JSON3.read(resp.body, GQLResponse{Any})
    checkbodyforerrors(body)
    # If checkbodyforerrors doesn't throw an error, then we should rethrow rather
    # then return body as it is likely output_type doesn't match the response and
    # needs to change
    @error "No errors in GraphQL response, error most likely in deserialisation.\nCheck type supplied to output_type."
    rethrow()
end