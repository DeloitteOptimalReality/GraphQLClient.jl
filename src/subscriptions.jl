const subscription_tracker = Ref{Dict}(Dict())

"""
    open_subscription(fn::Function,
                      [client::Client],
                      subscription_name::Union{Alias, AbstractString},
                      output_type::Type=Any;
                      sub_args=Dict(),
                      output_fields=String[],
                      initfn=nothing,
                      retry=true,
                      subtimeout=0,
                      stopfn=nothing,
                      throw_on_execution_error=false)

Subscribe to `subscription_name`, running `fn` on each received result and ending the
subcription when `fn` returns `true`.

By default `fn` receives a `GQLReponse{Any}`, where the data for an individual result
object can be found by `gql_response.data[subscription_name]`.

If used, `initfn` is called once the subscription is open.

The subscription uses the `ws_endpoint` field of the `client.`

This function is designed to be used with the `do` keyword.

# Arguments
- `fn::Function`: function to be run on each result, receives the response from the
    subscription`. Must return a boolean to indicate whether or not to close the subscription,
    with `true` closing the subscription.
- `client::Client`: GraphQL client (optional). If not supplied, [`global_graphql_client`](@ref) is used.
- `subscription_name::Union{Alias, AbstractString}`: name of subscription in server.
- `output_type::Type=Any`: output data type for subscription response object. An object
    of type `GQLResponse{output_type}` will be returned.For further information, see
    documentation for `GQLResponse`.

# Keyword Arguments
- `sub_args=Dict()`: dictionary of subscription argument key value pairs - can be
    nested with dictionaries and vectors.
- `output_fields=String[]`: output fields to be returned. Can be a string, or
    composed of dictionaries and vectors.
- `initfn=nothing`: optional function to be run once subscription is itialised.
- `retry=true`: retry if subscription fails to open.
- `subtimeout=0`: if `stopfn` supplied, this is the period that it is called at.
    If `stopfn` is not supplied, this is the timeout for waiting for data. The timer
    is reset after every subscription result is received.
- `stopfn=nothing`: a function to be called every `subtimeout` that stops the
    subscription if it returns positive. The timer is reset after every subscription
    result is received.
- `throw_on_execution_error=false`: set to `true` to stop an error being thrown if the GraphQL server
    response contains errors that occurred during execution.
- `verbose=0`: set to 1, 2 for extra logging.

# Examples
```julia
julia> open_subscription("subSaveUser", sub_args=Dict("role" => "SYSTEM_ADMIN")) do result
           fn(result)
       end
```

See also: [`GQLResponse`](@ref)
"""
function open_subscription(fn::Function,
                           subscription_name::Union{Alias, AbstractString},
                           output_type::Type=Any;
                           kwargs...)
    return open_subscription(fn, global_graphql_client(), subscription_name, output_type; kwargs...)
