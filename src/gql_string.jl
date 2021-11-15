"""
    @gql_str

Create a GraphQL query string. Currently, the main advantage of using this macro is that dollar signs do not need to be escaped (see example below). However, in the future this macro will perform (some) validation of the string.

# Examples
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
"""
macro gql_str(expr)
    return expr
end