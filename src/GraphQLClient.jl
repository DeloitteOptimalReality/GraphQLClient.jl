module GraphQLClient

using GraphQLParser
using HTTP
using JSON3
using StructTypes

export query, mutate, open_subscription, Client, GQLEnum, Alias,
    full_introspection!, get_queries, get_mutations, get_subscriptions,
    introspect_object, get_introspected_type, initialise_introspected_struct,
    create_introspected_struct, list_all_introspected_objects, global_graphql_client,
    @gql_str

include("constants.jl")
# Types
include("client.jl")
include("types.jl")

include("logging.jl")
include("gqlresponse.jl") 
include("exceptions.jl")
include("schema_utils.jl")
include("args.jl")
include("variables.jl")
include("output_fields.jl")
include("type_construction.jl")
include("http_execution.jl")
include("queries.jl")
include("mutations.jl")
include("subscriptions.jl")
include("introspection.jl")
include("gql_string.jl")

end # module