end
function open_subscription(fn::Function,
                           client::Client,
                           subscription_name::Union{Alias, AbstractString},
                           output_type::Type=Any;
                           sub_args=Dict(),
                           output_fields=String[],
                           initfn=nothing,
                           retry=true,
                           subtimeout=0,
                           stopfn=nothing,
                           throw_on_execution_error=false,
                           verbose=0)

    !in(get_name(subscription_name), get_subscriptions(client)) && throw(GraphQLError("$(get_name(subscription_name)) is not an existing subscription"))

    output_str = get_output_str(output_fields)
    payload = get_generic_query_payload(client, "subscription", subscription_name, sub_args, output_str)

    sub_id = string(length(keys(subscription_tracker[])) + 1)
    sub_id *= "-" * string(Threads.threadid())

    throw_if_assigned = Ref{GraphQLError}()
    headers = Dict(client.headers)
    # We currently implement the `apollographql/subscriptions-transport-ws` which is default in hasura and others
    # Defined here https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md
    # TODO: Add support for the newer `graphql-transport-ws` from the graphql-ws library.
    # ()
    headers["Sec-WebSocket-Protocol"] = "apollographql/subscriptions-transport-ws"

    HTTP.WebSockets.open(client.ws_endpoint; retry=retry, headers=headers) do ws
        # Start sub
        output_info(verbose) && println("Starting $(get_name(subscription_name)) subscription with ID $sub_id")
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
            throw(GraphQLError("Error while establishing connection.", payload))
        end

        start_message = Dict(
            "id" => string(sub_id), 
            "type" => GQL_CLIENT_START, 
            "payload" => payload
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
                throw_if_assigned[] = GraphQLError("Error during subscription. Server reporeted connection error")
                break
            end
            response.type == GQL_SERVER_ERROR                 && begin
                throw_if_assigned[] = GraphQLError("Error during subscription - GQL_SERVER_ERROR.", response.payload)
                break
            end
            # response.type == GQL_SERVER_DATA
            payload = response.payload
            if !isnothing(payload.errors) && !isempty(payload.errors) && throw_on_execution_error
                subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
                throw_if_assigned[] = GraphQLError("Error during subscription.", payload)
                break
            end
            # Handle multiple subs, do we need this?
            if response.id == string(sub_id)
                output_debug(verbose) && println("Result received on subscription with ID $sub_id")
                finish = fn(payload)
                if !isa(finish, Bool)
                    subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_ERROR
                    throw_if_assigned[] = ErrorException("Subscription function must return a boolean")
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
    # We can't throw errors from the ws handle function in HTTP.jl 1.#, as they get digested.
    isassigned(throw_if_assigned) && throw(throw_if_assigned[])
    output_debug(verbose) && println("Finished. Closing subscription")
    subscription_tracker[][sub_id] = SUBSCRIPTION_STATUS_CLOSED
    return
end

"""
    clear_subscriptions()

Removes all subscriptions from the `subscription_tracker`, throwing an error if any are still open.
"""
function clear_subscriptions()
    for (sub_id, val) in subscription_tracker[]
        val == "open" ?
            throw(GraphQLError("Subscription $sub_id is still open and cannot be cleared")) :
            delete!(subscription_tracker[], sub_id)
    end
end

function async_reader_with_timeout(ws::HTTP.WebSockets.WebSocket, subtimeout)::Channel
    ch = Channel(1)
    task = @async begin
        reader_task = current_task()
        function timeout_cb(timer)
            put!(ch, :timeout)
            Base.throwto(reader_task, InterruptException())
        end
        timeout = Timer(timeout_cb, subtimeout)
        data = HTTP.receive(ws)
        subtimeout > 0 && close(timeout) # Cancel the timeout
        put!(ch, data)
    end
    bind(ch, task)
    return ch
end

function async_reader_with_stopfn(ws::HTTP.WebSockets.WebSocket, stopfn, checktime)::Channel
    ch = Channel(1) # Could we make this channel concretely typed?
    task = @async begin
        reader_task = current_task()
        function timeout_cb(timer)
            if stopfn()
                put!(ch, :stopfn)
                Base.throwto(reader_task, InterruptException())
            else
                timeout = Timer(timeout_cb, checktime)
            end
        end
        timeout = Timer(timeout_cb, checktime)
        data = HTTP.WebSockets.receive(ws)
        close(timeout) # Cancel the timeout
        put!(ch, data)
    end
    bind(ch, task)
    return ch
end

"""
    readfromwebsocket(ws::IO, stopfn, subtimeout)

Read from the websocket with the following logic:
- If `stopfn` is nothing and `subtimeout` is 0, use `readavailable`
    which blocks data is written to the stream.
- If `stopfn` is not nothing, check the value of `stopfn` periodically.
    If it returns true, the websocket is closed. The period is set to 
    `subtimeout` if greater than 0, otherwise 2 seconds is used.
- If `stopfn` is nothing but `subtimeout` > 0, stop listening after
    `subtimeout` seconds if no data has been received.

A channel is returned with the data. If `stopfn` stops the websocket,
the data will be `:stopfn`. If the timeout stops the websocket,
the data will be `:timeout`
"""
function readfromwebsocket(ws::HTTP.WebSockets.WebSocket, stopfn, subtimeout)
    if isnothing(stopfn) && subtimeout > 0
        ch_out = async_reader_with_timeout(ws, subtimeout)
        data = take!(ch_out)
    elseif !isnothing(stopfn)
        checktime = subtimeout > 0 ? subtimeout : 2
        ch_out = async_reader_with_stopfn(ws, stopfn, checktime)
        data = take!(ch_out)
    else
        data = HTTP.receive(ws)
    end
    return data
end
struct Interrupt <: Exception
end

function checkreturn(data, verbose, sub_id)
    if data === :timeout
        output_info(verbose) && println("Subscription $sub_id timed out")
        throw(Interrupt())
    elseif data === :stopfn
        output_info(verbose) && println("Subscription $sub_id stopped by the stop function supplied")
        throw(Interrupt())
    end
end