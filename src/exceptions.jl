struct GraphQLError <: Exception
    msg::String
    errs
end
GraphQLError(msg) = GraphQLError(msg, nothing)
GraphQLError(err::HTTP.StatusError) = GraphQLError("Request to server failed.", JSON3.read(err.response.body, GQLResponse{Any}))    
function Base.showerror(io::IO, ex::GraphQLError)
    printstyled(io, "GraphQLError: " * ex.msg, color=Base.error_color())
    ex.errs !== nothing && display_errors(io, ex.errs)
end

print_heading(io::IO, heading) = printstyled(io, "\n\n$heading:\n\n", bold=true, color=Base.error_color())

function print_message(io::IO, message)
    print_heading(io, "Message")
    printstyled(io, message, color=Base.error_color())
end

function print_location(io::IO, location::GQLLocation)
    print_heading(io, "Location(s)")
    location = "line: " * string(location.line) * ", column: " * string(location.column)
    printstyled(io, location, color=Base.error_color())
end

function display_errors(io::IO, resp::GQLResponse)
    for err in resp.errors
        print_message(io, err.message)
        !isnothing(err.locations) && foreach(loc->print_location(io, loc), err.locations)
    end
end

struct GraphQLClientException <: Exception
    msg::String
end
function Base.showerror(io::IO, ex::GraphQLClientException)
    printstyled(io, "GraphQLClientException: " * ex.msg, color=Base.error_color())
end