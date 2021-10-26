@testset "global client" begin
    @test_throws GraphQLClient.GraphQLClientException global_graphql_client()
    client = Client("url"; introspect=false)
    global_graphql_client(client)
    @test global_graphql_client() === client
end

@testset "accessors" begin
    client = Client("url"; introspect=false)
    client.introspection_complete = true # dummy
    push!(client.queries, "queryname")
    push!(client.mutations, "mutationname")
    push!(client.subscriptions, "subscriptionname")
    @test get_queries(client) == ["queryname"]
    @test get_mutations(client) == ["mutationname"]
    @test get_subscriptions(client) == ["subscriptionname"]
end
