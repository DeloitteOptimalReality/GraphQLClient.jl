function test_error_handler(f, e::Exception, args...)
    try
        throw(e)
    catch err
        f(err, args...)
    end
end

@testset "Error handling" begin
    # checkbodyforerrors
    resp = GraphQLClient.GQLResponse{Any}(nothing, nothing)
    @test GraphQLClient.checkbodyforerrors(resp) == false
    resp = GraphQLClient.GQLResponse{Any}(GraphQLClient.GQLError[], nothing)
    @test GraphQLClient.checkbodyforerrors(resp) == false
    resp = GraphQLClient.GQLResponse{Any}([GraphQLClient.GQLError("message", nothing)], nothing)
    @test_throws GraphQLClient.GraphQLError GraphQLClient.checkbodyforerrors(resp) 

    # handle_error
    @test_throws ArgumentError test_error_handler(GraphQLClient.handle_error, ArgumentError("msg"))
    @test_throws HTTP.StatusError test_error_handler(GraphQLClient.handle_error, HTTP.StatusError(404, "POST", "", HTTP.Response(404;request=HTTP.Request(), body="{}")))
    @test_throws GraphQLClient.GraphQLError test_error_handler(GraphQLClient.handle_error, HTTP.StatusError(400, "POST", "", HTTP.Response(400;request=HTTP.Request(), body="{}")))

    # handle_deserialisation_error
    @test_throws MethodError test_error_handler(GraphQLClient.handle_deserialisation_error, MethodError(""), "", "")
    # Argument error without "invalid JSON"
    @test_throws ArgumentError test_error_handler(GraphQLClient.handle_deserialisation_error, ArgumentError(""), "", "")
    # Argument error with "invalid JSON" but default type
    @test_throws ArgumentError test_error_handler(GraphQLClient.handle_deserialisation_error, ArgumentError(""), "", Any)
    # Actual deserialisation error
    resp = HTTP.Response(200;body="{\"data\": {\"query\": 1}}")
    @test_throws ArgumentError test_error_handler(
        GraphQLClient.handle_deserialisation_error,
        ArgumentError("invalid JSON at byte"),
        resp,
        Dict, # anything apart from Any
    )
    @test_logs (:warn, r"Deserialisation of GraphQL response failed, trying to access execution errors") match_mode=:any try
        test_error_handler(GraphQLClient.handle_deserialisation_error, ArgumentError("invalid JSON at byte"), resp, Dict)
    catch
    end
    @test_logs (:error, r"No errors in GraphQL response") match_mode=:any try
        test_error_handler(GraphQLClient.handle_deserialisation_error, ArgumentError("invalid JSON at byte"), resp, Dict)
    catch
    end

    # Actual error that resulted in a deserialisation error
    resp = HTTP.Response(400;body="{\"errors\": [{\"message\": \"I stopped deserialisation!\"}]}")
    @test_throws GraphQLClient.GraphQLError test_error_handler(
        GraphQLClient.handle_deserialisation_error,
        ArgumentError("invalid JSON at byte"),
        resp,
        Dict, # anything apart from Any
    )
    @test_logs (:warn, r"Deserialisation of GraphQL response failed, trying to access execution errors") match_mode=:any try
        test_error_handler(GraphQLClient.handle_deserialisation_error, ArgumentError("invalid JSON at byte"), resp, Dict)
    catch
    end
end

function local_server_success(port)
    @async HTTP.serve(HTTP.Sockets.localhost, port) do req
        execution_string = String(req.body)
        return HTTP.Response("""
            {
                "data": {
                    "queryName": {
                        "field": \"$execution_string\"
                    }
                }
            }
        """)
    end
end

function local_server_success_json(port)
    @async HTTP.serve(HTTP.Sockets.localhost, port) do req
        return HTTP.Response(JSON3.write(
            Dict(
                "data" => Dict(
                    "queryName" => Dict(
                        "field" => JSON3.read(req.body)
                    )
                )
            )
        ))
    end
end

