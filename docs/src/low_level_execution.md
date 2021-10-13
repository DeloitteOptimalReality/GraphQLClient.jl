# Low Level Execution

If required, it is possible to define operation strings manually and execute them using either a `Client` or a URL. The following code blocks shows  methods with which this can be performed.

HTTP retrying and server runtime execution handling are controlled by keyword arguments in the same was as `query` and `mutate`. See [`GraphQLClient.execute`](@ref) for further details.
## Using a URL Directly

These methods except the `header` keyword argument to set HTTP headers, with the `Content-Type` being set to `"application/json"` if none is supplied.

```jldoctest execute; setup=:(using GraphQLClient)
julia> # Using URL and query string

julia> GraphQLClient.execute("https://countries.trevorblades.com", "query{country(code:\"BR\"){name}}")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}

julia> # Using URL, query string and variables kwarg

julia> variables = Dict("code" => "BR");

julia> GraphQLClient.execute("https://countries.trevorblades.com", "query(\$code: ID!){country(code:\$code){name}}"; variables)
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}

julia> # Using URL and supplying payload dictionary

julia> payload = Dict("query" => "query(\$code: ID!){country(code:\$code){name}}", "variables" => variables);

julia> GraphQLClient.execute("https://countries.trevorblades.com", payload)
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}

```

## Using a `Client`

These methods use `Client.headers` as the HTTP headers, with the `Content-Type` being set to `"application/json"` if none is supplied.

```jldoctest execute
julia> client = Client("https://countries.trevorblades.com");

julia> GraphQLClient.execute(client, "query{country(code:\"BR\"){name}}")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}

julia> GraphQLClient.execute(client, "query(\$code: ID!){country(code:\$code){name}}"; variables)
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}

julia> GraphQLClient.execute(client, payload)
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}
```