import HTTP
import Base.string

supported_protocols = []

PROTOCOL_APOLLO_OLD = "graphql-ws"
PROTOCOL_GRAPHQL_WS = "graphql-transport-ws"

GQL_WS_PROTOCOLS = [PROTOCOL_APOLLO_OLD, PROTOCOL_GRAPHQL_WS]

function handle_apollo_old(
    fn::Function,
    ws::HTTP.WebSockets.WebSocket,
    subscription_name::Union{Alias, AbstractString},
    subscription_payload,
    sub_id::AbstractString,
    output_type::Type=Any;
    initfn=nothing,
    subtimeout=0,
    stopfn=nothing,
    throw_on_execution_error=false,
    verbose=0,
    throw_if_assigned_ref=nothing)

    output_debug(verbose) && println("Communicating with unmaintained apollo ws protocol ($PROTOCOL_APOLLO_OLD)")
    HTTP.send(ws, JSON3.write(Dict("id" => sub_id, "type" => GQL_CLIENT_CONNECTION_INIT)))
    # Init function
    if !isnothing(initfn)
        output_debug(verbose) && println("Running subscription initialisation function")
        initfn()
    end

    data = readfromwebsocket(ws, stopfn, subtimeout)
    try checkreturn(data, verbose, sub_id)
    catch e
        e isa Interrupt && return
    end
    response = JSON3.read(data, GQLSubscriptionResponse{output_type})
    while response.type == GQL_SERVER_CONNECTION_KEEP_ALIVE
        data = readfromwebsocket(ws, stopfn, subtimeout)
        try checkreturn(data, verbose, sub_id)
        catch e
            e isa Interrupt && return
        end
        response = JSON3.read(data, GQLSubscriptionResponse{output_type})
    end
    if response.type == GQL_SERVER_CONNECTION_ERROR && throw_on_execution_error
        subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
        throw(GraphQLError("Error while establishing connection.", response.payload))
    end

    start_message = Dict(
        "id" => string(sub_id),
        "type" => GQL_CLIENT_START,
        "payload" => subscription_payload,
    )
    message_str = JSON3.write(start_message)
    HTTP.send(ws, message_str)
    subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_OPEN

    # Get listening
    output_debug(verbose) && println("Listening to $(get_name(subscription_name)) with ID $sub_id...")

    # Run function
    while true
        data = readfromwebsocket(ws, stopfn, subtimeout)
        try checkreturn(data, verbose, sub_id)
        catch e
            e isa Interrupt && break
        end
        # data = String(data)
        # println(data)
        response = JSON3.read(data, GQLSubscriptionResponse{output_type})

        response.type == GQL_SERVER_CONNECTION_KEEP_ALIVE && continue
        response.type == GQL_SERVER_COMPLETE              && break
        response.type == GQL_SERVER_CONNECTION_ERROR      && begin
            throw_if_assigned_ref[] = GraphQLError("Error during subscription. Server reporeted connection error")
            break
        end
        response.type == GQL_SERVER_ERROR                 && begin
            throw_if_assigned_ref[] = GraphQLError("Error during subscription - GQL_SERVER_ERROR.", response.payload)
            break
        end
        # response.type == GQL_SERVER_DATA
        payload = response.payload
        if !isnothing(payload.errors) && !isempty(payload.errors) && throw_on_execution_error
            subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
            throw_if_assigned_ref[] = GraphQLError("Error during subscription.", payload)
            break
        end
        # Handle multiple subs, do we need this?
        if response.id == string(sub_id)
            output_debug(verbose) && println("Result received on subscription with ID $sub_id")
            finish = fn(payload)
            if !isa(finish, Bool)
                subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
                throw_if_assigned_ref[] = ErrorException("Subscription function must return a boolean")
                break
            end
            if finish
                # Protocol says we need to let the server know we're unsubscribing
                output_debug(verbose) && println("Finished. Closing subscription")
                HTTP.send(ws, JSON3.write(Dict("id" => sub_id, "type" => GQL_CLIENT_STOP)))
                HTTP.send(ws, JSON3.write(Dict("id" => sub_id, "type" => GQL_CLIENT_CONNECTION_TERMINATE)))
                # close(ws)
                break
            end
        end
    end
