"""
    GQLLocation

Struct to contain the location of GraphQL errors.
"""
struct GQLLocation
    line::Int
    column::Int
end
StructTypes.StructType(::Type{GQLLocation}) = StructTypes.Struct()

Base.show(io::IO, ::MIME"text/plain", loc::GQLLocation) = print(io, "Line $(loc.line) Column $(loc.column)")
Base.show(io::IO, loc::GQLLocation) = print(io, "Line $(loc.line) Column $(loc.column)") # for string interpolation

"""
    GQLError

Struct to contain information for errors recieved from the GraphQL server.
"""
Base.@kwdef struct GQLError
    message::String
    locations::Union{Vector{GQLLocation}, Nothing} = nothing
    # path
end
StructTypes.StructType(::Type{GQLError}) = StructTypes.Struct()

function Base.show(io::IO, ::MIME"text/plain", err::GQLError)
    printstyled(io, "GQLError", color=Base.error_color())
    printstyled(io, "\n      message: ", err.message, color=Base.error_color())
    if !isnothing(err.locations)
        printstyled(io, "\n  location(s): $(err.locations[1])", color=Base.error_color())
        for i in 2:length(err.locations)
            printstyled(io, "\n               $(err.locations[i])", color=Base.error_color())
        end
    end
end

"""
    GQLResponse{T}

Output format for GraphQL queries, mutations and subscriptions.

# Accessing data

The `data` field of a `GQLResponse` object is a `Union{Nothing, Dict{String, Union{Nothing, T}}}`,
where the key is the query, mutation or subscription name (or `Alias`) and `T` is specified in the
`output_type` argument of `query`, `mutate`, `open_subscription` and `execute`. If this argument
is not supplied, it will default to `Any`. Typically this results in combinations of dictionaries
and vectors which can be accessed intuitively, following the GraphQL server schema. Alternatively, if
execution of a particular query fails, the value for that query will be `nothing`.

It is, however, possible to provide types with a StructTypes definition and GraphQLClient
will attempt to build the object from the response. This must be done carefully, however,
as if the response is not as expected (for example, missing fields or unexpected nulls) then
the deserialisation of the response into the struct can fail. If this occurs it should be
indicated by the warnings and errors outputted by GraphQLClient.

The fields of the type to deserialise can be modified to be a `Union` of `Nothing` and their
original type, as the deserialisation will input `Nothing` if the field is missing or null.

# Comparison with GraphQL Response Specification

The GraphQL specification specifies that the response can contain `data`, `errors` 
and `extensions` fields. It is important to note that in a `GQLResponse` object,
both `data` and `errors` fields will always be present, regardless of whether or not
they are returned in the server response. This is to ensure queries can be type
stable. If `errors` is `nothing`, then no errors occurred.  If `data`
is `null` this indicates an error occurred either during or before execution.
"""
struct GQLResponse{T}
    errors::Union{Nothing, Vector{GQLError}}
    data::Union{Nothing, Dict{String, Union{Nothing, T}}}
    # extensions::String # to implement
end
StructTypes.StructType(::Type{<:GQLResponse}) = StructTypes.Struct()

function Base.show(io::IO, ::MIME"text/plain", resp::GQLResponse)
    print(io, typeof(resp))
    if !isnothing(resp.errors)
        printstyled(io, "\n  errors: ",length(resp.errors), color=Base.error_color())
    end
    if isnothing(resp.data)
        print(io, "\n  data: null")
    elseif !isempty(resp.data)
        names = keys(resp.data)
        max_length = maximum(length.(names))
        print(io, "\n  data: $(typeof(resp.data))")
        for (key,val) in resp.data
            print(io, "\n$(lpad(key, max_length+10)): $(typeof(val))")
        end
    else
        print(io, "\n  data: empty")
    end
end

"""
    GQLSubscriptionResponse{T}

Struct for subsriptions that wraps a `GQLReponse{T}` alongside various metadata.
"""
struct GQLSubscriptionResponse{T}
    id::Union{String, Nothing}
    type::String
    payload::Union{GQLResponse{T}, Nothing}
end
StructTypes.StructType(::Type{<:GQLSubscriptionResponse}) = StructTypes.Struct()

function Base.show(io::IO, ::MIME"text/plain", resp::GQLSubscriptionResponse)
    print(io, typeof(resp))
    print(io, "\n  id: ", resp.id)
    print(io, "\n  type: ", resp.type)
    print(io, "\n  payload: ", typeof(resp.payload))
end