# Low Level Execution

If required, it is possible to define operation strings manually and execute them using either a `Client` or a URL. The following code blocks shows methods with which this can be performed.

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

julia> # Using URL, query string and operation_name kwarg

julia> query_string = """
           query getCountries{countries{name}}
           query getLanguages{languages{name}}
       """;

julia> GraphQLClient.execute("https://countries.trevorblades.com", query_string, operation_name="getCountries")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          countries: Vector{Any}

julia> GraphQLClient.execute("https://countries.trevorblades.com", query_string, operation_name="getLanguages")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          languages: Vector{Any}

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

julia> query_string = """
           query getCountries{countries{name}}
           query getLanguages{languages{name}}
       """;

julia> GraphQLClient.execute(client, query_string, operation_name="getCountries")
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          countries: Vector{Any}
```

## `gql` non-standard string literal

GraphQLClient provides the [`@gql_str`](@ref) macro which can be used to generate query strings by prepending a `String` with `gql`.

```julia-repl
julia> str = gql"query($code: ID!){country(code:$code){name}}"
"query(\$code: ID!){country(code:\$code){name}}"
```

By default this performs some validation on the string, as per [GraphQLParser.jl](https://github.com/mmiller-max/GraphQLParser.jl).
Validation errors can be turned off by using the second argument to the macro.

```julia-repl
julia> str = gql"query($code: ID!, $code: ID!){country(code:$code){name}}"
ERROR: LoadError: Validation Failed

GraphQLParser.RepeatedVariableDefinition
      message: There can only be one variable named "code".
     location: Line 1 Column 6

# Use second argument to turn off error (requires full macro form and escaping of $s)
julia> str = @gql_str "query(\$code: ID!, \$code: ID!){country(code:\$code){name}}" false
"query(\$code: ID!, \$code: ID!){country(code:\$code){name}}"
```
```
