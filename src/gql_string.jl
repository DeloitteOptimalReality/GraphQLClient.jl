"""
    @gql_str(document, throw_on_error=true)

Create and optionally validate a GraphQL query string.

The string is parsed and semi-validated by GraphQLParser.jl.
Validation that does not need the schema from the server is performed.
For further information see the GraphQLParser documentation.

Parsing errors will always be thrown, but other validation errors can be turned off using the second argument.

An additional advantage of using this macro is that dollar signs do not need to be escaped (see example below).

# Examples

General usage

```julia-repl
julia> client = Client("https://countries.trevorblades.com");

julia> str = gql\"""
query(\$code: ID!){
    country(
        code:\$code
    ){
        name
    }
}
\""";

julia> variables = Dict("code" => "BR");

julia> GraphQLClient.execute(client, str; variables=variables)
GraphQLClient.GQLResponse{Any}
  data: Dict{String, Any}
          country: Dict{String, Any}
```

Parsing error

```julia-repl
julia> str = gql\"""
query(code: ID!){  # no \$ before variable name
    country(
        code:\$code
    ){
        name
    }
}
\""";

# ERROR: LoadError: ArgumentError: invalid GraphQL string at byte position 7 while parsing
#     Variable name must start with '\$'
#     query(code: ID!){  # no \$ before 
#           ^
```

Validation error

```julia-repl
julia> str = gql\"""
{
    countries{
        name
    }
}

query{  # Can't have another operation when there is an anonymous operation
    countries{
        name
    }
}
\""";
# ERROR: LoadError: Validation Failed

# GraphQLParser.AnonymousOperationNotAlone
#       message: This anonymous operation must be the only defined operation.
#      location: Line 1 Column 1
```

Turning validation off

```julia-repl
julia> str = @gql_str \"""
{
    countries{
        name
    }
}

query{  # Can't have another operation when there is an anonymous operation
    countries{
        name
    }
}
\""" false
# No error
```
"""
macro gql_str(document, throw_on_error=true)
    is_valid_executable_document(document; throw_on_error)
    return document
end