function local_server_error(port)
    @async HTTP.serve(HTTP.Sockets.localhost, port) do req
        str = """
            {
                "data": {
                    "queryName": {
                        "field": null
                    }
                },
                "errors": [
                    {
                        "message": "Error Text"
                    }
                ]
            }
        """
        return HTTP.Response(str)
    end
end

@testset "execute" begin
    # Successful query
    port = 7999
    local_server_success(7999)
    client = Client("http://$(HTTP.Sockets.localhost):$port";introspect=false)

    execution_string = "execute this"
    response = GraphQLClient._execute(client.endpoint, execution_string, Dict())
    
    # Test execution string passed through correctly
    @test response.data["queryName"]["field"] == execution_string
    @inferred GraphQLClient._execute(client.endpoint, execution_string, Dict())

    # Test struct type inference
    struct S
        field::String
    end
    StructTypes.StructType(::Type{S}) = StructTypes.Struct()
    response = GraphQLClient._execute(client.endpoint, execution_string, Dict(), S)
    @test response.data["queryName"].field == execution_string
    @inferred GraphQLClient._execute(client.endpoint, execution_string, Dict(), S)

    # Test error in response
    port = 7996
    local_server_error(7996)
    client = Client("http://$(HTTP.Sockets.localhost):$port";introspect=false)
    execution_string = "execute this"
    response = GraphQLClient._execute(client.endpoint, execution_string, Dict())
    @test !isnothing(response.errors)
    @test !isempty(response.errors)
    @test response.errors[1].message == "Error Text"
    @test_throws GraphQLClient.GraphQLError GraphQLClient._execute(client.endpoint, execution_string, Dict(), throw_on_execution_error=true)
    @test_throws GraphQLClient.GraphQLError GraphQLClient._execute(client.endpoint, execution_string, Dict(), S) # deserialisation fails

    # Test error before response - wrong input to retries causes method error
    @test_throws MethodError GraphQLClient._execute(client.endpoint, execution_string, Dict(), retries=Dict())

    # Test execute methods
    port = 7990
    local_server_success_json(7990)
    struct S1; query::String; end
    struct S2; field::S1; end
    StructTypes.StructType(::Type{S1}) = StructTypes.Struct()
    StructTypes.StructType(::Type{S2}) = StructTypes.Struct()
    client = Client("http://$(HTTP.Sockets.localhost):$port";introspect=false)
    @inferred GraphQLClient.execute(client.endpoint, Dict("query" => "val"))
    @inferred GraphQLClient.execute(client.endpoint, Dict("query" => "val"), Dict(), S2)
    response = GraphQLClient.execute(client.endpoint, Dict("query" => "val"))
    @test response.data["queryName"]["field"]["query"] == "val"
    @inferred GraphQLClient.execute(client.endpoint, "val")
    @inferred GraphQLClient.execute(client.endpoint, "val", Dict(), S2)
    response = GraphQLClient.execute(client.endpoint, "val")
    @test response.data["queryName"]["field"]["query"] == "val"
    @inferred GraphQLClient.execute(client, Dict("query" => "val"))
    @inferred GraphQLClient.execute(client, Dict("query" => "val"), S2)
    response = GraphQLClient.execute(client, Dict("query" => "val"))
    @test response.data["queryName"]["field"]["query"] == "val"
    @inferred GraphQLClient.execute(client, "val")
    @inferred GraphQLClient.execute(client, "val", S2)
    response = GraphQLClient.execute(client, "val")
    @test response.data["queryName"]["field"]["query"] == "val"

    global_graphql_client(client)
    @inferred GraphQLClient.execute(Dict("query" => "val"))
    @inferred GraphQLClient.execute(Dict("query" => "val"), S2)
    response = GraphQLClient.execute(Dict("query" => "val"))
    @test response.data["queryName"]["field"]["query"] == "val"
    @inferred GraphQLClient.execute("val")
    @inferred GraphQLClient.execute("val", S2)
    response = GraphQLClient.execute("val")
    @test response.data["queryName"]["field"]["query"] == "val"
end