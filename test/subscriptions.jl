function listen_localhost()
    @async HTTP.listen(HTTP.Sockets.localhost, 8080) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                while !eof(ws)
                    data = readavailable(ws)
                    write(ws, data)
                end
            end
        end
    end
end

function do_nothing_localhost()
    @async HTTP.listen(HTTP.Sockets.localhost, 8081) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                while !eof(ws)
                    data = readavailable(ws)
                end
            end
        end
    end
end

@testset "timers" begin
    listen_localhost()
    HTTP.WebSockets.open("ws://127.0.0.1:8080") do ws
        # timeout
        ch = GraphQLClient.async_reader_with_timeout(ws, 0.1)
        @test take!(ch) == :timeout

        ch = GraphQLClient.async_reader_with_timeout(ws, 5)
        write(ws, "Data")
        @test String(take!(ch)) == "Data"

        # stopfn
        stop = Ref(false)
        stopfn() = stop[] 
        ch = GraphQLClient.async_reader_with_stopfn(ws, stopfn, 0.5)
        @test !isready(ch)
        stop[] = true
        sleep(1.0)
        @test take!(ch) == :stopfn
        stop[] = false
        ch = GraphQLClient.async_reader_with_stopfn(ws, stopfn, 0.5)
        write(ws, "Data")
        @test String(take!(ch)) == "Data"

        # readfromwebsocket - no timeout or stopfn
        write(ws, "Data")
        @test String(GraphQLClient.readfromwebsocket(ws, nothing, 0)) == "Data"

        # readfromwebsocket - timeout
        @test GraphQLClient.readfromwebsocket(ws, nothing, 0.1) == :timeout

        # readfromwebsocket - stopfn
        count = Ref(0)
        function stopfn2()
            if count[] > 0
                return true
            else
                count[] += 1
                return false
            end
        end
        @test GraphQLClient.readfromwebsocket(ws, stopfn2, 0.1) == :stopfn
    end
end

function send_error_localhost(message, port)
    @async HTTP.listen(HTTP.Sockets.localhost, port) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                while !eof(ws)
                    data = readavailable(ws)
                    isempty(data) && continue
                    query = JSON3.read(data)
                    error_payload = """
                    {   "id": "$(query["id"])",
                        "type": "sub",
                        "payload": {
                            "errors" : [
                                {
                                    "message": "$message",
                                    "locations": [{
                                        "line": 1,
                                        "column": 10
                                    }]
                                }
                            ]
                        }
                    }
                    """
                    write(ws, error_payload)
                end
            end
        end
    end
end

function send_data_localhost(sub_name, port)
    @async HTTP.listen(HTTP.Sockets.localhost, port) do http
        if HTTP.WebSockets.is_upgrade(http.message)
            HTTP.WebSockets.upgrade(http) do ws
                while !eof(ws)
                    data = readavailable(ws)
                    isempty(data) && continue
                    query = JSON3.read(data)
                    data_payload = """
                    {   "id": "$(query["id"])",
                        "type": "sub",
                        "payload": {
                            "data": {
                                "$sub_name": {
                                    "field": 1
                                }
                            }
                        }
                    }
                    """
                    write(ws, data_payload)
                end
            end
        end
    end
end

@testset "subscriptions.jl" begin
    # Set up client
    client = Client("http", "ws://127.0.0.1:8081"; introspect=false)
    client.introspection_complete = true
    push!(client.subscriptions, "MySub")

    @test_throws GraphQLClient.GraphQLError open_subscription(()->(), client, "Doesn't Exist")
    
    do_nothing_localhost()

    # init_func
    val = Ref(1)
    init_arg = 2
    initfn(arg) = val[] = arg
    open_subscription(
        (val)->(sleep(0.5); false),
        client,
        "MySub",
        initfn=() -> initfn(init_arg),
        output_fields="field",
        subtimeout=0.1)
    @test val[] == 2

    # Error response - not throwing
    port = 8093
    send_error_localhost("This failed", port)
    client = Client("http", "ws://127.0.0.1:$port"; introspect=false)
    client.introspection_complete = true
    push!(client.subscriptions, "MySub")
    results = []
    open_subscription(
        (val)->(push!(results, val); true),
        client,
        "MySub",
        output_fields="field")
    @test length(results) == 1
    @test results[1] isa GraphQLClient.GQLResponse
    @test isnothing(results[1].data)
    @test !isnothing(results[1].errors)
    @test !isempty(results[1].errors)
    @test results[1].errors[1].message == "This failed"

    # Error response, thrown
    @test_throws GraphQLClient.GraphQLError open_subscription(
        (val)->(push!(results, val); true),
        client,
        "MySub",
        output_fields="field",
        throw_on_execution_error=true)
    
    # Actual data returned
    port = 8096
    send_data_localhost("MySub", port)
    client = Client("http", "ws://127.0.0.1:$port"; introspect=false)
    client.introspection_complete = true
    push!(client.subscriptions, "MySub")
    results = []
    open_subscription(
        (val)->(push!(results, val); true),
        client,
        "MySub",
        output_fields="field")
    @test results[1] isa GraphQLClient.GQLResponse
    @test isnothing(results[1].errors)
    @test !isnothing(results[1].data) # No point testing content as we've coded it in the test function

    # Test struct types
    struct Response
        field::Int
    end
    StructTypes.StructType(::Type{Response}) = StructTypes.OrderedStruct()

    results = []
    open_subscription(
        (val)->(push!(results, val); true),
        client,
        "MySub",
        Response,
        output_fields="field")
    @test results[1] isa GraphQLClient.GQLResponse{Response}
    @test isnothing(results[1].errors)
    @test !isnothing(results[1].data) # No point testing content as we've coded it in the test function
end