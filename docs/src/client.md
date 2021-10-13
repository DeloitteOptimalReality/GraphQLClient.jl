# Client

## Connecting to a Server

A client can be instantiated by using the `Client` object

```julia
client = Client("https://countries.trevorblades.com")
```

If only the `endpoint` is suppplied, the `ws_endpoint` (used for subscriptions) is assumed to be the same with `"http"` replaced by `"ws"`.

Headers can be passed in a dictionary to the `headers` keyword argument, enabling things like authorisation tokens. These headers are 
used directly in the HTTP requests to the server.

```
client = Client(
    "https://myurl.com/queries",
    "wss://myurl.com/subscriptions",
    headers = Dict("Authorization" => "Bearer XXX"),
)
```

By default, when instantiated GraphQLClient will introspect the schema of the server and populate several fields of the `Client` object.

## Introspection

### What needs introspection?

The following functionality requires introspection, and will attempt to introspect the client if it has not already been done so

- Functions to view operations (see below)
- [`query`](@ref), [`mutate`](@ref) and [`open_subscription`](@ref)
    - check that the operation exists
    - use schema to build [variables](@ref variables_section) strings for arguments
- `query` - build `output_fields` if none supplied to function
- [Type Introspection](@ref type_introspection_page)

The following functionality does not need introspection

- [`GraphQLClient.execute`](@ref)

Introspection is an incredibly powerful feature of GraphQL, and we hope to add more functions that make use of the informaton available in the schema.

### Viewing Operations

The queries, mutations and subscriptions available from a server can be accessed by the following functions, which will all attempt to introspect the server if it has not already been completed.

```julia
get_queries(client)
get_mutations(client)
get_subscriptions(client)
```

### Client Fields

There are several fields of `Client` that contain information relating to the schema. Whilst part of the private interface and therefore changes may occur outside of semantic versioning (in particular the format of this information may be changed to be more concretely typed), it can be accessed. If you have the need to ensure that this information can be accessed as part of the public interface, and therefore subject to semantic versioning, please [open an issue](https://github.com/DeloitteDigitalAPAC/GraphQLClient.jl/issues).