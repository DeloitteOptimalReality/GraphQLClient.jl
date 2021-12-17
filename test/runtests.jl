using GraphQLClient
using GraphQLParser
using HTTP
using JSON3
using StructTypes
using Test

include("utils.jl")

@testset "GraphQLClient" begin
    @testset "Client" begin include("client.jl") end
    @testset "Introspection" begin include("introspection.jl") end
    @testset "Schema Utils" begin include("schema_utils.jl") end
    @testset "Output Fields" begin include("output_fields.jl") end
    @testset "Args" begin include("args.jl") end
    @testset "Variables" begin include("variables.jl") end
    @testset "GQLResponse" begin include("gqlresponse.jl") end
    @testset "Subscriptions" begin include("subscriptions.jl") end
    @testset "HTTP Execution" begin include("http_execution.jl") end
    @testset "Type Construction" begin include("type_construction.jl") end
    @testset "GQL String" begin include("gql_string.jl") end
end