end

function send_pong(ws::HTTP.WebSockets.WebSocket)
    return HTTP.send(ws, JSON3.write(Dict("type" => GQLWS_BI_PONG)))
end

function handle_graphql_ws(
    fn::Function,
    ws::HTTP.WebSockets.WebSocket,
    subscription_name::Union{Alias, AbstractString},
    subscription_payload,
    sub_id::AbstractString,
    output_type::Type=Any;
    initfn=nothing,
    subtimeout=0,
    stopfn=nothing,
    throw_on_execution_error=false,
    verbose=0,
    throw_if_assigned_ref=nothing)

    # TODO: Lock this; each client must only have *one* request open in this stage
    output_debug(verbose) && println("Communicating with GraphQL-WS protocol ($PROTOCOL_GRAPHQL_WS)")
    HTTP.send(ws, JSON3.write(Dict(
        "id" => sub_id,
        "type" => GQLWS_CLIENT_INIT)))
    # Init function
    if !isnothing(initfn)
        output_debug(verbose) && println("Running subscription initialisation function")
        initfn()
    end

    data = readfromwebsocket(ws, stopfn, subtimeout)
    response = JSON3.read(data, GQLSubscriptionResponse{output_type})
    while response.type == GQLWS_BI_PING
        send_pong(ws)
        data = readfromwebsocket(ws, stopfn, subtimeout)
        try checkreturn(data, verbose, sub_id)
        catch e
            e isa Interrupt && return
        end
        response = JSON3.read(data, GQLSubscriptionResponse{output_type})
    end

    if response.type == GQLWS_SERVER_ERROR && throw_on_execution_error
        subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
        throw(GraphQLError("Error while establishing connection.", response.payload))
    end

    if response.type != GQLWS_SERVER_CONNECTION_ACK
        error("Connection could not be established; Server did not ACK the request to initialize.")
    end

    start_message = Dict(
        "id" => string(sub_id),
        "type" => GQLWS_CLIENT_SUBSCRIBE,
        "payload" => subscription_payload
    )
    message_str = JSON3.write(start_message)
    HTTP.send(ws, message_str)
    subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_OPEN

    # Get listening
    output_debug(verbose) && println("Listening to $(get_name(subscription_name)) with ID $sub_id...")

    # Run function
    while true
        data = readfromwebsocket(ws, stopfn, subtimeout)
        try checkreturn(data, verbose, sub_id)
        catch e
            e isa Interrupt && break
        end
        # data = String(data)
        # println(data)
        response = JSON3.read(data, GQLSubscriptionResponse{output_type})

        response.type == GQLWS_BI_PING              && begin
            send_pong(ws)
            continue
        end
        response.type == GQLWS_BI_COMPLETE          && break
        response.type == GQLWS_SERVER_ERROR         && begin
            throw_if_assigned_ref[] = GraphQLError("Error during subscription. Server reporeted connection error")
            break
        end
        # response.type == GQLWS_SERVER_NEXT
        payload = response.payload
        if !isnothing(payload.errors) && !isempty(payload.errors) && throw_on_execution_error
            subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
            throw_if_assigned_ref[] = GraphQLError("Error during subscription.", payload)
            break
        end
        # Handle multiple subs, do we need this?
        if response.id == string(sub_id)
            output_debug(verbose) && println("Result received on subscription with ID $sub_id")
            finish = fn(payload)
            if !isa(finish, Bool)
                subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
                throw_if_assigned_ref[] = ErrorException("Subscription function must return a boolean")
                break
            end
            if finish
                # Protocol says we need to let the server know we're unsubscribing
                output_debug(verbose) && println("Finished. Closing subscription")
                HTTP.send(ws, JSON3.write(Dict("id" => sub_id, "type" => GQLWS_BI_COMPLETE)))
                # close(ws)
                break
            end
        end
    end
end